import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/match_history.dart';
import 'package:ludo_app/saved_game.dart';
import 'package:ludo_app/screens/game_over.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_app/screens/history_screen.dart';
import 'package:ludo_app/screens/home_screen.dart';
import 'package:ludo_app/screens/match_stats.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/close_game.dart';

/// Finished games are kept on the phone, with their stats, after the result
/// sheet has gone.
void main() {
  const engine = LudoEngine();
  const rules = RuleConfig(players: 2, tokensPerPlayer: 1);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  /// A game played to the end from [seed].
  GameState playedOut(int seed) {
    var s = GameState.newGame(rules, seed: seed);
    for (var i = 0; i < 4000 && !s.isOver; i++) {
      s = engine.apply(s, const RollDice());
      if (s.isOver) break;
      final moves = engine.legalMoves(s);
      s = engine.apply(
        s,
        moves.isEmpty ? const PassTurn() : PlayMove(moves.first),
      );
    }
    expect(s.isOver, isTrue);
    return s;
  }

  MatchRecord recordOf(int seed, {DateTime? at}) => MatchRecord(
    state: playedOut(seed),
    finishedAt: at ?? DateTime(2026, 10, 21, 14, 5),
    elapsed: const Duration(minutes: 6, seconds: 3),
    names: const ['Rajat', 'Green'],
    aiSeats: const {1: AiLevel.hard},
  );

  test('a record comes back with everything the stats page needs', () async {
    final before = recordOf(1);
    await MatchHistoryStore.add(before);
    final [after] = await MatchHistoryStore.load();

    expect(after.state.toJson(), before.state.toJson());
    expect(after.state.stats.totalThrows, before.state.stats.totalThrows);
    expect(after.elapsed, before.elapsed);
    expect(after.finishedAt, before.finishedAt);
    expect(after.nameOf(0), 'Rajat');
    expect(after.aiSeats, {1: AiLevel.hard});
    expect(after.online, isFalse);
  });

  test('keeps the ten newest, newest first', () async {
    for (var seed = 1; seed <= 12; seed++) {
      await MatchHistoryStore.add(recordOf(seed));
    }
    final kept = await MatchHistoryStore.load();
    expect(kept, hasLength(MatchHistoryStore.keep));
    expect(kept.first.state.toJson(), playedOut(12).toJson());
    expect(kept.last.state.toJson(), playedOut(3).toJson());
  });

  test('the same finished game is only kept once', () async {
    await MatchHistoryStore.add(recordOf(4));
    await MatchHistoryStore.add(recordOf(4));
    expect(await MatchHistoryStore.load(), hasLength(1));
  });

  test('a damaged history is read as empty, not as a crash', () async {
    SharedPreferences.setMockInitialValues({'ludo.history': '{not json'});
    expect(await MatchHistoryStore.load(), isEmpty);
  });

  testWidgets('a finished game lands in recent matches', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(
          rules: rules,
          seed: 3,
          aiSeats: {0: AiLevel.normal, 1: AiLevel.normal},
        ),
      ),
    );
    var over = false;
    for (var i = 0; i < 2500 && !over; i++) {
      await tester.pump(const Duration(milliseconds: 120));
      over = find.byType(GameOverSheet).evaluate().isNotEmpty;
    }
    expect(over, isTrue);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    final kept = await tester.runAsync(MatchHistoryStore.load);
    expect(kept, hasLength(1));
    expect(kept!.single.state.isOver, isTrue);
    expect(kept.single.aiSeats.keys, {0, 1});
    await closeGame(tester);
  });

  testWidgets('leaving after you finished still lands in recent matches', (
    tester,
  ) async {
    // Three seats: you are home, the computers play on, and you leave.
    const three = RuleConfig(players: 3, tokensPerPlayer: 1);
    final start = GameState.newGame(three, seed: 2);
    final tokens = [...start.tokens];
    tokens[0] = tokens[0].copyWith(progress: start.board.finalProgress);
    tokens[1] = tokens[1].copyWith(progress: 5);
    tokens[2] = tokens[2].copyWith(progress: 7);
    final s = start.copyWith(tokens: tokens, turn: 1);
    expect(s.isOver, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen.resumed(
          SavedGame(
            state: s,
            aiSeats: const {1: AiLevel.normal, 2: AiLevel.normal},
          ),
        ),
      ),
    );
    await tester.pump();
    await closeGame(tester);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));

    final kept = await tester.runAsync(MatchHistoryStore.load);
    expect(kept, hasLength(1));
    expect(kept!.single.state.hasFinished(0), isTrue);
  });

  testWidgets('recent matches lists them and opens their stats', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await MatchHistoryStore.add(recordOf(1));
      await MatchHistoryStore.add(recordOf(2));
    });
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Recent matches'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recent matches'));
    await tester.pumpAndSettle();
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(find.textContaining(' won'), findsNWidgets(2));
    expect(find.textContaining('6:03'), findsNWidgets(2));

    await tester.tap(find.textContaining(' won').first);
    await tester.pumpAndSettle();
    expect(find.byType(MatchStatsSheet), findsOneWidget);
    expect(find.text('Rajat'), findsOneWidget);
  });

  testWidgets('with nothing finished yet it says so', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HistoryScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Finished games show up here'), findsOneWidget);
  });

  test('when a game was played reads naturally', () {
    final now = DateTime(2026, 10, 21, 20);
    expect(whenPlayed(DateTime(2026, 10, 21, 14, 5), now), 'Today, 14:05');
    expect(whenPlayed(DateTime(2026, 10, 20, 9, 30), now), 'Yesterday, 09:30');
    expect(whenPlayed(DateTime(2026, 10, 3, 18, 12), now), '3 Oct, 18:12');
    expect(
      whenPlayed(DateTime(2025, 12, 31, 23, 59), now),
      '31 Dec 2025, 23:59',
    );
  });
}
