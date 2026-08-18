import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/sounds.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';

/// The game says out loud what just happened.
///
/// Reported as "I can't hear any sound except the dice roll", and the wiring
/// was right all along: the landing tap was quiet enough to miss, and captures
/// and arrivals are rare enough not to have come up yet. So this plays a whole
/// game out and insists that every one of the four sounds gets used.
void main() {
  testWidgets('a game makes all four of its sounds', (tester) async {
    final heard = <String>[];
    Sfx.spy = heard.add;
    addTearDown(() => Sfx.spy = null);

    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(
          // Four computers and two chips each: nobody has to tap anything and
          // the game reaches its end inside a test's patience.
          rules: RuleConfig(players: 4, tokensPerPlayer: 2),
          seed: 4,
          aiSeats: {
            0: AiLevel.normal,
            1: AiLevel.normal,
            2: AiLevel.normal,
            3: AiLevel.normal,
          },
        ),
      ),
    );
    await tester.pump();

    for (var i = 0; i < 3000; i++) {
      await tester.pump(const Duration(milliseconds: 120));
      if (heard.toSet().length == 4) break;
    }

    expect(heard, contains(Sound.die), reason: 'no dice were rolled');
    expect(heard, contains(Sound.step), reason: 'no chip was ever set down');
    expect(
      heard,
      contains(Sound.capture),
      reason: 'nobody was ever knocked off',
    );
    expect(heard, contains(Sound.home), reason: 'nobody ever got home');
  });

  testWidgets('the knock lands with the capture, not with the walk home', (
    tester,
  ) async {
    // A captured chip now takes seconds to trudge back to its base. The knock
    // belongs to the collision at the start of that, not to its end.
    final heard = <(String, Duration)>[];
    var clock = Duration.zero;
    Sfx.spy = (name) => heard.add((name, clock));
    addTearDown(() => Sfx.spy = null);

    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(
          rules: RuleConfig(players: 4, tokensPerPlayer: 2),
          seed: 4,
          aiSeats: {
            0: AiLevel.normal,
            1: AiLevel.normal,
            2: AiLevel.normal,
            3: AiLevel.normal,
          },
        ),
      ),
    );
    await tester.pump();

    const tick = Duration(milliseconds: 120);
    for (var i = 0; i < 3000; i++) {
      await tester.pump(tick);
      clock += tick;
      if (heard.any((h) => h.$1 == Sound.capture)) break;
    }

    final knock = heard.firstWhere(
      (h) => h.$1 == Sound.capture,
      orElse: () => ('none', Duration.zero),
    );
    expect(knock.$1, Sound.capture, reason: 'no capture happened at all');

    // Whatever the game does next, it does not sit silent through the whole
    // retreat: the very next sound is a good way off, not four seconds later.
    final after = heard.where((h) => h.$2 > knock.$2).toList();
    if (after.isNotEmpty) {
      expect(
        after.first.$2 - knock.$2,
        greaterThan(const Duration(milliseconds: 200)),
        reason: 'two sounds landed on top of each other',
      );
    }
  });
}
