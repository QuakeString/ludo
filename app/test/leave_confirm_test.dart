import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Back during a game asks first, so a slip of the thumb does not end it.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openGame(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    const GameScreen(rules: RuleConfig(players: 4), seed: 3),
              ),
            ),
            child: const Text('play'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('play'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('back asks, and staying keeps the game', (tester) async {
    await openGame(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Leave the game?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('leave-stay')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('back asks, and leaving leaves', (tester) async {
    await openGame(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('leave-go')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('play'), findsOneWidget);
  });
}
