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

    test('an opponent\'s token can never join your pair', () {
      var s = GameState.newGame(paired);
      final mine = progressForRing(s, 0, 6);
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

  group('capturing a pair', () {
    test('a single token may not land on a pair', () {
      var s = GameState.newGame(paired);
      final theirs = progressForRing(s, 1, 6);
      final mine = progressForRing(s, 0, 4);
      s = situation(paired,
          at: {0: mine, 4: theirs, 5: theirs}, pairs: {4: 0, 5: 0}, dice: 2);
      expect(engine.legalMoves(s).where((m) => m.tokenId == 0), isEmpty);
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

    test('with pairCapture never, even a pair cannot take a pair', () {
      final rules = paired.copyWith(pairCapture: PairCapture.never);
      var s = GameState.newGame(rules);
      final theirs = progressForRing(s, 1, 10);
      final mine = progressForRing(s, 0, 8);
      s = situation(rules,
          at: {0: mine, 1: mine, 4: theirs, 5: theirs},
          pairs: {0: 0, 1: 0, 4: 1, 5: 1},
          dice: 4);
      expect(engine.legalMoves(s), isEmpty);
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

    test('two unlinked opposing tokens are not a pair, and both go home', () {
      // Worth keeping next to the pair rules: two tokens sharing a square look
      // the same on the board whether they are linked or not, and the two
      // cases are governed differently. Unlinked, they are simply two chips —
      // land on them and both are sent home.
      var s = GameState.newGame(paired);
      final theirs = progressForRing(s, 1, 10);
      final mine = progressForRing(s, 0, 8);
      s = situation(paired, at: {0: mine, 4: theirs, 5: theirs}, dice: 2);
      final move = engine.legalMoves(s).single;
      expect(move.capturedTokenIds, unorderedEquals([4, 5]));
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
}
