import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/die.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';

/// Playing against the computer on one device.
///
/// The engine's own tests prove the computer picks good moves. What they
/// cannot see is whether the *screen* ever gives it the turn — and it did not:
/// a person rolling with no legal move auto-passed, and nothing handed over,
/// so the board sat on "Computer — roll the dice" for ever. These tests drive
/// the real widget, because that is the only place that bug lived.
void main() {
  Future<void> openGame(WidgetTester tester, {AiLevel level = AiLevel.normal}) {
    return tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          rules: const RuleConfig(players: 2, tokensPerPlayer: 4),
          seed: 7,
          aiSeats: {1: level},
        ),
      ),
    );
  }

  /// Taps whatever the controls currently offer, then lets timers run.
  Future<void> takeATurn(WidgetTester tester) async {
    final roll = find.byKey(rollDieKey);
    if (roll.evaluate().isNotEmpty) {
      if (roll.evaluate().isNotEmpty) await tester.tap(roll.first);
    }
    // Long enough for the auto-pass (900ms), the computer's beat (600ms) and
    // any move it plays out.
    await tester.pump(const Duration(milliseconds: 60));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('the computer takes its turn instead of the board freezing', (
    tester,
  ) async {
    await openGame(tester);
    await tester.pump();

    // Play as the person for a while. Rolling is all this test does — the
    // point is that control keeps coming back, not that it plays well.
    for (var i = 0; i < 12; i++) {
      await takeATurn(tester);
    }

    // If the handover were missing, the screen would be stuck announcing the
    // computer's turn with nothing ever happening.
    final stuck = find.textContaining('Computer (normal) — roll the dice');
    expect(
      stuck,
      findsNothing,
      reason: 'the board is waiting on a computer that will never play',
    );
  });

  testWidgets('a roll with nothing to play hands over instead of stopping', (
    tester,
  ) async {
    await openGame(tester);
    await tester.pump();

    // Every chip starts in the yard, so any roll that is not a six has no
    // legal move — the exact path that used to auto-pass into silence. Roll
    // until that happens.
    var sawTheDeadRoll = false;
    for (var i = 0; i < 10 && !sawTheDeadRoll; i++) {
      final button = find.byKey(rollDieKey);
      if (button.evaluate().isEmpty) break;
      await tester.tap(button.first);
      await tester.pump(const Duration(milliseconds: 30));
      sawTheDeadRoll = find
          .textContaining('no legal move')
          .evaluate()
          .isNotEmpty;
      if (!sawTheDeadRoll) {
        for (var j = 0; j < 30; j++) {
          await tester.pump(const Duration(milliseconds: 120));
        }
      }
    }
    expect(
      sawTheDeadRoll,
      isTrue,
      reason: 'ten rolls without a single non-six is not a real board',
    );

    // Now let everything run: the auto-pass, the computer's turn, its move.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }

    expect(
      find.textContaining('Computer (normal) — roll the dice'),
      findsNothing,
      reason: 'the computer was handed the turn and never took it',
    );
    expect(
      find.text('Thinking…'),
      findsNothing,
      reason: 'the board is still waiting on a turn nobody will play',
    );
  });
}
