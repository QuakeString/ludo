import 'package:flutter/material.dart';

import '../theme/seat_colors.dart';

/// A die, drawn rather than imaged so it stays crisp at any size and can take
/// the seat's colour.
///
/// It lives in a seat's panel beside the board, never on it. A die drawn on the
/// board has to sit somewhere, and every somewhere is either a square a chip
/// can occupy or a home base — which is how it ended up painted on top of four
/// chips.
class DieFace extends StatelessWidget {
  const DieFace({
    super.key,
    required this.value,
    required this.seat,
    this.size = 34,
    this.live = false,
  });

  /// 1..6, or 0 for a die not yet rolled.
  final int value;
  final int seat;
  final double size;

  /// Whether this seat is the one on turn — a live die is bigger and outlined
  /// in the seat's colour, so the die visibly belongs to somebody.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DiePainter(
          value: value,
          colour: seatColors[seat],
          face: live ? palette.die : palette.dieIdle,
          edge: live ? seatColors[seat] : palette.dieEdge,
          pip: palette.pip,
          live: live,
        ),
      ),
    );
  }
}

class _DiePainter extends CustomPainter {
  _DiePainter({
    required this.value,
    required this.colour,
    required this.face,
    required this.edge,
    required this.pip,
    required this.live,
  });

  final int value;
  final Color colour;
  final Color face;
  final Color edge;
  final Color pip;
  final bool live;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final centre = Offset(size.width / 2, size.height / 2);
    final box = Rect.fromCenter(
      center: centre,
      width: s * 0.86,
      height: s * 0.86,
    );
    final rr = RRect.fromRectAndRadius(box, Radius.circular(s * 0.18));

    if (live) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          box.inflate(s * 0.06),
          Radius.circular(s * 0.24),
        ),
        Paint()
          ..color = colour
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.055,
      );
    }
    canvas.drawRRect(rr, Paint()..color = face);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = edge
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.04,
    );

    if (value >= 1 && value <= 6) {
      for (final o in pips[value]!) {
        canvas.drawCircle(
          centre + Offset(o[0] * s * 0.22, o[1] * s * 0.22),
          s * 0.082,
          Paint()..color = pip,
        );
      }
    } else {
      // Not rolled yet: a resting place rather than a face.
      canvas.drawCircle(
        centre,
        s * 0.075,
        Paint()..color = pip.withValues(alpha: 0.25),
      );
    }
  }

  @override
  bool shouldRepaint(_DiePainter old) =>
      old.value != value || old.live != live || old.colour != colour;

  static const pips = <int, List<List<double>>>{
    1: [
      [0, 0],
    ],
    2: [
      [-1, -1],
      [1, 1],
    ],
    3: [
      [-1, -1],
      [0, 0],
      [1, 1],
    ],
    4: [
      [-1, -1],
      [1, -1],
      [-1, 1],
      [1, 1],
    ],
    5: [
      [-1, -1],
      [1, -1],
      [0, 0],
      [-1, 1],
      [1, 1],
    ],
    6: [
      [-1, -1],
      [1, -1],
      [-1, 0],
      [1, 0],
      [-1, 1],
      [1, 1],
    ],
  };
}
