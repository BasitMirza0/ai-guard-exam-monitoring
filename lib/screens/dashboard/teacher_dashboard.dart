import '../../widgets/profile_avatar.dart';
import '../../widgets/app_state_view.dart';
import '../../widgets/responsive_body.dart';
import '../../theme/app_theme.dart';
// lib/screens/dashboard/teacher_dashboard.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../video_detection_screen.dart';
import '../detection_screen.dart';
import '../live_detection_screen.dart';

class TeacherDashboard extends StatefulWidget {
  const TeacherDashboard({super.key});

  @override
  State<TeacherDashboard> createState() => _TeacherDashboardState();
}

class _TeacherDashboardState extends State<TeacherDashboard> {
  int _tab = 0;
  // 0=All Violations, 1=By Student, 2=DVR Alerts

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = user?.displayName ?? user?.email?.split('@')[0] ?? 'Teacher';

    return Scaffold(
      backgroundColor: AppColors.subtle,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            const Icon(
              Icons.supervisor_account_rounded,
              color: AppColors.primary,
              size: 22,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Teacher workspace',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 1.5,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: ProfileAvatar(
              photoUrl: profilePhotoUrl(user),
              name: name,
              size: 36,
            ),
          ),
          // Quick actions
          IconButton(
            icon: const Icon(
              Icons.videocam_rounded,
              color: AppColors.primary,
              size: 22,
            ),
            tooltip: "Live Detection",
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LiveDetectionScreen(),
                  ),
                ),
          ),
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
              color: Colors.redAccent,
              size: 22,
            ),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: DashboardBody(
        headers: [
          // ── Header strip ─────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome, $name',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      Text(
                        'Monitor exam violations in real time',
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                _liveViolationCount(),
              ],
            ),
          ),

          // ── Quick action buttons ─────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: AdaptiveRow(
              children: [
                Expanded(
                  child: _quickBtn(
                    context,
                    icon: Icons.image_search_rounded,
                    label: "Image",
                    color: const Color(0xFFEF4444),
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DetectionScreen(),
                          ),
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _quickBtn(
                    context,
                    icon: Icons.slow_motion_video_rounded,
                    label: "Video",
                    color: AppColors.accent,
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const VideoDetectionScreen(),
                          ),
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _quickBtn(
                    context,
                    icon: Icons.videocam_rounded,
                    label: "Live",
                    color: const Color(0xFF059669),
                    onTap:
                        () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LiveDetectionScreen(),
                          ),
                        ),
                  ),
                ),
              ],
            ),
          ),

          // ── Tabs ─────────────────────────────
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tabBtn('All Violations', 0),
                const SizedBox(width: 8),
                _tabBtn('By Student', 1),
                const SizedBox(width: 8),
                _tabBtn('DVR Alerts', 2, color: const Color(0xFF0891B2)),
              ],
            ),
          ),

          const SizedBox(height: 4),
        ],
        child:
            _tab == 0
                ? _allViolations()
                : _tab == 1
                ? _violationsByStudent()
                : _dvrAlerts(),
      ),
    );
  }

  Widget _quickBtn(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabBtn(String label, int index, {Color color = AppColors.primary}) {
    final selected = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : AppColors.subtle,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.muted,
          ),
        ),
      ),
    );
  }

  Widget _liveViolationCount() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('violations').snapshots(),
      builder: (_, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color:
                count > 0
                    ? const Color(0xFFFF4B4B).withValues(alpha: 0.1)
                    : AppColors.subtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  count > 0
                      ? const Color(0xFFFF4B4B).withValues(alpha: 0.3)
                      : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 14,
                color: count > 0 ? const Color(0xFFFF4B4B) : AppColors.muted,
              ),
              const SizedBox(width: 5),
              Text(
                '$count violations',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: count > 0 ? const Color(0xFFFF4B4B) : AppColors.muted,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Tab 1 — All violations ────────────────────
  Widget _allViolations() {
    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('violations')
              .orderBy('timestamp', descending: true)
              .limit(50)
              .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyState(
            Icons.verified_rounded,
            const Color(0xFF22C55E),
            'No violations recorded yet',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder:
              (_, i) => _violationCard(docs[i].data() as Map<String, dynamic>),
        );
      },
    );
  }

  // ── Tab 2 — By Student ────────────────────────
  Widget _violationsByStudent() {
    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('violations')
              .orderBy('timestamp', descending: true)
              .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyState(
            Icons.people_outline_rounded,
            AppColors.muted,
            'No violations yet',
          );
        }

        final Map<String, List<Map<String, dynamic>>> grouped = {};
        for (final doc in docs) {
          final d = doc.data() as Map<String, dynamic>;
          final sid =
              d['studentEmail']?.toString() ??
              d['studentId']?.toString() ??
              'Unknown';
          grouped.putIfAbsent(sid, () => []).add(d);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: grouped.length,
          itemBuilder: (_, i) {
            final student = grouped.keys.elementAt(i);
            final violations = grouped[student]!;
            return _studentGroup(student, violations);
          },
        );
      },
    );
  }

  // ── Tab 3 — DVR Alerts ────────────────────────
  Widget _dvrAlerts() {
    return StreamBuilder<QuerySnapshot>(
      stream:
          FirebaseFirestore.instance
              .collection('dvr_alerts')
              .orderBy('timestamp', descending: true)
              .limit(50)
              .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF0891B2)),
          );
        }
        final docs = snap.data?.docs ?? [];

        if (docs.isEmpty) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.videocam_off_rounded,
                color: Color(0xFF0891B2),
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                'No DVR alerts yet',
                style: TextStyle(
                  color: AppColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Run dvr_show.py on Mac to start',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(horizontal: 32),
                decoration: BoxDecoration(
                  color: const Color(0xFF0891B2).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: const Color(0xFF0891B2).withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  'cd ~/Desktop\n'
                  'python3 dvr_show.py',
                  style: TextStyle(
                    color: const Color(0xFF0891B2),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final viol = d['violation']?.toString() ?? '';
            final conf = (d['confidence'] as num?)?.toDouble() ?? 0.0;
            final src = d['source']?.toString() ?? 'DVR';
            final ts = d['timestamp'] as Timestamp?;
            final time = ts != null ? _formatTime(ts.toDate()) : 'Unknown';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF0891B2).withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0891B2).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.videocam_rounded,
                      color: Color(0xFF0891B2),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          viol.replaceAll('_', ' ').toUpperCase(),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.camera_alt_outlined,
                              size: 11,
                              color: AppColors.muted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              src,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.access_time,
                              size: 11,
                              color: AppColors.muted,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              time,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0891B2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      "${(conf * 100).toStringAsFixed(0)}%",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _studentGroup(String student, List<Map<String, dynamic>> violations) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.person_rounded,
            color: AppColors.primary,
            size: 20,
          ),
        ),
        title: Text(
          student,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        subtitle: Text(
          '${violations.length} violation${violations.length == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 11, color: AppColors.muted),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFF4B4B).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${violations.length}',
            style: const TextStyle(
              color: Color(0xFFFF4B4B),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        children:
            violations
                .map(
                  (v) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: _violationCard(v),
                  ),
                )
                .toList(),
      ),
    );
  }

  Widget _violationCard(Map<String, dynamic> d) {
    final ts = d['timestamp'] as Timestamp?;
    final time =
        ts != null
            ? '${ts.toDate().day}/${ts.toDate().month}  '
                '${ts.toDate().hour}:'
                '${ts.toDate().minute.toString().padLeft(2, '0')}'
            : 'Unknown';

    final reason = d['reason']?.toString() ?? 'Violation';
    final email = d['studentEmail']?.toString() ?? '';
    final score = d['attentionScore']?.toString() ?? '';

    IconData badgeIcon = Icons.warning_amber_rounded;
    if (reason.toLowerCase().contains('face')) {
      badgeIcon = Icons.face_retouching_off_rounded;
    } else if (reason.toLowerCase().contains('phone')) {
      badgeIcon = Icons.phone_android_rounded;
    } else if (reason.toLowerCase().contains('multiple')) {
      badgeIcon = Icons.group_rounded;
    } else if (reason.toLowerCase().contains('gaze') ||
        reason.toLowerCase().contains('looking')) {
      badgeIcon = Icons.remove_red_eye_outlined;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF4B4B).withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFF4B4B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(badgeIcon, color: const Color(0xFFFF4B4B), size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reason,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                time,
                style: const TextStyle(fontSize: 10, color: AppColors.muted),
              ),
              if (score.isNotEmpty)
                Text(
                  'Attn: $score%',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFFFF4B4B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyState(IconData icon, Color color, String msg) =>
      AppStateView(icon: icon, color: color, title: msg);

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}
