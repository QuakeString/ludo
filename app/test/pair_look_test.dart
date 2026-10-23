import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/theme/seat_colors.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

/// A linked pair is drawn side by side under one border; with someone else on
/// the square too it still paints.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final crowd in [false, true]) {
    test('a linked pair paints${crowd ? ' beside another chip' : ''}', () {
      const rules = RuleConfig(players: 2, pairMove: true);
      var s = GameState.newGame(rules, seed: 1);
      final ring = s.board.ringIndex(s.armOf(0), 10)!;
      final theirs =
          (ring - s.board.startRing(s.armOf(1)) + s.board.trackLength) %
          s.board.trackLength;
      final tokens = [...s.tokens];
      tokens[0] = tokens[0].copyWith(progress: 10, pairId: 0);
      tokens[1] = tokens[1].copyWith(progress: 10, pairId: 0);
      if (crowd) tokens[4] = tokens[4].copyWith(progress: theirs);
      s = s.copyWith(tokens: tokens, nextPairId: 1);

      for (final palette in [BoardPalette.light, BoardPalette.dark]) {
        final recorder = ui.PictureRecorder();
        BoardPainter(
          state: s,
          geometry: BoardGeometry.forSpec(s.board),
          palette: palette,
          legalMoves: const [],
          pulse: 0,
          layer: BoardLayer.chips,
        ).paint(Canvas(recorder), const Size(600, 600));
        expect(recorder.endRecording(), isNotNull);
      }
    });
  }
}
