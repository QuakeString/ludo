import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/close_game.dart';

import 'package:ludo_app/board/seat_panel.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';

/// Where the seat panels go, and whether you can see them.
void main() {
  Future<Map<int, Rect>> openAndMeasure(WidgetTester tester, int players) async {
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          rules: RuleConfig(players: players, tokensPerPlayer: 4),
          seed: 7,
        ),
      ),
    );
    await tester.pump();

    return {
      for (final e in tester.widgetList<SeatPanel>(find.byType(SeatPanel)))
        e.arm: tester.getRect(find.byWidget(e)),
    };
  }

  testWidgets('six seats deal three to a rail, not two and four', (
    tester,
  ) async {
    // A hexagon has two houses exactly halfway down the board, and asking
    // "is this house above the middle" put both of them below it: six players
    // came out as two panels along the top and four squeezed along the bottom.
    final panels = await openAndMeasure(tester, 6);
    expect(panels.length, 6);

    final mid = panels.values.map((r) => r.center.dy).reduce((a, b) => a + b) /
        panels.length;
    final top = panels.values.where((r) => r.center.dy < mid).length;
    expect(
      top,
      3,
      reason: 'the rails are $top and ${6 - top}, not three and three',
    );
    await closeGame(tester);
  });

  testWidgets('the roll pointer stays on the screen, whichever seat it is', (
    tester,
  ) async {
    // It used to sit beside the die, which for the seat whose panel is pushed
    // against the right edge put it off the screen entirely — the one player
    // being told to roll was the one who could not see it being said.
    for (final players in [2, 4, 6]) {
      await openAndMeasure(tester, players);
      final width = tester.view.physicalSize.width;

      final pointers = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_Chevron',
      );
      expect(
        pointers,
        findsOneWidget,
        reason: '$players seats: exactly one seat is being asked to roll',
      );

      final at = tester.getRect(pointers.first);
      expect(at.left, greaterThanOrEqualTo(0.0),
          reason: '$players seats: the pointer runs off the left');
      expect(at.right, lessThanOrEqualTo(width),
          reason: '$players seats: the pointer runs off the right at $at');
      await closeGame(tester);
    }
  });
}
