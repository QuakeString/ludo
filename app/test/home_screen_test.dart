import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_app/screens/home_screen.dart';
import 'package:ludo_app/screens/online_screen.dart';
import 'package:ludo_app/screens/setup_screen.dart';
import 'package:ludo_app/screens/game_screen.dart';

/// The front door.
///
/// It used to open straight onto the settings — seat counts, chip counts,
/// difficulty — which asks the wrong question first: how you want to play
/// decides which of those even apply.
void main() {
  Future<void> openHome(WidgetTester tester, {Size? size}) async {
    tester.view.physicalSize = size ?? const Size(400, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
  }

  testWidgets('offers four ways to play and no settings at all', (
    tester,
  ) async {
    await openHome(tester);
    for (final card in [
      'Pass & play',
      'Play the computer',
      'Play with friends',
      'Online',
    ]) {
      expect(find.text(card), findsOneWidget, reason: '$card is missing');
    }

    // None of the dials. They belong behind a mode, not in front of one.
    expect(find.byType(SegmentedButton<int>), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Start game'), findsNothing);
  });

  testWidgets('each card leads where it says', (tester) async {
    await openHome(tester);

    await tester.tap(find.text('Pass & play'));
    await tester.pumpAndSettle();
    expect(find.byType(SetupScreen), findsOneWidget);
    expect(
      tester.widget<SetupScreen>(find.byType(SetupScreen)).mode,
      LocalMode.passAndPlay,
    );
    // And the table it offers is one of people: choosing to pass a phone round
    // and being handed a table of computers is the app not having listened.
    expect(
      find.widgetWithText(SegmentedButton<int>, '0'),
      findsWidgets,
      reason: 'no computer-count control',
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play the computer'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<SetupScreen>(find.byType(SetupScreen)).mode,
      LocalMode.computer,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Play with friends'));
    // Pumped, not settled: this screen opens a socket and spins while it
    // waits, and a spinner never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(OnlineScreen), findsOneWidget);
  });

  testWidgets('the card with nothing behind it says so instead of pretending', (
    tester,
  ) async {
    // There is no matchmaking queue yet — rooms exist, joining strangers does
    // not. A card that leads somewhere it cannot deliver is worse than one
    // that admits it.
    await openHome(tester);
    expect(find.text('SOON'), findsOneWidget);

    await tester.tap(find.text('Online'));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byType(OnlineScreen), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('choosing the computer starts with computers at the table', (
    tester,
  ) async {
    await openHome(tester);
    await tester.tap(find.text('Play the computer'));
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Start game'),
      find.byType(ListView),
      const Offset(0, -140),
    );
    await tester.tap(find.text('Start game'));
    // The board animates from the moment it opens, so it is pumped rather
    // than settled.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final game = tester.widget<GameScreen>(find.byType(GameScreen));
    expect(
      game.aiSeats.length,
      game.rules.players - 1,
      reason: 'every seat but yours should be a computer',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
  });
}
