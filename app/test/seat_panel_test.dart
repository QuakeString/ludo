import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/board/seat_panel.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

/// A player's name and die belong over that player's corner.
///
/// They drifted twice. First the rail took the whole window while the board is
/// a square in the middle of it, which on a desktop put a die half a screen
/// from its house. Then the rail was split in half per side — which is still
/// not where a house is: a house sits a fifth of the way across the board, not
/// a quarter.
void main() {
  testWidgets('every seat panel sits over its own house', (tester) async {
    // A desktop window, which is the case that went wrong. On a narrow screen
    // a panel can be wider than the distance from the board's edge to the
    // middle of the house, and then it is clamped to stay on the rail — right,
    // but not what is under test here.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(rules: RuleConfig(players: 4), seed: 3),
      ),
    );
    await tester.pump();

    final boardFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is BoardPainter,
    );
    final board = tester.getRect(boardFinder.first);
    final state =
        (tester.widget<CustomPaint>(boardFinder.first).painter as BoardPainter)
            .state;
    final geometry = BoardGeometry.forSpec(state.board);

    for (var seat = 0; seat < 4; seat++) {
      final arm = state.armOf(seat);
      final slots = geometry.yardSlots(arm);
      final houseX =
          slots.map((p) => p.x).reduce((a, b) => a + b) / slots.length;

      final panel = find.byWidgetPredicate(
        (w) => w is SeatPanel && w.arm == arm,
      );
      expect(panel, findsOneWidget, reason: 'no panel for arm $arm');

      expect(
        tester.getCenter(panel).dx,
        closeTo(board.left + houseX * board.width, 1.0),
        reason: 'the panel for arm $arm is not over its house',
      );
    }
  });
}
