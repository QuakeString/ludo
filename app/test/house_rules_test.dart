import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_app/screens/house_rules.dart';
import 'package:ludo_app/screens/setup_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';

import 'support/close_game.dart';

/// Whoever sets the table up picks its house rules, and everyone at it can
/// read them on the rule board.
void main() {
  test('classic rules are counted as no changes', () {
    expect(changesFromClassic(const RuleConfig()), 0);
    expect(
      changesFromClassic(
        const RuleConfig(entryRoll: 0, safeSquares: SafeSquares.none),
      ),
      2,
    );
  });

  test('the rule board says what changed, in words', () {
    final classic = ruleLines(const RuleConfig());
    expect(classic, contains('Only a 6 brings a chip out of the base.'));
    expect(classic, contains('No turn timer.'));

    final house = ruleLines(
      const RuleConfig(
        entryRoll: 0,
        extraRollOnSix: false,
        safeSquares: SafeSquares.none,
        mustCaptureToWin: true,
        turnTimerDots: 6,
        secondsPerDot: 10,
      ),
    );
    expect(house, contains('Any number brings a chip out of the base.'));
    expect(house, contains('A six does not give another roll.'));
    expect(house, contains('No square is safe.'));
    expect(house.join(' '), contains('knock off at least one chip'));
    expect(house.join(' '), contains('60 seconds'));
  });

  testWidgets('sharing chips with a partner is offered only to teams', (
    tester,
  ) async {
    Future<void> show(RuleConfig r) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RulesEditor(rules: r, onChanged: (_) {}),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('custom-rules')));
      await tester.pumpAndSettle();
    }

    await show(const RuleConfig());
    expect(find.byKey(const ValueKey('rule-share')), findsNothing);

    const teams = RuleConfig(
      teams: [
        [0, 2],
        [1, 3],
      ],
      partnersShareChips: true,
    );
    await show(teams);
    expect(find.byKey(const ValueKey('rule-share')), findsOneWidget);
    expect(changesFromClassic(teams), 1);
    expect(ruleLines(teams).join(' '), contains("each other's chips"));
  });

  testWidgets('pass & play starts with the rules that were picked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: SetupScreen()));

    await tester.tap(find.byKey(const ValueKey('custom-rules')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Any number'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('rule-mustcapture')));
    await tester.tap(find.byKey(const ValueKey('rule-mustcapture')));
    await tester.pumpAndSettle();
    expect(find.text('2 changes from classic'), findsOneWidget);

    await tester.ensureVisible(find.text('Start game'));
    await tester.tap(find.text('Start game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final game = tester.widget<GameScreen>(find.byType(GameScreen));
    expect(game.rules.entryRoll, 0);
    expect(game.rules.mustCaptureToWin, isTrue);

    // And the table can read them back.
    await tester.tap(find.byKey(const ValueKey('game-rules')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('rule-board')), findsOneWidget);
    expect(
      find.text('Any number brings a chip out of the base.'),
      findsOneWidget,
    );
    await closeGame(tester);
  });
}
