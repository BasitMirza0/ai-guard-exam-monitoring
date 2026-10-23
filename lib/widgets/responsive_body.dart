import 'package:flutter/material.dart';

/// Limits reading width on tablets without changing the route or its state.
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({
    super.key,
    required this.child,
    this.maxWidth = 1120,
    this.alignment = Alignment.center,
  });
  final Widget child;
  final double maxWidth;
  final AlignmentGeometry alignment;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    ),
  );
}

/// Headers participate in the same scroll as the lazy, independently updated list.
class DashboardBody extends StatelessWidget {
  const DashboardBody({super.key, required this.headers, required this.child});
  final List<Widget> headers;
  final Widget child;
  @override
  Widget build(BuildContext context) => ResponsiveBody(
    child: NestedScrollView(
      headerSliverBuilder:
          (_, __) =>
              headers
                  .map((header) => SliverToBoxAdapter(child: header))
                  .toList(),
      body: child,
    ),
  );
}

/// Stacks controls when their labels would be cramped, including enlarged text.
class AdaptiveRow extends StatelessWidget {
  const AdaptiveRow({
    super.key,
    required this.children,
    this.minItemWidth = 150,
  });
  final List<Widget> children;
  final double minItemWidth;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final items = children.where((child) => child is! SizedBox).toList();
      final scale = MediaQuery.textScalerOf(context).scale(1);
      if (constraints.maxWidth >=
          items.length * minItemWidth * scale.clamp(1.0, 1.5)) {
        return Row(children: children);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) const SizedBox(height: 12),
            items[index] is Flexible
                ? (items[index] as Flexible).child
                : items[index],
          ],
        ],
      );
    },
  );
}

class AdaptiveGrid extends StatelessWidget {
  const AdaptiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 180,
    this.maxColumns = 4,
  });
  final List<Widget> children;
  final double minItemWidth;
  final int maxColumns;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.5);
      final columns = ((constraints.maxWidth + 16) /
              (minItemWidth * scale + 16))
          .floor()
          .clamp(1, maxColumns);
      final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final child in children)
            SizedBox(
              width: width,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 150),
                child: child,
              ),
            ),
        ],
      );
    },
  );
}
