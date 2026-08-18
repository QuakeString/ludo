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
        _paintChips(canvas, px, cell);
      case BoardLayer.motions:
        _paintMotions(canvas, px, cell);
    }
  }

  /// Chips mid-move, drawn above everything else.
  void _paintMotions(Canvas canvas, Offset Function(Pt) px, double cell) {
    if (motions.isEmpty) return;
    final chipWidth = cell * (spec.arms == 4 ? 0.78 : 0.66);
    for (final entry in motions.entries) {
      final token = state.tokens[entry.key];
      final m = entry.value;
      ChipArt.paint(
        canvas,
        px(m.ground),
        chipWidth,
        colourOfArm(state.armOf(token.owner)),
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
        Paint()..color = colourOfArm(arm).withValues(alpha: 0.9),
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
            for (final o in outer) centroid + (o - centroid) * 0.80,
          ], true),
          Paint()..color = palette.homeInterior,
        );
      }

      // Four resting places, always drawn — switching between three and four
      // chips must never change the board, and an unseated arm still shows
      // where its chips would stand.
      for (final slot in geometry.yardSlots(arm)) {
        canvas.drawCircle(px(slot), cell * 0.38, Paint()..color = palette.slot);
      }
    }
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
  Color _armColour(int arm) => colourOfArm(arm);

  // --- chips ---------------------------------------------------------------

  void _paintChips(Canvas canvas, Offset Function(Pt) px, double cell) {
    final chipWidth = cell * (spec.arms == 4 ? 0.78 : 0.66);
    final movable = {for (final m in legalMoves) ...m.tokenIds};
    final layout = chipLayout(state, geometry);

    // Group by where they stand, so a crowded square can be drawn as a group
    // rather than as overlapping singles.
    final groups = <String, List<Token>>{};
    for (final token in state.tokens) {
      if (motions.containsKey(token.id)) continue; // in flight
      final arm = state.armOf(token.owner);
      final key = token.inYard
          ? 'yard-${token.owner}'
          : spec.isFinished(token.progress)
          ? 'home-${token.owner}'
          : 'p-$arm-${token.progress}';
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

  /// Up to two chips draw in full; three or more collapse to one plus a count.
  /// Same-seat groups stack front to back, mixed seats sit side by side —
  /// whose chips are there matters more than how many.
  void _paintGroup(
    Canvas canvas,
    Offset at,
    double width,
    List<Token> group,
    Set<int> movable,
    double cell,
  ) {
    final owners = group.map((t) => t.owner).toSet();

    if (group.length == 1) {
      _chip(canvas, at, width, group.first, movable, cell);
      return;
    }

    if (owners.length == 1) {
      if (group.length == 2) {
        _chip(
          canvas,
          at + Offset(-width * 0.22, -width * 0.10),
          width * 0.86,
          group[0],
          movable,
          cell,
        );
        _chip(
          canvas,
          at + Offset(width * 0.22, width * 0.06),
          width * 0.86,
          group[1],
          movable,
          cell,
        );
      } else {
        _chip(
          canvas,
          at + Offset(-width * 0.12, -width * 0.08),
          width * 0.8,
          group.first,
          movable,
          cell,
          ghost: true,
        );
        _chip(
          canvas,
          at + Offset(width * 0.06, width * 0.05),
          width * 0.92,
          group[1],
          movable,
          cell,
          badge: group.length,
        );
      }
      return;
    }

    // Mixed seats: side by side, shrunk so each colour stays readable.
    final byOwner = <int, List<Token>>{};
    for (final t in group) {
      byOwner.putIfAbsent(t.owner, () => []).add(t);
    }
    final entries = byOwner.entries.toList();
    final scale = entries.length == 2 ? 0.74 : 0.62;
    for (var i = 0; i < entries.length; i++) {
      final angle = (i / entries.length) * 2 * math.pi - math.pi / 2;
      final spread = entries.length == 2 ? width * 0.30 : width * 0.34;
      final offset = entries.length == 2
          ? Offset(i == 0 ? -spread : spread, i == 0 ? 0 : width * 0.08)
          : Offset(math.cos(angle) * spread, math.sin(angle) * spread * 0.6);
      final tokens = entries[i].value;
      _chip(
        canvas,
        at + offset,
        width * scale,
        tokens.first,
        movable,
        cell,
        badge: tokens.length > 1 ? tokens.length : null,
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
  }) {
    // The ring is drawn by _paintLegalRings, between the board and the chips,
    // because it turns and this layer is recorded once and replayed.
    final colour = colourOfArm(state.armOf(token.owner));
    ChipArt.paint(
      canvas,
      ground,
      width,
      ghost ? colour.withValues(alpha: 0.55) : colour,
      badge: badge,
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
