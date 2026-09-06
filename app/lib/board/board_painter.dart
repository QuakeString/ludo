import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

import '../theme/seat_colors.dart';
import 'chip_layout.dart';
import 'chip_painter.dart';
import 'move_animation.dart';

/// Which slice of the board a painter draws.
///
/// Split so the still parts can sit inside RepaintBoundaries and the moving
/// parts cannot force them to be drawn again. Caching the *drawing commands*
/// is not enough — replaying them still rasterises every square, every frame.
enum BoardLayer { furniture, glow, chips, motions }

/// How far in the painted interior of a hexagon house sits from its outline.
///
/// The gap between the two is the house's coloured border, and it carries the
/// seat's colour at the size the eye actually picks it out from across the
/// board — so it is worth a few percent of the house. Shared with whatever
/// else draws that border, because two numbers meaning one thing drift.
const double houseInset = 0.74;

/// How much of a square a chip takes up.
///
/// Both numbers went up: on a phone a chip was a bead you had to look for
/// rather than a piece you could see, and the six-arm board — whose squares
/// are the smaller of the two to begin with — was where it was worst. The
/// hexagon still gets the smaller share because its track bends, so two chips
/// on neighbouring squares sit closer together than two on a straight run.
double chipShare(int arms) => arms == 4 ? 0.88 : 0.78;

/// Draws a whole board from engine state plus geometry.
///
/// The painter knows nothing about rules — it asks the engine what is legal and
/// the geometry where things go, then draws. That is what lets the same widget
/// render the four-seat cross and the six-seat hexagon without a branch in
/// sight beyond the shapes themselves.
class BoardPainter extends CustomPainter {
  BoardPainter({
    required this.state,
    required this.geometry,
    required this.palette,
    required this.legalMoves,
    this.pulse = 0,
    this.motions = const {},
    this.glowSeat,
    this.layer = BoardLayer.furniture,
  });

  final GameState state;
  final BoardGeometry geometry;
  final BoardPalette palette;
  final List<Move> legalMoves;

  /// 0..1, drives the ring's outward pulse.
  final double pulse;

  /// The seat whose house should glow — set only while they still have to
  /// roll, so the board asks for a roll and then stops asking.
  final int? glowSeat;

  /// Tokens in flight, keyed by token id. These are lifted out of the static
  /// layout and drawn last, so a hopping chip passes over the board rather
  /// than under whatever it is hopping towards.
  final Map<int, ChipMotion> motions;

  final BoardLayer layer;

  BoardSpec get spec => state.board;

  /// The projector for the paint currently running, so helpers below can map
  /// board coordinates without every one of them taking it as an argument.
  Offset Function(Pt)? _lastPx;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2);
    Offset px(Pt p) => origin + Offset(p.x * side, p.y * side);
    _lastPx = px;
    final cell = geometry.cellSize * side;

    switch (layer) {
      case BoardLayer.furniture:
        _paintPlate(canvas, px, side);
        _paintTrack(canvas, px, cell);
        _paintHomeColumns(canvas, px, cell);
        _paintStars(canvas, px, cell);
        _paintTurnInArrows(canvas, px, cell);
        _paintCentre(canvas, px);
        _paintYards(canvas, px, cell);
      case BoardLayer.glow:
        _paintGlow(canvas, px, cell);
      case BoardLayer.chips:
        // Above the house flush, which is painted between the furniture and
        // here and repaints the very band the letters sit on — drawn with the
        // furniture they were there in a still and gone the moment a seat took
        // its turn, which is exactly when you look. Under the chips, though:
        // this is the seat's own corner and the chips have first claim on it.
        _paintTeamMarks(canvas, px, cell);
        _paintChips(canvas, px, cell);
      case BoardLayer.motions:
        _paintMotions(canvas, px, cell);
    }
  }

  /// Chips mid-move, drawn above everything else.
  void _paintMotions(Canvas canvas, Offset Function(Pt) px, double cell) {
    if (motions.isEmpty) return;
    final chipWidth = cell * chipShare(spec.arms);
    for (final entry in motions.entries) {
      final token = state.tokens[entry.key];
      final m = entry.value;
      final colour = colourOfArm(state.armOf(token.owner), spec.arms);

      // The streak the chip leaves behind it, in its own colour, thinning and
      // fading with age. Drawn oldest first and under the chip, so it reads as
      // one stroke rather than a row of dots.
      for (var i = m.trail.length - 1; i >= 0; i--) {
        final age = (i + 1) / m.trail.length; // 1 is the oldest
        canvas.drawCircle(
          px(m.trail[i]),
          chipWidth * 0.46 * (1 - age * 0.66),
          Paint()..color = colour.withValues(alpha: 0.46 * (1 - age)),
        );
      }

      ChipArt.paint(
        canvas,
        px(m.ground),
        chipWidth,
        colour,
        lift: m.lift * chipWidth * 0.7,
        squash: m.squash,
        scale: m.scale,
        spin: m.spin,
        fade: m.fade,
      );
    }
  }

  // --- board furniture -----------------------------------------------------

  void _paintPlate(Canvas canvas, Offset Function(Pt) px, double side) {
    final outline = geometry.plateOutline();
    final path = Path()..addPolygon([for (final p in outline) px(p)], true);
    canvas.drawPath(path, Paint()..color = palette.plate);
    canvas.drawPath(
      path,
      Paint()
        ..color = palette.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = side * 0.003,
    );
  }

  void _paintCell(
    Canvas canvas,
    CellShape shape,
    Offset Function(Pt) px,
    double cell,
    Color fill,
  ) {
    canvas.save();
    canvas.translate(px(shape.centre).dx, px(shape.centre).dy);
    if (shape.rotation != 0) canvas.rotate(shape.rotation);
    final r = Rect.fromCenter(center: Offset.zero, width: cell, height: cell);
    canvas.drawRect(r, Paint()..color = fill);
    canvas.drawRect(
      r,
      Paint()
        ..color = palette.line
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.035,
    );
    canvas.restore();
  }

  void _paintTrack(Canvas canvas, Offset Function(Pt) px, double cell) {
    for (var i = 0; i < spec.trackLength; i++) {
      _paintCell(canvas, geometry.ringCell(i), px, cell, palette.cell);
    }
    // A seat's start square wears its colour. Every arm is drawn, seated or
    // not: a two-player game is still played on a four-armed board, and a board
    // missing two of its arms looks broken rather than empty.
    for (var arm = 0; arm < spec.arms; arm++) {
      _paintCell(
        canvas,
        geometry.ringCell(spec.startRing(arm)),
        px,
        cell,
        _armColour(arm),
      );
    }
  }

  void _paintHomeColumns(Canvas canvas, Offset Function(Pt) px, double cell) {
    for (var arm = 0; arm < spec.arms; arm++) {
      final colour = _armColour(arm);
      for (var i = 0; i < spec.homeColumn; i++) {
        _paintCell(canvas, geometry.homeCell(arm, i), px, cell, colour);
      }
    }
  }

  void _paintStars(Canvas canvas, Offset Function(Pt) px, double cell) {
    for (final ring in geometry.starRingIndices()) {
      final c = px(geometry.ringCell(ring).centre);
      final path = Path();
      for (var i = 0; i < 10; i++) {
        final a = math.pi / 5 * i - math.pi / 2;
        final r = (i.isEven ? 0.34 : 0.15) * cell;
        final pt = c + Offset(math.cos(a) * r, math.sin(a) * r);
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..color = palette.star
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.055
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  /// The arrow on each turn-in square, pointing the way into that seat's home.
  ///
  /// Drawn as a line and a chevron rather than a filled wedge: it is a
  /// direction sign on a square a chip has to stand on, so it should read at a
  /// glance and then get out of the way.
  void _paintTurnInArrows(Canvas canvas, Offset Function(Pt) px, double cell) {
    for (var arm = 0; arm < spec.arms; arm++) {
      final turnIn = geometry.turnInCell(arm);
      final from = px(turnIn.centre);
      final to = px(geometry.homeCell(arm, 0).centre);
      final dir = to - from;
      final len = dir.distance;
      if (len == 0) continue;
      final unit = dir / len;
      final normal = Offset(-unit.dy, unit.dx);

      final tip = from + unit * (cell * 0.30);
      final tail = from - unit * (cell * 0.30);
      final wing = cell * 0.17;

      final paint = Paint()
        ..color = _armColour(arm)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.055
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawLine(tail, tip, paint);
      canvas.drawPath(
        Path()
          ..moveTo(
            tip.dx - unit.dx * wing + normal.dx * wing,
            tip.dy - unit.dy * wing + normal.dy * wing,
          )
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(
            tip.dx - unit.dx * wing - normal.dx * wing,
            tip.dy - unit.dy * wing - normal.dy * wing,
          ),
        paint,
      );
    }
  }

  void _paintCentre(Canvas canvas, Offset Function(Pt) px) {
    final wedges = geometry.centreWedges();
    for (var arm = 0; arm < wedges.length; arm++) {
      final tri = wedges[arm];
      // Every wedge wears its arm's colour, seated or not. This was the last
      // place still keyed off "is somebody sitting here", which left the
      // middle of the board with white quarters while the houses and columns
      // around them were coloured.
      canvas.drawPath(
        Path()..addPolygon([px(tri.a), px(tri.b), px(tri.c)], true),
        Paint()..color = colourOfArm(arm, spec.arms).withValues(alpha: 0.9),
      );
    }
  }

  void _paintYards(Canvas canvas, Offset Function(Pt) px, double cell) {
    for (var arm = 0; arm < spec.arms; arm++) {
      final colour = _armColour(arm);

      if (geometry is CrossGeometry) {
        final (tl, br) = (geometry as CrossGeometry).yardSquare(arm);
        final rect = Rect.fromPoints(px(tl), px(br));
        canvas.drawRect(rect, Paint()..color = colour);
        canvas.drawRect(
          rect.deflate(cell),
          Paint()..color = palette.homeInterior,
        );
      } else {
        final tri = geometry.yardShape(arm);
        final outer = [px(tri.a), px(tri.b), px(tri.c)];
        canvas.drawPath(
          Path()..addPolygon(outer, true),
          Paint()..color = colour,
        );
        final centroid = Offset(
          outer.map((o) => o.dx).reduce((a, b) => a + b) / 3,
          outer.map((o) => o.dy).reduce((a, b) => a + b) / 3,
        );
        canvas.drawPath(
          Path()..addPolygon([
            for (final o in outer) centroid + (o - centroid) * houseInset,
          ], true),
          Paint()..color = palette.homeInterior,
        );
      }

      // One resting place per chip this game gives a seat, drawn whether or
      // not anybody is sitting there — an unseated arm still shows where its
      // chips would stand. The arrangement follows the count, so three chips
      // make a triangle rather than a square with a corner missing.
      //
      // A seat that somebody is actually playing gets its rests ringed in its
      // own colour, darkened. Unringed they were all the same grey, so an
      // empty house in a four-handed game looked exactly like an empty house
      // on an arm nobody is using, and the difference between "their chips are
      // all out on the board" and "nobody lives here" is worth seeing.
      final seated = state.seatArms.contains(arm);
      for (final slot in geometry.yardSlots(
        arm,
        count: state.rules.tokensPerPlayer,
      )) {
        final at = px(slot);
        final r = cell * 0.38;
        canvas.drawCircle(at, r, Paint()..color = palette.slot);
        if (seated) {
          // A hairline, and no more than that. The ring only has to answer
          // "is anybody playing this arm" for a house that happens to be
          // empty; drawn heavily it becomes a target painted on the board and
          // competes with the chips it is meant to sit quietly behind.
          canvas.drawCircle(
            at,
            r,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = cell * 0.028
              ..color = Color.lerp(colour, Colors.black, 0.22)!
                  .withValues(alpha: 0.34),
          );
        }
      }
    }
  }

  /// A letter in each house saying which side it plays for.
  ///
  /// In a team game the whole point is that two houses are one player, and
  /// nothing on the board said so: four colours sat round a board looking
  /// exactly as they do in a free-for-all, and which of them were partners was
  /// something you had to remember from the setup screen or work out from who
  /// declined to knock you off.
  ///
  /// A letter rather than a shared colour or a shared border. Colour is
  /// already spoken for — it is how a seat is named, and two seats sharing one
  /// would stop being two seats. A letter adds a second, independent thing to
  /// read, which is what a second, independent fact needs.
  ///
  /// It goes in the corner of the house nearest the middle of the board, on
  /// the coloured band rather than on the white inside, because the inside
  /// belongs to the chips.
  void _paintTeamMarks(Canvas canvas, Offset Function(Pt) px, double cell) {
    if (!state.rules.isTeamGame) return;

    for (var seat = 0; seat < state.rules.players; seat++) {
      final arm = state.armOf(seat);
      final letter = String.fromCharCode(65 + state.rules.teamOf(seat));

      final Offset at;
      if (geometry is CrossGeometry) {
        final (tl, br) = (geometry as CrossGeometry).yardSquare(arm);
        final rect = Rect.fromPoints(px(tl), px(br));
        final middle = px(const Pt(0.5, 0.5));
        // The corner of the square nearest the middle of the board — which is
        // the one corner of a house that is always a solid block of colour,
        // whichever of the four houses it is.
        at = Offset(
          (rect.left - middle.dx).abs() < (rect.right - middle.dx).abs()
              ? rect.left + cell * 0.5
              : rect.right - cell * 0.5,
          (rect.top - middle.dy).abs() < (rect.bottom - middle.dy).abs()
              ? rect.top + cell * 0.5
              : rect.bottom - cell * 0.5,
        );
      } else {
        // The house is a triangle with its point toward the middle, and that
        // point is the roomiest part of its band — nearly a square deep,
        // against less than half a square along either side. So the letter
        // goes a little way back from the point, and is drawn smaller than on
        // the cross, because the wedge it sits in is narrow even at its best.
        final tri = geometry.yardShape(arm);
        final apex = px(tri.a);
        final centroid = (px(tri.a) + px(tri.b) + px(tri.c)) / 3;
        at = apex + (centroid - apex) * 0.155;
      }
      _letter(
        canvas,
        at,
        letter,
        cell * (geometry is CrossGeometry ? 0.62 : 0.5),
      );
    }
  }

  /// One letter, centred on [at] — centred on the letter, not on its box.
  ///
  /// The distinction is the whole of this function. A line of text is taller
  /// than the letter in it: there is room above for accents and room below for
  /// the tails of g and y, and a capital A uses neither. Centring the box
  /// therefore leaves the letter sitting visibly high in it, which in the
  /// middle of a paragraph nobody notices and in the corner of a coloured band
  /// looks like it was dropped there rather than placed.
  ///
  /// So it is positioned from the baseline instead, with the capital's own
  /// height straddling [at]. The 0.711 is Roboto's cap height as a fraction of
  /// its point size — the app sets no font, so Roboto is what it gets.
  void _letter(Canvas canvas, Offset at, String letter, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: letter,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w800,
          // Dark on the seat's own colour. The house colours do not follow the
          // theme — a red house is the same red at midnight — so one ink works
          // for both, and black on all six of them beats white on four of them.
          color: Colors.black.withValues(alpha: 0.62),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const capHeightRatio = 0.711;
    final baseline =
        painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
    painter.paint(
      canvas,
      Offset(
        at.dx - painter.width / 2,
        at.dy + size * capHeightRatio / 2 - baseline,
      ),
    );
  }

  /// The breathing outline round the house of whoever has to roll.
  void _paintGlow(Canvas canvas, Offset Function(Pt) px, double cell) {
    final seat = glowSeat;
    if (seat == null) return;
    final arm = state.armOf(seat);
    final colour = _armColour(arm);

    if (geometry is CrossGeometry) {
      final (tl, br) = (geometry as CrossGeometry).yardSquare(arm);
      _glow(
        canvas,
        Path()..addRect(Rect.fromPoints(px(tl), px(br))),
        colour,
        cell,
      );
    } else {
      final tri = geometry.yardShape(arm);
      _glow(
        canvas,
        Path()..addPolygon([px(tri.a), px(tri.b), px(tri.c)], true),
        colour,
        cell,
      );
    }
  }

  /// A breathing outline round the house of whoever has to roll.
  ///
  /// Only while they are still to roll: once the dice are down the thing that
  /// needs attention is a chip on the board, not the house.
  void _glow(Canvas canvas, Path path, Color colour, double cell) {
    // Steady, not breathing. A pulsing glow needs a frame every 16ms for as
    // long as somebody has to roll, which is most of a game — and on the web
    // that is a CPU core spent on a slow throb nobody asked for. The house
    // lighting up is the signal; it does not have to move.
    const breath = 0.75;

    // Clipped to the board. A halo is drawn by stroking outward, and a house
    // sits on the board's edge — unclipped it spills onto the page and reads
    // as a rendering fault rather than as a light.
    final plate = Path()
      ..addPolygon([
        for (final p in geometry.plateOutline()) _lastPx!(p),
      ], true);
    canvas.save();
    canvas.clipPath(plate);
    for (var i = 2; i >= 1; i--) {
      canvas.drawPath(
        path,
        Paint()
          ..color = colour.withValues(alpha: 0.14 * breath / i)
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * (0.20 + 0.28 * breath) * i,
      );
    }
    canvas.restore();

    // A crisp lit edge just inside the house, so it reads as the house lighting
    // up rather than as a smudge near it.
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.30 + 0.40 * breath)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cell * 0.09,
    );
  }

  /// The colour an arm wears — its own, whether or not anybody is sitting
  /// there. An empty corner of a Ludo board is still a coloured corner; what
  /// marks it empty is that no chips are standing in it.
  Color _armColour(int arm) => colourOfArm(arm, spec.arms);

  // --- chips ---------------------------------------------------------------

  void _paintChips(Canvas canvas, Offset Function(Pt) px, double cell) {
    final chipWidth = cell * chipShare(spec.arms);
    final movable = {for (final m in legalMoves) ...m.tokenIds};
    final layout = chipLayout(state, geometry);

    // Group by where they are drawn — literally the same point on the canvas —
    // and not by whose chip it is and how far round it has come.
    //
    // Progress is counted from each player's own start square, so two players
    // standing on one square of the shared track have different owners *and*
    // different progress. Keyed on those, they went into separate groups and
    // were each drawn alone at the same spot, one flat on top of the other.
    // Which meant the mixed-colour spreading below could never once run: the
    // only crowd it was ever handed was a player's own chips.
    final groups = <String, List<Token>>{};
    for (final token in state.tokens) {
      if (motions.containsKey(token.id)) continue; // in flight
      final at = layout[token.id];
      if (at == null) continue;
      final key = token.inYard
          ? 'yard-${token.owner}'
          : '${at.x.toStringAsFixed(5)},${at.y.toStringAsFixed(5)}';
      groups.putIfAbsent(key, () => []).add(token);
    }

    for (final group in groups.values) {
      if (group.first.inYard) {
        // Idle chips sit in their own resting places, never stacked.
        for (final token in group) {
          _chip(canvas, px(layout[token.id]!), chipWidth, token, movable, cell);
        }
        continue;
      }
      final at = px(layout[group.first.id]!);
      _paintGroup(canvas, at, chipWidth, group, movable, cell);
    }
  }

  /// Two or more chips on one square lean apart, so every head shows.
  ///
  /// They used to be shrunk and set side by side, which made a crowded square
  /// read as two small counters rather than two pieces sharing a square. Real
  /// pieces jostled together tip away from each other; that is all this is,
  /// and it keeps them full size.
  void _paintGroup(
    Canvas canvas,
    Offset at,
    double width,
    List<Token> group,
    Set<int> movable,
    double cell,
  ) {
    if (group.length == 1) {
      _chip(canvas, at, width, group.first, movable, cell);
      return;
    }

    // One of each colour first: whose chips are standing there matters more
    // than how many, so a player's second chip never crowds out another
    // player's first.
    final byOwner = <int, List<Token>>{};
    for (final t in group) {
      byOwner.putIfAbsent(t.owner, () => []).add(t);
    }
    final order = <Token>[
      for (final own in byOwner.values) own.first,
      for (final own in byOwner.values) ...own.skip(1),
    ];

    // Three leaning pieces still read; beyond that they are a heap, so the
    // rest are counted on a badge instead.
    final shown = order.length <= 3 ? order.length : 3;
    final hidden = order.length - shown;

    // How far they go over depends on how many there are: two barely tip,
    // three have to lean properly for the middle one's head to clear the
    // others. One angle for every crowd left three of them stacked.
    final lean = 0.10 * shown;
    final spread = 0.09 * shown;

    for (var i = 0; i < shown; i++) {
      // -1 for the leftmost, +1 for the rightmost, 0 for one in the middle.
      final fan = (i / (shown - 1)) * 2 - 1;
      _chip(
        canvas,
        at + Offset(fan * width * spread, 0),
        width * 0.92,
        order[i],
        movable,
        cell,
        tilt: fan * lean,
        badge: (hidden > 0 && i == shown - 1) ? order.length : null,
      );
    }
  }

  void _chip(
    Canvas canvas,
    Offset ground,
    double width,
    Token token,
    Set<int> movable,
    double cell, {
    int? badge,
    bool ghost = false,
    double tilt = 0,
  }) {
    // The ring is drawn by _paintLegalRings, between the board and the chips,
    // because it turns and this layer is recorded once and replayed.
    final colour = colourOfArm(state.armOf(token.owner), spec.arms);
    ChipArt.paint(
      canvas,
      ground,
      width,
      ghost ? colour.withValues(alpha: 0.55) : colour,
      badge: badge,
      tilt: tilt,
    );
  }

  @override
  bool shouldRepaint(BoardPainter old) {
    if (old.layer != layer ||
        old.palette != palette ||
        !identical(old.state, state)) {
      return true;
    }
    // The still layers must not repaint for an animation frame; that is the
    // whole point of splitting them out.
    return switch (layer) {
      BoardLayer.furniture => false,
      BoardLayer.chips => old.motions.length != motions.length,
      BoardLayer.glow => old.glowSeat != glowSeat,
      BoardLayer.motions => true,
    };
  }
}
