import 'dart:convert';

import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

/// The dice.
///
/// The generator is xorshift32, stepped through the game state rather than
/// drawn from `dart:math`. That is a deliberate trade: a game's whole sequence
/// of rolls follows from its seed, so a match replays exactly, the server and
/// every client agree on the dice without sending them, and a test can
/// reproduce a position. What it costs is that fairness is now this code's
/// problem rather than the platform's — hence these.
void main() {
  const engine = LudoEngine();

  /// Rolls [n] dice from [seed], playing nothing.
  List<int> rolls(int n, {int seed = 1, int sides = 6}) {
    // Triple sixes forfeit a turn under the default rules, which eats the
    // third six before it can be counted — nothing to do with the generator,
    // but it would look like one face coming up short.
    final rules = RuleConfig(
      diceSides: sides,
      sixRun: SixRun.unlimited,
    );
    var s = GameState.newGame(rules, seed: seed);
    final out = <int>[];
    for (var i = 0; i < n; i++) {
      s = engine.apply(s, const RollDice());
      final v = s.dice;
      if (v != null) out.add(v);
      s = s.copyWith(dice: null);
    }
    return out;
  }

  test('every face comes up about as often as every other', () {
    const n = 60000;
    final counts = List.filled(7, 0);
    for (final v in rolls(n, seed: 12345)) {
      counts[v]++;
    }

    // Expect n/6 of each. The standard deviation of a count like this is
    // sqrt(n * 1/6 * 5/6), about 91 here; four of those is a threshold a fair
    // die clears essentially always and a broken one does not.
    const expected = n / 6;
    final sd = (n * (1 / 6) * (5 / 6));
    final tolerance = 4 * (sd > 0 ? _sqrt(sd) : 0);
    for (var face = 1; face <= 6; face++) {
      expect(
        (counts[face] - expected).abs(),
        lessThan(tolerance),
        reason: 'face $face came up ${counts[face]} times in $n',
      );
    }
  });

  test('one roll says nothing about the next', () {
    // xorshift32's low bits are its weakest, and a six-sided die reads exactly
    // those. Parity is the sharpest cheap test of them: if consecutive rolls
    // shared a low bit, odd would follow odd far more or far less than half
    // the time.
    final r = rolls(60000, seed: 999);
    var same = 0;
    for (var i = 1; i < r.length; i++) {
      if (r[i].isEven == r[i - 1].isEven) same++;
    }
    expect(same / (r.length - 1), closeTo(0.5, 0.02));
  });

  test('the dice do not travel to the players', () {
    // The state of the generator is the whole future of the dice: four lines
    // of arithmetic turn it into every roll the rest of the game will make.
    // It used to go out in the state the server broadcasts after every move,
    // which handed every player at the table a perfect prediction of their own
    // and everybody else's throws.
    var s = GameState.newGame(const RuleConfig(), seed: 4242);
    for (var i = 0; i < 30; i++) {
      s = engine.autoPlayTurn(s);
    }

    expect(s.toJson().containsKey('rng'), isFalse,
        reason: 'the dice are being broadcast');
    expect(jsonEncode(s.toJson()), isNot(contains('rng')));

    // What a player receives still describes the position exactly.
    final asSeen = GameState.fromJson(
      jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>,
    );
    expect(asSeen.fingerprint(), s.fingerprint());
    expect(asSeen.rng, isNot(s.rng), reason: 'the dice came through anyway');

    // And the machine that owns the game can still write it down in full.
    final saved = GameState.fromJson(
      jsonDecode(jsonEncode(s.toJson(withDice: true))) as Map<String, Object?>,
    );
    expect(saved.rng, s.rng);
  });

  test('a different seed is a different game', () {
    final a = rolls(40, seed: 1);
    final b = rolls(40, seed: 2);
    final c = rolls(40, seed: 1);
    expect(a, c, reason: 'the same seed must replay exactly');
    expect(a, isNot(b), reason: 'seeds are not being used');
  });

  test('no seat is luckier than any other', () {
    // Reported as "one specific player always gets double six then a five, and
    // it repeats". It did — under a fixed seed, where seat 3 opened 6,6,5 in
    // every game played on the device, because every game used seed 1. The
    // generator was never the problem, but "is one seat favoured" is worth
    // holding down whatever the cause, so: whole games, real turn order, extra
    // rolls on a six and all.
    const rules = RuleConfig(players: 4, tokensPerPlayer: 4);
    final bySeat = List.generate(4, (_) => List.filled(7, 0));

    for (var game = 0; game < 120; game++) {
      var s = GameState.newGame(rules, seed: 1 + game * 7919);
      for (var step = 0; step < 4000 && !s.isOver; step++) {
        if (s.awaitingRoll) {
          final seat = s.turn;
          s = engine.apply(s, const RollDice());
          final v = s.dice;
          if (v != null) bySeat[seat][v]++;
          continue;
        }
        s = engine.autoPlayTurn(s);
      }
    }

    for (var seat = 0; seat < 4; seat++) {
      final n = bySeat[seat].reduce((a, b) => a + b);
      expect(n, greaterThan(5000), reason: 'seat $seat barely played');
      for (var face = 1; face <= 6; face++) {
        // A wide band on purpose: this is here to catch a seat being fed one
        // number systematically, not to re-test the generator — the flatness
        // test above does that properly. Sixes land a little under the rest
        // for every seat because three of them forfeit the turn, and that
        // third six is never dealt.
        expect(
          bySeat[seat][face] / n,
          closeTo(1 / 6, 0.012),
          reason: 'seat $seat sees face $face too often or too rarely',
        );
      }
    }
  });

  test('the sequence does not fall into a short cycle', () {
    // xorshift32 has a period of 2^32-1, so nothing should repeat here. A
    // generator that got stuck would show up as a repeated window.
    final r = rolls(20000, seed: 7);
    final windows = <String>{};
    for (var i = 0; i + 12 <= r.length; i += 12) {
      windows.add(r.sublist(i, i + 12).join());
    }
    // Twelve rolls have 6^12 arrangements; among 1666 windows, a repeat would
    // mean something far more suspicious than luck.
    expect(windows.length, greaterThan(1600));
  });
}

double _sqrt(double v) {
  var x = v;
  for (var i = 0; i < 40; i++) {
    x = 0.5 * (x + v / x);
  }
  return x;
}
