import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/board/die.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';

void main() {
  GameState st(WidgetTester tester) {
    final f = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is BoardPainter,
    );
    return (tester.widget<CustomPaint>(f.first).painter as BoardPainter).state;
  }

  testWidgets('probe', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(
          rules: RuleConfig(players: 2, tokensPerPlayer: 4),
          seed: 11,
        ),
      ),
    );
    await tester.pump();

    var attempts = 0, worked = 0;
    for (var turn = 0; turn < 40; turn++) {
      // Wait until the die is offered.
      var waited = 0;
      while (find.byKey(rollDieKey).evaluate().isEmpty && waited < 80) {
        await tester.pump(const Duration(milliseconds: 60));
        waited++;
      }
      if (find.byKey(rollDieKey).evaluate().isEmpty) break;

      final before = st(tester).dice;
      final at = tester.getCenter(find.byKey(rollDieKey).first);
      final g = await tester.startGesture(at, kind: PointerDeviceKind.touch);
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 30));
      attempts++;
      if (st(tester).dice != null && st(tester).dice != before) worked++;

      // Let the turn play out.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    debugPrint('TAPPROBE attempts=$attempts worked=$worked');
  });
}
