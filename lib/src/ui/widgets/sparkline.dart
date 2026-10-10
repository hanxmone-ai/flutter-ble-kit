import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A small line chart of recent values, newest on the right.
class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.capacity = 60, this.height = 72});

  final List<num> values;

  /// How many points fit across the width.
  final int capacity;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          capacity: capacity,
          line: scheme.primary,
          fill: scheme.primary.withValues(alpha: 0.12),
          grid: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.capacity,
    required this.line,
    required this.fill,
    required this.grid,
  });

  final List<num> values;
  final int capacity;
  final Color line;
  final Color fill;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.length < 2) return;
    final lo = values.reduce(math.min).toDouble() - 3;
    final hi = values.reduce(math.max).toDouble() + 3;
    final step = size.width / (capacity - 1);
    final start = size.width - step * (values.length - 1);
    Offset point(int i) => Offset(
          start + step * i,
          size.height - (values[i] - lo) / (hi - lo) * size.height,
        );
    final path = Path()..moveTo(point(0).dx, point(0).dy);
    for (var i = 1; i < values.length; i++) {
      final p = point(i);
      path.lineTo(p.dx, p.dy);
    }
    final area = Path.from(path)
      ..lineTo(point(values.length - 1).dx, size.height)
      ..lineTo(start, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(point(values.length - 1), 3.5, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => true;
}
