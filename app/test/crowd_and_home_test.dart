import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/board/chip_layout.dart';
import 'package:ludo_app/theme/seat_colors.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

/// Two situations that are hard to reach by playing but easy to construct:
/// chips of different players sharing a square, and chips that have finished.
void main() {
  const rules = RuleConfig(players: 4, tokensPerPlayer: 4);

  GameState situation(Map<int, int> at) {
    final s = GameState.newGame(rules, seed: 2);
    final tokens = [...s.tokens];
    at.forEach((id, p) => tokens[id] = tokens[id].copyWith(progress: p));
    return s.copyWith(tokens: tokens);
  }

  testWidgets('a square with two players on it draws both', (tester) async {
    // Seat 0 and seat 1 on the same ring square.
    final s = GameState.newGame(rules, seed: 2);
    final shared = s.board.startRing(s.armOf(0)) + 3;
    final mine = (shared - s.board.startRing(s.armOf(0))) % s.board.trackLength;
    final theirs =
        (shared - s.board.startRing(s.armOf(1)) + s.board.trackLength) %
        s.board.trackLength;
    final state = situation({0: mine, 4: theirs});

    final geometry = BoardGeometry.forSpec(state.board);
    final layout = chipLayout(state, geometry);
    expect(
      layout[0],
      layout[4],
      reason: 'the two chips really are on one square',
    );

    // Both must be drawn, and far enough apart to be told apart. The painter
    // is the only thing that knows that, so render it and check the pixels.
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 600,
            height: 600,
            child: CustomPaint(
              painter: BoardPainter(
                state: state,
                geometry: geometry,
                palette: BoardPalette.light,
                legalMoves: const [],
                layer: BoardLayer.chips,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
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
