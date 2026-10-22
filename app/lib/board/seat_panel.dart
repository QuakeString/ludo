import 'package:flutter/material.dart';

import '../theme/seat_colors.dart';
import '../screens/avatars.dart';
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
    required this.arms,
    required this.name,
    required this.home,
    required this.total,
    required this.onTurn,
    this.isComputer = false,
    this.dice,
    this.turnLength,
    this.turnEndsAt,
    this.connected = true,
    this.awaitingRoll = false,
    this.onRoll,
    this.compact = false,
    this.pointerBelow = true,
    this.teamLetter,
    this.avatar,
    this.avatarKey,
    this.onAvatarTap,
  });

  /// Marks the picture, so things thrown at this seat know where to land.
  final Key? avatarKey;

  /// Tapping the picture: online, that is how you throw something at them.
  final VoidCallback? onAvatarTap;

  /// The player's picture, as [Avatar] writes it, or null for none.
  final String? avatar;

  /// The arm this seat plays from — which is what decides its colour.
  final int arm;

  /// How many arms the board has. The two boards seat the colours differently,
  /// so an arm number alone does not name a colour.
  final int arms;
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

  /// The whole of a turn, when turns are timed, and when this one runs out.
  /// The border of the seat on turn drains away as the time does.
  final Duration? turnLength;
  final DateTime? turnEndsAt;
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

  /// Which side this seat plays for, as the same letter written on its house.
  /// Null outside a team game, where there are no sides to tell apart.
  final String? teamLetter;

  /// Which side of the panel the roll pointer hangs off — down for a panel
  /// above the board, up for one below it. Either way it lands in the gap
  /// between this rail and the board, pointing back at the die.
  final bool pointerBelow;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final colour = colourOfArm(arm, arms);
    final die = RepaintBoundary(
      child: DieFace(
        value: dice,
        arm: arm,
        arms: arms,
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
        // The seat on turn gets a thick border, drawn over the edge by
        // [_TurnRing] so it can drain away with the clock.
        border: Border.all(
          color: onTurn ? Colors.transparent : palette.panelEdge,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Expanded, not Flexible: it takes the slack as well as giving it
          // up. Giving way keeps a long name from overflowing when three
          // panels share a phone at six seats; taking the slack is what holds
          // the die against the panel's right-hand edge, which is where the
          // arrow pointing at it is placed from.
          // No name here: it is written on the house itself, which leaves
          // the card room for a picture big enough to recognise.
          Expanded(
            child: Semantics(
              label: name,
              child: Row(
                children: [
                  GestureDetector(
                    key: avatarKey,
                    onTap: onAvatarTap,
                    child: AvatarBubble(
                      avatar: avatar,
                      colour: colour,
                      radius: _avatarRadius(compact),
                      robot: isComputer,
                    ),
                  ),
                  SizedBox(width: compact ? 4 : 6),
                  // Shrunk rather than overflowed, so a narrow card never
                  // shows an overflow stripe.
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (teamLetter != null) ...[
                            _TeamBadge(
                              letter: teamLetter!,
                              colour: colour,
                              compact: compact,
                            ),
                            const SizedBox(height: 3),
                          ],
                          Text(
                            '$home/$total',
                            style: TextStyle(
                              fontSize: compact ? 11 : 13,
                              fontWeight: FontWeight.w600,
                              color: palette.faint,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
        // The width it is given is the width it takes. A Stack loosens what it
        // passes down by default, so the panel sized itself to its own text
        // instead — and two panels in a column stopped lining up the moment
        // one seat's name was longer than the other's. "Yellow" sat hard
        // against the edge of the screen while "Red", directly above it, kept
        // a margin. Passed through, both are the width of the house they
        // belong to.
        fit: StackFit.passthrough,
        children: [
          // The whole card rolls, not just the die: a tap that lands a
          // little off the die still counts.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRoll,
            // Always in the tree, so a turn starting or ending never rebuilds
            // the die from scratch.
            child: RepaintBoundary(
              child: _TurnRing(
                on: onTurn,
                colour: colour,
                length: turnLength,
                endsAt: turnEndsAt,
                child: panel,
              ),
            ),
          ),
          if (awaitingRoll)
            Positioned(
              // Under the die, or over it — never off the panel's right-hand
              // end. Beside the die it fell clean off the screen for the seat
              // whose panel sits against the right edge, which on a six-handed
              // board is one seat in three: the arrow saying "you are the one
              // to roll" was the one thing that player could not see.
              //
              // Above and below there is always room, because the gap between
              // a rail and the board is the one piece of space that exists on
              // every screen this game runs on.
              right:
                  (compact ? 6.0 : 9.0) +
                  (compact ? 44.0 : 54.0) / 2 -
                  _pointerWidth(compact) / 2,
              top: pointerBelow ? null : -(_pointerHeight(compact) - 1),
              bottom: pointerBelow ? -(_pointerHeight(compact) - 1) : null,
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
                  child: _RollPointer(
                    colour: colour,
                    compact: compact,
                    pointUp: pointerBelow,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The narrowest a seat panel can be drawn without its contents colliding.
///
/// The avatar and the die are fixed sizes and the name between them can give
/// up all of its width, so this is simply the sum of the parts that cannot
/// shrink, plus a few pixels so the name is not always nothing. Stated here,
/// beside the numbers it is made of, because the layout that sizes panels to
/// the house they sit over has to know when a house has become too small to
/// hold one — on a short screen it does.
double _avatarRadius(bool compact) => compact ? 19 : 24;

// Padding, picture, gap, gap before the die, die, a little count.
double minPanelWidth(bool compact) => compact
    ? 12 + _avatarRadius(true) * 2 + 4 + 6 + 44 + 10
    : 18 + _avatarRadius(false) * 2 + 6 + 9 + 54 + 10;

/// The thick border round the seat on turn. With a turn clock it drains
/// away, clockwise from the top, as the time runs out; without one it stays
/// whole.
class _TurnRing extends StatefulWidget {
  const _TurnRing({
    required this.on,
    required this.colour,
    required this.length,
    required this.endsAt,
    required this.child,
  });

  /// Drawn only for the seat on turn.
  final bool on;
  final Color colour;
  final Duration? length;
  final DateTime? endsAt;
  final Widget child;

  static const width = 4.0;

  @override
  State<_TurnRing> createState() => _TurnRingState();
}

class _TurnRingState extends State<_TurnRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _left = AnimationController(
    vsync: this,
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_TurnRing old) {
    super.didUpdateWidget(old);
    if (old.on != widget.on ||
        old.endsAt != widget.endsAt ||
        old.length != widget.length) {
      _start();
    }
  }

  void _start() {
    final length = widget.length, endsAt = widget.endsAt;
    if (!widget.on ||
        length == null ||
        endsAt == null ||
        length <= Duration.zero) {
      _left.stop();
      _left.value = 1;
      return;
    }
    final remaining = endsAt.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _left.value = 0;
      return;
    }
    _left.value = (remaining.inMilliseconds / length.inMilliseconds).clamp(
      0,
      1,
    );
    _left.animateTo(0, duration: remaining, curve: Curves.linear);
  }

  @override
  void dispose() {
    _left.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: widget.on
          ? _RingPainter(colour: widget.colour, left: _left)
          : null,
      child: widget.child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.colour, required this.left})
    : super(repaint: left);

  final Color colour;
  final Animation<double> left;

  @override
  void paint(Canvas canvas, Size size) {
    const w = _TurnRing.width;
    final r = Rect.fromLTWH(w / 2, w / 2, size.width - w, size.height - w);
    const radius = 12.0 - w / 2;
    // Traced by hand from the top centre, so the drained part opens there.
    final path = Path()
      ..moveTo(r.center.dx, r.top)
      ..lineTo(r.right - radius, r.top)
      ..arcToPoint(
        Offset(r.right, r.top + radius),
        radius: const Radius.circular(radius),
      )
      ..lineTo(r.right, r.bottom - radius)
      ..arcToPoint(
        Offset(r.right - radius, r.bottom),
        radius: const Radius.circular(radius),
      )
      ..lineTo(r.left + radius, r.bottom)
      ..arcToPoint(
        Offset(r.left, r.bottom - radius),
        radius: const Radius.circular(radius),
      )
      ..lineTo(r.left, r.top + radius)
      ..arcToPoint(
        Offset(r.left + radius, r.top),
        radius: const Radius.circular(radius),
      )
      ..close();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    // The track the border drains from.
    canvas.drawPath(path, paint..color = colour.withValues(alpha: 0.18));
    final f = left.value;
    if (f <= 0) return;
    final metric = path.computeMetrics().first;
    final len = metric.length;
    canvas.drawPath(
      metric.extractPath(len * (1 - f), len),
      paint..color = colour,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.colour != colour || old.left != left;
}

double _pointerWidth(bool compact) => compact ? 22.0 : 28.0;
double _pointerHeight(bool compact) => compact ? 15.0 : 19.0;

/// How much clear space a rail needs on its board side for the roll pointer.
///
/// The pointer hangs outside the panel, and outside is somebody else's space:
/// the board is drawn after the rail, so an arrow poking into the board's rows
/// was simply painted over — a tip of it showed and the rest did not. Rather
/// than reach across two widgets to fix the paint order, the rail asks for the
/// room it needs and the arrow stays inside it.
///
/// It costs the board nothing on a phone held upright, where the board's size
/// is set by the screen's width and there is height to spare.
double rollPointerLane(bool compact) => _pointerHeight(compact) + 3;

/// A chevron nudging toward the die of whoever has to roll.
///
/// It travels rather than blinks: a moving thing is found by the eye without
/// being looked for, which is the whole job of "it is your turn".
class _RollPointer extends StatefulWidget {
  const _RollPointer({
    required this.colour,
    required this.compact,
    required this.pointUp,
  });

  final Color colour;
  final bool compact;

  /// True when the pointer sits below the die and points up at it.
  final bool pointUp;

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
  // 625ms each way, so a there-and-back is 1250ms — the same beat the house
  // border flushes on. Two things asking for the same thing at once should ask
  // in time with each other; at different speeds they read as two separate
  // pieces of nagging rather than one signal.
  late final AnimationController _travel = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 625),
    // Four there-and-backs, then it rests at the die. Five seconds of
    // nudging finds the eye; a pointer still sliding a minute later only
    // keeps the screen drawing — and the battery draining — for nobody.
  )..repeat(reverse: true, count: 8);

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
    final w = _pointerWidth(widget.compact);
    final h = _pointerHeight(widget.compact);
    final toward = widget.pointUp ? -1.0 : 1.0;

    return AnimatedBuilder(
      animation: _t,
      builder: (context, child) => Transform.translate(
        // Travels toward the die, which is above it or below it.
        offset: Offset(0, toward * (3 - _t.value * 8)),
        child: Opacity(opacity: 0.62 + 0.38 * _t.value, child: child),
      ),
      // Built once and carried through every frame: the shape does not change,
      // only where it is and how strongly it shows.
      child: CustomPaint(
        size: Size(w, h),
        painter: _Chevron(colour: widget.colour, pointUp: widget.pointUp),
      ),
    );
  }
}

/// A solid triangle, corners taken off, pointing up or down.
///
/// Rounded because a hard-cornered triangle at this size reads as a warning
/// sign; this one is only saying "over here".
class _Chevron extends CustomPainter {
  const _Chevron({required this.colour, required this.pointUp});

  final Color colour;
  final bool pointUp;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final r = w * 0.16;
    final pts = pointUp
        ? <Offset>[Offset(w / 2, 0), Offset(w, h), Offset(0, h)]
        : <Offset>[Offset(w / 2, h), Offset(0, 0), Offset(w, 0)];

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
          colors: [Color.lerp(colour, Colors.white, 0.30)!, colour],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_Chevron old) =>
      old.colour != colour || old.pointUp != pointUp;
}

/// The seat's side, as a letter.
class _TeamBadge extends StatelessWidget {
  const _TeamBadge({
    required this.letter,
    required this.colour,
    required this.compact,
  });

  final String letter;
  final Color colour;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final r = compact ? 13.0 : 15.0;
    return Container(
      width: r,
      height: r,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Outlined in the seat's colour rather than filled with it: filled, it
        // becomes a second avatar and the eye stops on it instead of reading
        // past it to the name.
        border: Border.all(color: colour.withValues(alpha: 0.75), width: 1.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        letter,
        style: TextStyle(
          fontSize: compact ? 8.5 : 9.5,
          fontWeight: FontWeight.w800,
          color: colour,
          height: 1,
        ),
      ),
    );
  }
}
