import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/screens/throw_flight.dart';
import 'package:ludo_protocol/ludo_protocol.dart';

/// Tapping a player's picture throws something at them: a tray to pick from,
/// then the thing flies across and lands with a show.
void main() {
  testWidgets('the tray offers every throw and returns the one picked', (
    tester,
  ) async {
    int? picked = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async =>
                picked = await pickThrow(context, at: 'Ammu'),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Throw at Ammu'), findsOneWidget);
    for (final (emoji, _) in throwables) {
      expect(find.text(emoji), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('throw-3')));
    await tester.pumpAndSettle();
    expect(picked, 3);
  });

  for (var i = 0; i < throwables.length; i++) {
    testWidgets('${throwables[i].$2} flies, lands and clears away', (
      tester,
    ) async {
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: ThrowFlight(
                  index: i,
                  from: const Offset(40, 500),
                  to: const Offset(300, 100),
                  onDone: () => done = true,
                ),
              ),
            ],
          ),
        ),
      );
      expect(find.text(throwables[i].$1), findsOneWidget);
      // Every frame of the show draws without trouble.
      for (var ms = 0; ms < 2400; ms += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pump(const Duration(milliseconds: 100));
      expect(done, isTrue);
    });
  }
}
