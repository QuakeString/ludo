import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../theme/seat_colors.dart';

/// How long a die tumbles before it settles.
///
/// Shared rather than private because the turn flow has to outlast it: a roll
/// that decides nothing still has to show its number, and a hold shorter than
/// the tumble shows no number at all.
const int dieRollMillis = 780;

/// A real die: a cube, projected, not a square with dots on it.
///
/// The eight corners are carried in 3D and rotated properly, so the roll is an
/// actual tumble rather than a picture being swapped. That also means the three
/// faces you can see are genuinely the three faces of a cube in that
/// orientation — the shading and the foreshortening come out on their own.
class DieFace extends StatefulWidget {
  const DieFace({
    super.key,
    required this.value,
    required this.arm,
    this.size = 42,
    this.live = false,
    this.onTap,
    this.mute = false,
  });

  /// The number showing, or null when this seat has not rolled.
  final int? value;

  /// The board position this die belongs to.
  final int arm;
  final double size;

  /// Whether this seat is the one on turn.
  final bool live;

  /// Set when tapping the die should roll it.
  final VoidCallback? onTap;

  /// Suppresses the rattle — for previews and tests.
  final bool mute;

  @override
  State<DieFace> createState() => _DieFaceState();
}

class _DieFaceState extends State<DieFace> with SingleTickerProviderStateMixin {
  late final AnimationController _roll = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: dieRollMillis),
  );

  AudioPlayer? _player;

  /// Where the tumble starts from, so each roll looks different.
  double _fromX = 0, _fromY = 0;
  int _spin = 0;

  /// The face left showing. A real die on a table always shows a number — a
  /// blank cube reads as something failing to load rather than as a die
  /// waiting to be thrown.
  int _showing = 1;

  @override
  void initState() {
    super.initState();
    // A die that is not being thrown rests, tilted, on its place. 0 is the
    // *start* of a throw — leaving it there points the cube straight at the
    // camera, and a cube seen straight on is a square.
    _roll.value = 1;
    if (widget.value != null) _showing = widget.value!;
  }

  @override
  void didUpdateWidget(DieFace old) {
    super.didUpdateWidget(old);
    // A number appearing where there was none is a roll. A number changing is
    // also a roll — the same face twice running still gets thrown.
    if (widget.value != null && widget.value != old.value) {
      _showing = widget.value!;
      _startTumble();
    }
  }

  void _startTumble() {
    // Vary the throw so two rolls never animate identically. Derived from the
    // value and the tick count rather than a random source, so a widget test
    // sees the same thing twice.
    final salt = (widget.value ?? 1) * 7 + _roll.hashCode % 5;
    _fromX = -2.2 - (salt % 3) * 0.6;
    _fromY = 1.8 + (salt % 4) * 0.5;
    _spin = 2 + salt % 2;
    _roll.forward(from: 0);
    _rattle();
  }

  Future<void> _rattle() async {
    if (widget.mute) return;
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      await player.play(AssetSource('sounds/dice_roll.wav'), volume: 0.55);
    } catch (_) {
      // No audio device, a browser that has not had a gesture yet, a test —
      // none of which is a reason for the dice not to roll.
    }
  }

  @override
  void dispose() {
    _roll.dispose();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);

    // Not this seat's turn: an empty place, waiting for the die to come round.
    if (!widget.live) {
      return _EmptyPlace(size: widget.size, palette: palette);
    }

    final die = AnimatedBuilder(
      animation: _roll,
      builder: (context, _) => CustomPaint(
        size: Size.square(widget.size),
        painter: _CubePainter(
          value: _showing,
          colour: colourOfArm(widget.arm),
          face: palette.die,
          pip: palette.pip,
          t: _roll.value,
          fromX: _fromX,
          fromY: _fromY,
          spin: _spin,
        ),
      ),
    );

    return widget.onTap == null
        ? die
        : GestureDetector(
            // A stable handle for whoever needs to find the roll control —
            // tests, and later an accessibility action.
            key: rollDieKey,
            onTap: widget.onTap,
            behavior: HitTestBehavior.opaque,
            child: die,
          );
  }
}

/// The die that can be tapped to roll, when there is one.
const rollDieKey = ValueKey<String>('roll-die');

/// The number a settled die actually shows when it has been rolled [value].
///
/// Exposed so a test can assert the one thing a die must never get wrong: the
/// number you read off it is the number that was rolled. It got this wrong for
/// 2 and 5 — the chip moved the right distance while the face showed the
/// number on the opposite side.
int faceShownFor(int value) {
  final (rx, ry) = _CubePainter._restFor(value);
  var best = 0;
  var bestZ = double.negativeInfinity;
  for (var f = 0; f < 6; f++) {
    final z = _CubePainter._rotate(_CubePainter._normalOf(f), rx, ry)[2];
    if (z > bestZ) {
      bestZ = z;
      best = f;
    }
  }
  return _CubePainter._values[best];
}

/// The resting place of a seat that does not currently hold the die.
class _EmptyPlace extends StatelessWidget {
  const _EmptyPlace({required this.size, required this.palette});

  final double size;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Container(
          width: size * 0.62,
          height: size * 0.62,
          decoration: BoxDecoration(
            border: Border.all(color: palette.dieEdge, width: 1),
            borderRadius: BorderRadius.circular(size * 0.10),
          ),
        ),
      ),
    );
  }
}

/// Draws the cube.
///
/// A real Ludo die is a rounded, glossy, ivory thing with coloured pips — not a
/// box with hard corners. Three details do most of that work here: the corners
/// and edges are rounded, the faces are lit rather than flat-filled, and a
/// specular highlight sits where the light is coming from.
///
/// The rounding is done by drawing the silhouette in the bright edge tone and
/// then laying each face on top, inset and rounded. What shows through between
/// the faces *is* the rounded edge, which is both simpler and more convincing
/// than trying to model a filleted cube.
class _CubePainter extends CustomPainter {
  _CubePainter({
    required this.value,
    required this.colour,
    required this.face,
    required this.pip,
    required this.t,
    required this.fromX,
    required this.fromY,
    required this.spin,
  });

  final int value;
  final Color colour;
  final Color face;
  final Color pip;

  /// 0 at the start of the throw, 1 when it has settled.
  final double t;
  final double fromX, fromY;
  final int spin;

  /// Opposite faces of a die sum to seven. +Z is 1, so -Z is 6, and so on.
  static const _faces = <List<int>>[
    [0, 1, 2, 3], // +Z
    [5, 4, 7, 6], // -Z
    [1, 5, 6, 2], // +X
    [4, 0, 3, 7], // -X
    [4, 5, 1, 0], // -Y (up on screen, y grows downward)
    [3, 2, 6, 7], // +Y
  ];
  static const _values = [1, 6, 3, 4, 2, 5];

  static const _corners = <List<double>>[
    [-1, -1, 1],
    [1, -1, 1],
    [1, 1, 1],
    [-1, 1, 1],
    [-1, -1, -1],
    [1, -1, -1],
    [1, 1, -1],
    [-1, 1, -1],
  ];

  /// Ludo dice are not all-black: the one is blue and the four is red. Small
  /// thing, but it is the difference between "a die" and "the die on the table
  /// next to the board".
  static Color _pipColour(int n, Color ink) => switch (n) {
    1 => const Color(0xFF1B3FAE),
    4 => const Color(0xFFD32F2F),
    _ => ink,
  };

  /// The rotation that brings a given number to the front.
  /// Screen y grows downward, so the face marked 2 sits at -Y and needs a
  /// *negative* turn about X to come forward. Having those two signs the wrong
  /// way round swapped 2 and 5 on the settled die: the chip moved the number
  /// that was rolled while the die showed the number opposite it.
  static (double, double) _restFor(int v) => switch (v) {
    1 => (0, 0),
    6 => (0, math.pi),
    3 => (0, -math.pi / 2),
    4 => (0, math.pi / 2),
    2 => (-math.pi / 2, 0),
    _ => (math.pi / 2, 0),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final half = s * 0.31;
    final centre = Offset(size.width / 2, size.height / 2);

    // The throw tumbles in three dimensions, and then the die lands square to
    // the camera. A number read off a corner-on cube is a number you have to
    // work out; the point of the roll is the answer, so the answer is shown
    // flat. The 3D is in the throw, not in the result.
    final (restX, restY) = _restFor(value);

    final settle = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
    final rx = _lerp(fromX - spin * math.pi * 2, restX, settle);
    final ry = _lerp(fromY + spin * math.pi * 2, restY, settle);

    // A throw arcs: the die lifts and drops back onto its place.
    final hop = math.sin(math.pi * t.clamp(0.0, 1.0)) * s * 0.17;

    Offset project(List<double> v) {
      final p = _rotate(v, rx, ry);
      // Weak perspective — enough to read as a solid, not so much that the
      // near face balloons and the die turns into a truncated pyramid.
      final k = 7.0 / (7.0 - p[2]);
      return centre + Offset(p[0] * half * k, p[1] * half * k - hop);
    }

    final projected = [for (final c in _corners) project(c)];

    // Contact shadow, so the die sits on its place rather than floating over
    // it. It tightens as the die comes down.
    final drop = 1 - math.sin(math.pi * t.clamp(0.0, 1.0));
    canvas.drawOval(
      Rect.fromCenter(
        center: centre + Offset(s * 0.03, half * 0.98),
        width: half * (1.5 + 0.5 * drop),
        height: half * 0.34 * (0.7 + 0.3 * drop),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.16 * (0.45 + 0.55 * drop))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.05),
    );

    // The silhouette, rounded, in the bright tone the edges catch.
    final hull = _convexHull(projected);
    final body = _rounded(hull, half * 0.30);
    canvas.drawPath(body, Paint()..color = _lighten(face, 0.5));

    final visible = <int>[];
    for (var f = 0; f < 6; f++) {
      final quad = [for (final i in _faces[f]) projected[i]];
      if (!_isBackFacing(quad)) visible.add(f);
    }

    for (final f in visible) {
      final quad = [for (final i in _faces[f]) projected[i]];
      final normal = _rotate(_normalOf(f), rx, ry);
      final inset = _shrink(quad, half * 0.16);
      canvas.drawPath(
        _rounded(inset, half * 0.22),
        Paint()..color = _shade(face, normal),
      );
      _pips(canvas, inset, _values[f], normal);
    }

    // Gloss: a soft sheen across the upper half, and a small hard highlight
    // where the light actually is. Clipped to the body so it wraps the die.
    canvas.save();
    canvas.clipPath(body);
    final bounds = body.getBounds();
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.42),
            Colors.white.withValues(alpha: 0.0),
            Colors.black.withValues(alpha: 0.06),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(bounds),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center:
            bounds.topLeft + Offset(bounds.width * 0.36, bounds.height * 0.20),
        width: bounds.width * 0.30,
        height: bounds.height * 0.16,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.03),
    );
    canvas.restore();

    // No coloured rim. A Ludo die is ivory; whose turn it is, is already said
    // by the panel around it, and a tinted outline just makes the die look
    // like a game token rather than a die.
  }

  /// Pips laid on the face itself, so they foreshorten with it.
  void _pips(Canvas canvas, List<Offset> quad, int n, List<double> normal) {
    final origin = quad[0];
    final a = quad[1] - origin;
    final b = quad[3] - origin;
    final lit = _light(normal);
    final ink = _pipColour(n, pip);

    canvas.save();
    // Map the unit square onto the face, so a circle drawn here comes out as
    // the ellipse that face would show.
    canvas.transform(
      Float64List.fromList([
        a.dx, a.dy, 0, 0, //
        b.dx, b.dy, 0, 0, //
        0, 0, 1, 0, //
        origin.dx, origin.dy, 0, 1,
      ]),
    );
    for (final o in _pipLayout[n]!) {
      final at = Offset(0.5 + o[0] * 0.225, 0.5 + o[1] * 0.225);
      // Pips are sunk into the face: a dark rim below, the colour above.
      canvas.drawCircle(
        at.translate(0, 0.012),
        0.092,
        Paint()..color = Colors.black.withValues(alpha: 0.22),
      );
      canvas.drawCircle(
        at,
        0.086,
        Paint()..color = Color.lerp(ink, Colors.black, (1 - lit) * 0.45)!,
      );
      canvas.drawCircle(
        at.translate(-0.019, -0.019),
        0.027,
        Paint()..color = Colors.white.withValues(alpha: 0.22),
      );
    }
    canvas.restore();
  }

  // --- shading ---------------------------------------------------------------

  static double _light(List<double> n) {
    // A light up and to the left. The spread matters more than the level:
    // three faces within a few percent of each other read as one flat shape,
    // however correct the geometry underneath is.
    const lx = -0.35, ly = -0.78, lz = 0.52;
    final d = n[0] * lx + n[1] * ly + n[2] * lz;
    return (0.66 + 0.34 * d).clamp(0.46, 1.0);
  }

  Color _shade(Color base, List<double> normal) {
    final l = _light(normal);
    // Toward a warm grey, not toward black — that is what keeps the shaded
    // sides reading as the same ivory material as the lit top.
    final dark = Color.lerp(base, const Color(0xFF8A8175), 0.85)!;
    return Color.lerp(dark, base, l)!;
  }

  static Color _lighten(Color base, double amount) =>
      Color.lerp(base, Colors.white, amount)!;

  // --- geometry --------------------------------------------------------------

  /// Pulls a polygon's corners toward its centre, leaving room for the rounded
  /// edge to show between neighbouring faces.
  static List<Offset> _shrink(List<Offset> quad, double by) {
    final c = quad.reduce((a, b) => a + b) / quad.length.toDouble();
    return [
      for (final p in quad)
        (p - c).distance <= by ? c : c + (p - c) * (1 - by / (p - c).distance),
    ];
  }

  /// A polygon with its corners rounded off.
  static Path _rounded(List<Offset> pts, double radius) {
    final path = Path();
    final n = pts.length;
    for (var i = 0; i < n; i++) {
      final cur = pts[i];
      final prev = pts[(i - 1 + n) % n];
      final next = pts[(i + 1) % n];
      final toPrev = prev - cur, toNext = next - cur;
      final lp = toPrev.distance, ln = toNext.distance;
      if (lp == 0 || ln == 0) continue;
      final r = math.min(radius, math.min(lp, ln) / 2);
      final a = cur + toPrev / lp * r;
      final b = cur + toNext / ln * r;
      if (i == 0) {
        path.moveTo(a.dx, a.dy);
      } else {
        path.lineTo(a.dx, a.dy);
      }
      path.quadraticBezierTo(cur.dx, cur.dy, b.dx, b.dy);
    }
    path.close();
    return path;
  }

  /// The outline of the projected cube — six of the eight corners, in order.
  static List<Offset> _convexHull(List<Offset> pts) {
    final sorted = [...pts]
      ..sort(
        (a, b) => a.dx == b.dx ? a.dy.compareTo(b.dy) : a.dx.compareTo(b.dx),
      );
    double cross(Offset o, Offset a, Offset b) =>
        (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

    final lower = <Offset>[];
    for (final p in sorted) {
      while (lower.length >= 2 &&
          cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Offset>[];
    for (final p in sorted.reversed) {
      while (upper.length >= 2 &&
          cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  static List<double> _normalOf(int f) => switch (f) {
    0 => [0, 0, 1],
    1 => [0, 0, -1],
    2 => [1, 0, 0],
    3 => [-1, 0, 0],
    4 => [0, -1, 0],
    _ => [0, 1, 0],
  };

  static bool _isBackFacing(List<Offset> quad) {
    // Signed area tells which way a face is wound on screen. Screen y grows
    // downward, so a face turned toward the viewer comes out *positive* — the
    // opposite of the usual maths-axes intuition, and worth stating because
    // getting it backwards draws the inside of the cube, which looks like
    // folded paper rather than a die.
    var area = 0.0;
    for (var i = 0; i < quad.length; i++) {
      final p = quad[i], q = quad[(i + 1) % quad.length];
      area += p.dx * q.dy - q.dx * p.dy;
    }
    return area <= 0;
  }

  static List<double> _rotate(List<double> v, double rx, double ry) {
    final cy = math.cos(ry), sy = math.sin(ry);
    final x1 = v[0] * cy + v[2] * sy;
    final z1 = -v[0] * sy + v[2] * cy;
    final cx = math.cos(rx), sx = math.sin(rx);
    final y2 = v[1] * cx - z1 * sx;
    final z2 = v[1] * sx + z1 * cx;
    return [x1, y2, z2];
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  static const _pipLayout = <int, List<List<double>>>{
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

  @override
  bool shouldRepaint(_CubePainter old) =>
      old.t != t ||
      old.value != value ||
      old.colour != colour ||
      old.face != face;
}
