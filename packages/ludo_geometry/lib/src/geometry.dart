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
  Pt tokenAt(int arm, int progress, {int slot = 0, int yardCount = 4});

  /// The square at a ring index, for drawing the track.
  CellShape ringCell(int ringIndex);

  /// A square of a seat's home column, 0-based from the outside in.
  CellShape homeCell(int arm, int homeIndex);

  /// The square a seat turns off the ring into its home column — the one
  /// carrying the arrow.
  CellShape turnInCell(int arm);

  /// Where a seat's idle chips wait, arranged for however many it has.
  ///
  /// The arrangement is the point, not the count: chips in a house stand in
  /// the shape of the house. Four make a triangle with one in the middle,
  /// three make the triangle alone, two stand side by side. Laying out three
  /// in four fixed places leaves a hole where the missing chip was, which
  /// reads as a chip already gone rather than as a seat that plays with three.
  List<Pt> yardSlots(int arm, {int count = 4});

  /// Outline of the home base a seat's yard sits in.
  Tri yardShape(int arm);

  /// The board's outer edge.
  List<Pt> plateOutline();

  /// The centre, split one wedge per arm.
  List<Tri> centreWedges();

  /// Ring indices carrying a safe star.
  List<int> starRingIndices();
}

/// Where a finished token rests: inside its own wedge of the centre.
///
/// Every seat used to send its finished chips to the exact middle, so a red
/// chip and a blue one that had both got home sat on top of each other with
/// nothing to say whose was whose. Each wedge is that seat's colour already —
/// the chips belong in it.
Pt homeRest(BoardGeometry g, int arm) {
  final wedge = g.centreWedges()[arm % g.centreWedges().length];
  const centre = Pt(0.5, 0.5);
  // The wedge is a triangle with its point at the middle of the board; its
  // other two corners are the outer edge.
  final outer = Pt((wedge.a.x + wedge.b.x) / 2, (wedge.a.y + wedge.b.y) / 2);
  // Most of the way out, so the chips sit in the wide part of the wedge rather
  // than crowding its point.
  const t = 0.58;
  return Pt(
    centre.x + (outer.x - centre.x) * t,
    centre.y + (outer.y - centre.y) * t,
  );
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
  Pt tokenAt(int arm, int progress, {int slot = 0, int yardCount = 4}) {
    if (progress < 0) {
      final slots = yardSlots(arm, count: yardCount);
      return slots[slot % slots.length];
    }
    if (spec.isFinished(progress)) return homeRest(this, arm);
    final home = spec.homeIndex(progress);
    if (home != null) return homeCell(arm, home).centre;
    return ringCell(spec.ringIndex(arm, progress)!).centre;
  }

  @override
  List<Pt> yardSlots(int arm, {int count = 4}) {
    final o = yardOrigins[arm];
    // In the block's own six-by-six grid. A square house has no apex to build
    // a triangle on, so four sit in a square and the smaller counts borrow the
    // same idea: a triangle for three, a level pair for two.
    final places = switch (count) {
      <= 1 => const [
          [3.0, 3.0],
        ],
      2 => const [
          [1.9, 3.0],
          [4.1, 3.0],
        ],
      3 => const [
          [3.0, 1.85],
          [1.85, 4.1],
          [4.15, 4.1],
        ],
      _ => const [
          [1.9, 1.9],
          [4.1, 1.9],
          [1.9, 4.1],
          [4.1, 4.1],
        ],
    };
    return [
      for (final d in places) Pt((o[0] + d[0]) / grid, (o[1] + d[1]) / grid)
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

  // Design space, normalised away on output. Every radius below is measured in
  // it, so shrinking the unit scales the whole board up about its centre —
  // cells, track and plate together, leaving the spacing between neighbouring
  // squares untouched.
  //
  // It was 660, which left a ring of empty space outside the plate for the
  // seats' dice to sit in. The dice moved off the board into the seat panels,
  // so that ring is now just margin, and the board takes it back.
  // 560 rather than 600 because the plate is no longer a fat regular twelve-gon
  // reaching 282: its corners now sit on the track at 262.9. Everything here is
  // in board units where a square is 30 across, so shrinking the reference
  // simply scales the whole board back up to fill the space it is given.
  static const _u = 560.0;
  static const _c = 30.0; // cell edge
  static const _centre = _u / 2;

  /// Outermost track row. The innermost then lands at 94, which is what makes
  /// the track continuous — see the note on [_armSlotFor].
  static const _rOut = 244.0;
  static const _hub = 90.0; // centre hexagon circumradius
  static const _yardIn = 90.0; // apex — sits exactly on a hub corner

  /// The outer corner of an outermost track square: half a square past the
  /// last row, and one and a half squares off the arm's axis. The plate's
  /// corners are exactly these, which is what makes everything else land.
  static const _rimOut = _rOut + _c / 2; // 259
  static const _rimSide = _c * 1.5; // 45

  /// (radius, lateral offset) of a chip's resting place in a home base.
  ///
  /// The house is an equilateral triangle 181 across, sitting between radius
  /// 90 and 246.8, so its centroid is at 194.53 and each of its three points
  /// is 104.53 away from that. The chips stand 36% of the way out to those
  /// points — far enough that the three of them read as a triangle, near
  /// enough to leave a clear band of house around them.
  ///
  /// It was half way out, which put a chip's edge four units off the painted
  /// border: the chips looked flung into the corners rather than set down in
  /// the middle of a house. At 36% that gap is about twelve.
  static const _slotMiddle = [194.53, 0.0];
  static const _slotPoints = [
    [156.90, 0.0], // toward the apex, pointing at the middle of the board
    [213.35, -32.59], // and toward each corner of the base
    [213.35, 32.59],
  ];

  /// Two chips stand across the house rather than on two of its three points,
  /// which would read as a triangle with a piece missing.
  static const _slotPair = [
    [194.53, -28.0],
    [194.53, 28.0],
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
  Pt tokenAt(int arm, int progress, {int slot = 0, int yardCount = 4}) {
    if (progress < 0) {
      final slots = yardSlots(arm, count: yardCount);
      return slots[slot % slots.length];
    }
    if (spec.isFinished(progress)) return homeRest(this, arm);
    final home = spec.homeIndex(progress);
    if (home != null) return homeCell(arm, home).centre;
    return ringCell(spec.ringIndex(arm, progress)!).centre;
  }

  @override
  List<Pt> yardSlots(int arm, {int count = 4}) {
    final ya = _yardAngle(arm);
    final places = switch (count) {
      <= 1 => const [_slotMiddle],
      2 => _slotPair,
      3 => _slotPoints,
      _ => [..._slotPoints, _slotMiddle],
    };
    return [for (final s in places) _pt(ya, s[0], s[1])];
  }

  @override
  Tri yardShape(int arm) {
    // Apex on a hub corner, base on the plate's own long edge — the two plate
    // corners either side of this house. Because those corners are the track's
    // own outer corners, the two long sides of the triangle lie exactly along
    // the outer edge of the lane on each side: no gap to the board's rim, and
    // no white wedge between a house and the path beside it.
    final plate = plateOutline();
    return Tri(
      _pt(_yardAngle(arm), _yardIn),
      plate[(1 + 2 * arm) % 12],
      plate[(2 + 2 * arm) % 12],
    );
  }

  @override
  List<Pt> plateOutline() => [
        // Twelve sides, deliberately not equal. Each corner is the outer
        // corner of an outermost track square, which gives six short sides —
        // one across the end of each arm, exactly as wide as the three squares
        // behind it — and six long ones, each spanning a house.
        //
        // A regular twelve-gon was the mistake. It forced every house onto a
        // 146-wide base while the arm it sat beside only ever filled 90 of its
        // own, so the houses read as bigger than the paths, and a house long
        // enough to reach the hub came out as a sliver. Built this way a house
        // is 181 across, its sides run flush along the outer edge of the track
        // lanes either side of it, and the triangle falls out equilateral to
        // within a fortieth of a unit — without anybody having to solve for it.
        for (var a = 0; a < 6; a++) ...[
          _pt(_armAngle(a), _rimOut, -_rimSide),
          _pt(_armAngle(a), _rimOut, _rimSide),
        ]
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
  List<int> starRingIndices() =>
      [for (var a = 0; a < spec.arms; a++) spec.starRing(a)];
}
