import 'dart:convert';

import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

const engine = LudoEngine();

/// Plays a whole game with auto-play, returning the final state and how many
/// turns it took. [cap] guards against a rule set that cannot terminate.
({GameState state, int turns}) playOut(RuleConfig rules, int seed,
    {int cap = 20000}) {
  var s = GameState.newGame(rules, seed: seed);
  var turns = 0;
  while (!s.isOver && turns < cap) {
    s = engine.autoPlayTurn(s);
    turns++;
  }
  return (state: s, turns: turns);
}

void main() {
  group('determinism', () {
    test('the same seed replays to the same state, every time', () {
      for (final seed in [1, 2, 42, 999, 123456]) {
        final a = playOut(const RuleConfig(), seed);
        final b = playOut(const RuleConfig(), seed);
        expect(a.state.fingerprint(), b.state.fingerprint(),
            reason: 'seed $seed diverged');
        expect(a.turns, b.turns);
      }
    });

    test('different seeds really do produce different games', () {
      final prints = {
        for (final seed in [1, 2, 3, 4, 5, 6, 7, 8])
          playOut(const RuleConfig(), seed).state.fingerprint()
      };
      expect(prints.length, greaterThan(1));
    });

    test('a state carries its own dice cursor, so replay needs only the seed',
        () {
      var s = GameState.newGame(const RuleConfig(), seed: 77);
      final rolls = <int>[];
      for (var i = 0; i < 20; i++) {
        expect(engine.peekRoll(s), isNot(0));
        final before = engine.peekRoll(s);
        s = engine.apply(s, const RollDice());
        if (s.dice != null) {
          expect(s.dice, before, reason: 'peek must match the real roll');
          rolls.add(s.dice!);
        }
        s = s.copyWith(dice: null); // discard the move, keep the cursor
      }
      final replay = <int>[];
      var t = GameState.newGame(const RuleConfig(), seed: 77);
      for (var i = 0; i < 20; i++) {
        t = engine.apply(t, const RollDice());
        if (t.dice != null) replay.add(t.dice!);
        t = t.copyWith(dice: null);
      }
      expect(replay, rolls);
    });

    test('dice stay inside the face range and cover it', () {
      var s = GameState.newGame(const RuleConfig(), seed: 5);
      final seen = <int>{};
      for (var i = 0; i < 600; i++) {
        s = engine.apply(s, const RollDice());
        if (s.dice != null) {
          expect(s.dice, inInclusiveRange(1, 6));
          seen.add(s.dice!);
        }
        s = s.copyWith(dice: null, consecutiveSixes: 0);
      }
      expect(seen, {1, 2, 3, 4, 5, 6}, reason: 'every face should turn up');
    });
  });

  group('games finish', () {
    final configs = <String, RuleConfig>{
      'classic 4p': const RuleConfig(),
      'quick 2 tokens, any entry': RuleConfig.quick,
      'aggressive': RuleConfig.aggressive,
      'six seats, pairs on': RuleConfig.sixSeat,
      'two players': const RuleConfig(players: 2),
      'three players': const RuleConfig(players: 3),
      'five players': const RuleConfig(players: 5, tokensPerPlayer: 3),
      'no safe squares': const RuleConfig(safeSquares: SafeSquares.none),
      'loose home entry': const RuleConfig(exactHomeEntry: false),
      'teams 2v2': const RuleConfig(players: 4, tokensPerPlayer: 2, teams: [
        [0, 2],
        [1, 3]
      ]),
      'teams 3v3 with pairs': const RuleConfig(
        players: 6,
        tokensPerPlayer: 3,
        pairMove: true,
        teams: [
          [0, 2, 4],
          [1, 3, 5]
        ],
      ),
    };

    configs.forEach((label, rules) {
      test('$label reaches a winner', () {
        for (final seed in [1, 17, 205, 4096]) {
          final r = playOut(rules, seed);
          expect(r.state.isOver, isTrue,
              reason: '$label did not finish from seed $seed '
                  'after ${r.turns} turns');
          expect(r.state.winner, isNotNull);
        }
      });
    });

    test('mustCaptureToWin still finishes — captures happen on the way', () {
      // Without safe squares, captures are frequent enough that this rule
      // never deadlocks.
      const rules =
          RuleConfig(mustCaptureToWin: true, safeSquares: SafeSquares.stars);
      for (final seed in [3, 88, 1500]) {
        final r = playOut(rules, seed, cap: 60000);
        expect(r.state.isOver, isTrue, reason: 'seed $seed stalled');
        expect(r.state.captures[r.state.winner!], greaterThan(0));
      }
    });
  });

  group('invariants hold across a whole game', () {
    test('token count, ownership and progress stay sane', () {
      for (final rules in [
        const RuleConfig(),
        RuleConfig.sixSeat,
        const RuleConfig(
            players: 6,
            tokensPerPlayer: 3,
            pairMove: true,
            teams: [
              [0, 2, 4],
              [1, 3, 5]
            ]),
      ]) {
        var s = GameState.newGame(rules, seed: 31);
        final expectedTokens = rules.players * rules.tokensPerPlayer;
        var guard = 0;
        while (!s.isOver && guard++ < 20000) {
          s = engine.autoPlayTurn(s);

          expect(s.tokens, hasLength(expectedTokens));
          for (final t in s.tokens) {
            expect(t.progress, greaterThanOrEqualTo(-1));
            expect(t.progress, lessThanOrEqualTo(s.board.finalProgress));
            expect(t.owner, inInclusiveRange(0, rules.players - 1));
          }
          // Every pair has exactly two members, both on the same square.
          final byPair = <int, List<Token>>{};
          for (final t in s.tokens) {
            if (t.isPaired) byPair.putIfAbsent(t.pairId, () => []).add(t);
          }
          for (final entry in byPair.entries) {
            expect(entry.value, hasLength(2),
                reason: 'pair ${entry.key} has ${entry.value.length} members');
            expect(entry.value.first.progress, entry.value.last.progress,
                reason: 'pair ${entry.key} is split across two squares');
          }
        }
        expect(s.isOver, isTrue, reason: '$rules never finished');
      }
    });

    test('a captured token always goes back to its own yard', () {
      var s = GameState.newGame(const RuleConfig(safeSquares: SafeSquares.none),
          seed: 12);
      var captureSeen = 0;
      var guard = 0;
      while (!s.isOver && guard++ < 20000) {
        final before = s;
        final moves = engine.legalMoves(
            s.awaitingRoll ? (s = engine.apply(s, const RollDice())) : s);
        if (s.awaitingRoll) continue;
        final capturing = moves.where((m) => m.isCapture);
        if (capturing.isEmpty) {
          s = engine.apply(
              s, moves.isEmpty ? const PassTurn() : PlayMove(moves.first));
          continue;
        }
        final m = capturing.first;
        s = engine.apply(s, PlayMove(m));
        captureSeen++;
        for (final id in m.capturedTokenIds) {
          expect(s.tokens[id].progress, -1);
          expect(s.tokens[id].owner, before.tokens[id].owner,
              reason: 'capture must not change ownership');
        }
      }
      expect(captureSeen, greaterThan(0), reason: 'no captures ever happened');
    });
  });

  serialisationTests();

  group('auto-play', () {
    test('prefers a capture over a plain advance', () {
      var s = GameState.newGame(const RuleConfig());
      final b = s.board;
      // Seat 1's token sits on ring 3; seat 0 can reach it, or move elsewhere.
      final victim =
          (3 - b.startRing(s.armOf(1)) + b.trackLength) % b.trackLength;
      final tokens = [...s.tokens];
      tokens[0] = tokens[0].copyWith(progress: 2);
      tokens[1] = tokens[1].copyWith(progress: 20);
      tokens[4] = tokens[4].copyWith(progress: victim);
      s = s.copyWith(tokens: tokens, dice: 1);

      final best = engine.bestMove(s)!;
      expect(best.isCapture, isTrue);
      expect(best.tokenId, 0);
    });

    test('prefers finishing a token', () {
      final finalP = BoardSpec.cross.finalProgress;
      var s = GameState.newGame(const RuleConfig());
      final tokens = [...s.tokens];
      tokens[0] = tokens[0].copyWith(progress: finalP - 2);
      tokens[1] = tokens[1].copyWith(progress: 10);
      s = s.copyWith(tokens: tokens, dice: 2);
      expect(engine.bestMove(s)!.toProgress, finalP);
    });

    test('returns null when there is nothing to do', () {
      final s = GameState.newGame(const RuleConfig()).copyWith(dice: 3);
      expect(engine.bestMove(s), isNull);
    });
  });
}

void serialisationTests() {
  group('a game survives the round trip', () {
    test('a fresh game, a game in progress and a finished game all restore',
        () {
      for (final rules in [
        const RuleConfig(),
        RuleConfig.sixSeat,
        const RuleConfig(
          players: 6,
          tokensPerPlayer: 3,
          pairMove: true,
          teams: [
            [0, 2, 4],
            [1, 3, 5],
          ],
        ),
      ]) {
        for (final turns in [0, 40, 100000]) {
          var s = GameState.newGame(rules, seed: 12345);
          for (var i = 0; i < turns && !s.isOver; i++) {
            s = engine.autoPlayTurn(s);
          }
          final back = GameState.fromJson(
              jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>);
          expect(back.fingerprint(), s.fingerprint(),
              reason: '$rules after $turns turns');
          expect(back.rules.toJson(), s.rules.toJson());
          expect(back.seatArms, s.seatArms);
          expect(back.rngState, s.rngState);
        }
      }
    });

    test('a restored game carries on identically', () {
      var live = GameState.newGame(RuleConfig.sixSeat, seed: 909);
      for (var i = 0; i < 50; i++) {
        live = engine.autoPlayTurn(live);
      }
      var restored = GameState.fromJson(
          jsonDecode(jsonEncode(live.toJson())) as Map<String, Object?>);

      for (var i = 0; i < 60 && !live.isOver; i++) {
        live = engine.autoPlayTurn(live);
        restored = engine.autoPlayTurn(restored);
        expect(restored.fingerprint(), live.fingerprint(),
            reason: 'diverged $i turns after restoring');
      }
    });

    test('pairs survive the trip', () {
      var s = GameState.newGame(const RuleConfig(pairMove: true));
      final tokens = [...s.tokens];
      tokens[0] = tokens[0].copyWith(progress: 5, pairId: 3);
      tokens[1] = tokens[1].copyWith(progress: 5, pairId: 3);
      s = s.copyWith(tokens: tokens, nextPairId: 4);
      final back = GameState.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>);
      expect(back.tokens[0].pairId, 3);
      expect(back.tokens[1].pairId, 3);
      expect(back.pairMembers(3), hasLength(2));
    });
  });
}
