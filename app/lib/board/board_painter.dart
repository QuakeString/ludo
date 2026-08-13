import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

import '../theme/seat_colors.dart';
import 'chip_painter.dart';
import 'move_animation.dart';

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
  });

  final GameState state;
  final BoardGeometry geometry;
  final BoardPalette palette;
  final List<Move> legalMoves;

  /// 0..1, drives the ring's outward pulse.
  final double pulse;

  /// Tokens in flight, keyed by token id. These are lifted out of the static
  /// layout and drawn last, so a hopping chip passes over the board rather
  /// than under whatever it is hopping towards.
  final Map<int, ChipMotion> motions;

  BoardSpec get spec => state.board;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2);
    Offset px(Pt p) => origin + Offset(p.x * side, p.y * side);
    final cell = geometry.cellSize * side;

    _paintPlate(canvas, px, side);
    _paintTrack(canvas, px, cell);
    _paintHomeColumns(canvas, px, cell);
    _paintStars(canvas, px, cell);
    _paintTurnInArrows(canvas, px, cell);
    _paintCentre(canvas, px);
    _paintYards(canvas, px, cell);
    _paintDice(canvas, px, cell);
    _paintChips(canvas, px, cell);
    _paintMotions(canvas, px, cell);
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
        seatColors[token.owner],
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
    // A seat's start square wears its colour.
    for (var p = 0; p < state.rules.players; p++) {
      final arm = state.armOf(p);
      _paintCell(
        canvas,
        geometry.ringCell(spec.startRing(arm)),
        px,
        cell,
        seatColors[p],
      );
    }
  }

  void _paintHomeColumns(Canvas canvas, Offset Function(Pt) px, double cell) {
    for (var p = 0; p < state.rules.players; p++) {
      final arm = state.armOf(p);
      for (var i = 0; i < spec.homeColumn; i++) {
        _paintCell(canvas, geometry.homeCell(arm, i), px, cell, seatColors[p]);
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
  void _paintTurnInArrows(Canvas canvas, Offset Function(Pt) px, double cell) {
    for (var p = 0; p < state.rules.players; p++) {
      final arm = state.armOf(p);
      final turnIn = geometry.turnInCell(arm);
      final from = px(turnIn.centre);
      final to = px(geometry.homeCell(arm, 0).centre);
      final dir = to - from;
      final len = dir.distance;
      if (len == 0) continue;
      final unit = dir / len;
      final normal = Offset(-unit.dy, unit.dx);

      final tip = from + unit * (cell * 0.26);
      final backA = from - unit * (cell * 0.10) + normal * (cell * 0.26);
      final backB = from - unit * (cell * 0.10) - normal * (cell * 0.26);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(backA.dx, backA.dy)
        ..lineTo(backB.dx, backB.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..color = palette.cell
          ..style = PaintingStyle.stroke
          ..strokeWidth = cell * 0.09
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(path, Paint()..color = seatColors[p]);

      final tail = from - unit * (cell * 0.34);
      canvas.drawLine(
        tail,
        from - unit * (cell * 0.08),
        Paint()
          ..color = seatColors[p]
          ..strokeWidth = cell * 0.14
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _paintCentre(Canvas canvas, Offset Function(Pt) px) {
    final wedges = geometry.centreWedges();
    for (var arm = 0; arm < wedges.length; arm++) {
      final seat = _seatOnArm(arm);
      final tri = wedges[arm];
      canvas.drawPath(
        Path()..addPolygon([px(tri.a), px(tri.b), px(tri.c)], true),
        Paint()
          ..color = seat == null
              ? palette.cell
              : seatColors[seat].withValues(alpha: 0.9),
      );
    }
  }

  void _paintYards(Canvas canvas, Offset Function(Pt) px, double cell) {
    for (var p = 0; p < state.rules.players; p++) {
      final arm = state.armOf(p);
      final colour = seatColors[p];

      if (geometry is CrossGeometry) {
        final (tl, br) = (geometry as CrossGeometry).yardSquare(arm);
        final rect = Rect.fromPoints(px(tl), px(br));
        final rr = RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.35));
        canvas.drawRRect(rr, Paint()..color = colour);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.deflate(cell),
            Radius.circular(cell * 0.28),
          ),
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
      // chips must never change the board.
      for (final slot in geometry.yardSlots(arm)) {
        canvas.drawCircle(px(slot), cell * 0.38, Paint()..color = palette.slot);
      }
    }
  }

  void _paintDice(Canvas canvas, Offset Function(Pt) px, double cell) {
    for (var p = 0; p < state.rules.players; p++) {
      final live = p == state.turn;
      final value = live ? (state.dice ?? 0) : 0;
      final centre = px(geometry.dicePlace(state.armOf(p)));
      final size = cell * (live ? 1.5 : 1.05);
      final rect = Rect.fromCenter(center: centre, width: size, height: size);
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(size * 0.2));

      if (live) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.inflate(size * 0.12),
            Radius.circular(size * 0.3),
          ),
          Paint()
            ..color = seatColors[p]
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.09,
        );
      }
      canvas.drawRRect(
        rr,
        Paint()..color = live ? palette.die : palette.dieIdle,
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..color = live ? seatColors[p] : palette.dieEdge
          ..style = PaintingStyle.stroke
          ..strokeWidth = size * 0.05,
      );

      if (value >= 1) {
        for (final o in _pips[value]!) {
          canvas.drawCircle(
            centre + Offset(o[0] * size * 0.26, o[1] * size * 0.26),
            size * 0.095,
            Paint()..color = palette.pip,
          );
        }
      } else if (!live) {
        // An idle place, waiting for its turn.
        canvas.drawCircle(
          centre,
          size * 0.09,
          Paint()..color = palette.pip.withValues(alpha: 0.25),
        );
      }
    }
  }

  static const _pips = <int, List<List<double>>>{
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

  // --- chips ---------------------------------------------------------------

  void _paintChips(Canvas canvas, Offset Function(Pt) px, double cell) {
    final chipWidth = cell * (spec.arms == 4 ? 0.78 : 0.66);
    final movable = {for (final m in legalMoves) ...m.tokenIds};

    // Group by where they stand, so a crowded square can be drawn as a group
    // rather than as overlapping singles.
    final groups = <String, List<Token>>{};
    for (final token in state.tokens) {
      final arm = state.armOf(token.owner);
      final key = token.inYard
          ? 'yard-${token.owner}'
          : spec.isFinished(token.progress)
          ? 'home-${token.owner}'
          : 'p-$arm-${token.progress}';
      if (motions.containsKey(token.id)) continue; // in flight
      groups.putIfAbsent(key, () => []).add(token);
    }

    for (final group in groups.values) {
      final first = group.first;
      final arm = state.armOf(first.owner);

      if (first.inYard) {
        // Idle chips sit in their own resting places, never stacked.
        final slots = geometry.yardSlots(arm);
        for (var i = 0; i < group.length; i++) {
          _chip(
            canvas,
            px(slots[i % slots.length]),
            chipWidth,
            group[i],
            movable,
            cell,
          );
        }
        continue;
      }

      final at = px(geometry.tokenAt(arm, first.progress));
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
    final colour = seatColors[token.owner];
    if (movable.contains(token.id) && !ghost) {
      ChipArt.paintLegalRing(canvas, ground, width, colour, pulse: pulse);
    }
    ChipArt.paint(
      canvas,
      ground,
      width,
      ghost ? colour.withValues(alpha: 0.55) : colour,
      badge: badge,
    );
  }

  /// Which seat, if any, plays from a given arm.
  int? _seatOnArm(int arm) {
    for (var p = 0; p < state.rules.players; p++) {
      if (state.armOf(p) == arm) return p;
    }
    return null;
  }

  @override
  bool shouldRepaint(BoardPainter old) =>
      old.state != state ||
      old.palette != palette ||
      old.pulse != pulse ||
      old.legalMoves.length != legalMoves.length ||
      !identical(old.motions, motions) ||
      old.motions.length != motions.length;
}
