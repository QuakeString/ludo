import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/close_game.dart';

import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/board/die.dart';
import 'package:ludo_app/board/seat_panel.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

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

  testWidgets('the panels line up in columns, whatever the names are', (
    tester,
  ) async {
    // Reported from a phone with an arrow drawn on it. The panels were sized
    // to what was written in them, so "Yellow" came out wider than "Red" and
    // was pinned against the edge of the screen while "Red", directly above
    // it, kept its margin. One long name and the column stopped lining up.
    //
    // They are the width of the house they sit over now, so the two rails and
    // the board make one grid.
    final panels = await openAndMeasure(tester, 4);
    expect(panels.length, 4);

    final byColumn = <String, List<Rect>>{};
    for (final r in panels.values) {
      byColumn
          .putIfAbsent(r.center.dx < 200 ? 'left' : 'right', () => [])
          .add(r);
    }
    expect(byColumn.keys.toSet(), {'left', 'right'});

    for (final entry in byColumn.entries) {
      final rects = entry.value;
      expect(rects, hasLength(2), reason: '${entry.key}: not two panels');
      expect(
        rects[0].left,
        closeTo(rects[1].left, 0.5),
        reason: '${entry.key} column: left edges disagree',
      );
      expect(
        rects[0].right,
        closeTo(rects[1].right, 0.5),
        reason: '${entry.key} column: right edges disagree',
      );
    }

    // And the width is the house's, not the text's.
    final board = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is BoardPainter,
      ).first,
    );
    final side = board.shortestSide;
    final geometry = BoardGeometry.forSpec(BoardSpec.cross);
    final tri = geometry.yardShape(0);
    final houseWidth =
        ([tri.a.x, tri.b.x, tri.c.x]..sort()).last -
            ([tri.a.x, tri.b.x, tri.c.x]..sort()).first;
    for (final r in panels.values) {
      expect(
        r.width,
        closeTo(houseWidth * side, 1),
        reason: 'a panel is not the width of its house',
      );
    }
    await closeGame(tester);
  });

  testWidgets('the die sits at the panel edge the arrow points from', (
    tester,
  ) async {
    // The arrow is placed from the panel's right-hand edge, so the die has to
    // be there. Given a width larger than its contents the row packed to the
    // left and left the die stranded in the middle, with the arrow bobbing
    // under empty panel.
    await openAndMeasure(tester, 4);
    final die = tester.getRect(find.byKey(rollDieKey).first);
    final pointer = tester.getRect(
      find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter.runtimeType.toString() == '_Chevron',
      ).first,
    );
    expect(
      pointer.center.dx,
      closeTo(die.center.dx, 2),
      reason: 'the arrow is not under the die it points at',
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
