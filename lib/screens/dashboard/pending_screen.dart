import '../../theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class PendingScreen extends StatelessWidget {
  final String status; // 'pending' | 'rejected' | 'admin_mobile'
  const PendingScreen({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final config = _getConfig(status);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Icon
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: config['color'].withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        config['icon'] as IconData,
                        size: 50,
                        color: config['color'] as Color,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Title
                    Text(
                      config['title'] as String,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Subtitle
                    Text(
                      config['subtitle'] as String,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.muted,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Info box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: (config['color'] as Color).withValues(
                          alpha: 0.06,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (config['color'] as Color).withValues(
                            alpha: 0.2,
                          ),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: config['color'] as Color,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              config['info'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                color: config['color'] as Color,
                                fontWeight: FontWeight.w600,
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Sign out button
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton(
                        onPressed: () => FirebaseAuth.instance.signOut(),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(
                            color: AppColors.border,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          'Sign Out',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _getConfig(String status) {
    switch (status) {
      case 'rejected':
        return {
          'icon': Icons.cancel_rounded,
          'color': const Color(0xFFFF4B4B),
          'title': 'Access Denied',
          'subtitle':
              'Your registration has been reviewed\nand access was not granted.',
          'info':
              'Please contact your institution administrator for assistance.',
        };
      case 'admin_mobile':
        return {
          'icon': Icons.computer_rounded,
          'color': AppColors.primary,
          'title': 'Web Access Only',
          'subtitle':
              'The Admin Panel is only accessible\nthrough a web browser.',
          'info':
              'Please open this application in Chrome or any web browser to access the Admin Panel.',
        };
      case 'pending':
      default:
        return {
          'icon': Icons.hourglass_top_rounded,
          'color': const Color(0xFFF59E0B),
          'title': 'Awaiting Approval',
          'subtitle':
              'Your account has been created\nand is pending admin approval.',
          'info':
              'An administrator will review your registration and approve your access. You will be able to log in once approved.',
        };
    }
  }
}
