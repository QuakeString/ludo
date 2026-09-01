import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

const engine = LudoEngine();

/// Builds a state with tokens placed exactly where a test needs them, and a
/// roll already on the table. Far clearer than rolling until the dice obliges.
GameState situation(
  RuleConfig rules, {
  Map<int, int> at = const {},
  Map<int, int> pairs = const {},
  int turn = 0,
  int? dice,
  List<int>? captures,
}) {
  var s = GameState.newGame(rules);
  final tokens = [...s.tokens];
  at.forEach((id, progress) {
    tokens[id] = tokens[id].copyWith(progress: progress);
  });
  pairs.forEach((id, pairId) {
    tokens[id] = tokens[id].copyWith(pairId: pairId);
  });
  return s.copyWith(
    tokens: tokens,
    turn: turn,
    dice: dice,
    nextPairId:
        pairs.isEmpty ? 0 : pairs.values.reduce((a, b) => a > b ? a : b) + 1,
    captures: captures,
  );
}

/// Progress value that puts [player]'s token on absolute ring square [ring].
int progressForRing(GameState s, int player, int ring) {
  final b = s.board;
  return (ring - b.startRing(s.armOf(player)) + b.trackLength) % b.trackLength;
}

void main() {
  const classic = RuleConfig(); // 4 players, 4 tokens, roll 6 to start

  group('leaving the yard', () {
    test('needs the entry roll', () {
      final s = situation(classic, dice: 3);
      expect(engine.legalMoves(s), isEmpty);

      final six = situation(classic, dice: 6);
      final moves = engine.legalMoves(six);
      expect(moves, hasLength(4),
          reason: 'any of the four tokens may come out');
      expect(moves.every((m) => m.kind == MoveKind.enter), isTrue);
      expect(moves.first.toProgress, 0);
    });

    test('entryRoll 0 lets any roll bring a token out', () {
      final s = situation(classic.copyWith(entryRoll: 0), dice: 1);
      expect(engine.legalMoves(s), hasLength(4));
    });

    test('entering lands on the seat\'s own start square', () {
      final s = situation(classic, dice: 6);
      final next = engine.apply(s, PlayMove(engine.legalMoves(s).first));
      final token = next.tokens.first;
      expect(token.progress, 0);
      expect(next.board.ringIndex(next.armOf(0), token.progress),
          next.board.startRing(next.armOf(0)));
    });
  });

  group('advancing', () {
    test('a token moves the number rolled', () {
      final s = situation(classic, at: {0: 4}, dice: 3);
      final moves = engine.legalMoves(s);
      expect(moves, hasLength(1));
      expect(moves.single.toProgress, 7);
    });

    test('home must be entered on an exact count', () {
      final finalP = BoardSpec.cross.finalProgress;
      // Two short of home: a 2 finishes, a 3 overshoots and is not offered.
      expect(
          engine.legalMoves(situation(classic, at: {0: finalP - 2}, dice: 2)),
          hasLength(1));
      expect(
          engine.legalMoves(situation(classic, at: {0: finalP - 2}, dice: 3)),
          isEmpty);
    });

    test('with exactHomeEntry off, an overshoot stops on home', () {
      final finalP = BoardSpec.cross.finalProgress;
      final s = situation(classic.copyWith(exactHomeEntry: false),
          at: {0: finalP - 2}, dice: 5);
      final moves = engine.legalMoves(s);
      expect(moves, hasLength(1));
      expect(moves.single.toProgress, finalP);
    });

    test('finished tokens are not offered moves', () {
      final finalP = BoardSpec.cross.finalProgress;
      final s = situation(classic, at: {0: finalP, 1: 5}, dice: 2);
      final moves = engine.legalMoves(s);
      expect(moves, hasLength(1));
      expect(moves.single.tokenId, 1);
    });

    test('the home column is private — opponents never reach it', () {
      final s = situation(classic, at: {0: 51});
      expect(s.board.ringIndex(s.armOf(0), 51), isNull);
      expect(s.board.isOnHomeStretch(51), isTrue);
    });
  });

  group('capturing', () {
    test('landing on an opponent sends it back to its yard', () {
      var s = situation(classic, at: {0: 2}, dice: 1);
      final victimProgress = progressForRing(s, 1, 3);
      s = situation(classic, at: {0: 2, 4: victimProgress}, dice: 1);

      final move = engine.legalMoves(s).single;
      expect(move.isCapture, isTrue);
      expect(move.capturedTokenIds, [4]);

      final next = engine.apply(s, PlayMove(move));
      expect(next.tokens[4].progress, -1, reason: 'victim is back in its yard');
      expect(next.tokens[0].progress, 3);
      expect(next.captures[0], 1);
    });

    test('a safe square protects whoever stands on it', () {
      // Ring 8 is a star on the cross board.
      var s = GameState.newGame(classic);
      final attacker = progressForRing(s, 0, 6);
      final victim = progressForRing(s, 1, 8);
      s = situation(classic, at: {0: attacker, 4: victim}, dice: 2);

      final move = engine.legalMoves(s).single;
      expect(move.toProgress, attacker + 2);
      expect(move.isCapture, isFalse, reason: 'the star shields the victim');

      final next = engine.apply(s, PlayMove(move));
      expect(next.tokens[4].progress, victim, reason: 'victim did not move');
    });

    test('partners do not capture each other', () {
      const teamed = RuleConfig(players: 4, teams: [
        [0, 2],
        [1, 3]
      ]);
      var s = GameState.newGame(teamed);
      final mover = progressForRing(s, 0, 2);
      final partner = progressForRing(s, 2, 3);
      s = situation(teamed, at: {0: mover, 8: partner}, dice: 1);

      final move = engine.legalMoves(s).single;
      expect(move.isCapture, isFalse);
      final next = engine.apply(s, PlayMove(move));
      expect(next.tokens[8].progress, partner, reason: 'partner stays put');
    });

    test('partnersCanCapture lets a team play rough', () {
      const teamed = RuleConfig(players: 4, partnersCanCapture: true, teams: [
        [0, 2],
        [1, 3]
      ]);
      var s = GameState.newGame(teamed);
      final mover = progressForRing(s, 0, 2);
      final partner = progressForRing(s, 2, 3);
      s = situation(teamed, at: {0: mover, 8: partner}, dice: 1);
      expect(engine.legalMoves(s).single.capturedTokenIds, [8]);
    });

    test('a capture can grant another roll when the rules say so', () {
      final rules = classic.copyWith(captureGrantsExtraRoll: true);
      var s = GameState.newGame(rules);
      final victim = progressForRing(s, 1, 3);
      s = situation(rules, at: {0: 2, 4: victim}, dice: 1);
      final next = engine.apply(s, PlayMove(engine.legalMoves(s).single));
      expect(next.turn, 0, reason: 'still my turn');
      expect(next.awaitingRoll, isTrue);
    });
  });

  group('crowded squares', () {
    test('a crowd is just a crowd — nothing blocks passage or landing', () {
      // Two of one player on a square used to be a wall. That rule is gone:
      // chips pass through each other, and landing on the pile sends all of it
      // home.
      var s = GameState.newGame(classic);
      final crowd = progressForRing(s, 1, 5);
      final me = progressForRing(s, 0, 3);

      final past = situation(classic, at: {0: me, 4: crowd, 5: crowd}, dice: 4);
      expect(
        engine.legalMoves(past),
        isNotEmpty,
        reason: 'a chip must be able to travel past a crowd',
      );

      final onto = situation(classic, at: {0: me, 4: crowd, 5: crowd}, dice: 2);
      final move = engine.legalMoves(onto).single;
      expect(
        move.capturedTokenIds,
        unorderedEquals([4, 5]),
        reason: 'landing on them sends both home',
      );
    });

    test('your own tokens never get in your way', () {
      var s = GameState.newGame(classic);
      final me = progressForRing(s, 0, 3);
      final mine = progressForRing(s, 0, 5);
      s = situation(classic, at: {0: me, 1: mine, 2: mine}, dice: 4);
      expect(engine.legalMoves(s).where((m) => m.tokenId == 0), hasLength(1));
    });
  });

  group('turn flow', () {
    test('a six keeps the turn, anything else passes it on', () {
      final s = situation(classic, at: {0: 4}, dice: 6);
      final advance =
          engine.legalMoves(s).firstWhere((m) => m.kind == MoveKind.advance);
      expect(engine.apply(s, PlayMove(advance)).turn, 0);

      final s3 = situation(classic, at: {0: 4}, dice: 3);
      final after3 = engine.apply(s3, PlayMove(engine.legalMoves(s3).single));
      expect(after3.turn, 1);
    });

    test('passing hands the turn on', () {
      final stuck = situation(classic, dice: 3); // all in the yard, needs a 6
      expect(engine.legalMoves(stuck), isEmpty);
      expect(engine.apply(stuck, const PassTurn()).turn, 1);
    });

    test('an unplayable six passes the turn on like any other number', () {
      final finalP = BoardSpec.cross.finalProgress;
      // Three tokens home, the last one two short — a six overshoots it.
      final s = situation(classic,
          at: {0: finalP - 2, 1: finalP, 2: finalP, 3: finalP}, dice: 6);
      expect(engine.legalMoves(s), isEmpty);
      expect(s.isOver, isFalse);

      final after = engine.apply(s, const PassTurn());
      expect(after.turn, 1,
          reason: 'a six you cannot play is a wasted six, not a free re-roll');
      expect(after.awaitingRoll, isTrue);
      expect(after.consecutiveSixes, 0);
    });

    test('passing with a move available is refused', () {
      final s = situation(classic, at: {0: 4}, dice: 3);
      expect(() => engine.apply(s, const PassTurn()),
          throwsA(isA<IllegalActionError>()));
    });

    test('three sixes in a row forfeit the turn', () {
      // Drive the RNG until we find a seed that rolls three sixes running.
      var s = GameState.newGame(classic, seed: 7).copyWith(consecutiveSixes: 2);
      var found = false;
      for (var seed = 1; seed < 400 && !found; seed++) {
        final probe = GameState.newGame(classic, seed: seed)
            .copyWith(consecutiveSixes: 2);
        if (engine.peekRoll(probe) == 6) {
          s = probe;
          found = true;
        }
      }
      expect(found, isTrue, reason: 'needed a seed that rolls a six');
      final after = engine.apply(s, const RollDice());
      expect(after.turn, 1, reason: 'the third six loses the turn');
      expect(after.dice, isNull);
    });

    test('rolling twice without moving is refused', () {
      final s = situation(classic, dice: 4);
      expect(() => engine.apply(s, const RollDice()),
          throwsA(isA<IllegalActionError>()));
    });

    test('moving before rolling is refused', () {
      final s = situation(classic, at: {0: 4});
      expect(
        () => engine.apply(
            s,
            PlayMove(const Move(
              kind: MoveKind.advance,
              tokenIds: [0],
              owner: 0,
              steps: 3,
              fromProgress: 4,
              toProgress: 7,
            ))),
        throwsA(isA<IllegalActionError>()),
      );
    });

    test('a fabricated move is refused', () {
      final s = situation(classic, at: {0: 4}, dice: 3);
      expect(
        () => engine.apply(
            s,
            PlayMove(const Move(
              kind: MoveKind.advance,
              tokenIds: [0],
              owner: 0,
              steps: 30,
              fromProgress: 4,
              toProgress: 34, // not what a 3 gives
            ))),
        throwsA(isA<IllegalActionError>()),
      );
    });
  });

  group('must capture to win', () {
    final rules = classic.copyWith(mustCaptureToWin: true);

    test('a token cannot finish before its owner has captured', () {
      final finalP = BoardSpec.cross.finalProgress;
      final s = situation(rules, at: {0: finalP - 2}, dice: 2);
      expect(engine.legalMoves(s), isEmpty);
    });

    test('after a capture, finishing is allowed', () {
      final finalP = BoardSpec.cross.finalProgress;
      final s = situation(rules,
          at: {0: finalP - 2}, dice: 2, captures: [1, 0, 0, 0]);
      expect(engine.legalMoves(s), hasLength(1));
    });
  });

  group('winning', () {
    test('a seat that brings every token home wins', () {
      final finalP = BoardSpec.cross.finalProgress;
      final s = situation(classic,
          at: {0: finalP, 1: finalP, 2: finalP, 3: finalP - 3}, dice: 3);
      expect(s.isOver, isFalse);
      final next = engine.apply(s, PlayMove(engine.legalMoves(s).single));
      expect(next.isOver, isTrue);
      expect(next.winner, 0);
      expect(next.finishOrder, contains(0));
    });

    test('a team wins only when every partner is home', () {
      const teamed = RuleConfig(players: 4, tokensPerPlayer: 2, teams: [
        [0, 2],
        [1, 3]
      ]);
      final finalP = BoardSpec.cross.finalProgress;
      // Seat 0 is home; seat 2 still has one token to bring in.
      final s = situation(teamed,
          at: {0: finalP, 1: finalP, 4: finalP, 5: finalP - 2},
          turn: 2,
          dice: 2);
      expect(s.hasFinished(0), isTrue);
      expect(s.winningTeam, isNull, reason: 'the partner is not home yet');

      final next = engine.apply(s, PlayMove(engine.legalMoves(s).single));
      expect(next.winningTeam, 0);
      expect(next.isOver, isTrue);
    });

    test('a finished player keeps rolling for a partner', () {
      const teamed = RuleConfig(players: 4, tokensPerPlayer: 2, teams: [
        [0, 2],
        [1, 3]
      ]);
      final finalP = BoardSpec.cross.finalProgress;
      final s = situation(teamed,
          at: {0: finalP, 1: finalP, 4: 10, 5: 12}, turn: 0, dice: 3);
      expect(s.hasFinished(0), isTrue);
      expect(s.movableOwners(0), [2]);
      final moves = engine.legalMoves(s);
      expect(moves, hasLength(2));
      expect(moves.every((m) => m.owner == 2), isTrue,
          reason: 'seat 0 is moving its partner\'s tokens');
    });

    test('without the partner rule, a finished seat is simply skipped', () {
      const teamed = RuleConfig(
        players: 4,
        tokensPerPlayer: 2,
        finishedPlayerMovesPartner: false,
        teams: [
          [0, 2],
          [1, 3]
        ],
      );
      final finalP = BoardSpec.cross.finalProgress;
      // Seat 0 is home; seat 3 is on the board and about to move.
      final s = situation(teamed,
          at: {0: finalP, 1: finalP, 6: 10, 7: 12}, turn: 3, dice: 3);
      expect(s.movableOwners(0), isEmpty);
      final next = engine.apply(s, PlayMove(engine.legalMoves(s).first));
      expect(next.turn, 1, reason: 'the turn skips seat 0 entirely');
    });
  });
}
