import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The ring around a chip that can move, as a widget rather than a repaint.
///
/// Drawn once into a cached layer and then *rotated*. That distinction is the
/// whole point: repainting the ring means the engine redraws a frame, and on
/// the web a frame costs the whole surface however little of it changed.
/// Turning a layer that already exists is a transform, which the compositor
/// can do without asking anything to paint again.
class TurningRing extends StatelessWidget {
  const TurningRing({
    super.key,
    required this.diameter,
    required this.colour,
    required this.turns,
  });

  final double diameter;
  final Color colour;
  final Animation<double> turns;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RotationTransition(
        turns: turns,
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.square(diameter),
            painter: _DashedRing(colour),
          ),
        ),
      ),
    );
  }
}

class _DashedRing extends CustomPainter {
  _DashedRing(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final width = size.shortestSide;
    final r = width * 0.34;

    // A soft disc underneath lifts the ring off a busy square.
    canvas.drawCircle(
      centre,
      r + width * 0.08,
      Paint()..color = colour.withValues(alpha: 0.13),
    );

    const dashes = 10;
    final sweep = math.pi * 2 / dashes;
    final gap = sweep * 0.42;
    final rect = Rect.fromCircle(center: centre, radius: r);

    // A white dash under the coloured one, so a blue ring on a blue house can
    // still be seen.
    final halo = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 0.082
      ..strokeCap = StrokeCap.round;
    final ink = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 0.05
      ..strokeCap = StrokeCap.round;

    for (final paint in [halo, ink]) {
      for (var i = 0; i < dashes; i++) {
        canvas.drawArc(rect, i * sweep, sweep - gap, false, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRing old) => old.colour != colour;
}
