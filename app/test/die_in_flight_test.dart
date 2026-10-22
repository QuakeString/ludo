import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/die.dart';

/// Online the number comes from the server. The die starts tumbling the
/// moment it is tapped, and lands when the number arrives.
void main() {
  Widget die({int? value, bool rolling = false}) => MaterialApp(
    home: Center(
      child: DieFace(
        value: value,
        arm: 0,
        arms: 4,
        live: true,
        mute: true,
        rolling: rolling,
      ),
    ),
  );

  testWidgets('tumbles while the number is on its way, then lands', (
    tester,
  ) async {
    await tester.pumpWidget(die());
    await tester.pump(const Duration(seconds: 5));
    final before = tester.binding.hasScheduledFrame;

    await tester.pumpWidget(die(rolling: true));
    // Still tumbling well past one throw: it waits for the number.
    await tester.pump(const Duration(milliseconds: dieRollMillis * 2));
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pumpWidget(die(value: 5));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, before);
  });

  testWidgets('comes to rest if the number never comes', (tester) async {
    await tester.pumpWidget(die());
    await tester.pump(const Duration(seconds: 5));
    final before = tester.binding.hasScheduledFrame;
    await tester.pumpWidget(die(rolling: true));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(die());
    await tester.pump(const Duration(milliseconds: dieRollMillis));
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, before);
  });
}
