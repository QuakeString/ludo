import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/saved_game.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// With pair move on, two chips on a safe square get a 🔗 to link them, and
/// the turn waits for the player rather than playing itself.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a 🔗 on a safe square links the two chips', (tester) async {
    const rules = RuleConfig(players: 2, tokensPerPlayer: 2, pairMove: true);
    var s = GameState.newGame(rules, seed: 5);
    // A safe square some way round, past the start.
    final safe = [
      for (var p = 2; p < 40; p++)
        if (s.safeRingSquares.contains(s.board.ringIndex(s.armOf(0), p))) p,
    ].first;
    final tokens = [...s.tokens];
    tokens[0] = tokens[0].copyWith(progress: safe);
    tokens[1] = tokens[1].copyWith(progress: safe);
    s = s.copyWith(tokens: tokens, turn: 0, dice: 4);

    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: GameScreen.resumed(SavedGame(state: s))),
    );
    await tester.pump();

    final link = find.byKey(const ValueKey('pair-0-1'));
    expect(link, findsOneWidget);

    // Two chips on one square with one roll is "nothing to choose" for a
    // plain move, but the pairing is a choice, so the turn waits.
    await tester.pump(const Duration(seconds: 3));
    expect(link, findsOneWidget);

    await tester.tap(link);
    await tester.pump();
    expect(link, findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
