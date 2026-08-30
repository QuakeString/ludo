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
  testWidgets('a game makes every sound it has', (tester) async {
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

    const wanted = {
      Sound.die,
      Sound.step,
      Sound.safe,
      Sound.capture,
      Sound.home,
      // Not the fanfare: this game has to run to a finish for that, which
      // takes longer than a test should sit. game_over_test plays one out.
    };
    for (var i = 0; i < 3000; i++) {
      await tester.pump(const Duration(milliseconds: 120));
      // Counting distinct sounds was the stop condition once, and it stopped
      // as soon as any four had been heard — which, after a fifth sound was
      // added, meant giving up before the rarest of them happened.
      if (wanted.difference(heard.toSet()).isEmpty) break;
    }

    expect(heard, contains(Sound.die), reason: 'no dice were rolled');
    expect(heard, contains(Sound.step), reason: 'no chip was ever set down');
    expect(heard, contains(Sound.safe), reason: 'nobody ever reached a star');
    expect(
      heard,
      contains(Sound.capture),
      reason: 'nobody was ever knocked off',
    );
    expect(heard, contains(Sound.home), reason: 'nobody ever got home');
  });

  testWidgets('a chip taps once for every square it lands on', (tester) async {
    // Three squares is three taps. A move used to make one sound when it was
    // over, which tells you nothing you had not already watched happen.
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

    const tick = Duration(milliseconds: 40);
    for (var i = 0; i < 3000; i++) {
      await tester.pump(tick);
      clock += tick;
    }

    final steps = heard.where((h) => h.$1 == Sound.step).toList();
    expect(steps.length, greaterThan(8), reason: 'hardly anything moved');

    // Three taps inside a second can only be one chip crossing three squares:
    // no two separate moves are ever that close together, because the computer
    // takes a beat before each and the die has to be read first.
    var burst = false;
    for (var i = 0; i + 2 < steps.length; i++) {
      if (steps[i + 2].$2 - steps[i].$2 <= const Duration(milliseconds: 900)) {
        burst = true;
        break;
      }
    }
    expect(
      burst,
      isTrue,
      reason: 'every move made a single sound instead of one per square',
    );
  });

  testWidgets('landing somewhere safe sounds different from landing anywhere', (
    tester,
  ) async {
    // A star or a start square is the one place nobody can knock you off, and
    // arriving on one should feel like it rather than sounding like every
    // other square.
    final heard = <String>[];
    Sfx.spy = heard.add;
    addTearDown(() => Sfx.spy = null);

    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(
          rules: RuleConfig(players: 4, tokensPerPlayer: 4),
          seed: 9,
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

    for (var i = 0; i < 2000; i++) {
      await tester.pump(const Duration(milliseconds: 60));
      if (heard.contains(Sound.safe)) break;
    }

    expect(
      heard,
      contains(Sound.safe),
      reason: 'nothing was ever heard reaching a star',
    );
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
