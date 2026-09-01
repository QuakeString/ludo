import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/close_game.dart';

import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/board/die.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';

/// Turns that take themselves.
///
/// Two things a player should never be asked to do: acknowledge a roll that
/// cannot be played, and hunt down the single chip that a roll happens to
/// allow. Neither is a decision. But the screen must still *show* the number
/// that caused it — the first attempt passed 900ms after a throw that tumbles
/// for 780, so the face nobody could read was the face the whole turn hung on.
/// The position the board is actually drawing.
GameState boardState(WidgetTester tester) {
  final finder = find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is BoardPainter,
  );
  return (tester.widget<CustomPaint>(finder.first).painter as BoardPainter)
      .state;
}

void main() {
  Future<void> openGame(
    WidgetTester tester, {
    int tokens = 4,
    int seed = 7,
    Map<int, AiLevel> ai = const {1: AiLevel.normal},
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          rules: RuleConfig(players: 2, tokensPerPlayer: tokens),
          seed: seed,
          aiSeats: ai,
        ),
      ),
    );
  }

  testWidgets('a dead roll stays on show until the die has stopped', (
    tester,
  ) async {
    await openGame(tester);
    await tester.pump();

    // Every chip is in the yard, so anything but a six is a dead roll. Roll
    // until one turns up.
    var elapsed = Duration.zero;
    var found = false;
    for (var i = 0; i < 12 && !found; i++) {
      final die = find.byKey(rollDieKey);
      if (die.evaluate().isEmpty) break;
      await tester.tap(die.first);
      elapsed = const Duration(milliseconds: 30);
      await tester.pump(elapsed);
      found = find.textContaining('no legal move').evaluate().isNotEmpty;
      if (!found) {
        for (var j = 0; j < 40; j++) {
          await tester.pump(const Duration(milliseconds: 120));
        }
      }
    }
    expect(found, isTrue, reason: 'twelve rolls without a non-six');

    // The die is still tumbling here, and for a while after. The number has
    // to survive all of it — and then be legible for a good moment more.
    await tester.pump(Duration(milliseconds: dieRollMillis) - elapsed);
    expect(
      find.textContaining('no legal move'),
      findsOneWidget,
      reason: 'the turn passed before the die had even settled',
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.textContaining('no legal move'),
      findsOneWidget,
      reason: 'a settled die must stay readable, not blink past',
    );

    // And then it does go. It must not sit there for ever.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byType(GameScreen), findsOneWidget);
    await closeGame(tester);
  });

  testWidgets('four spellings of one move is not a choice either', (
    tester,
  ) async {
    // Every chip starts in the yard, so a six offers one move per chip — four
    // entries in the list, one thing that can actually happen, because a
    // player's chips are interchangeable. Being asked to pick between them is
    // a quiz, not a decision.
    await openGame(tester, ai: const {});
    await tester.pump();

    var out = false;
    for (var i = 0; i < 40 && !out; i++) {
      final die = find.byKey(rollDieKey);
      if (die.evaluate().isNotEmpty) await tester.tap(die.first);
      for (var j = 0; j < 26; j++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      // Nothing above ever touches the board — only the die.
      out = boardState(tester).tokens.any((t) => !t.inYard);
    }

    expect(
      out,
      isTrue,
      reason:
          'a six with a full yard sat waiting for a tap that is not a '
          'choice anybody can make wrongly',
    );
    await closeGame(tester);
  });

  testWidgets('the only move plays itself — nobody taps a chip', (
    tester,
  ) async {
    // Two people, no computer, one chip each. From the first six onwards
    // every roll leaves exactly one thing that can be done, and nothing in
    // this test ever touches the board — so if forced moves were not played
    // for you, not a single chip could move and the game could not end.
    await openGame(tester, tokens: 1, seed: 3, ai: const {});
    await tester.pump();

    var over = false;
    for (var i = 0; i < 2500 && !over; i++) {
      final die = find.byKey(rollDieKey);
      if (die.evaluate().isNotEmpty) {
        await tester.tap(die.first);
      }
      await tester.pump(const Duration(milliseconds: 120));
      over = find.text('Game over').evaluate().isNotEmpty;
    }

    expect(
      over,
      isTrue,
      reason: 'the game stalled waiting for a tap on a move with no choice',
    );
    // And somebody actually got a chip round the board to do it. Twice over
    // now, since the end-of-game sheet tallies the same thing the seat panel
    // does — which is the point of it.
    expect(find.text('1/1'), findsAtLeastNWidgets(1));
  });
}
