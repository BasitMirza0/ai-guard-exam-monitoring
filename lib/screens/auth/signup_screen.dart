import '../../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'auth_layout.dart';
import '../../services/auth_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  final _confirm = TextEditingController();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isPassObscured = true; // separate toggles — avoids shared state bug
  bool _isConfirmObscured = true;
  String _selectedRole = 'student';

  final List<Map<String, dynamic>> _roles = [
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

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  // ── Google Sign-Up ──────────────────────────────────────────────────────
  Future<void> _handleGoogleSignUp() async {
    setState(() => _isGoogleLoading = true);
    try {
      await AuthService().signInWithGoogle();
      // main.dart StreamBuilder routes to _NoProfileScreen for new users,
      // or to dashboard for returning users.
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (!msg.contains('cancelled')) {
        _showError('Google sign-in failed. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  // ── Email Sign-Up ───────────────────────────────────────────────────────
  Future<void> _handleSignUp() async {
    if (_name.text.trim().isEmpty ||
        _email.text.trim().isEmpty ||
        _pass.text.isEmpty) {
      _showError('Please fill all fields');
      return;
    }
    if (_pass.text != _confirm.text) {
      _showError('Passwords do not match');
      return;
    }
    if (_pass.text.length < 6) {
      _showError('Password must be at least 6 characters');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await AuthService().signUp(
        _email.text.trim(),
        _pass.text,
        role: _selectedRole,
        name: _name.text.trim(),
      );

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder:
              (_) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                backgroundColor: Colors.white,
                title: Column(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF22C55E),
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Registration Submitted',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
                content: const Text(
                  'Your account has been created and is awaiting admin approval.\n\nYou will be able to log in once an administrator approves your account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.muted,
                    height: 1.6,
                  ),
                ),
                actions: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'OK, Go to Login',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
        );
      }
    } catch (e) {
      _showError(e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isLoading || _isGoogleLoading;
    return AuthLayout(
      title: 'Make it official.',
      subtitle: 'Create your account to get started with AI Guard.',
      onBack: () => Navigator.pop(context),
      footer: TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text(
          'Already have an account? Sign in',
          textAlign: TextAlign.center,
        ),
      ),
      children: [
        AuthField(
          controller: _name,
          label: 'Full name',
          hint: 'Your full name',
          keyboard: TextInputType.name,
          autofillHints: const [AutofillHints.name],
        ),
        const SizedBox(height: 18),
        AuthField(
          controller: _email,
          label: 'Email address',
          hint: 'demo@example.com',
          keyboard: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
        ),
        const SizedBox(height: 18),
        AuthField(
          controller: _pass,
          label: 'Password',
          hint: 'At least 6 characters',
          obscure: _isPassObscured,
          autofillHints: const [AutofillHints.newPassword],
          onToggle: () => setState(() => _isPassObscured = !_isPassObscured),
        ),
        const SizedBox(height: 18),
        AuthField(
          controller: _confirm,
          label: 'Confirm password',
          hint: 'Re-enter your password',
          obscure: _isConfirmObscured,
          onToggle:
              () => setState(() => _isConfirmObscured = !_isConfirmObscured),
          onSubmitted: busy ? null : (_) => _handleSignUp(),
        ),
        const SizedBox(height: 22),
        const Text(
          'I am joining as a',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children:
              _roles
                  .map(
                    (role) => ChoiceChip(
                      avatar: Icon(role['icon'] as IconData, size: 18),
                      label: Text(role['label'] as String),
                      selected: _selectedRole == role['value'],
                      onSelected:
                          busy
                              ? null
                              : (_) => setState(
                                () => _selectedRole = role['value'] as String,
                              ),
                      selectedColor: AppColors.primarySoft,
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      side: BorderSide(
                        color:
                            _selectedRole == role['value']
                                ? authGreen
                                : AppColors.border,
                      ),
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 18),
        const Text(
          'An administrator will review your account before you can access exams.',
          style: TextStyle(color: authMuted, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 22),
        AuthButton(
          label: 'Create account',
          loading: _isLoading,
          onPressed: busy ? null : _handleSignUp,
        ),
        const AuthDivider(),
        AuthButton(
          label: 'Sign up with Google',
          loading: _isGoogleLoading,
          secondary: true,
          onPressed: busy ? null : _handleGoogleSignUp,
          icon: _GoogleIcon(),
        ),
      ],
    );
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.ink,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// ── Google "G" Icon ──────────────────────────────────────────────────────────
class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: const Size(20, 20), painter: _GoogleGPainter());
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    final segments = [
      const Color(0xFFEA4335),
      const Color(0xFFFBBC05),
      const Color(0xFF34A853),
      const Color(0xFF4285F4),
    ];

    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.38;

    for (int i = 0; i < 4; i++) {
      paint.color = segments[i];
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.65),
        -1.5708 + i * 1.5708,
        1.5708,
        false,
        paint,
      );
    }

    final cutPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r * 0.47, cutPaint);

    final barPaint =
        Paint()
          ..color = const Color(0xFF4285F4)
          ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(cx, cy - r * 0.12, r * 0.85, r * 0.24),
        const Radius.circular(2),
      ),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
