import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/saved_game.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A roll with nothing to play passes by itself, even when chips that could
/// link stand somewhere on the board. Two of a partner's chips sharing a
/// square once counted as a choice, and the turn sat on a Pass button.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a dead roll passes beside a partner\'s unlinked chips', (
    tester,
  ) async {
    const teamed = RuleConfig(
      players: 4,
      pairMove: true,
      teams: [
        [0, 2],
        [1, 3],
      ],
    );
    final start = GameState.newGame(teamed);
    final tokens = [...start.tokens];
    // Every red chip in the yard, two yellow chips side by side.
    tokens[8] = tokens[8].copyWith(progress: 10);
    tokens[9] = tokens[9].copyWith(progress: 10);
    final s = start.copyWith(tokens: tokens, turn: 0, dice: 3);

    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: GameScreen.resumed(SavedGame(state: s))),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final shown =
        (tester
                    .widget<CustomPaint>(
                      find
                          .byWidgetPredicate(
                            (w) =>
                                w is CustomPaint && w.painter is BoardPainter,
                          )
                          .first,
                    )
                    .painter
                as BoardPainter)
            .state;
    expect(shown.turn, isNot(0), reason: 'the turn stayed with red');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
