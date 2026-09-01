import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_app/screens/setup_screen.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';

/// Six players is not only three against three.
///
/// The setup screen offered one shape per seat count and called it "3 v 3",
/// so a table of six could never be three pairs — which is a different game,
/// not a variant of the same one.
void main() {
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SetupScreen()));
    await tester.pumpAndSettle();
  }

  Future<GameState> start(WidgetTester tester) async {
    await tester.dragUntilVisible(
      find.text('Start game'),
      find.byType(ListView),
      const Offset(0, -140),
    );
    await tester.tap(find.text('Start game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final game = tester.widget<GameScreen>(find.byType(GameScreen));
    return GameState.newGame(game.rules);
  }

  testWidgets('six seats offer both shapes; four offer only the one', (
    tester,
  ) async {
    await open(tester);

    // Four seats: teams are possible, but there is nothing to choose between,
    // so no chooser is put on the screen for the sake of it.
    await tester.tap(find.text('4').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play as teams'));
    await tester.pumpAndSettle();
    expect(find.text('2 v 2'), findsNothing);
    expect(find.text('Partners sit opposite each other'), findsOneWidget);

    await tester.tap(find.text('6').first);
    await tester.pumpAndSettle();
    expect(find.text('3 v 3'), findsOneWidget);
    expect(find.text('2 v 2 v 2'), findsOneWidget);
  });

  testWidgets('picking three pairs really starts a game of three sides', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('6').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play as teams'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 v 2 v 2'));
    await tester.pumpAndSettle();

    final state = await start(tester);
    expect(state.rules.players, 6);
    expect(state.rules.teams, hasLength(3));
    expect(state.rules.teams!.every((g) => g.length == 2), isTrue);
    // Opposite, not adjacent: on a six-arm board seat 0 faces seat 3.
    expect(state.rules.teams, [
      [0, 3],
      [1, 4],
      [2, 5],
    ]);
    // And the engine agrees it is a team game with three sides in it.
    expect(state.rules.isTeamGame, isTrue);
    expect(state.rules.partnersOf(0), [3]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('and three against three still does what it always did', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text('6').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play as teams'));
    await tester.pumpAndSettle();

    final state = await start(tester);
    expect(state.rules.teams, [
      [0, 2, 4],
      [1, 3, 5],
    ]);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
