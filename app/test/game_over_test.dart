import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/close_game.dart';

import 'package:ludo_app/board/sounds.dart';
import 'package:ludo_app/screens/game_over.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';

/// What happens after the last chip goes home.
///
/// The game used to simply stop. The board sat there with "Game over" in the
/// corner: no word on who came second, nothing to show for the captures, no
/// fanfare, and no way out but the system's back button.
void main() {
  /// A finished game: seat 1 home, the rest part-way.
  GameState finished() {
    const rules = RuleConfig(players: 4, tokensPerPlayer: 2);
    var s = GameState.newGame(rules, seed: 5);
    final tokens = [...s.tokens];
    for (final t in s.tokensOf(1)) {
      tokens[t.id] = t.copyWith(progress: s.board.finalProgress);
    }
    // Seat 2 nearly there, seat 0 with one home, seat 3 with none.
    tokens[0] = tokens[0].copyWith(progress: s.board.finalProgress);
    tokens[4] = tokens[4].copyWith(progress: 30);
    final caps = [1, 3, 0, 2];
    return s.copyWith(tokens: tokens, finishOrder: const [1], captures: caps);
  }

  test('the table is ranked, winner first, then by what they managed', () {
    final s = finished();
    final table = placings(s);

    expect(table.first.seat, 1, reason: 'the winner is not first');
    expect(table.first.place, 1);
    expect(table.map((p) => p.seat).toSet(), {0, 1, 2, 3});

    // Seat 0 got one home, so it must place above the two that got none.
    final bySeat = {for (final p in table) p.seat: p};
    expect(bySeat[0]!.place, 2);
    // Between the two with nothing home, the one with more captures leads.
    expect(bySeat[3]!.place, lessThan(bySeat[2]!.place));
    expect(bySeat[1]!.captures, 3);
    expect(bySeat[0]!.home, 1);
  });

  testWidgets('the end of a game says who won, and offers a way on', (
    tester,
  ) async {
    final heard = <String>[];
    Sfx.spy = heard.add;
    addTearDown(() => Sfx.spy = null);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          rules: const RuleConfig(players: 2, tokensPerPlayer: 1),
          seed: 3,
          aiSeats: const {1: AiLevel.normal},
        ),
      ),
    );
    await tester.pump();

    // Play it out. One chip each, so this does not take long.
    var over = false;
    for (var i = 0; i < 2500 && !over; i++) {
      final die = find.byKey(const ValueKey<String>('roll-die'));
      if (die.evaluate().isNotEmpty) await tester.tap(die.first);
      await tester.pump(const Duration(milliseconds: 120));
      over = find.byType(GameOverSheet).evaluate().isNotEmpty;
    }

    expect(over, isTrue, reason: 'the game never announced an ending');
    expect(find.textContaining('wins'), findsWidgets);
    expect(find.text('Play again'), findsOneWidget);
    expect(find.text('Leave'), findsOneWidget);
    expect(heard, contains(Sound.victory), reason: 'nobody cheered');

    // And playing again really starts a new game.
    await tester.tap(find.text('Play again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(GameOverSheet), findsNothing);

    await closeGame(tester);
  });
}
