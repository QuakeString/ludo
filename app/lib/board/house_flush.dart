import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

import 'board_painter.dart';

/// The house of whoever has to roll, its border flushing deep and pale.
///
/// A soft halo around the house was the first attempt at this and it was
/// nearly invisible: a glow on a light board is a smudge, and a still one says
/// nothing at all. The house already wears a thick band of its player's
/// colour, so the band does the signalling itself — the same colour going dark
/// and light. Nothing is added to the board; what is already there moves.
///
/// Painted over the board rather than in it, and fenced behind its own
/// boundary. The board is a finished picture, and re-rasterising all of it
/// sixty times a second to make one border breathe is what cost a whole CPU
/// core the last time something on the board animated.
class HouseFlush extends StatelessWidget {
  const HouseFlush({
    super.key,
    required this.geometry,
    required this.arm,
    required this.colour,
    required this.side,
    required this.beat,
  });

  final BoardGeometry geometry;

  /// The house to light up — the position, not the seat.
  final int arm;
  final Color colour;

  /// The board's square, in pixels.
  final double side;

  /// Repeating 0 to 1. Two flushes per turn of it, which at the shared 2.5s
  /// ticker is a beat and a quarter each — slow enough to read as breathing
  /// rather than blinking.
  final Animation<double> beat;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: beat,
        builder: (context, _) => CustomPaint(
          size: Size.square(side),
          painter: _FlushPainter(
            geometry: geometry,
            arm: arm,
            colour: colour,
            t: beat.value,
          ),
        ),
      ),
    );
  }
}

class _FlushPainter extends CustomPainter {
  _FlushPainter({
    required this.geometry,
    required this.arm,
    required this.colour,
    required this.t,
  });

  final BoardGeometry geometry;
  final int arm;
  final Color colour;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    Offset px(Pt p) => Offset(p.x * s, p.y * s);
    final cell = geometry.cellSize * s;

    final wave = (1 - math.cos(t * 4 * math.pi)) / 2;
    final tone = Color.lerp(
      Color.lerp(colour, Colors.black, 0.34)!,
      Color.lerp(colour, Colors.white, 0.48)!,
      wave,
    )!;

    // The band is the house minus its own interior — exactly the shape the
    // board painter fills with the seat's colour, so this lands on top of it
    // and nowhere else.
    final band = Path()..fillType = PathFillType.evenOdd;
    final g = geometry;
    if (g is CrossGeometry) {
      final (tl, br) = g.yardSquare(arm);
      final rect = Rect.fromPoints(px(tl), px(br));
      band
        ..addRect(rect)
        ..addRect(rect.deflate(cell));
    } else {
      final tri = g.yardShape(arm);
      final outer = [px(tri.a), px(tri.b), px(tri.c)];
      final centroid = Offset(
        outer.map((o) => o.dx).reduce((a, b) => a + b) / 3,
        outer.map((o) => o.dy).reduce((a, b) => a + b) / 3,
      );
      band
        ..addPolygon(outer, true)
        ..addPolygon([
          for (final o in outer) centroid + (o - centroid) * houseInset,
        ], true);
    }
    canvas.drawPath(band, Paint()..color = tone);
  }

  @override
  bool shouldRepaint(_FlushPainter old) =>
      old.t != t || old.arm != arm || old.colour != colour;
}
