import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/die.dart';
import 'package:ludo_app/saved_game.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_app/screens/home_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Closing the app halfway through a game, and getting it back.
void main() {
  const engine = LudoEngine();
  const rules = RuleConfig(players: 2, tokensPerPlayer: 4);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A game some way in, with a roll pending.
  GameState midGame() {
    var s = GameState.newGame(rules, seed: 99);
    for (var i = 0; i < 30; i++) {
      s = engine.apply(s, const RollDice());
      final moves = engine.legalMoves(s);
      s = engine.apply(
        s,
        moves.isEmpty ? const PassTurn() : PlayMove(moves.first),
      );
    }
    return engine.apply(s, const RollDice());
  }

  test('a saved game comes back as the same game, dice included', () async {
    final before = midGame();
    await SavedGameStore.save(
      SavedGame(
        state: before,
        aiSeats: const {1: AiLevel.hard},
        elapsed: const Duration(minutes: 7),
      ),
    );

    final after = (await SavedGameStore.load())!;
    expect(after.state.fingerprint(), before.fingerprint());
    expect(after.aiSeats, {1: AiLevel.hard});
    expect(after.elapsed, const Duration(minutes: 7));

    // Same position is not enough: the rolls still to come must be the same
    // ones, or a resumed game is a different game that looks alike.
    expect(after.state.rng, before.rng);
    var a = before, b = after.state;
    for (var i = 0; i < 20; i++) {
      final moves = engine.legalMoves(a);
      final action = moves.isEmpty ? const PassTurn() : PlayMove(moves.first);
      a = engine.apply(engine.apply(a, action), const RollDice());
      b = engine.apply(engine.apply(b, action), const RollDice());
      expect(b.fingerprint(), a.fingerprint());
    }
  });

  test('a finished game and a cleared slot offer nothing', () async {
    await SavedGameStore.save(SavedGame(state: midGame()));
    await SavedGameStore.clear();
    expect(await SavedGameStore.load(), isNull);

    var s = GameState.newGame(rules, seed: 3);
    while (!s.isOver) {
      s = engine.apply(s, const RollDice());
      final moves = engine.legalMoves(s);
      if (s.awaitingRoll) continue;
      s = engine.apply(
        s,
        moves.isEmpty ? const PassTurn() : PlayMove(moves.first),
      );
    }
    await SavedGameStore.save(SavedGame(state: s));
    expect(await SavedGameStore.load(), isNull);
  });

  test('a save from some other version is ignored, not misread', () async {
    SharedPreferences.setMockInitialValues({
      'ludo.savedGame': '{"v": 0, "state": {}}',
    });
    expect(await SavedGameStore.load(), isNull);
  });

  testWidgets('playing a local game keeps it saved as it goes', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GameScreen(rules: rules, seed: 11)),
    );
    await tester.pump();
    final fresh = (await SavedGameStore.load())!;
    expect(
      fresh.state.fingerprint(),
      GameState.newGame(rules, seed: 11).fingerprint(),
    );

    await tester.tap(find.byKey(rollDieKey).first);
    await tester.pump();
    final rolled = (await SavedGameStore.load())!;
    expect(rolled.state.stats.toJson(), isNot(fresh.state.stats.toJson()));

    // Let anything the roll set going finish before the test ends.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  });

  testWidgets('the front page offers the saved game back', (tester) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final saved = midGame();
    await SavedGameStore.save(SavedGame(state: saved));
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Continue game'), findsOneWidget);
    await tester.tap(find.text('Continue game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final screen = tester.widget<GameScreen>(find.byType(GameScreen));
    expect(screen.resumeFrom!.state.fingerprint(), saved.fingerprint());

    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  });

  testWidgets('nothing to continue, nothing offered', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Continue game'), findsNothing);
  });
}
