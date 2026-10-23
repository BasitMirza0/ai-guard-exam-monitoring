import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The same vector geometry is used in launcher assets and the in-app brand.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 48, this.tile = true});
  final double size;
  final bool tile;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'AI Guard',
    image: true,
    child: RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _MarkPainter(tile: tile)),
      ),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.tile});
  final bool tile;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 64, size.height / 64);
    if (tile) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 64, 64),
          const Radius.circular(16),
        ),
        Paint()..color = AppColors.primary,
      );
    }
    final stroke =
        Paint()
          ..color = const Color(0xFFF5F4E8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final shield =
        Path()
          ..moveTo(32, 12)
          ..lineTo(49, 19)
          ..lineTo(49, 33)
          ..cubicTo(49, 44, 42, 51, 32, 56)
          ..cubicTo(22, 51, 15, 44, 15, 33)
          ..lineTo(15, 19)
          ..close();
    canvas.drawPath(shield, stroke);
    canvas.drawPath(
      Path()
        ..moveTo(24, 40)
        ..lineTo(32, 26)
        ..lineTo(40, 40),
      stroke,
    );
    canvas.drawLine(
      const Offset(28, 35),
      const Offset(36, 35),
      stroke..color = const Color(0xFFB9DAC8),
    );
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => oldDelegate.tile != tile;
}
