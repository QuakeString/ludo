import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';

/// A chip standing on the outside row keeps its head.
///
/// The chips are pieces, not counters: each is drawn taller than the square it
/// stands on, so one on the board's edge reaches past it. The stack the board
/// is built from clips to its bounds by default, and it sliced those heads off
/// flat — which looks like a rendering fault, because it is one.
void main() {
  testWidgets('the board does not clip its own chips', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(rules: RuleConfig(players: 4), seed: 3),
      ),
    );
    await tester.pump();

    // The stack holding the board's layers is the one whose children paint
    // with a BoardPainter.
    final stacks = find.byWidgetPredicate(
      (w) =>
          w is Stack &&
          w.children.any(
            (c) =>
                c is RepaintBoundary &&
                c.child is CustomPaint &&
                (c.child! as CustomPaint).painter is BoardPainter,
          ),
    );
    expect(stacks, findsOneWidget, reason: 'the board stack moved');
    expect(
      tester.widget<Stack>(stacks).clipBehavior,
      Clip.none,
      reason: 'chips on the outside row will have their heads cut flat',
    );
  });
}
