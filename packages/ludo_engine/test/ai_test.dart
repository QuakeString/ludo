import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

const engine = LudoEngine();

GameState situation(
  RuleConfig rules, {
  Map<int, int> at = const {},
  int turn = 0,
  int? dice,
}) {
  final s = GameState.newGame(rules);
  final tokens = [...s.tokens];
  at.forEach((id, p) => tokens[id] = tokens[id].copyWith(progress: p));
  return s.copyWith(tokens: tokens, turn: turn, dice: dice);
}

int progressForRing(GameState s, int player, int ring) {
  final b = s.board;
  return (ring - b.startRing(s.armOf(player)) + b.trackLength) % b.trackLength;
}

void main() {
  const classic = RuleConfig();

  group('every level', () {
    test('returns null when there is nothing to play', () {
      final stuck = situation(classic, dice: 3); // all in the yard, needs a 6
      for (final level in AiLevel.values) {
        expect(LudoAi(level: level).chooseMove(stuck), isNull,
            reason: level.name);
      }
    });

    test('only ever returns a legal move', () {
      for (final level in AiLevel.values) {
        var s = GameState.newGame(classic, seed: 21);
        final ai = LudoAi(level: level, depth: 2);
        for (var i = 0; i < 200 && !s.isOver; i++) {
          if (s.awaitingRoll) {
            s = engine.apply(s, const RollDice());
            continue;
          }
          final legal = engine.legalMoves(s);
          final choice = ai.chooseMove(s);
          if (legal.isEmpty) {
            expect(choice, isNull);
            s = engine.apply(s, const PassTurn());
          } else {
            expect(choice, isNotNull, reason: level.name);
            expect(
              legal.any((m) =>
                  m.toProgress == choice!.toProgress &&
                  m.tokenId == choice.tokenId),
              isTrue,
              reason: '${level.name} chose a move that is not on offer',
            );
            s = engine.apply(s, PlayMove(choice!));
          }
        }
      }
    });

    test('is deterministic — the same position always gets the same move', () {
      var s = GameState.newGame(classic, seed: 404);
      for (var i = 0; i < 30; i++) {
        s = engine.autoPlayTurn(s);
      }
      if (s.awaitingRoll) s = engine.apply(s, const RollDice());

      for (final level in AiLevel.values) {
        final ai = LudoAi(level: level, depth: 2);
        final first = ai.chooseMove(s);
        for (var i = 0; i < 5; i++) {
          final again = ai.chooseMove(s);
          expect(again?.tokenId, first?.tokenId, reason: level.name);
          expect(again?.toProgress, first?.toProgress, reason: level.name);
        }
      }
    });

    test('choosing a move never disturbs the dice cursor', () {
      var s = GameState.newGame(classic, seed: 55);
      for (var i = 0; i < 20; i++) {
        s = engine.autoPlayTurn(s);
      }
      if (s.awaitingRoll) s = engine.apply(s, const RollDice());
      final before = s.rng;
      for (final level in AiLevel.values) {
        LudoAi(level: level, depth: 2).chooseMove(s);
      }
      expect(s.rng, before,
          reason: 'thinking must not consume the game\'s dice');
    });

    test('can play a whole game to a winner', () {
      for (final level in AiLevel.values) {
        final ai = LudoAi(level: level, depth: 2);
        var s = GameState.newGame(classic, seed: 88);
        var guard = 0;
        while (!s.isOver && guard++ < 5000) {
          s = ai.playTurn(s);
        }
        expect(s.isOver, isTrue, reason: '${level.name} never finished');
      }
    });
  });

  group('normal', () {
    test('takes a capture over a plain advance', () {
      var s = GameState.newGame(classic);
      final victim = progressForRing(s, 1, 3);
      s = situation(classic, at: {0: 2, 1: 30, 4: victim}, dice: 1);
      final move = const LudoAi(level: AiLevel.normal).chooseMove(s)!;
      expect(move.isCapture, isTrue);
    });
  });

  group('hard', () {
    test('takes an available capture', () {
      var s = GameState.newGame(classic);
      final victim = progressForRing(s, 1, 3);
      s = situation(classic, at: {0: 2, 1: 30, 4: victim}, dice: 1);
      final move = const LudoAi(level: AiLevel.hard, depth: 2).chooseMove(s)!;
      expect(move.isCapture, isTrue);
    });

    test('avoids parking a chip right in front of an opponent', () {
      // Two choices, both plain advances. One lands on ring 20, which an
      // opponent sitting on ring 17 reaches with a 3. The other is out of
      // everyone's reach. A one-move-ahead player cannot tell them apart.
      var s = GameState.newGame(classic);
      final hunter = progressForRing(s, 1, 17);
      final safeish = progressForRing(s, 0, 40);
      final exposed = progressForRing(s, 0, 17);
      s = situation(classic, at: {0: exposed, 1: safeish, 4: hunter}, dice: 3);

      final moves = engine.legalMoves(s);
      expect(moves, hasLength(2), reason: 'the test needs a real choice');

      final choice = const LudoAi(level: AiLevel.hard, depth: 3).chooseMove(s)!;
      final landsOn = s.board.ringIndex(s.armOf(0), choice.toProgress);
      expect(landsOn, isNot(20),
          reason: 'hard walked into a square an opponent covers with a 3');
    });

    test('thinks inside its node budget', () {
      var s = GameState.newGame(classic, seed: 7);
      for (var i = 0; i < 80; i++) {
        s = engine.autoPlayTurn(s);
      }
      if (s.isOver) return;
      if (s.awaitingRoll) s = engine.apply(s, const RollDice());
      if (engine.legalMoves(s).isEmpty) return;

      final watch = Stopwatch()..start();
      const LudoAi(level: AiLevel.hard, depth: 3, nodeBudget: 40000)
          .chooseMove(s);
      watch.stop();
      // Generous for CI, but it would catch a search that had blown up.
      expect(watch.elapsedMilliseconds, lessThan(2000),
          reason: 'a turn must not stall the device');
    });
  });

  group('the levels really are ordered', () {
    // Kept small so the suite stays quick; example/ai_arena.dart runs the
    // large sample that the numbers in the README come from.
    test('hard beats easy clearly', () {
      final r = const AiArena()
          .head2head(AiLevel.hard, AiLevel.easy, games: 30, hardDepth: 2);
      expect(r.games, greaterThan(20), reason: 'too many games hit the cap');
      expect(r.aWinRate, greaterThan(0.6), reason: r.toString());
    });

    test('normal beats easy clearly', () {
      final r =
          const AiArena().head2head(AiLevel.normal, AiLevel.easy, games: 30);
      expect(r.aWinRate, greaterThan(0.6), reason: r.toString());
    });

    test('a level drawn against itself is close to even', () {
      final r =
          const AiArena().head2head(AiLevel.normal, AiLevel.normal, games: 30);
      expect(r.aWinRate, inInclusiveRange(0.25, 0.75), reason: r.toString());
    });
  });
}
