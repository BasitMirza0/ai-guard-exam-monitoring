import '../../widgets/responsive_body.dart';
import '../../widgets/profile_avatar.dart';
import '../../widgets/workspace_components.dart';
import '../../theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../detection_screen.dart';
import '../video_detection_screen.dart';
import '../live_detection_screen.dart';
import 'camera_screen.dart';

class StudentDashboard extends StatelessWidget {
  const StudentDashboard({super.key});
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? '';
    final name =
        user?.displayName?.trim().isNotEmpty == true
            ? user!.displayName!
            : email.split('@').first;
    return StudentWorkspace(
      name: name,
      email: email,
      photoUrl: profilePhotoUrl(user),
      onLogout: () => FirebaseAuth.instance.signOut(),
      onLive:
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const LiveDetectionScreen()),
          ),
      onExam:
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CameraScreen()),
          ),
      onImage:
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DetectionScreen()),
          ),
      onVideo:
          () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const VideoDetectionScreen()),
          ),
      recentActivity: _ViolationList(uid: user?.uid ?? ''),
    );
  }
}

/// Presentation is independent of Firebase so layouts can be verified directly.
class StudentWorkspace extends StatelessWidget {
  const StudentWorkspace({
    super.key,
    required this.name,
    required this.email,
    this.photoUrl,
    required this.onLogout,
    required this.onLive,
    required this.onExam,
    required this.onImage,
    required this.onVideo,
    required this.recentActivity,
  });
  final String name, email;
  final String? photoUrl;
  final VoidCallback onLogout, onLive, onExam, onImage, onVideo;
  final Widget recentActivity;
  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting =
        hour < 12
            ? 'Good morning'
            : hour < 17
            ? 'Good afternoon'
            : 'Good evening';
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: AppColors.primary, size: 22),
            SizedBox(width: 10),
            Flexible(child: Text('AI Guard')),
          ],
        ),
        actions: [
          IconButton(
            onPressed: onLogout,
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded, size: 21),
          ),
        ],
      ),
      body: ResponsiveBody(
        maxWidth: 800,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Row(
                    children: [
                      ProfileAvatar(photoUrl: photoUrl, name: name),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              greeting,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              name.isEmpty ? 'Welcome back' : name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                            if (email.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Your workspace.',
                    style: TextStyle(
                      fontSize: 30,
                      letterSpacing: -.9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Start a session or review your exam activity.',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: AppColors.muted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  WorkspaceAction(
                    title: 'Live detection',
                    description: 'Analyze your camera feed in real time.',
                    icon: Icons.videocam_outlined,
                    featured: true,
                    onTap: onLive,
                  ),
                  const SizedBox(height: 12),
                  WorkspaceAction(
                    title: 'Start an exam',
                    description: 'Enter your monitored exam session.',
                    icon: Icons.assignment_outlined,
                    onTap: onExam,
                  ),
                  const SizedBox(height: 32),
                  const _SectionTitle(
                    title: 'Analysis tools',
                    subtitle: 'Review images and recorded videos.',
                  ),
                  const SizedBox(height: 16),
                  AdaptiveRow(
                    children: [
                      Expanded(
                        child: _AnalysisTile(
                          title: 'Image analysis',
                          subtitle: 'Upload or capture a photo',
                          icon: Icons.image_outlined,
                          onTap: onImage,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _AnalysisTile(
                          title: 'Video analysis',
                          subtitle: 'Review a recorded video',
                          icon: Icons.video_library_outlined,
                          onTap: onVideo,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  const _SectionTitle(
                    title: 'Recent activity',
                    subtitle: 'Your latest exam observations.',
                  ),
                  const SizedBox(height: 16),
                  recentActivity,
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12,
          height: 1.5,
          color: AppColors.muted,
        ),
      ),
    ],
  );
}

class _AnalysisTile extends StatelessWidget {
  const _AnalysisTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: AppColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      // A route-opening ripple would freeze offstage and resume on Back.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.primary, size: 26),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.muted,
              ),
            ),
            const SizedBox(height: 16),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 18,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    ),
  );
}

// ─── Violations List ─────────────────────────────────
class _ViolationList extends StatelessWidget {
  final String uid;
  const _ViolationList({required this.uid});

  @override
  Widget build(BuildContext context) {
    if (uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('violations')
              .where('studentId', isEqualTo: uid)
              .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
                strokeWidth: 2,
              ),
            ),
          );
        }

        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.verified_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No violations on record',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Great work — keep it up',
                        style: TextStyle(fontSize: 11, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final sorted =
            docs.toList()..sort((a, b) {
              final aTs = (a.data() as Map)['timestamp'] as Timestamp?;
              final bTs = (b.data() as Map)['timestamp'] as Timestamp?;
              if (aTs == null || bTs == null) return 0;
              return bTs.compareTo(aTs);
            });

        return Column(
          children:
              sorted.take(10).map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final ts = d['timestamp'] as Timestamp?;
                final time = ts != null ? _fmt(ts.toDate()) : '—';
                final reason = d['reason']?.toString() ?? 'Violation';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFFDC2626),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              reason,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              time,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
        );
      },
    );
  }

  String _fmt(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
