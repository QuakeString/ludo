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

  testWidgets('an early tap never throws the next player\'s die', (
    tester,
  ) async {
    // A tap made while the die is still busy is kept for a moment, so a
    // player who taps a little early is not ignored. It used to be kept
    // across the change of turn too, and then the next player's die threw
    // itself — nobody had touched it.
    // A table whose first throw is not a six: nothing can leave home, so the
    // turn passes by itself after the number is shown.
    const rules = RuleConfig(players: 2, tokensPerPlayer: 4);
    var seed = 1;
    while (const LudoEngine()
            .apply(GameState.newGame(rules, seed: seed), const RollDice())
            .dice ==
        6) {
      seed++;
    }
    await tester.pumpWidget(
      MaterialApp(home: GameScreen(rules: rules, seed: seed)),
    );
    await tester.pump();

    await tester.tap(find.byKey(rollDieKey).first);
    await tester.pump(const Duration(milliseconds: 60));
    final first = boardState(tester);
    expect(first.dice, isNotNull);

    // Again, straight away, while the first throw is still tumbling.
    await tester.tap(find.byKey(rollDieKey).first);

    // Play the turn out until the die is somebody else's to throw.
    var next = first;
    for (var i = 0; i < 100 && next.turn == first.turn; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      next = boardState(tester);
    }
    expect(next.turn, isNot(first.turn));

    // Long past any window the early tap could have had.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final later = boardState(tester);
    expect(later.turn, next.turn);
    expect(
      later.awaitingRoll,
      isTrue,
      reason: 'the next player\'s die rolled without anyone touching it',
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
    await closeGame(tester);
  });

  testWidgets('every corner of the die rolls it, not just the middle', (
    tester,
  ) async {
    // "I need to click near to center." The arrow pointing at the die was an
    // icon, and an icon glyph brings the font's own margins with it: the box
    // was half again as wide as the arrow drawn in it, and that invisible
    // half lay across the right-hand third of the die, quietly eating every
    // press that landed there. Nothing looked wrong, which is why it took
    // three goes to find.
    //
    // So this walks the die's whole face rather than trusting its middle.
    final die = find.byKey(rollDieKey);
    final missed = <Offset>[];

    await open(tester);
    final rect = tester.getRect(die.first);
    await closeGame(tester);

    // Two pixels in from each edge — inside the button, and as near the rim as
    // a finger can be while still meaning to press it.
    const pad = 2.0;
    final spots = <Offset>[
      rect.center,
      Offset(rect.left + pad, rect.top + pad),
      Offset(rect.right - pad, rect.top + pad),
      Offset(rect.left + pad, rect.bottom - pad),
      Offset(rect.right - pad, rect.bottom - pad),
      Offset(rect.right - pad, rect.center.dy),
      Offset(rect.left + pad, rect.center.dy),
      Offset(rect.center.dx, rect.top + pad),
      Offset(rect.center.dx, rect.bottom - pad),
    ];

    for (final at in spots) {
      await open(tester);
      expect(boardState(tester).awaitingRoll, isTrue);
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 20));
      if (boardState(tester).dice == null) {
        missed.add(at - rect.center);
      }
      await closeGame(tester);
    }

    expect(
      missed,
      isEmpty,
      reason: 'taps this far from the die\'s centre did nothing: $missed',
    );
  });
}
