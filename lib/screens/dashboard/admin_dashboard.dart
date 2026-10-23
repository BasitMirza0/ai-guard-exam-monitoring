import '../../widgets/profile_avatar.dart';
import '../../widgets/app_state_view.dart';
import '../../widgets/responsive_body.dart';
import '../../widgets/admin_workspace.dart';
import '../../theme/app_theme.dart';
// lib/screens/dashboard/admin_dashboard.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../models/account_status.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({
    super.key,
    this.usersStream,
    this.violationsStream,
    this.adminName,
  });
  final Stream<QuerySnapshot>? usersStream;
  final Stream<QuerySnapshot>? violationsStream;
  final String? adminName;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _tab = 0;
  late final _usersStream =
      widget.usersStream ??
      FirebaseFirestore.instance.collection('users').snapshots();
  late final _violationsStream =
      widget.violationsStream ??
      FirebaseFirestore.instance.collection('violations').snapshots();

  @override
  Widget build(BuildContext context) {
    final user =
        widget.adminName != null ? null : FirebaseAuth.instance.currentUser;
    final name =
        widget.adminName ??
        user?.displayName ??
        user?.email?.split('@')[0] ??
        'Admin';

    return StreamBuilder<QuerySnapshot>(
      stream: _usersStream,
      builder:
          (context, users) => StreamBuilder<QuerySnapshot>(
            stream: _violationsStream,
            builder: (context, violations) {
              _usersSnapshot = users;
              _violationsSnapshot = violations;
              return AdminWorkspace(
                name: name,
                photoUrl: profilePhotoUrl(user),
                selected: _tab,
                onSelect: (value) => setState(() => _tab = value),
                onSignOut: () => FirebaseAuth.instance.signOut(),
                stats: _buildStatsRow(),
                content: _buildTabContent(),
              );
            },
          ),
    );
  }

  AsyncSnapshot<QuerySnapshot> _usersSnapshot = const AsyncSnapshot.waiting();
  AsyncSnapshot<QuerySnapshot> _violationsSnapshot =
      const AsyncSnapshot.waiting();

  // ── Stats Row ─────────────────────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Container(
      padding: EdgeInsets.zero,
      child: AdaptiveRow(
        children: [
          _statCard(
            'Awaiting review',
            'users',
            const Color(0xFFF59E0B),
            filter: 'pending',
          ),
          const SizedBox(width: 10),
          _statCard('Total users', 'users', AppColors.primary),
          const SizedBox(width: 10),
          _statCard('Violations', 'violations', const Color(0xFFEF4444)),
        ],
      ),
    );
  }

  Widget _statCard(
    String label,
    String collection,
    Color color, {
    String? filter,
  }) {
    return Expanded(
      child: Builder(
        builder: (_) {
          final snap =
              collection == 'violations' ? _violationsSnapshot : _usersSnapshot;
          final count =
              snap.data?.docs
                  .where(
                    (doc) =>
                        filter == null ||
                        accountStatus(doc.data() as Map<String, dynamic>) ==
                            filter,
                  )
                  .length ??
              0;
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snap.hasError
                      ? '—'
                      : snap.hasData
                      ? '$count'
                      : '…',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_tab) {
      case 0:
        return _approvalsTab();
      case 1:
        return _usersTab();
      case 2:
        return _violationsTab();
      case 3:
        return _systemTab();
      default:
        return _approvalsTab();
    }
  }

  // ── Approvals Tab ─────────────────────────────────────────────────────────
  Widget _approvalsTab() {
    return Builder(
      builder: (context) {
        final snap = _usersSnapshot;
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }
        if (snap.hasError) {
          return _emptyState(
            icon: Icons.cloud_off_outlined,
            color: AppColors.muted,
            title: 'Unable to load this section',
            subtitle: 'Check your connection and account permissions.',
          );
        }
        final docs =
            snap.data?.docs
                .where(
                  (doc) =>
                      accountStatus(doc.data() as Map<String, dynamic>) ==
                      'pending',
                )
                .toList() ??
            [];
        if (docs.isEmpty) {
          return _emptyState(
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF22C55E),
            title: 'You’re all caught up',
            subtitle: 'New account requests will appear here for your review.',
          );
        }

        final sorted = List.from(docs)..sort((a, b) {
          final aTs = (a.data() as Map)['createdAt'] as Timestamp?;
          final bTs = (b.data() as Map)['createdAt'] as Timestamp?;
          if (aTs == null || bTs == null) return 0;
          return bTs.compareTo(aTs);
        });

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final d = sorted[i].data() as Map<String, dynamic>;
            return _approvalCard(d, sorted[i].id);
          },
        );
      },
    );
  }

  Widget _approvalCard(Map<String, dynamic> d, String docId) {
    final email = d['email']?.toString() ?? '';
    final name = d['name']?.toString() ?? '';
    final role = d['role']?.toString() ?? 'student';
    final ts = d['createdAt'] as Timestamp?;
    final time = ts != null ? _formatDate(ts.toDate()) : 'Unknown date';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                child: Text(
                  (name.isNotEmpty
                          ? name[0]
                          : email.isNotEmpty
                          ? email[0]
                          : '?')
                      .toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isNotEmpty ? name : email,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.night,
                      ),
                    ),
                    if (name.isNotEmpty)
                      Text(
                        email,
                        style: TextStyle(fontSize: 12, color: AppColors.muted),
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
                  color: AppColors.subtle,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _capitalize(role),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Registered $time',
            style: TextStyle(fontSize: 11, color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rejectUser(docId, email),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  child: Text(
                    'Decline',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _approveUser(docId, email),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                  child: Text(
                    'Approve',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Users Tab ─────────────────────────────────────────────────────────────
  Widget _usersTab() {
    return Builder(
      builder: (context) {
        final snap = _usersSnapshot;
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }
        if (snap.hasError) {
          return _emptyState(
            icon: Icons.cloud_off_outlined,
            color: AppColors.muted,
            title: 'Unable to load this section',
            subtitle: 'Check your connection and account permissions.',
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyState(
            icon: Icons.people_outline_rounded,
            color: AppColors.primary,
            title: 'No users yet',
            subtitle: 'Registered users will appear here.',
          );
        }

        final sorted = List.from(docs)..sort((a, b) {
          final aTs = (a.data() as Map)['createdAt'] as Timestamp?;
          final bTs = (b.data() as Map)['createdAt'] as Timestamp?;
          if (aTs == null || bTs == null) return 0;
          return bTs.compareTo(aTs);
        });

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final d = sorted[i].data() as Map<String, dynamic>;
            return _userCard(d, sorted[i].id);
          },
        );
      },
    );
  }

  Widget _userCard(Map<String, dynamic> d, String docId) {
    final role = d['role']?.toString() ?? 'student';
    final status = accountStatus(d);
    final email = d['email']?.toString() ?? '';
    final name = d['name']?.toString() ?? '';

    final statusColor =
        status == 'approved'
            ? const Color(0xFF22C55E)
            : status == 'rejected'
            ? const Color(0xFFEF4444)
            : const Color(0xFFF59E0B);

    final initials =
        name.isNotEmpty
            ? name[0].toUpperCase()
            : email.isNotEmpty
            ? email[0].toUpperCase()
            : '?';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.primary.withValues(alpha: 0.08),
            child: Text(
              initials,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isNotEmpty ? name : email,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.night,
                  ),
                ),
                if (name.isNotEmpty)
                  Text(
                    email,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.muted,
                    ),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _capitalize(role),
                      style: TextStyle(fontSize: 11, color: AppColors.muted),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: const BoxDecoration(
                        color: AppColors.border,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _capitalize(status),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (val) => _changeRole(docId, val),
            icon: const Icon(
              Icons.more_vert_rounded,
              color: AppColors.muted,
              size: 20,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            itemBuilder:
                (_) => [
                  _menuItem('Set as Student', 'student', Icons.school_rounded),
                  _menuItem('Set as Teacher', 'teacher', Icons.person_rounded),
                  _menuItem(
                    'Set as Admin',
                    'admin',
                    Icons.admin_panel_settings_rounded,
                  ),
                  const PopupMenuDivider(),
                  if (status != 'approved')
                    _menuItem(
                      'Approve',
                      '_approve',
                      Icons.check_circle_rounded,
                      color: const Color(0xFF22C55E),
                    ),
                  if (status != 'rejected')
                    _menuItem(
                      'Reject',
                      '_reject',
                      Icons.cancel_rounded,
                      color: const Color(0xFFEF4444),
                    ),
                ],
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String label,
    String value,
    IconData icon, {
    Color? color,
  }) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color ?? const Color(0xFF475569)),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: color ?? AppColors.ink),
          ),
        ],
      ),
    );
  }

  // ── Violations Tab ────────────────────────────────────────────────────────
  Widget _violationsTab() {
    return Builder(
      builder: (context) {
        final snap = _violationsSnapshot;
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }
        if (snap.hasError) {
          return _emptyState(
            icon: Icons.cloud_off_outlined,
            color: AppColors.muted,
            title: 'Unable to load this section',
            subtitle: 'Check your connection and account permissions.',
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyState(
            icon: Icons.shield_outlined,
            color: const Color(0xFF22C55E),
            title: 'No violations recorded',
            subtitle: 'Recorded examination events will appear here.',
          );
        }

        final sorted = List.from(docs)..sort((a, b) {
          final aTs = (a.data() as Map)['timestamp'] as Timestamp?;
          final bTs = (b.data() as Map)['timestamp'] as Timestamp?;
          if (aTs == null || bTs == null) return 0;
          return bTs.compareTo(aTs);
        });

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final d = sorted[i].data() as Map<String, dynamic>;
            return _violationCard(d);
          },
        );
      },
    );
  }

  Widget _violationCard(Map<String, dynamic> d) {
    final ts = d['timestamp'] as Timestamp?;
    final time = ts != null ? _formatDate(ts.toDate()) : 'Unknown';
    final reason = d['reason']?.toString() ?? 'Violation';
    final email = d['studentEmail']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFEF4444),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  reason,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.night,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: TextStyle(fontSize: 11, color: AppColors.muted),
                  ),
              ],
            ),
          ),
          Text(time, style: TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      ),
    );
  }

  // ── System Tab ────────────────────────────────────────────────────────────
  Widget _systemTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _systemSection('About the system', [
          _systemRow(
            Icons.model_training_rounded,
            'Detection model',
            'Remote YOLO analysis; local ML Kit exams',
          ),
          _systemRow(
            Icons.track_changes_rounded,
            'Tracking',
            'Backend-defined; see deployment documentation',
          ),
          _systemRow(
            Icons.cloud_outlined,
            'Backend',
            'FastAPI on Google Colab',
          ),
          _systemRow(
            Icons.phone_android_rounded,
            'Frontend',
            'Flutter (Web + Mobile)',
          ),
        ]),
        const SizedBox(height: 16),
        _systemSection('Access control', [
          _systemRow(
            Icons.admin_panel_settings_outlined,
            'Admin',
            'Web browser only',
          ),
          _systemRow(
            Icons.school_outlined,
            'Students',
            'Mobile app, requires approval',
          ),
          _systemRow(
            Icons.person_outline_rounded,
            'Teachers',
            'Mobile app, requires approval',
          ),
        ]),
        const SizedBox(height: 16),
        _systemSection('Firebase', [
          _systemRow(
            Icons.lock_outline_rounded,
            'Authentication',
            'Firebase Auth',
          ),
          _systemRow(Icons.storage_outlined, 'Database', 'Cloud Firestore'),
          _systemRow(
            Icons.check_circle_outline_rounded,
            'Account access',
            'Managed by Firebase Auth',
          ),
        ]),
      ],
    );
  }

  Widget _systemSection(String title, List<Widget> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 2),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.muted,
              letterSpacing: 0.3,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children:
                items.asMap().entries.map((e) {
                  final isLast = e.key == items.length - 1;
                  return Column(
                    children: [
                      e.value,
                      if (!isLast)
                        const Divider(
                          height: 1,
                          indent: 52,
                          color: AppColors.subtle,
                        ),
                    ],
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _systemRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: const Color(0xFF475569)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.night,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty State ───────────────────────────────────────────────────────────
  Widget _emptyState({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return AppStateView(
      icon: icon,
      color: color,
      title: title,
      subtitle: subtitle,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Future<void> _approveUser(String docId, String email) async {
    await AuthService().approveUser(docId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$email approved'),
          backgroundColor: const Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _rejectUser(String docId, String email) async {
    await AuthService().rejectUser(docId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$email declined'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  Future<void> _changeRole(String docId, String value) async {
    if (value == '_approve') {
      await AuthService().approveUser(docId);
    } else if (value == '_reject') {
      await AuthService().rejectUser(docId);
    } else {
      await FirebaseFirestore.instance.collection('users').doc(docId).update({
        'role': value,
      });
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Updated'),
          backgroundColor: const Color(0xFF22C55E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }
}
