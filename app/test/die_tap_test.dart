import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/close_game.dart';

import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/board/die.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';

/// Tapping the die rolls it — every time, not most times.
///
/// Reported from a real phone and a real browser: "most of the time it does
/// not roll on the first try, sometimes it does". A test that taps
/// instantaneously never sees this, because a finger does not.
void main() {
  GameState boardState(WidgetTester tester) {
    final finder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is BoardPainter,
    );
    return (tester.widget<CustomPaint>(finder.first).painter as BoardPainter)
        .state;
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(
          rules: RuleConfig(players: 2, tokensPerPlayer: 4),
          seed: 11,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('an instant tap rolls', (tester) async {
    await open(tester);
    expect(boardState(tester).awaitingRoll, isTrue);

    await tester.tap(find.byKey(rollDieKey).first);
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      boardState(tester).dice,
      isNotNull,
      reason: 'an instant tap did not roll',
    );
    await closeGame(tester);
  });

  testWidgets('a real press-and-release rolls', (tester) async {
    await open(tester);

    // What a finger actually does: press, hold for a moment while the screen
    // carries on animating underneath it, then let go.
    final at = tester.getCenter(find.byKey(rollDieKey).first);
    final touch = await tester.startGesture(at, kind: PointerDeviceKind.touch);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    await touch.up();
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      boardState(tester).dice,
      isNotNull,
      reason: 'a press held for a tenth of a second did not roll',
    );
    await closeGame(tester);
  });

  testWidgets('a tap that arrives too early is kept, not dropped', (
    tester,
  ) async {
    // The die is only a real throw to make in the gaps between everything
    // else, and the gaps are short. Tapping while a chip is still walking used
    // to do nothing at all, which reads as the game ignoring you rather than
    // as the game being busy — and is why rolling "did not work the first
    // time, most of the time".
    await open(tester);

    // Roll, then tap again immediately, while the die is still tumbling and
    // the turn is very much not ready for another throw.
    await tester.tap(find.byKey(rollDieKey).first);
    await tester.pump(const Duration(milliseconds: 60));
    final first = boardState(tester).dice;
    expect(first, isNotNull);

    expect(
      find.byKey(rollDieKey),
      findsWidgets,
      reason: 'the die stopped being a button the moment it was busy',
    );
    await tester.tap(find.byKey(rollDieKey).first);
    await tester.pump(const Duration(milliseconds: 30));

    // Nothing happens yet — it is not this player's throw to make again.
    expect(boardState(tester).dice, first);

    // But it is not forgotten either: as soon as the board comes free the
    // waiting tap is spent.
    var rolledAgain = false;
    for (var i = 0; i < 80 && !rolledAgain; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final s = boardState(tester);
      rolledAgain = s.dice != null && !s.awaitingRoll && s.dice != first;
    }
    expect(
      rolledAgain,
      isTrue,
      reason: 'the early tap was thrown away instead of being honoured',
    );
    await closeGame(tester);
  });

  testWidgets('a press that drifts a little still rolls', (tester) async {
    await open(tester);

    // Fingers move. A few pixels of travel is a tap, not a drag, and a die is
    // not a scrollable thing that a small slide should mean something else to.
    final at = tester.getCenter(find.byKey(rollDieKey).first);
    final touch = await tester.startGesture(at, kind: PointerDeviceKind.touch);
    await tester.pump(const Duration(milliseconds: 30));
    await touch.moveBy(const Offset(3, 4));
    await tester.pump(const Duration(milliseconds: 30));
    await touch.up();
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      boardState(tester).dice,
      isNotNull,
      reason: 'a tap that moved three pixels was thrown away',
    );
  });
}
