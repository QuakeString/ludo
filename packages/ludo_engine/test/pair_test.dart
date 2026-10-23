import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

const engine = LudoEngine();

GameState situation(
  RuleConfig rules, {
  Map<int, int> at = const {},
  Map<int, int> pairs = const {},
  int turn = 0,
  int? dice,
}) {
  final s = GameState.newGame(rules);
  final tokens = [...s.tokens];
  at.forEach((id, p) => tokens[id] = tokens[id].copyWith(progress: p));
  pairs.forEach((id, p) => tokens[id] = tokens[id].copyWith(pairId: p));
  return s.copyWith(
    tokens: tokens,
    turn: turn,
    dice: dice,
    nextPairId:
        pairs.isEmpty ? 0 : pairs.values.reduce((a, b) => a > b ? a : b) + 1,
  );
}

int progressForRing(GameState s, int player, int ring) {
  final b = s.board;
  return (ring - b.startRing(s.armOf(player)) + b.trackLength) % b.trackLength;
}

void main() {
  const paired = RuleConfig(pairMove: true);

  group('forming a pair', () {
    test('two of your tokens on one square may link', () {
      final s = situation(paired, at: {0: 5, 1: 5}, dice: 4);
      final forms = engine.pairActions(s).whereType<FormPair>();
      expect(forms, hasLength(1));

      final next = engine.apply(s, forms.first);
      expect(next.tokens[0].pairId, next.tokens[1].pairId);
      expect(next.tokens[0].isPaired, isTrue);
    });

    test('tokens on different squares cannot link', () {
      final s = situation(paired, at: {0: 5, 1: 6}, dice: 4);
      expect(engine.pairActions(s).whereType<FormPair>(), isEmpty);
    });

    test('pairing is off unless the rule is on', () {
      final s = situation(const RuleConfig(), at: {0: 5, 1: 5}, dice: 4);
      expect(engine.pairActions(s), isEmpty);
    });

    test('a partner\'s token may join the pair in a team game', () {
      const teamed = RuleConfig(players: 4, pairMove: true, teams: [
        [0, 2],
        [1, 3]
      ]);
      var s = GameState.newGame(teamed);
      final ring = 6;
      final mine = progressForRing(s, 0, ring);
      final partners = progressForRing(s, 2, ring);
      s = situation(teamed, at: {0: mine, 8: partners}, dice: 4);

      final forms = engine.pairActions(s).whereType<FormPair>();
      expect(forms, hasLength(1));
      final next = engine.apply(s, forms.first);
      expect(next.tokens[0].pairId, next.tokens[8].pairId);
    });

    test('two of a partner\'s chips are not yours to link', () {
      const teamed = RuleConfig(players: 4, pairMove: true, teams: [
        [0, 2],
        [1, 3]
      ]);
      final s = situation(teamed, at: {8: 10, 9: 10}, dice: 3);
      expect(engine.pairActions(s), isEmpty);
    });

    test('an opponent\'s token can never join your pair', () {
      var s = GameState.newGame(paired);
      final mine = progressForRing(s, 0, 8);
      final theirs = progressForRing(s, 1, 6);
      s = situation(paired, at: {0: mine, 4: theirs}, dice: 4);
      expect(engine.pairActions(s).whereType<FormPair>(), isEmpty);
    });

    test('pairing is a free action — the roll is still there to spend', () {
      final s = situation(paired, at: {0: 5, 1: 5}, dice: 4);
      final next =
          engine.apply(s, engine.pairActions(s).whereType<FormPair>().first);
      expect(next.dice, 4);
      expect(next.turn, 0);
    });
  });

  group('moving as a pair', () {
    test('an even roll moves the pair half the pips', () {
      final s =
          situation(paired, at: {0: 5, 1: 5}, pairs: {0: 0, 1: 0}, dice: 4);
      final moves = engine.legalMoves(s);
      expect(moves, hasLength(1));
      expect(moves.single.kind, MoveKind.advancePair);
      expect(moves.single.toProgress, 7, reason: '4 pips move the pair 2');

      final next = engine.apply(s, PlayMove(moves.single));
      expect(next.tokens[0].progress, 7);
      expect(next.tokens[1].progress, 7,
          reason: 'both members travel together');
    });

    test('an odd roll cannot move a locked pair at all', () {
      final s =
          situation(paired, at: {0: 5, 1: 5}, pairs: {0: 0, 1: 0}, dice: 3);
      expect(engine.legalMoves(s), isEmpty,
          reason: 'the pair sits still and you must move something else');
    });

    test('an odd roll still moves your unpaired tokens', () {
      final s = situation(paired,
          at: {0: 5, 1: 5, 2: 20}, pairs: {0: 0, 1: 0}, dice: 3);
      final moves = engine.legalMoves(s);
      expect(moves, hasLength(1));
      expect(moves.single.tokenId, 2);
    });

    test('members are never offered a move of their own', () {
      final s =
          situation(paired, at: {0: 5, 1: 5}, pairs: {0: 0, 1: 0}, dice: 4);
      expect(engine.legalMoves(s).where((m) => m.kind == MoveKind.advance),
          isEmpty);
    });

    test('with pairMoveEvenOnly off, a pair moves the full roll', () {
      final rules = paired.copyWith(pairMoveEvenOnly: false);
      final s =
          situation(rules, at: {0: 5, 1: 5}, pairs: {0: 0, 1: 0}, dice: 3);
      final moves = engine.legalMoves(s);
      expect(moves.single.toProgress, 8);
    });
  });

  group('the lock', () {
    test('a pair cannot be broken away from a safe square', () {
      final s =
          situation(paired, at: {0: 5, 1: 5}, pairs: {0: 0, 1: 0}, dice: 4);
      expect(engine.canBreakPair(s, 0), isFalse);
      expect(engine.pairActions(s).whereType<BreakPair>(), isEmpty);
      expect(() => engine.apply(s, const BreakPair(0)),
          throwsA(isA<IllegalActionError>()));
    });

    test('on a star, the pair may split', () {
      // Ring 8 is a star; for seat 0 that is progress 8.
      final s =
          situation(paired, at: {0: 8, 1: 8}, pairs: {0: 0, 1: 0}, dice: 4);
      expect(engine.canBreakPair(s, 0), isTrue);
      final next = engine.apply(s, const BreakPair(0));
      expect(next.tokens[0].isPaired, isFalse);
      expect(next.tokens[1].isPaired, isFalse);
    });

    test('in the home column, the pair may split', () {
      final s =
          situation(paired, at: {0: 52, 1: 52}, pairs: {0: 0, 1: 0}, dice: 4);
      expect(s.board.isOnHomeStretch(52), isTrue);
      expect(engine.canBreakPair(s, 0), isTrue);
    });

    test('in the home column, either chip may go on alone', () {
      final finalP = BoardSpec.cross.finalProgress;
      final s = situation(paired,
          at: {0: finalP - 1, 1: finalP - 1}, pairs: {0: 0, 1: 0}, dice: 1);
      final singles =
          engine.legalMoves(s).where((m) => m.kind == MoveKind.advance);
      expect(singles.map((m) => m.tokenId), containsAll([0, 1]));

      final next =
          engine.apply(s, PlayMove(singles.firstWhere((m) => m.tokenId == 0)));
      expect(next.tokens[0].progress, finalP);
      expect(next.tokens[1].progress, finalP - 1);
      expect(next.tokens[1].isPaired, isFalse);
    });

    test('in the home column, a 2 takes the pair home together', () {
      final finalP = BoardSpec.cross.finalProgress;
      final s = situation(paired,
          at: {0: finalP - 1, 1: finalP - 1}, pairs: {0: 0, 1: 0}, dice: 2);
      final pair = engine
          .legalMoves(s)
          .singleWhere((m) => m.kind == MoveKind.advancePair);
      final next = engine.apply(s, PlayMove(pair));
      expect(next.tokens[0].progress, finalP);
      expect(next.tokens[1].progress, finalP);
    });

    test('with the lock off, a pair splits anywhere', () {
      final rules = paired.copyWith(pairLockedUntilSafe: false);
      final s =
          situation(rules, at: {0: 5, 1: 5}, pairs: {0: 0, 1: 0}, dice: 4);
      expect(engine.canBreakPair(s, 0), isTrue);
    });

    test('reaching home unlinks a token automatically', () {
      final finalP = BoardSpec.cross.finalProgress;
      final s = situation(paired,
          at: {0: finalP - 1, 1: finalP - 1}, pairs: {0: 0, 1: 0}, dice: 2);
      final next = engine.apply(s, PlayMove(engine.legalMoves(s).single));
      expect(next.tokens[0].progress, finalP);
      expect(next.tokens[0].isPaired, isFalse);
      expect(next.tokens[1].isPaired, isFalse);
    });
  });

  group('a partner pair at the turn-in', () {
    const teamed = RuleConfig(players: 4, pairMove: true, teams: [
      [0, 2],
      [1, 3]
    ]);
    final turnIn = BoardSpec.cross.trackLength - 2;

    GameState partnersAt(int progress, int dice, {bool rival = false}) {
      final s = GameState.newGame(teamed);
      final ring = s.board.ringIndex(s.armOf(0), progress)!;
      return situation(teamed,
          at: {
            0: progress,
            8: progressForRing(s, 2, ring),
            if (rival) 4: progressForRing(s, 1, ring),
          },
          pairs: {0: 0, 8: 0},
          dice: dice);
    }

    test('one square short, a 6 cannot carry the pair past it', () {
      final s = partnersAt(turnIn - 1, 6);
      expect(
          engine.legalMoves(s).where((m) => m.tokenId == 0 || m.tokenId == 8),
          isEmpty);
    });

    test('one square short, a 2 brings the pair to it', () {
      final s = partnersAt(turnIn - 1, 2);
      final m = engine.legalMoves(s).single;
      expect(m.kind, MoveKind.advancePair);
      final next = engine.apply(s, PlayMove(m));
      expect(next.tokens[0].progress, turnIn);
      expect(next.tokens[0].isPaired, isTrue);
    });

    test('at it, any roll walks my chip home alone', () {
      for (final dice in [1, 3, 5, 6]) {
        final s = partnersAt(turnIn, dice);
        final m =
            engine.legalMoves(s).singleWhere((m) => m.kind == MoveKind.advance);
        expect(m.tokenId, 0);
        final next = engine.apply(s, PlayMove(m));
        expect(next.tokens[0].progress, turnIn + dice);
        expect(next.tokens[8].progress, s.tokens[8].progress,
            reason: 'the partner stays');
        expect(next.tokens[8].isPaired, isFalse);
      }
    });

    test('an opponent standing there takes the partner left behind', () {
      final s = partnersAt(turnIn, 3, rival: true);
      final m =
          engine.legalMoves(s).singleWhere((m) => m.kind == MoveKind.advance);
      final next = engine.apply(s, PlayMove(m));
      expect(next.tokens[8].inYard, isTrue);
      expect(next.tokens[4].progress, s.tokens[4].progress);
    });
  });

  group('capturing a pair', () {
    test('a single token may land on a pair but cannot take it', () {
      var s = GameState.newGame(paired);
      final theirs = progressForRing(s, 1, 6);
      final mine = progressForRing(s, 0, 4);
      s = situation(paired,
          at: {0: mine, 4: theirs, 5: theirs}, pairs: {4: 0, 5: 0}, dice: 2);
      final move = engine.legalMoves(s).singleWhere((m) => m.tokenId == 0);
      expect(move.toProgress, mine + 2);
      expect(move.isCapture, isFalse);
    });

    test('a second single token arriving takes the pair', () {
      var s = GameState.newGame(paired);
      final theirs = progressForRing(s, 1, 6);
      final mine = progressForRing(s, 0, 4);
      // Token 1 already sits beside their pair; token 0 joins it.
      s = situation(paired,
          at: {0: mine, 1: mine + 2, 4: theirs, 5: theirs},
          pairs: {4: 0, 5: 0},
          dice: 2);
      final move = engine.legalMoves(s).singleWhere((m) => m.tokenId == 0);
      expect(move.capturedTokenIds, unorderedEquals([4, 5]));
      final next = engine.apply(s, PlayMove(move));
      expect(next.tokens[4].progress, -1);
      expect(next.tokens[5].progress, -1);
    });

    test('an opposing pair captures both members', () {
      var s = GameState.newGame(paired);
      final theirs = progressForRing(s, 1, 8 + 2); // ring 10, not a star
      final mine = progressForRing(s, 0, 8);
      s = situation(paired,
          at: {0: mine, 1: mine, 4: theirs, 5: theirs},
          pairs: {0: 0, 1: 0, 4: 1, 5: 1},
          dice: 4); // pair moves 2
      final move = engine.legalMoves(s).single;
      expect(move.kind, MoveKind.advancePair);
      expect(move.capturedTokenIds, unorderedEquals([4, 5]));

      final next = engine.apply(s, PlayMove(move));
      expect(next.tokens[4].progress, -1);
      expect(next.tokens[5].progress, -1);
      expect(next.tokens[4].isPaired, isFalse,
          reason: 'a captured pair is broken up');
      expect(next.captures[0], 2);
    });

    test('a pair lands beside a single chip without taking it', () {
      var s = GameState.newGame(paired);
      final theirs = progressForRing(s, 1, 10);
      final mine = progressForRing(s, 0, 8);
      s = situation(paired,
          at: {0: mine, 1: mine, 4: theirs}, pairs: {0: 0, 1: 0}, dice: 4);
      final move = engine.legalMoves(s).single;
      expect(move.kind, MoveKind.advancePair);
      expect(move.isCapture, isFalse);
      final next = engine.apply(s, PlayMove(move));
      expect(next.tokens[4].progress, theirs);
      expect(next.tokens[0].progress, mine + 2);
    });

    test('with pairCapture never, even a pair cannot take a pair', () {
      final rules = paired.copyWith(pairCapture: PairCapture.never);
      var s = GameState.newGame(rules);
      final theirs = progressForRing(s, 1, 10);
      final mine = progressForRing(s, 0, 8);
      s = situation(rules,
          at: {0: mine, 1: mine, 4: theirs, 5: theirs},
          pairs: {0: 0, 1: 0, 4: 1, 5: 1},
          dice: 4);
      final move = engine.legalMoves(s).single;
      expect(move.isCapture, isFalse, reason: 'pairs are never taken');
    });

    test('with pairCapture anyone, a single token takes both', () {
      final rules = paired.copyWith(pairCapture: PairCapture.anyone);
      var s = GameState.newGame(rules);
      final theirs = progressForRing(s, 1, 10);
      final mine = progressForRing(s, 0, 8);
      s = situation(rules,
          at: {0: mine, 4: theirs, 5: theirs}, pairs: {4: 0, 5: 0}, dice: 2);
      final move = engine.legalMoves(s).single;
      expect(move.capturedTokenIds, unorderedEquals([4, 5]));
    });

    test('a pair is not a wall — opponents may pass over it', () {
      var s = GameState.newGame(paired);
      final theirs = progressForRing(s, 1, 10);
      final mine = progressForRing(s, 0, 8);
      s = situation(paired,
          at: {0: mine, 4: theirs, 5: theirs}, pairs: {4: 0, 5: 0}, dice: 4);
      final move = engine.legalMoves(s).single;
      expect(move.toProgress, mine + 4,
          reason: 'the pair was passed, not blocked');
    });

    test('two unlinked opposing tokens still stand together', () {
      // Two chips sharing a square look the same on the board whether they
      // are linked or not, so they are treated the same: one chip landing
      // there stands beside them and takes nobody.
      var s = GameState.newGame(paired);
      final theirs = progressForRing(s, 1, 10);
      final mine = progressForRing(s, 0, 8);
      s = situation(paired, at: {0: mine, 4: theirs, 5: theirs}, dice: 2);
      expect(engine.legalMoves(s).single.isCapture, isFalse);
    });

    test('a pair can take two unlinked chips standing together', () {
      var s = GameState.newGame(paired);
      final theirs = progressForRing(s, 1, 10);
      final mine = progressForRing(s, 0, 8);
      s = situation(paired,
          at: {0: mine, 1: mine, 4: theirs, 5: theirs},
          pairs: {0: 0, 1: 0},
          dice: 4); // a pair moves half the pips
      final move = engine.legalMoves(s).single;
      expect(move.kind, MoveKind.advancePair);
      expect(move.capturedTokenIds, unorderedEquals([4, 5]));
    });

    test('partners sharing a square are not knocked off by one chip', () {
      const teams = RuleConfig(teams: [
        [0, 2],
        [1, 3]
      ]);
      var s = GameState.newGame(teams);
      final square = progressForRing(s, 1, 10); // seat 1's chip 4 lands here
      // Seats 0 and 2 have one chip each on the square seat 1 is about to
      // land on.
      final p0 = progressForRing(s, 0, 10);
      final p2 = progressForRing(s, 2, 10);
      s = situation(teams, at: {0: p0, 8: p2, 4: square - 2}, turn: 1, dice: 2);
      expect(engine.legalMoves(s).single.isCapture, isFalse,
          reason: 'one chip sent a player and their partner home together');

      // Once one of them has walked on, the other is alone and fair game.
      s = situation(teams, at: {0: p0, 4: square - 2}, turn: 1, dice: 2);
      expect(engine.legalMoves(s).single.capturedTokenIds, [0]);
    });

    test('a pair on a safe square is not captured at all', () {
      var s = GameState.newGame(paired);
      final theirs = progressForRing(s, 1, 21); // ring 21 is a star
      final mine = progressForRing(s, 0, 19);
      s = situation(paired,
          at: {0: mine, 1: mine, 4: theirs, 5: theirs},
          pairs: {0: 0, 1: 0, 4: 1, 5: 1},
          dice: 4);
      final move = engine.legalMoves(s).single;
      expect(move.isCapture, isFalse);
    });
  });

  group('pairs that make and unmake themselves', () {
    final base = GameState.newGame(paired);
    bool safe(int progress) =>
        base.safeRingSquares.contains(base.board.ringIndex(0, progress));
    // Two squares a roll of 2 apart, neither safe; and a safe one with an
    // ordinary square two before it.
    final plain = [
      for (var p = 3; p < 40; p++)
        if (!safe(p) && !safe(p - 2)) p
    ].first;
    final star = [
      for (var p = 3; p < 40; p++)
        if (safe(p) && !safe(p - 4)) p
    ].first;

    test('a chip that stops beside one it may pair with links up', () {
      final s = situation(paired, at: {0: plain - 2, 1: plain}, dice: 2);
      final move = engine.legalMoves(s).firstWhere((m) => m.tokenId == 0);
      final next = engine.apply(s, PlayMove(move));
      expect(next.tokens[0].isPaired, isTrue);
      expect(next.tokens[0].pairId, next.tokens[1].pairId);
    });

    test('but not on a safe square, where the 🔗 is offered instead', () {
      final s = situation(paired, at: {0: star - 2, 1: star}, dice: 2);
      final move = engine.legalMoves(s).firstWhere((m) => m.tokenId == 0);
      final next = engine.apply(s, PlayMove(move));
      expect(next.tokens[0].isPaired, isFalse);
    });

    test('a pair that lands on a safe square comes apart', () {
      final s = situation(paired,
          at: {0: star - 2, 1: star - 2}, pairs: {0: 0, 1: 0}, dice: 4);
      final move = engine.legalMoves(s).single;
      expect(move.kind, MoveKind.advancePair);
      final next = engine.apply(s, PlayMove(move));
      expect(next.tokens[0].progress, star);
      expect(next.tokens[0].isPaired, isFalse);
      expect(next.tokens[1].isPaired, isFalse);
    });

    test('with pair move off, nothing links', () {
      final s =
          situation(const RuleConfig(), at: {0: plain - 2, 1: plain}, dice: 2);
      final move = engine.legalMoves(s).firstWhere((m) => m.tokenId == 0);
      expect(engine.apply(s, PlayMove(move)).tokens[0].isPaired, isFalse);
    });
  });
}
