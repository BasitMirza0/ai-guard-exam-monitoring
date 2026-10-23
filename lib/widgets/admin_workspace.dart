import 'package:flutter/material.dart';
import '../branding/brand_mark.dart';
import '../theme/app_theme.dart';
import 'profile_avatar.dart';
import 'responsive_body.dart';

/// Admin chrome is independent of Firebase so layout can be checked at any size.
class AdminWorkspace extends StatelessWidget {
  const AdminWorkspace({
    super.key,
    required this.name,
    this.photoUrl,
    required this.selected,
    required this.onSelect,
    required this.onSignOut,
    required this.stats,
    required this.content,
  });
  final String name;
  final String? photoUrl;
  final int selected;
  final ValueChanged<int> onSelect;
  final VoidCallback onSignOut;
  final Widget stats, content;
  static const labels = ['Approvals', 'Users', 'Violations', 'System'];
  static const titles = [
    'Account approvals',
    'People & access',
    'Violation activity',
    'System overview',
  ];
  static const descriptions = [
    'Review account requests and welcome people to your workspace.',
    'Manage your community, account roles and access permissions.',
    'Review recorded events from your examination workspace.',
    'Your platform configuration and access policies, in one place.',
  ];
  static const icons = [
    Icons.fact_check_outlined,
    Icons.people_outline_rounded,
    Icons.flag_outlined,
    Icons.tune_rounded,
  ];

  Widget _navigation(BuildContext context, bool wide) {
    return Flex(
      direction: wide ? Axis.vertical : Axis.horizontal,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        4,
        (i) => Padding(
          padding: EdgeInsets.only(bottom: wide ? 6 : 0, right: wide ? 0 : 6),
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor:
                  selected == i
                      ? (wide ? Colors.white : AppColors.primary)
                      : (wide ? const Color(0xFFB5C9BF) : AppColors.muted),
              backgroundColor:
                  selected == i
                      ? (wide ? const Color(0xFF285343) : AppColors.primarySoft)
                      : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => onSelect(i),
            child: Row(
              mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
              children: [
                Icon(icons[i], size: 20),
                const SizedBox(width: 10),
                if (wide)
                  Expanded(
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontWeight:
                            selected == i ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  )
                else
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontWeight:
                          selected == i ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                if (wide && selected == i) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide =
          constraints.maxWidth >= 1000 &&
          MediaQuery.textScalerOf(context).scale(14) < 24;
      final padding = constraints.maxWidth < 600 ? 16.0 : 32.0;
      final body = DashboardBody(
        headers: [
          Padding(
            padding: EdgeInsets.fromLTRB(padding, 28, padding, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!wide) ...[
                  Row(
                    children: [
                      const BrandMark(size: 32),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'AI Guard',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Sign out',
                        onPressed: onSignOut,
                        icon: const Icon(Icons.logout_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'WORKSPACE / ADMINISTRATION',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                          color: AppColors.muted,
                        ),
                      ),
                    ),
                    if (wide)
                      Text(
                        'Welcome, $name',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.muted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  titles[selected],
                  style: TextStyle(
                    fontSize: wide ? 30 : 25,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    color: AppColors.night,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  descriptions[selected],
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: AppColors.muted,
                  ),
                ),
                const SizedBox(height: 24),
                stats,
                if (!wide) ...[
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _navigation(context, false),
                  ),
                ],
              ],
            ),
          ),
        ],
        child: Padding(
          padding: EdgeInsets.fromLTRB(padding, 0, padding, 24),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Icon(icons[selected], color: AppColors.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          labels[selected] == 'System'
                              ? 'Platform details'
                              : labels[selected] == 'Approvals'
                              ? 'Pending requests'
                              : labels[selected] == 'Users'
                              ? 'Workspace directory'
                              : 'Recorded events',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Expanded(child: content),
              ],
            ),
          ),
        ),
      );
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Row(
            children: [
              if (wide)
                SizedBox(
                  width: 260,
                  child: ColoredBox(
                    color: AppColors.primaryDark,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              BrandMark(size: 38),
                              SizedBox(width: 10),
                              Text(
                                'AI Guard',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const Padding(
                            padding: EdgeInsets.only(left: 48, top: 2),
                            child: Text(
                              'Admin console',
                              style: TextStyle(
                                color: Color(0xFFB5C9BF),
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(height: 48),
                          const Padding(
                            padding: EdgeInsets.only(left: 16, bottom: 14),
                            child: Text(
                              'MANAGE',
                              style: TextStyle(
                                color: Color(0xFF92B2A2),
                                fontSize: 10,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _navigation(context, true),
                          const Spacer(),
                          const Divider(color: Color(0xFF36594A)),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              ProfileAvatar(
                                name: name,
                                photoUrl: photoUrl,
                                size: 36,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const Text(
                                      'Administrator',
                                      style: TextStyle(
                                        color: Color(0xFFB5C9BF),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: onSignOut,
                            icon: const Icon(Icons.logout_rounded, size: 17),
                            label: const Text('Sign out'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFB5C9BF),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(child: body),
            ],
          ),
        ),
      );
    },
  );
}
