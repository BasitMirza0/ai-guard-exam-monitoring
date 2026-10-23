import 'package:flutter/material.dart';
import '../branding/brand_mark.dart';
import '../theme/app_theme.dart';

/// Static rules with a separately anchored action. Wide, short displays use two
/// columns; exceptionally small viewports scale only the rules to fit.
class ExamInstructions extends StatelessWidget {
  const ExamInstructions({
    super.key,
    required this.onBegin,
    this.error,
    this.onRetry,
    this.monitoringNotice,
  });
  final VoidCallback? onBegin;
  final String? error;
  final VoidCallback? onRetry;
  final String? monitoringNotice;

  static const _rules = [
    (
      Icons.face_outlined,
      'Keep your face visible',
      'Face the camera throughout the exam.',
    ),
    (
      Icons.visibility_outlined,
      'Keep your eyes on screen',
      'Looking away triggers a warning.',
    ),
    (
      Icons.phone_android_outlined,
      'No mobile phones',
      'Phone detection ends the exam immediately.',
    ),
    (
      Icons.person_outline,
      'Stay alone',
      'Other people in frame will end the exam.',
    ),
    (
      Icons.devices_outlined,
      'No external materials',
      'Laptops, monitors and books are not allowed.',
    ),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final short = bounds.maxHeight < 500;
      final wide = bounds.maxWidth >= 620;
      final padding = short ? 12.0 : 24.0;
      return ColoredBox(
        color: AppColors.background,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const BrandMark(size: 36),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'AI Guard',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  SizedBox(height: short ? 4 : 20),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, area) {
                        final contentWidth = area.maxWidth;
                        final rules = <Widget>[
                          Text(
                            'Before you begin',
                            style: TextStyle(
                              fontSize: short ? 24 : 30,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Read the rules for a smooth, fair exam.',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
                          ),
                          if (monitoringNotice != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              monitoringNotice!,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: AppColors.muted,
                              ),
                            ),
                          ],
                          SizedBox(height: short ? 12 : 20),
                          for (final rule in _rules)
                            Padding(
                              padding: EdgeInsets.only(bottom: short ? 8 : 14),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: AppColors.primarySoft,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      rule.$1,
                                      size: 20,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          rule.$2,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          rule.$3,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            height: 1.4,
                                            color: AppColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ];
                        const note = Text(
                          'When the exam starts, look straight at the camera for 2 seconds to calibrate your position.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: AppColors.primary,
                          ),
                        );
                        final information = Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.primarySoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: note,
                        );
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: contentWidth,
                              child:
                                  wide && short
                                      ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: rules,
                                            ),
                                          ),
                                          const SizedBox(width: 24),
                                          Expanded(child: information),
                                        ],
                                      )
                                      : Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [...rules, information],
                                      ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (error != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            error!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: onRetry,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: onBegin,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(
                        onBegin == null ? 'Preparing exam…' : 'Begin Exam',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
