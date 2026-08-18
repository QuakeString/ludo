import 'dart:io';
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
    var reds = 0, blues = 0;
    for (
      var y = (centre.dy - cell * 1.6).round();
      y < (centre.dy + cell * 1.6).round();
      y++
    ) {
      for (
        var x = (centre.dx - cell * 1.6).round();
        x < (centre.dx + cell * 1.6).round();
        x++
      ) {
        if (x < 0 || y < 0 || x >= side || y >= side) continue;
        final i = (y * side + x) * 4;
        final r = pixels.getUint8(i);
        final g = pixels.getUint8(i + 1);
        final b = pixels.getUint8(i + 2);
        // Classified by which channel leads rather than by matching a colour:
        // a chip is shaded, so no pixel of it is the flat seat colour.
        if (r > b + 40 && r > g + 40) reds++;
        if (b > r + 40 && b > g + 20) blues++;
      }
    }

    expect(reds, greaterThan(60), reason: 'no red chip on the shared square');
    expect(blues, greaterThan(60), reason: 'the blue chip is hidden under it');

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

    // Red, green and blue must all reach the square.
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
    var reds = 0, greens = 0, blues = 0;
    for (
      var y = (centre.dy - cell * 2).round();
      y < (centre.dy + cell * 2).round();
      y++
    ) {
      for (
        var x = (centre.dx - cell * 2).round();
        x < (centre.dx + cell * 2).round();
        x++
      ) {
        if (x < 0 || y < 0 || x >= side || y >= side) continue;
        final i = (y * side + x) * 4;
        final r = pixels.getUint8(i);
        final g = pixels.getUint8(i + 1);
        final b = pixels.getUint8(i + 2);
        if (r > b + 40 && r > g + 40) reds++;
        if (g > r + 30 && g > b + 30) greens++;
        if (b > r + 40 && b > g + 20) blues++;
      }
    }
    expect(reds, greaterThan(60), reason: 'red is buried');
    expect(greens, greaterThan(60), reason: 'green is buried');
    expect(blues, greaterThan(60), reason: 'blue is buried');
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
