import 'dart:math' as math;

import 'package:ludo_engine/ludo_engine.dart';

/// A point in the board's unit square: (0,0) top-left, (1,1) bottom-right.
///
/// Keeping layout resolution-free means the same numbers drive a 5-inch phone,
/// a 27-inch monitor and a server-rendered PNG.
class Pt {
  const Pt(this.x, this.y);
  final double x;
  final double y;

  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator *(double k) => Pt(x * k, y * k);

  double get length => math.sqrt(x * x + y * y);

  @override
  String toString() => '(${x.toStringAsFixed(4)}, ${y.toStringAsFixed(4)})';

  @override
  bool operator ==(Object other) =>
      other is Pt && (other.x - x).abs() < 1e-9 && (other.y - y).abs() < 1e-9;

  @override
  int get hashCode => Object.hash(x, y);
}

/// A square on the board, positioned and oriented.
class CellShape {
  const CellShape({
    required this.centre,
    required this.size,
    this.rotation = 0,
  });

  final Pt centre;

  /// Edge length, as a fraction of the board's width.
  final double size;

  /// Radians clockwise. Always 0 on the cross board; arms of the hexagon are
  /// rotated so their squares run along the arm.
  final double rotation;
}

/// A triangle, used for home bases and the wedges of the centre.
class Tri {
  const Tri(this.a, this.b, this.c);
  final Pt a;
  final Pt b;
  final Pt c;
  List<Pt> get points => [a, b, c];
}

/// Where everything sits, for one board shape.
///
/// The engine says *what* is legal; this says *where* it is drawn. Splitting
/// them means the rules can be tested without pixels and the layout can be
/// tested without a rendering framework.
abstract class BoardGeometry {
  factory BoardGeometry.forSpec(BoardSpec spec) =>
      spec.arms == 4 ? CrossGeometry(spec) : HexGeometry(spec);

  BoardSpec get spec;

  /// Edge length of one track square, as a fraction of the board width.
  double get cellSize;

  /// Where a token sits, for any progress value including -1 (its yard).
  /// [slot] picks which of the four yard places an idle token rests in.
  Pt tokenAt(int arm, int progress, {int slot = 0});

  /// The square at a ring index, for drawing the track.
  CellShape ringCell(int ringIndex);

  /// A square of a seat's home column, 0-based from the outside in.
  CellShape homeCell(int arm, int homeIndex);

  /// The square a seat turns off the ring into its home column — the one
  /// carrying the arrow.
  CellShape turnInCell(int arm);

  /// Where a seat's idle tokens wait. Always four, whatever the token count.
  List<Pt> yardSlots(int arm);

  /// Outline of the home base a seat's yard sits in.
  Tri yardShape(int arm);

  /// The board's outer edge.
  List<Pt> plateOutline();

  /// The centre, split one wedge per arm.
  List<Tri> centreWedges();

  /// Where a seat's die rests.
  Pt dicePlace(int arm);

  /// Ring indices carrying a safe star.
  List<int> starRingIndices();
}

/// The classic 15x15 cross, for two to four seats.
class CrossGeometry implements BoardGeometry {
  CrossGeometry(this.spec) : assert(spec.arms == 4);

  @override
  final BoardSpec spec;

  static const grid = 15;

  /// The 52 ring squares in travel order, starting at arm 0's start square.
  ///
  /// Written out rather than derived: the classic board's path is a specific
  /// shape, and a table anyone can check beats a clever loop nobody can.
  static const List<List<int>> ringCells = [
    // out along row 6 from arm 0's start
    [1, 6], [2, 6], [3, 6], [4, 6], [5, 6],
    // up column 6
    [6, 5], [6, 4], [6, 3], [6, 2], [6, 1], [6, 0],
    [7, 0], // across the top
    // down column 8
    [8, 0], [8, 1], [8, 2], [8, 3], [8, 4], [8, 5],
    // right along row 6
    [9, 6], [10, 6], [11, 6], [12, 6], [13, 6], [14, 6],
    [14, 7], // down the right edge
    // left along row 8
    [14, 8], [13, 8], [12, 8], [11, 8], [10, 8], [9, 8],
    // down column 8
    [8, 9], [8, 10], [8, 11], [8, 12], [8, 13], [8, 14],
    [7, 14], // across the bottom
    // up column 6
    [6, 14], [6, 13], [6, 12], [6, 11], [6, 10], [6, 9],
    // left along row 8
    [5, 8], [4, 8], [3, 8], [2, 8], [1, 8], [0, 8],
    [0, 7], // up the left edge
    [0, 6],
  ];

  /// Top-left corner of each arm's 6x6 yard block.
  static const yardOrigins = [
    [0, 0], // arm 0 (left arm) — its start square is (1,6)
    [9, 0], // arm 1 (top)
    [9, 9], // arm 2 (right)
    [0, 9], // arm 3 (bottom)
  ];

  @override
  double get cellSize => 1 / grid;

  Pt _cellCentre(int col, int row) =>
      Pt((col + 0.5) / grid, (row + 0.5) / grid);

  @override
  CellShape ringCell(int ringIndex) {
    final c = ringCells[ringIndex % ringCells.length];
    return CellShape(centre: _cellCentre(c[0], c[1]), size: cellSize);
  }

  @override
  CellShape homeCell(int arm, int homeIndex) {
    final i = homeIndex + 1; // column runs from just inside the edge, inwards
    return switch (arm) {
      0 => CellShape(centre: _cellCentre(i, 7), size: cellSize),
      1 => CellShape(centre: _cellCentre(7, i), size: cellSize),
      2 => CellShape(centre: _cellCentre(14 - i, 7), size: cellSize),
      _ => CellShape(centre: _cellCentre(7, 14 - i), size: cellSize),
    };
  }

  @override
  CellShape turnInCell(int arm) =>
      ringCell((spec.startRing(arm) + spec.trackLength - 2) % spec.trackLength);

  @override
  Pt tokenAt(int arm, int progress, {int slot = 0}) {
    if (progress < 0) return yardSlots(arm)[slot % 4];
    if (spec.isFinished(progress)) return const Pt(0.5, 0.5);
    final home = spec.homeIndex(progress);
    if (home != null) return homeCell(arm, home).centre;
    return ringCell(spec.ringIndex(arm, progress)!).centre;
  }

  @override
  List<Pt> yardSlots(int arm) {
    final o = yardOrigins[arm];
    return [
      for (final d in const [
        [1.9, 1.9],
        [4.1, 1.9],
        [1.9, 4.1],
        [4.1, 4.1],
      ])
        Pt((o[0] + d[0]) / grid, (o[1] + d[1]) / grid)
    ];
  }

  /// The cross board's yards are square, so this reports the block's corners
  /// as a degenerate triangle-free shape via [yardSquare] instead.
  @override
  Tri yardShape(int arm) {
    final o = yardOrigins[arm];
    return Tri(
      Pt(o[0] / grid, o[1] / grid),
      Pt((o[0] + 6) / grid, o[1] / grid),
      Pt((o[0] + 6) / grid, (o[1] + 6) / grid),
    );
  }

  /// Top-left and bottom-right of a seat's yard block.
  (Pt, Pt) yardSquare(int arm) {
    final o = yardOrigins[arm];
    return (
      Pt(o[0] / grid, o[1] / grid),
      Pt((o[0] + 6) / grid, (o[1] + 6) / grid),
    );
  }

  @override
  List<Pt> plateOutline() => const [Pt(0, 0), Pt(1, 0), Pt(1, 1), Pt(0, 1)];

  @override
  List<Tri> centreWedges() {
    const c = Pt(0.5, 0.5);
    final lo = 6 / grid, hi = 9 / grid;
    return [
      Tri(Pt(lo, lo), Pt(lo, hi), c), // arm 0, left
      Tri(Pt(lo, lo), Pt(hi, lo), c), // arm 1, top
      Tri(Pt(hi, lo), Pt(hi, hi), c), // arm 2, right
      Tri(Pt(lo, hi), Pt(hi, hi), c), // arm 3, bottom
    ];
  }

  /// On the cross board the die rests in the middle of its own yard.
  @override
  Pt dicePlace(int arm) {
    final o = yardOrigins[arm];
    return Pt((o[0] + 3) / grid, (o[1] + 3) / grid);
  }

  @override
  List<int> starRingIndices() =>
      [for (var a = 0; a < spec.arms; a++) spec.starRing(a)];
}

/// The hexagon, for five or six seats: a twelve-sided plate, six arms, a
/// six-sided centre and triangular home bases whose apexes meet its corners.
///
/// Radii are in the design's own 660-unit space and divided through at the end,
/// so the numbers here match the drawings exactly.
class HexGeometry implements BoardGeometry {
  HexGeometry(this.spec) : assert(spec.arms == 6);

  @override
  final BoardSpec spec;

  static const _u = 660.0; // design space, normalised away on output
  static const _c = 30.0; // cell edge
  static const _centre = 330.0;

  /// Outermost track row. The innermost then lands at 94, which is what makes
  /// the track continuous — see the note on [_armSlotFor].
  static const _rOut = 244.0;
  static const _hub = 90.0; // centre hexagon circumradius
  static const _plate = 282.0; // twelve-gon circumradius
  static const _yardIn = 90.0; // apex — sits exactly on a hub corner
  static const _yardOut = 247.0;
  static const _yardHalfWidth = 70.0;
  static const _dieR = 297.0;

  /// (radius, lateral offset) of the four resting places in a home base.
  static const _slots = [
    [183.0, 0.0],
    [211.0, -24.0],
    [211.0, 24.0],
    [223.0, 0.0],
  ];

  @override
  double get cellSize => _c / _u;

  double _armAngle(int arm) => -90 + 60.0 * arm;
  double _yardAngle(int arm) => _armAngle(arm) + 30;

  /// Polar placement: [radius] out along [angleDeg], then [lateral] sideways.
  Pt _pt(double angleDeg, double radius, [double lateral = 0]) {
    final a = angleDeg * math.pi / 180;
    final ux = math.cos(a), uy = math.sin(a);
    return Pt(
      (_centre + ux * radius - uy * lateral) / _u,
      (_centre + uy * radius + ux * lateral) / _u,
    );
  }

  /// Which arm, lane and row a track square occupies.
  ///
  /// Rows run inwards: row 0 is the tip, row 5 the innermost. Lane +1 is the
  /// side facing the seat's own home base, lane −1 the far side, lane 0 the
  /// middle (the tip square and, below it, the home column).
  ///
  /// The thirteen squares of a seat's sector mirror the classic cross exactly:
  /// five inward down its own near lane, a diagonal step into the *next* arm's
  /// far lane, six back outward, then that arm's tip and near-tip square. The
  /// diagonal step is the whole reason the innermost row sits at radius 94 —
  /// solving `r² − 103.94r + 2701 = (1.41·30)²` puts the two facing squares
  /// exactly one diagonal apart. At the 102 the first draft used they were
  /// 1.7 squares apart and the track simply did not join up.
  ///
  /// Travel runs from arm k to arm k+1, matching the order the engine numbers
  /// start squares in, and a seat's home base sits beside the lane it starts
  /// on — the +1 lane, at angle armAngle + 30.
  static ({int arm, int lane, int row}) _slotFor(int sector, int within) {
    final next = (sector + 1) % 6; // the arm the path carries on into
    if (within < 5) return (arm: sector, lane: 1, row: within + 1);
    if (within < 11) return (arm: next, lane: -1, row: 10 - within);
    if (within == 11) return (arm: next, lane: 0, row: 0);
    return (arm: next, lane: 1, row: 0);
  }

  @override
  CellShape ringCell(int ringIndex) {
    final idx = ringIndex % spec.trackLength;
    final slot = _slotFor(idx ~/ spec.squaresPerArm, idx % spec.squaresPerArm);
    final ang = _armAngle(slot.arm);
    return CellShape(
      centre: _pt(ang, _rOut - slot.row * _c, slot.lane * _c),
      size: cellSize,
      rotation: (ang + 90) * math.pi / 180,
    );
  }

  @override
  CellShape homeCell(int arm, int homeIndex) {
    final ang = _armAngle(arm);
    return CellShape(
      centre: _pt(ang, _rOut - (homeIndex + 1) * _c),
      size: cellSize,
      rotation: (ang + 90) * math.pi / 180,
    );
  }

  @override
  CellShape turnInCell(int arm) {
    final ang = _armAngle(arm);
    return CellShape(
      centre: _pt(ang, _rOut),
      size: cellSize,
      rotation: (ang + 90) * math.pi / 180,
    );
  }

  @override
  Pt tokenAt(int arm, int progress, {int slot = 0}) {
    if (progress < 0) return yardSlots(arm)[slot % 4];
    if (spec.isFinished(progress)) return const Pt(0.5, 0.5);
    final home = spec.homeIndex(progress);
    if (home != null) return homeCell(arm, home).centre;
    return ringCell(spec.ringIndex(arm, progress)!).centre;
  }

  @override
  List<Pt> yardSlots(int arm) {
    final ya = _yardAngle(arm);
    return [for (final s in _slots) _pt(ya, s[0], s[1])];
  }

  @override
  Tri yardShape(int arm) {
    final ya = _yardAngle(arm);
    return Tri(
      _pt(ya, _yardIn),
      _pt(ya, _yardOut, -_yardHalfWidth),
      _pt(ya, _yardOut, _yardHalfWidth),
    );
  }

  @override
  List<Pt> plateOutline() => [
        // Twelve sides: vertices every 30 degrees, offset so six edges face
        // the arms and six face the home bases.
        for (var i = 0; i < 12; i++) _pt(-105 + 30.0 * i, _plate)
      ];

  /// The centre hexagon's corners — each one is also a home base's apex.
  List<Pt> centreOutline() =>
      [for (var i = 0; i < 6; i++) _pt(-120 + 60.0 * i, _hub)];

  @override
  List<Tri> centreWedges() => [
        for (var k = 0; k < 6; k++)
          Tri(const Pt(0.5, 0.5), _pt(-120 + 60.0 * k, _hub),
              _pt(-60 + 60.0 * k, _hub))
      ];

  @override
  Pt dicePlace(int arm) => _pt(_yardAngle(arm), _dieR);

  @override
  List<int> starRingIndices() =>
      [for (var a = 0; a < spec.arms; a++) spec.starRing(a)];
}
