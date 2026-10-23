import '../../branding/brand_mark.dart';
import '../../theme/app_theme.dart';
import 'package:flutter/material.dart';

const authGreen = AppColors.primary;
const authMuted = AppColors.muted;

class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
    required this.footer,
    this.onBack,
  });
  final String title, subtitle;
  final List<Widget> children;
  final Widget footer;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: authGreen,
          onPrimary: Colors.white,
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: authGreen),
        ),
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screen = MediaQuery.sizeOf(context);
              final compact = screen.height < 700 || constraints.maxWidth < 360;
              final wide =
                  constraints.maxWidth >= 900 &&
                  constraints.maxHeight >= 650 &&
                  MediaQuery.textScalerOf(context).scale(1) < 1.4;
              final form = SizedBox.expand(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.symmetric(
                    horizontal: constraints.maxWidth < 380 ? 22 : 36,
                    vertical: compact ? 20 : 28,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                if (onBack != null)
                                  IconButton(
                                    onPressed: onBack,
                                    tooltip: 'Back to sign in',
                                    icon: const Icon(Icons.arrow_back_rounded),
                                  ),
                                const Flexible(child: _Brand()),
                              ],
                            ),
                            SizedBox(height: compact ? 24 : 32),
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: compact ? 30 : 34,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -1.3,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                color: authMuted,
                              ),
                            ),
                            SizedBox(height: compact ? 24 : 28),
                            ...children,
                            const SizedBox(height: 22),
                            Center(child: footer),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
              return Row(
                children: [
                  if (wide)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.all(48),
                        decoration: BoxDecoration(
                          color: authGreen,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _Brand(light: true),
                            const Spacer(),
                            const Icon(
                              Icons.school_outlined,
                              size: 64,
                              color: Color(0xFFC5DCC5),
                            ),
                            const SizedBox(height: 32),
                            const Text(
                              'A fairer exam.\nA clearer future.',
                              style: TextStyle(
                                fontSize: 44,
                                height: 1.12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -1.5,
                                color: Color(0xFFF5F4E8),
                              ),
                            ),
                            const SizedBox(height: 22),
                            const Text(
                              'One workspace for students and teachers.\nStay focused on what matters: learning.',
                              style: TextStyle(
                                color: Color(0xFFC5D6CC),
                                fontSize: 16,
                                height: 1.7,
                              ),
                            ),
                            const Spacer(),
                            const Divider(color: Color(0xFF436455)),
                            const SizedBox(height: 18),
                            const Text(
                              'BUILT FOR ACADEMIC INTEGRITY',
                              style: TextStyle(
                                color: Color(0xFFC5D6CC),
                                fontSize: 11,
                                letterSpacing: 1.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(child: form),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({this.light = false});
  final bool light;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const BrandMark(size: 40),
      const SizedBox(width: 12),
      Flexible(
        child: Text(
          'AI Guard',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: light ? const Color(0xFFF5F4E8) : authGreen,
          ),
        ),
      ),
    ],
  );
}

class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboard = TextInputType.text,
    this.obscure = false,
    this.onToggle,
    this.onSubmitted,
    this.autofillHints,
  });
  final TextEditingController controller;
  final String label, hint;
  final TextInputType keyboard;
  final bool obscure;
  final VoidCallback? onToggle;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: controller,
        scrollPadding: const EdgeInsets.all(32),
        obscureText: obscure,
        keyboardType:
            onToggle != null ? TextInputType.visiblePassword : keyboard,
        autofillHints: autofillHints,
        autocorrect: false,
        enableSuggestions: onToggle == null,
        textInputAction:
            onSubmitted == null ? TextInputAction.next : TextInputAction.done,
        onSubmitted: onSubmitted,
        style: const TextStyle(fontSize: 14, color: AppColors.ink),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: authMuted, fontSize: 14),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: authGreen, width: 1.5),
          ),
          suffixIcon:
              onToggle == null
                  ? null
                  : IconButton(
                    onPressed: onToggle,
                    tooltip: obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 20,
                      color: authMuted,
                    ),
                  ),
        ),
      ),
    ],
  );
}

class AuthButton extends StatelessWidget {
  const AuthButton({
    super.key,
    required this.label,
    required this.loading,
    required this.onPressed,
    this.secondary = false,
    this.icon,
  });
  final String label;
  final bool loading, secondary;
  final VoidCallback? onPressed;
  final Widget? icon;
  @override
  Widget build(BuildContext context) {
    final content =
        loading
            ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: secondary ? authGreen : Colors.white,
              ),
            )
            : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[icon!, const SizedBox(width: 12)],
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            );
    return SizedBox(
      width: double.infinity,
      // Grow with accessibility text instead of clipping a fixed-height label.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child:
            secondary
                ? OutlinedButton(
                  onPressed: onPressed,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.ink,
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: content,
                )
                : FilledButton(
                  onPressed: onPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: authGreen,
                    disabledBackgroundColor: const Color(0xFF718A7D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: content,
                ),
      ),
    );
  }
}

class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: 24),
    child: Row(
      children: [
        Expanded(child: Divider(color: AppColors.border)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('or', style: TextStyle(fontSize: 12, color: authMuted)),
        ),
        Expanded(child: Divider(color: AppColors.border)),
      ],
    ),
  );
}
