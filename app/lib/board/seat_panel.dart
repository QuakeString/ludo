import 'package:flutter/material.dart';

import '../theme/seat_colors.dart';
import 'die.dart';

/// One player's place at the table: who they are, how many chips they have
/// home, and their own spot for the die.
///
/// Every seat has a die place; only the seat on turn has a die in it. That is
/// the whole of "the die travels to whoever is next" — no animation needed for
/// it to read correctly, because the empty places make it obvious where it went
/// and where it came from.
class SeatPanel extends StatelessWidget {
  const SeatPanel({
    super.key,
    required this.arm,
    required this.name,
    required this.home,
    required this.total,
    required this.onTurn,
    this.isComputer = false,
    this.dice,
    this.timerDots = 0,
    this.dotsLit = 0,
    this.connected = true,
    this.awaitingRoll = false,
    this.onRoll,
    this.compact = false,
  });

  /// The arm this seat plays from — which is what decides its colour.
  final int arm;
  final String name;

  /// Chips finished, out of [total].
  final int home;
  final int total;

  final bool onTurn;

  /// Marked with a robot rather than spelled out in the name, which keeps the
  /// panel narrow enough for six of them to share a phone.
  final bool isComputer;

  /// The face showing, or null when this seat has not rolled.
  final int? dice;

  final int timerDots;
  final int dotsLit;
  final bool connected;

  /// This seat still has to roll. Drives the pointer at the die — and stops
  /// once the dice are down, because from then on the thing to do is move a
  /// chip, not roll again.
  final bool awaitingRoll;

  /// Set when this seat may roll right now — the die itself is the button,
  /// which is the shortest path between "it is my turn" and doing something.
  final VoidCallback? onRoll;

  /// Six seats have to fit two rows of three on a phone.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final colour = colourOfArm(arm);
    final die = RepaintBoundary(
      child: DieFace(
        value: dice,
        arm: arm,
        size: compact ? 44 : 54,
        live: onTurn,
        // The die is the roll button. There is no second one anywhere else.
        onTap: onRoll,
      ),
    );

    final panel = AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 9,
        vertical: compact ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: onTurn ? colour.withValues(alpha: 0.13) : palette.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: onTurn ? colour : palette.panelEdge,
          width: onTurn ? 1.6 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Avatar(arm: arm, compact: compact, robot: isComputer),
          SizedBox(width: compact ? 6 : 8),
          // Flexible, so a long name gives way rather than overflowing when
          // three panels share a phone's width at six seats.
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: compact ? 11 : 12.5,
                    fontWeight: onTurn ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                // Shrunk rather than overflowed. The chips-home count and the
                // turn clock are a fixed width, so a bigger die or a narrower
                // panel pushed them off the end — and an overflow stripe is
                // the one thing on screen worse than small text.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$home/$total',
                        style: TextStyle(
                          fontSize: compact ? 10 : 11,
                          color: palette.faint,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (onTurn && timerDots > 0) ...[
                        const SizedBox(width: 6),
                        for (var i = 0; i < timerDots; i++)
                          Container(
                            margin: const EdgeInsets.only(right: 2.5),
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < dotsLit
                                  ? colour
                                  : colour.withValues(alpha: 0.2),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 6 : 9),
          die,
        ],
      ),
    );

    return Opacity(
      opacity: connected ? 1 : 0.45,
      // The pointer sits outside the panel, in a stack that does not clip, so
      // it can appear and disappear without the panel changing size. Inside the
      // row it pushed the contents about every time the turn changed, and a
      // panel that grows and shrinks under your eye looks broken.
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerRight,
        children: [
          panel,
          if (awaitingRoll)
            Positioned(
              right: compact ? -26.0 : -32.0,
              // Deaf to touch, and that is the point. The pointer's box used to
              // reach back over the right-hand third of the die — an icon glyph
              // carries a lot of empty margin — so a tap anywhere but the die's
              // centre landed on the arrow and did nothing at all. It is
              // decoration; nothing about it should ever take a press.
              //
              // Boundaried, and this is not a micro-optimisation. Without it a
              // repaint of this one small arrow travels up to the nearest
              // boundary — the whole screen — and re-rasterises the entire
              // board sixty times a second. Measured: one full CPU core for an
              // arrow, and nothing at all once it is fenced off.
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: _RollPointer(colour: colour, compact: compact),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A chevron nudging toward the die of whoever has to roll.
///
/// It travels rather than blinks: a moving thing is found by the eye without
/// being looked for, which is the whole job of "it is your turn".
class _RollPointer extends StatefulWidget {
  const _RollPointer({required this.colour, required this.compact});

  final Color colour;
  final bool compact;

  @override
  State<_RollPointer> createState() => _RollPointerState();
}

class _RollPointerState extends State<_RollPointer>
    with SingleTickerProviderStateMixin {
  // Stepped seven times a second by a timer once, to save CPU. That was a bad
  // trade made on a bad measurement: the browser it was measured in renders
  // through SwiftShader, a software rasteriser, where every animated frame
  // costs a core no matter how little of the screen changes or how carefully
  // it is fenced behind a RepaintBoundary. On a machine with a GPU that work
  // is not on the CPU at all. So the number said "animation is ruinous" when
  // what it meant was "this container has no graphics card", and a visible
  // stutter was shipped to buy back nothing.
  //
  // A real sixty-frame slide, then. It runs only while somebody actually has
  // to roll, which is the honest saving — an idle screen animates nothing.
  late final AnimationController _travel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 820),
  )..repeat(reverse: true);

  late final Animation<double> _t = CurvedAnimation(
    parent: _travel,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _travel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Painted, not an icon. A glyph is a letter in a font: it comes with the
    // font's own margins baked in, so the box needed to draw an arrow this big
    // was half again as wide as the arrow, and that invisible half sat on top
    // of the die. Drawn directly, the box is the arrow.
    final w = widget.compact ? 20.0 : 26.0;
    final h = widget.compact ? 26.0 : 33.0;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Transform.translate(
        // Travels toward the die, which is to its left.
        offset: Offset(3 - _t.value * 9, 0),
        child: Opacity(opacity: 0.62 + 0.38 * _t.value, child: child),
      ),
      // Built once and carried through every frame: the shape does not change,
      // only where it is and how strongly it shows.
      child: CustomPaint(
        size: Size(w, h),
        painter: _Chevron(colour: widget.colour),
      ),
    );
  }
}

/// A solid triangle pointing left, with its corners taken off.
///
/// Rounded because a hard-cornered triangle at this size reads as a warning
/// sign; this one is only saying "over here".
class _Chevron extends CustomPainter {
  const _Chevron({required this.colour});

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = h * 0.16;
    final pts = <Offset>[
      Offset(0, h / 2), // the point
      Offset(w, 0),
      Offset(w, h),
    ];

    final path = Path();
    for (var i = 0; i < 3; i++) {
      final cur = pts[i];
      final prev = pts[(i + 2) % 3];
      final next = pts[(i + 1) % 3];
      final toPrev = prev - cur, toNext = next - cur;
      final a = cur + toPrev / toPrev.distance * r;
      final b = cur + toNext / toNext.distance * r;
      if (i == 0) {
        path.moveTo(a.dx, a.dy);
      } else {
        path.lineTo(a.dx, a.dy);
      }
      path.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
    }
    path.close();

    // A shadow under it, so it reads as sitting above the board rather than
    // printed on it.
    canvas.drawPath(
      path.shift(const Offset(0, 1.5)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(colour, Colors.white, 0.30)!,
            colour,
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_Chevron old) => old.colour != colour;
}

/// A place for a photo. Until profiles exist it is the seat's colour with an
/// initial, which is still a face rather than a blank.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.arm,
    required this.compact,
    required this.robot,
  });

  final int arm;
  final bool compact;
  final bool robot;

  @override
  Widget build(BuildContext context) {
    final r = compact ? 12.0 : 14.0;
    return CircleAvatar(
      radius: r,
      backgroundColor: colourOfArm(arm),
      child: Icon(
        robot ? Icons.smart_toy : Icons.person,
        size: r * 1.05,
        color: Colors.white,
      ),
    );
  }
}
