import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class WorkspaceAction extends StatelessWidget {
  const WorkspaceAction({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.onTap,
    this.featured = false,
  });
  final String title, description;
  final IconData icon;
  final VoidCallback onTap;
  final bool featured;
  @override
  Widget build(BuildContext context) => Material(
    color: featured ? AppColors.primary : Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: featured ? AppColors.primary : AppColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      // A route-opening ripple would freeze offstage and resume on Back.
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    featured
                        ? Colors.white.withValues(alpha: .1)
                        : AppColors.subtle,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                size: 24,
                color: featured ? Colors.white : AppColors.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: featured ? Colors.white : AppColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: TextStyle(
                      color:
                          featured ? const Color(0xFFC5D6CC) : AppColors.muted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_rounded,
              size: 19,
              color: featured ? const Color(0xFFC5D6CC) : AppColors.primary,
            ),
          ],
        ),
      ),
    ),
  );
}

class AnalysisHeader extends StatelessWidget {
  const AnalysisHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
  final String title, subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppColors.primary, size: 24),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -.8,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 14,
            height: 1.6,
            color: AppColors.muted,
          ),
        ),
      ],
    ),
  );
}

class ConnectionStatus extends StatelessWidget {
  const ConnectionStatus({
    super.key,
    required this.online,
    required this.onRetry,
    this.checking = false,
  });
  final bool online, checking;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.subtle,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: checking ? null : onRetry,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            if (checking)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                online
                    ? Icons.check_circle_outline_rounded
                    : Icons.cloud_off_outlined,
                size: 18,
                color: online ? AppColors.primary : AppColors.muted,
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                checking
                    ? 'Connecting to analysis service…'
                    : online
                    ? 'Analysis service connected'
                    : 'Service unavailable. Tap to retry.',
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppColors.muted,
                ),
              ),
            ),
            if (!checking)
              const Icon(
                Icons.refresh_rounded,
                size: 18,
                color: AppColors.muted,
              ),
          ],
        ),
      ),
    ),
  );
}
