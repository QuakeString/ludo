import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/board/chip_layout.dart';
import 'package:ludo_app/theme/seat_colors.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

/// Two situations that are hard to reach by playing but easy to construct:
/// chips of different players sharing a square, and chips that have finished.
/// The board and its chips together, for looking at.
Future<ui.Image> wholeBoard(GameState state, BoardGeometry geometry, int side) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(side.toDouble(), side.toDouble());
  canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF2EFE7));
  for (final l in [BoardLayer.furniture, BoardLayer.chips]) {
    BoardPainter(
      state: state,
      geometry: geometry,
      palette: BoardPalette.light,
      legalMoves: const [],
      layer: l,
    ).paint(canvas, size);
  }
  return recorder.endRecording().toImage(side, side);
}


/// How many pixels near [centre] belong to each of the given seats.
///
/// Classified by nearest seat colour rather than by which channel leads. The
/// old way — "red if the red channel is ahead of the others" — only works for
/// colours that happen to be primaries, and stopped meaning anything the
/// moment the boards were repainted and a seat could be yellow or magenta.
Map<int, int> countSeats(
  ByteData pixels,
  int side,
  Offset centre,
  double cell,
  GameState state,
  List<int> seats,
) {
  final wanted = {
    for (final seat in seats)
      seat: colourOfArm(state.armOf(seat), state.board.arms),
  };
  final found = {for (final seat in seats) seat: 0};

  for (var y = (centre.dy - cell * 1.6).round();
      y < (centre.dy + cell * 1.6).round();
      y++) {
    for (var x = (centre.dx - cell * 1.6).round();
        x < (centre.dx + cell * 1.6).round();
        x++) {
      if (x < 0 || y < 0 || x >= side || y >= side) continue;
      final i = (y * side + x) * 4;
      final r = pixels.getUint8(i);
      final g = pixels.getUint8(i + 1);
      final b = pixels.getUint8(i + 2);

      var best = -1;
      var bestGap = double.infinity;
      for (final entry in wanted.entries) {
        final c = entry.value;
        final gap = math.sqrt(
          math.pow(r - (c.r * 255), 2) +
              math.pow(g - (c.g * 255), 2) +
              math.pow(b - (c.b * 255), 2),
        );
        if (gap < bestGap) {
          bestGap = gap;
          best = entry.key;
        }
      }
      // A chip is shaded, so no pixel of it is the flat seat colour — but it
      // is far nearer its own colour than the board's white or anyone else's.
      if (bestGap < 110) found[best] = found[best]! + 1;
    }
  }
  return found;
}

void main() {
  const rules = RuleConfig(players: 4, tokensPerPlayer: 4);

  GameState situation(Map<int, int> at) {
    final s = GameState.newGame(rules, seed: 2);
    final tokens = [...s.tokens];
    at.forEach((id, p) => tokens[id] = tokens[id].copyWith(progress: p));
    return s.copyWith(tokens: tokens);
  }

  /// Paints one layer and hands back its pixels.
  Future<(ByteData, int)> raster(CustomPainter painter, int side) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final size = Size(side.toDouble(), side.toDouble());
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFF2EFE7),
    );
    painter.paint(canvas, size);
    final image = await recorder.endRecording().toImage(side, side);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return (bytes!, side);
  }

  test('a square with two players on it draws both', () async {
    // Seat 0 and seat 2 — red and blue, the pair in the report — brought onto
    // one square of the shared track. Progress is counted from each player's
    // own start, so the same square is a different number for each of them.
    final fresh = GameState.newGame(rules, seed: 2);
    final board = fresh.board;
    final shared = board.startRing(fresh.armOf(0)) + 3;
    int progressFor(int seat) =>
        (shared - board.startRing(fresh.armOf(seat)) + board.trackLength) %
        board.trackLength;
    final state = situation({0: progressFor(0), 8: progressFor(2)});

    final geometry = BoardGeometry.forSpec(state.board);
    final layout = chipLayout(state, geometry);
    expect(layout[0], layout[8], reason: 'the two chips share a square');

    // Now the part that matters, and the part the first version of this test
    // skipped: what actually comes out of the painter. It asserted only that
    // painting did not throw, which it never did — the blue chip was being
    // drawn exactly underneath the red one the whole time.
    const side = 900;
    final (pixels, _) = await raster(
      BoardPainter(
        state: state,
        geometry: geometry,
        palette: BoardPalette.light,
        legalMoves: const [],
        layer: BoardLayer.chips,
      ),
      side,
    );

    final cell = geometry.cellSize * side;
    final centre = Offset(layout[0]!.x * side, layout[0]!.y * side);
    final seen = countSeats(pixels, side, centre, cell, state, [0, 2]);

    expect(seen[0], greaterThan(60),
        reason: 'no chip of the first seat on the shared square');
    expect(seen[2], greaterThan(60),
        reason: 'the other seat is hidden underneath it');

    // Counting pixels says both are there; only an eye says they look right.
    final png = await (await wholeBoard(
      state,
      geometry,
      side,
    )).toByteData(format: ui.ImageByteFormat.png);
    Directory('build/board-previews').createSync(recursive: true);
    File('build/board-previews/crowded-square.png')
        .writeAsBytesSync(png!.buffer.asUint8List());
  });

  test('three on a square lean further than two', () async {
    // The angle is not fixed: three pieces have to go over further than two
    // for the middle one's head to clear the others.
    final fresh = GameState.newGame(rules, seed: 2);
    final board = fresh.board;
    final shared = board.startRing(fresh.armOf(0)) + 3;
    int progressFor(int seat) =>
        (shared - board.startRing(fresh.armOf(seat)) + board.trackLength) %
        board.trackLength;

    final state = situation({
      0: progressFor(0),
      4: progressFor(1),
      8: progressFor(2),
    });
    final geometry = BoardGeometry.forSpec(state.board);
    final layout = chipLayout(state, geometry);
    expect(layout[0], layout[4]);
    expect(layout[0], layout[8]);

    const side = 900;
    final png = await (await wholeBoard(
      state,
      geometry,
      side,
    )).toByteData(format: ui.ImageByteFormat.png);
    Directory('build/board-previews').createSync(recursive: true);
    File('build/board-previews/crowded-three.png')
        .writeAsBytesSync(png!.buffer.asUint8List());

    // All three seats must reach the square.
    final (pixels, _) = await raster(
      BoardPainter(
        state: state,
        geometry: geometry,
        palette: BoardPalette.light,
        legalMoves: const [],
        layer: BoardLayer.chips,
      ),
      side,
    );
    final cell = geometry.cellSize * side;
    final centre = Offset(layout[0]!.x * side, layout[0]!.y * side);
    final seen = countSeats(pixels, side, centre, cell * 1.25, state, [0, 1, 2]);
    for (final seat in [0, 1, 2]) {
      expect(seen[seat], greaterThan(60), reason: 'seat $seat is buried');
    }
  });

  test('finished chips rest in their own wedge, not on each other', () {
    final s = GameState.newGame(rules, seed: 2);
    final geometry = BoardGeometry.forSpec(s.board);
    final finished = s.board.finalProgress;

    final spots = [
      for (var seat = 0; seat < 4; seat++)
        geometry.tokenAt(s.armOf(seat), finished),
    ];
    expect(
      spots.toSet(),
      hasLength(4),
      reason: 'four seats finishing must not pile onto one point',
    );

    // Each within its own wedge of the centre, and none of them at the middle.
    for (var seat = 0; seat < 4; seat++) {
      expect(spots[seat], isNot(const Pt(0.5, 0.5)));
    }
  });
}
