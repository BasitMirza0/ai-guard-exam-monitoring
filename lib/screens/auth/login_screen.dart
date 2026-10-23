import '../../theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'auth_layout.dart';
import '../../services/auth_service.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _isObscured = true;

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  // ── Google Sign-In ──────────────────────────────────────────────────────
  Future<void> _handleGoogleSignIn() async {
    setState(() => _isGoogleLoading = true);
    try {
      await AuthService().signInWithGoogle();
      // main.dart StreamBuilder handles all routing from here.
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      if (!msg.contains('cancelled')) {
        _showSnackBar(
          e is StateError
              ? e.message.toString()
              : 'Google sign-in failed. Try again.',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  // ── Email Login ─────────────────────────────────────────────────────────
  Future<void> _handleLogin() async {
    if (_email.text.trim().isEmpty || _pass.text.isEmpty) {
      _showSnackBar('Please enter credentials');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final status = await AuthService().login(_email.text.trim(), _pass.text);

      if (!mounted) return;

      if (status == 'approved') {
        // StreamBuilder in main.dart routes automatically.
      } else if (status == 'pending') {
        _showSnackBar(
          'Your account is awaiting admin approval.',
          isWarning: true,
        );
      } else if (status == 'rejected') {
        _showSnackBar('Your account access has been denied.', isError: true);
      } else {
        _showSnackBar('Account not found. Please register first.');
      }
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (msg.contains('user-not-found') ||
          msg.contains('wrong-password') ||
          msg.contains('invalid-credential') ||
          msg.contains('INVALID_LOGIN_CREDENTIALS')) {
        msg = 'Invalid email or password.';
      }
      _showSnackBar(msg, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetEmail = TextEditingController();
    await showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            backgroundColor: Colors.white,
            title: const Text(
              'Reset Password',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.ink,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Enter your email and we will send a reset link.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.muted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.subtle,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TextField(
                    controller: resetEmail,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(
                        Icons.alternate_email_rounded,
                        color: AppColors.primary,
                        size: 18,
                      ),
                      hintText: 'Your email address',
                      hintStyle: TextStyle(color: Colors.black38),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (resetEmail.text.trim().isEmpty) {
                    _showSnackBar('Please enter your email');
                    return;
                  }
                  final email = resetEmail.text.trim();
                  Navigator.pop(context);
                  try {
                    await AuthService().forgotPassword(email);
                    if (mounted) {
                      _showSnackBar(
                        'Reset link sent! Check your email.',
                        isSuccess: true,
                      );
                    }
                  } catch (e) {
                    if (mounted) _showSnackBar('Error: $e', isError: true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Send Link',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
    );
    resetEmail.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busy = _isLoading || _isGoogleLoading;
    return AuthLayout(
      title: 'Welcome back.',
      subtitle: 'Sign in to your examination workspace.',
      footer: TextButton(
        onPressed:
            busy
                ? null
                : () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SignupScreen()),
                ),
        child: const Text(
          'New to AI Guard? Create an account',
          textAlign: TextAlign.center,
        ),
      ),
      children: [
        AuthField(
          controller: _email,
          label: 'Email address',
          hint: 'demo@example.com',
          keyboard: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username],
        ),
        const SizedBox(height: 20),
        AuthField(
          controller: _pass,
          label: 'Password',
          hint: 'Enter your password',
          obscure: _isObscured,
          autofillHints: const [AutofillHints.password],
          onToggle: () => setState(() => _isObscured = !_isObscured),
          onSubmitted: busy ? null : (_) => _handleLogin(),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: busy ? null : _showForgotPasswordDialog,
            child: const Text('Forgot password?'),
          ),
        ),
        const SizedBox(height: 12),
        AuthButton(
          label: 'Sign in',
          loading: _isLoading,
          onPressed: busy ? null : _handleLogin,
        ),
        const AuthDivider(),
        AuthButton(
          label: 'Continue with Google',
          loading: _isGoogleLoading,
          secondary: true,
          onPressed: busy ? null : _handleGoogleSignIn,
          icon: _GoogleIcon(),
        ),
      ],
    );
  }

  void _showSnackBar(
    String m, {
    bool isSuccess = false,
    bool isWarning = false,
    bool isError = false,
  }) {
    Color bg = AppColors.ink;
    if (isSuccess) bg = const Color(0xFF22C55E);
    if (isWarning) bg = const Color(0xFFF59E0B);
    if (isError) bg = const Color(0xFFFF4B4B);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(m),
        behavior: SnackBarBehavior.floating,
        backgroundColor: bg,
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

    // Draw colored arcs for the Google "G"
    final segments = [
      // red (top-right)
      const Color(0xFFEA4335),
      // yellow (bottom-right)
      const Color(0xFFFBBC05),
      // green (bottom-left)
      const Color(0xFF34A853),
      // blue (top-left)
      const Color(0xFF4285F4),
    ];

    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.38;

    for (int i = 0; i < 4; i++) {
      paint.color = segments[i];
      final startAngle =
          -1.5708 + i * 1.5708; // 0°, 90°, 180°, 270° shifted -90°
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.65),
        startAngle,
        1.5708,
        false,
        paint,
      );
    }

    // White cutout inside arc to make the G shape
    final cutPaint =
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), r * 0.47, cutPaint);

    // Draw the horizontal bar of the "G"
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
