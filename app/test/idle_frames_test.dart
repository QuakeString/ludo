import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';

import 'support/close_game.dart';

/// A table nobody touches stops drawing, so a phone left on it while
/// somebody thinks is not spending its battery on a still picture.
void main() {
  testWidgets('a game waiting on a roll goes still after a few seconds', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(rules: RuleConfig(players: 2), seed: 1),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      SchedulerBinding.instance.hasScheduledFrame,
      isTrue,
      reason: 'it should nudge the player to roll at first',
    );

    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(SchedulerBinding.instance.hasScheduledFrame, isFalse);
    await closeGame(tester);
  });
}
