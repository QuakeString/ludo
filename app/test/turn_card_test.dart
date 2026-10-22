import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/seat_panel.dart';

Widget _panel({
  VoidCallback? onRoll,
  bool onTurn = true,
  Duration? turnLength,
  DateTime? turnEndsAt,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 200,
        child: SeatPanel(
          arm: 0,
          arms: 4,
          name: 'You',
          home: 0,
          total: 4,
          onTurn: onTurn,
          onRoll: onRoll,
          turnLength: turnLength,
          turnEndsAt: turnEndsAt,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('a tap anywhere on the card rolls, not only on the die', (
    tester,
  ) async {
    var rolls = 0;
    await tester.pumpWidget(_panel(onRoll: () => rolls++));
    final card = tester.getRect(find.byType(SeatPanel));
    // Off the die: the name's corner of the card.
    await tester.tapAt(card.topLeft + const Offset(8, 8));
    expect(rolls, 1);
    await tester.tapAt(card.bottomLeft + const Offset(40, -6));
    expect(rolls, 2);
  });

  testWidgets('the turn border drains with the clock and keeps going', (
    tester,
  ) async {
    await tester.pumpWidget(
      _panel(
        turnLength: const Duration(seconds: 30),
        turnEndsAt: DateTime.now().add(const Duration(seconds: 30)),
      ),
    );
    // The border animates on its own between server updates.
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pump(const Duration(seconds: 31));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
