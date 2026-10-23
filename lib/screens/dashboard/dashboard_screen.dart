import '../../widgets/profile_avatar.dart';
import '../../widgets/responsive_body.dart';
import '../../theme/app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'camera_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isWeb = size.width > 900;

    return Scaffold(
      backgroundColor: AppColors.subtle,
      appBar: _buildAppBar(context),
      body: ResponsiveBody(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Center(
            child: Container(
              constraints: BoxConstraints(maxWidth: isWeb ? 1200 : size.width),
              padding: EdgeInsets.symmetric(
                horizontal: isWeb ? 40.0 : 20.0,
                vertical: 20.0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroSection(size, isWeb),
                  const SizedBox(height: 32),
                  _buildSectionHeader("Workspace"),
                  const SizedBox(height: 16),
                  _buildActionGrid(context, isWeb),
                  const SizedBox(height: 32),
                  _buildSectionHeader("Activity overview"),
                  const SizedBox(height: 16),
                  _buildMetricsRow(),
                  const SizedBox(height: 32),
                  _buildSystemHealthCard(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      title: Row(
        children: [
          const Icon(Icons.shield_outlined, color: AppColors.primary, size: 24),
          const SizedBox(width: 10),
          Text(
            "Dashboard",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: 2.0,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
      actions: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: IconButton(
            onPressed: () => FirebaseAuth.instance.signOut(),
            icon: const Icon(
              Icons.power_settings_new_rounded,
              color: Colors.redAccent,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroSection(Size size, bool isWeb) {
    final user = FirebaseAuth.instance.currentUser;
    final userDisplayName =
        user?.displayName ??
        user?.email?.split('@')[0].toUpperCase() ??
        "ADMIN";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.accent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "PROCTOR ID: #22941",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Welcome back,",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                Text(
                  userDisplayName,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isWeb ? 32 : 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _buildProfilePic(profilePhotoUrl(user)),
        ],
      ),
    );
  }

  Widget _buildProfilePic(String? photoUrl) => ProfileAvatar(
    photoUrl: photoUrl,
    name: FirebaseAuth.instance.currentUser?.displayName ?? '',
    size: 70,
  );

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 14,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildActionGrid(BuildContext context, bool isWeb) {
    return AdaptiveGrid(
      maxColumns: isWeb ? 4 : 2,
      children: [
        _proCard(
          context,
          "START EXAM",
          Icons.play_circle_fill_rounded,
          const Color(0xFF10B981),
          true,
          () {
            // CameraScreen now selects the front camera internally —
            // no need to pass a CameraDescription here.
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CameraScreen()),
            );
          },
        ),
        _proCard(
          context,
          "INCIDENTS",
          Icons.assignment_late_rounded,
          AppColors.accent,
          false,
          () {},
        ),
        _proCard(
          context,
          "VERIFY ID",
          Icons.face_retouching_natural_rounded,
          const Color(0xFFF59E0B),
          false,
          () {},
        ),
        _proCard(
          context,
          "SETTINGS",
          Icons.settings_suggest_rounded,
          AppColors.muted,
          false,
          () {},
        ),
      ],
    );
  }

  Widget _proCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    bool isPrimary,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color:
                isPrimary ? color.withValues(alpha: 0.4) : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsRow() {
    return AdaptiveRow(
      children: [
        _metricItem(
          "LIVE SESSIONS",
          "142",
          Icons.bolt_rounded,
          AppColors.accent,
        ),
        const SizedBox(width: 12),
        _metricItem(
          "SECURITY ALERTS",
          "02",
          Icons.security_rounded,
          Colors.orange,
        ),
      ],
    );
  }

  Widget _metricItem(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 9,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemHealthCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const Icon(Icons.api_rounded, color: Colors.greenAccent, size: 18),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "AI CORE STATUS",
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: Colors.white54,
                ),
              ),
              Text(
                "OPTIMAL PERFORMANCE",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.greenAccent,
                ),
              ),
            ],
          ),
          const Spacer(),
          const Text(
            "98.2ms",
            style: TextStyle(
              color: Colors.white30,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
