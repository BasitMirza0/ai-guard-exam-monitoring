import 'branding/app_launch.dart';
import 'branding/brand_mark.dart';
import 'navigation/clean_page_transitions.dart';
import 'widgets/responsive_body.dart';
import 'theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'models/account_status.dart';
import 'screens/auth/login_screen.dart';
import 'screens/dashboard/student_dashboard.dart';
import 'screens/dashboard/teacher_dashboard.dart';
import 'screens/dashboard/admin_dashboard.dart';
import 'screens/dashboard/pending_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AiCheatApp());
}

Future<void> _initializeApp() => Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
).then((_) {});

class AiCheatApp extends StatelessWidget {
  const AiCheatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI Guard',
      theme: AppTheme.light,
      scrollBehavior: const AppScrollBehavior(),
      navigatorObservers: [appRouteObserver],
      home: AppLaunch(
        initialize: _initializeApp,
        builder: (_, onReady) => _AuthRouter(onReady: onReady),
      ),
    );
  }
}

class _AuthRouter extends StatelessWidget {
  const _AuthRouter({required this.onReady});
  final VoidCallback onReady;
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const _LoadingScreen(message: 'Connecting...');
      }
      if (!snapshot.hasData) {
        return LaunchDestination(onReady: onReady, child: const LoginScreen());
      }
      return _RoleRouter(uid: snapshot.data!.uid, onReady: onReady);
    },
  );
}

// ── Loading Screen ────────────────────────────────────────────────────────────
class _LoadingScreen extends StatelessWidget {
  final String message;
  const _LoadingScreen({this.message = 'Loading...'});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const BrandMark(size: 64),
            const SizedBox(height: 24),
            Text(
              'AI Guard',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(color: AppColors.muted, fontSize: 13),
            ),
            const SizedBox(height: 24),
            const CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Role Router ───────────────────────────────────────────────────────────────
class _RoleRouter extends StatelessWidget {
  final String uid;
  const _RoleRouter({required this.uid, required this.onReady});
  final VoidCallback onReady;
  Widget _ready(Widget child) =>
      LaunchDestination(onReady: onReady, child: child);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        // Loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen(message: 'Loading your profile...');
        }

        // Firestore error
        if (snapshot.hasError) {
          debugPrint('[Router] Firestore error: ${snapshot.error}');
          return _ready(
            _ErrorScreen(uid: uid, error: snapshot.error.toString()),
          );
        }

        // No document
        if (!snapshot.hasData || !snapshot.data!.exists) {
          debugPrint('[Router] Profile not found');
          return _ready(_NoProfileScreen(uid: uid));
        }

        // Route by role and status
        final data = snapshot.data!.data() as Map<String, dynamic>;
        final role = (data['role'] as String?) ?? 'student';
        final status = accountStatus(data);

        debugPrint('[Router] role=$role status=$status isWeb=$kIsWeb');

        // Status checks
        if (status == 'pending') {
          return _ready(const PendingScreen(status: 'pending'));
        }
        if (status == 'rejected') {
          return _ready(const PendingScreen(status: 'rejected'));
        }

        // Role checks
        if (role == 'admin') {
          if (kIsWeb) return _ready(const AdminDashboard());
          return _ready(const PendingScreen(status: 'admin_mobile'));
        }

        if (role == 'teacher') return _ready(const TeacherDashboard());

        // Default → student
        return _ready(const StudentDashboard());
      },
    );
  }
}

// ── Error Screen ──────────────────────────────────────────────────────────────
class _ErrorScreen extends StatelessWidget {
  final String uid;
  final String error;
  const _ErrorScreen({required this.uid, required this.error});

  @override
  Widget build(BuildContext context) => const _AccountStatusScreen(
    icon: Icons.error_outline_rounded,
    title: 'Unable to load your account',
    message:
        'Check your connection and sign in again. If this continues, contact your institution administrator.',
  );
}

// ── No Profile Screen ─────────────────────────────────────────────────────────
// Shown when authenticated but no Firestore doc exists.
// For new Google users → role selection → creates pending profile → signs out.
class _NoProfileScreen extends StatefulWidget {
  final String uid;
  const _NoProfileScreen({required this.uid});

  @override
  State<_NoProfileScreen> createState() => _NoProfileScreenState();
}

class _NoProfileScreenState extends State<_NoProfileScreen> {
  String _selectedRole = 'student';
  bool _isLoading = false;

  bool get _isGoogleUser {
    final user = FirebaseAuth.instance.currentUser;
    return user?.providerData.any((p) => p.providerId == 'google.com') ?? false;
  }

  Future<void> _completeSetup() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser!;
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'uid': user.uid,
        'email': user.email ?? '',
        'name': user.displayName ?? user.email?.split('@')[0] ?? '',
        'role': _selectedRole,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'authProvider': 'google',
        'photoURL': user.photoURL,
      });
      await FirebaseAuth.instance.signOut();
      // StreamBuilder in main.dart will route back to LoginScreen automatically.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: const Color(0xFFFF4B4B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isGoogleUser) return _buildGoogleSetup();
    return _buildNoProfileFallback();
  }

  Widget _buildGoogleSetup() {
    final roles = [
      {
        'value': 'student',
        'label': 'Student',
        'icon': Icons.school_rounded,
        'desc': 'Take monitored exams',
      },
      {
        'value': 'teacher',
        'label': 'Teacher',
        'icon': Icons.person_rounded,
        'desc': 'Review examination incidents',
      },
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      size: 50,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Complete registration',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Choose your role, then submit your approval request.',
                    style: TextStyle(fontSize: 13, color: AppColors.muted),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          color: Color(0xFFF59E0B),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Your request will appear in the admin approval list after you submit this form.',
                            style: TextStyle(
                              fontSize: 11,
                              color: const Color(0xFFF59E0B),
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.07),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select your role',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...roles.map((role) {
                          final selected = _selectedRole == role['value'];
                          return GestureDetector(
                            onTap:
                                () => setState(
                                  () => _selectedRole = role['value'] as String,
                                ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    selected
                                        ? AppColors.primary.withValues(
                                          alpha: 0.06,
                                        )
                                        : AppColors.background,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color:
                                      selected
                                          ? AppColors.primary
                                          : AppColors.border,
                                  width: selected ? 2 : 1.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color:
                                          selected
                                              ? AppColors.primary
                                              : AppColors.border,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      role['icon'] as IconData,
                                      size: 18,
                                      color:
                                          selected
                                              ? Colors.white
                                              : AppColors.muted,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          role['label'] as String,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color:
                                                selected
                                                    ? AppColors.primary
                                                    : AppColors.ink,
                                          ),
                                        ),
                                        Text(
                                          role['desc'] as String,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (selected)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppColors.primary,
                                      size: 20,
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _completeSetup,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              elevation: 0,
                            ),
                            child:
                                _isLoading
                                    ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                    : Text(
                                      'Submit for approval',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1,
                                        fontSize: 13,
                                      ),
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: Text(
                      'Cancel & Sign Out',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoProfileFallback() => const _AccountStatusScreen(
    icon: Icons.person_search_outlined,
    title: 'Profile not found',
    message:
        'Your account does not have a profile yet. Contact your institution administrator for help.',
  );
}

class _AccountStatusScreen extends StatelessWidget {
  const _AccountStatusScreen({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: ResponsiveBody(
      maxWidth: 480,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Sign out'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
