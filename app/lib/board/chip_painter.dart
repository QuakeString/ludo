import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Draws the game chip.
///
/// A carrom-style pawn lit from the upper left with a hard white rim — the rim
/// is what keeps a blue chip readable on a blue square, which is where most
/// Ludo apps fall down. Drawn as vector geometry so one shape recolours for
/// all six seats and stays sharp at every density.
///
/// Everything is authored in a 100 x 132 box and scaled, so the proportions
/// match the design spec exactly.
class ChipArt {
  /// Silhouette of the body: flared base, waist, collar shelf.
  static final Path _body = Path()
    ..moveTo(16, 114)
    ..cubicTo(16, 102, 30, 96, 37, 82)
    ..cubicTo(40, 76, 40, 70, 38, 64)
    ..lineTo(62, 64)
    ..cubicTo(60, 70, 60, 76, 63, 82)
    ..cubicTo(70, 96, 84, 102, 84, 114)
    ..cubicTo(84, 121, 16, 121, 16, 114)
    ..close();

  static final Rect _collar = Rect.fromCenter(
    center: const Offset(50, 62),
    width: 38,
    height: 12,
  );
  static const Offset _head = Offset(50, 40);
  static const double _headR = 22;

  /// Where the chip meets the board, in authoring units.
  static const Offset groundPoint = Offset(50, 117);

  /// Height of the drawn chip as a multiple of its width — useful for laying
  /// out hit areas and stacks.
  static const double aspect = 1.32;

  /// Paints a chip whose base rests on [ground], [width] wide.
  ///
  /// [lift] raises it off the board (for a hop or a selection), shrinking and
  /// fading the contact shadow the way a real lifted piece would.
  static void paint(
    Canvas canvas,
    Offset ground,
    double width,
    Color color, {
    double lift = 0,
    double squash = 1,
    double scale = 1,
    double spin = 0,
    double fade = 1,
    int? badge,
    Color rim = Colors.white,
  }) {
    final s = width * scale / 100;
    canvas.save();
    canvas.translate(ground.dx, ground.dy);

    // Contact shadow stays on the board while the chip rises.
    final shadowScale = (1 - lift / (width * 2.4)).clamp(0.35, 1.0);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: 62 * s * shadowScale,
        height: 17 * s * shadowScale,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.26 * shadowScale),
    );

    canvas.translate(0, -lift);
    canvas.scale(2 - squash, squash);
    // A spin reads as rotation about the chip's own axis, so it foreshortens
    // horizontally rather than tipping over.
    if (spin != 0) canvas.scale(math.cos(spin).abs().clamp(0.15, 1.0), 1);
    canvas.scale(s);
    canvas.translate(-groundPoint.dx, -groundPoint.dy);

    // White rim: stroke every part first so the outline reads as one union,
    // then fill on top. Stroking after filling would leave a seam where the
    // head meets the collar.
    final rimPaint = Paint()
      ..color = rim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeJoin = StrokeJoin.round;
    final rimFill = Paint()..color = rim;
    for (final draw in [rimPaint, rimFill]) {
      canvas.drawPath(_body, draw);
      canvas.drawOval(_collar, draw);
      canvas.drawCircle(_head, _headR, draw);
    }

    final base = Paint()
      ..color = fade >= 1 ? color : color.withValues(alpha: fade);
    canvas.drawPath(_body, base);
    _shade(canvas, _body.getBounds(), (p) => canvas.drawPath(_body, p));
    canvas.drawOval(_collar, Paint()..color = _darken(color, 0.78));
    canvas.drawCircle(_head, _headR, base);
    _shade(
      canvas,
      Rect.fromCircle(center: _head, radius: _headR),
      (p) => canvas.drawCircle(_head, _headR, p),
    );

    // One specular highlight, upper left — a single light source for the
    // whole board.
    canvas.save();
    canvas.translate(42, 32);
    canvas.rotate(-0.49);
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 18, height: 13),
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, 9, [
          Colors.white.withValues(alpha: 0.75),
          Colors.white.withValues(alpha: 0),
        ]),
    );
    canvas.restore();

    if (badge != null) _paintBadge(canvas, badge);
    canvas.restore();
  }

  /// Left-to-right light-to-dark wash, so every part is lit consistently.
  static void _shade(Canvas canvas, Rect bounds, void Function(Paint) draw) {
    draw(
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(bounds.left, bounds.center.dy),
          Offset(bounds.right, bounds.center.dy),
          [
            Colors.white.withValues(alpha: 0.34),
            Colors.white.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.30),
          ],
          const [0, 0.45, 1],
        ),
    );
  }

  /// Three or more chips on a square collapse to one chip plus a count.
  static void _paintBadge(Canvas canvas, int count) {
    const centre = Offset(80, 100);
    canvas.drawCircle(centre, 21, Paint()..color = Colors.white);
    canvas.drawCircle(centre, 19, Paint()..color = const Color(0xFF2A2622));
    final tp = TextPainter(
      text: TextSpan(
        text: '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  static Color _darken(Color c, double f) => Color.fromARGB(
    (c.a * 255).round(),
    (c.r * 255 * f).round(),
    (c.g * 255 * f).round(),
    (c.b * 255 * f).round(),
  );

  /// The ring that says "this chip can move now".
  ///
  /// Drawn under the chip in the seat's own colour, so a glance answers both
  /// questions at once: where your chips are, and which of them this roll can
  /// actually move.
  static void paintLegalRing(
    Canvas canvas,
    Offset ground,
    double width,
    Color color, {
    double pulse = 0,
  }) {
    final r = width * 0.66;
    canvas.drawCircle(
      ground,
      r + width * 0.14,
      Paint()..color = color.withValues(alpha: 0.13),
    );
    canvas.drawCircle(
      ground,
      r,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 0.09,
    );
    if (pulse > 0) {
      canvas.drawCircle(
        ground,
        r * (1 + 0.4 * pulse),
        Paint()
          ..color = color.withValues(alpha: 0.75 * (1 - pulse))
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 0.08,
      );
    }
  }
}
