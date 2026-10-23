import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The new-game button asks first, so a stray tap does not wipe the board.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openGame(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(rules: RuleConfig(players: 4), seed: 3),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const ValueKey('game-reset')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('reset asks, and cancel keeps the game', (tester) async {
    await openGame(tester);
    expect(find.text('Start a new game?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reset-cancel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Start a new game?'), findsNothing);
    expect(find.byType(GameScreen), findsOneWidget);
  });

  testWidgets('reset asks, and confirming deals again', (tester) async {
    await openGame(tester);
    await tester.tap(find.byKey(const ValueKey('reset-go')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Start a new game?'), findsNothing);
    expect(find.byType(GameScreen), findsOneWidget);
  });
}
