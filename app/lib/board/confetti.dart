import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/seat_colors.dart';

/// Paper thrown in the air when somebody wins.
///
/// It falls, tumbles, and then it is over: the controller runs once and stops,
/// rather than looping for as long as the screen is open. A celebration that
/// never ends is not a celebration, and on the web every animated frame costs
/// whatever the machine charges for one.
class Confetti extends StatefulWidget {
  const Confetti({super.key, this.pieces = 90, this.seed = 7});

  final int pieces;
  final int seed;

  @override
  State<Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<Confetti>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fall = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  )..forward();

  late final List<_Piece> _paper = _make();

  List<_Piece> _make() {
    final rnd = math.Random(widget.seed);
    return [
      for (var i = 0; i < widget.pieces; i++)
        _Piece(
          x: rnd.nextDouble(),
          // Staggered above the top edge, so they arrive in a shower rather
          // than a single curtain.
          y: -0.15 - rnd.nextDouble() * 0.85,
          drift: (rnd.nextDouble() - 0.5) * 0.35,
          fall: 0.75 + rnd.nextDouble() * 0.75,
          spin: (rnd.nextDouble() - 0.5) * 9,
          phase: rnd.nextDouble() * math.pi * 2,
          size: 0.010 + rnd.nextDouble() * 0.012,
          colour: seatColors[rnd.nextInt(seatColors.length)],
          narrow: rnd.nextDouble() < 0.5,
        ),
    ];
  }

  @override
  void dispose() {
    _fall.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _fall,
          builder: (context, _) => CustomPaint(
            painter: _ConfettiPainter(_paper, _fall.value),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _Piece {
  const _Piece({
    required this.x,
    required this.y,
    required this.drift,
    required this.fall,
    required this.spin,
    required this.phase,
    required this.size,
    required this.colour,
    required this.narrow,
  });

  final double x, y, drift, fall, spin, phase, size;
  final Color colour;
  final bool narrow;
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.paper, this.t);

  final List<_Piece> paper;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final fade = t < 0.82 ? 1.0 : (1 - (t - 0.82) / 0.18).clamp(0.0, 1.0);
    for (final p in paper) {
      final y = p.y + p.fall * t * 1.5;
      if (y < -0.2 || y > 1.2) continue;
      // Paper does not fall straight: it slides sideways as it turns over.
      final sway = math.sin(p.phase + t * 7) * 0.035;
      final x = p.x + p.drift * t + sway;

      canvas.save();
      canvas.translate(x * size.width, y * size.height);
      canvas.rotate(p.phase + p.spin * t);
      // Foreshortened as it tumbles, which is what makes a flat scrap read as
      // paper rather than as a falling dot.
      final flat = math.cos(p.phase * 2 + t * 11).abs().clamp(0.15, 1.0);
      final w = p.size * size.shortestSide * (p.narrow ? 0.6 : 1.0);
      final h = p.size * size.shortestSide * 1.7 * flat;
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: w, height: h),
        Paint()..color = p.colour.withValues(alpha: fade),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.t != t;
}
