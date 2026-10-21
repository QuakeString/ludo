import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/screens/kick_banner.dart';
import 'package:ludo_protocol/ludo_protocol.dart';

/// The host is asked, with a clock, whether a player who keeps missing turns
/// may stay.
void main() {
  Future<List<String>> open(WidgetTester tester) async {
    final answers = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: KickBanner(
            ask: const KickAsk(seat: 1, name: 'Ammu', missed: 5, seconds: 10),
            until: DateTime.now().add(const Duration(seconds: 10)),
            onKeep: () => answers.add('keep'),
            onRemove: () => answers.add('remove'),
          ),
        ),
      ),
    );
    return answers;
  }

  testWidgets('names the player and counts down', (tester) async {
    await open(tester);
    expect(find.textContaining('Ammu has missed 5 turns'), findsOneWidget);
    expect(find.text('10s'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('6s'), findsOneWidget);
  });

  testWidgets('the host can keep or remove them', (tester) async {
    final answers = await open(tester);
    await tester.tap(find.byKey(const ValueKey('kick-keep')));
    await tester.tap(find.byKey(const ValueKey('kick-remove')));
    expect(answers, ['keep', 'remove']);
  });
}
