import 'moves.dart';
import 'rules.dart';
import 'state.dart';

/// The rules, as pure functions over [GameState].
///
/// Nothing here touches the clock, the network or the screen, so the same code
/// decides moves on a phone in aeroplane mode and on the server that referees
/// an online match.
class LudoEngine {
  const LudoEngine();

  // --- dice ----------------------------------------------------------------

  /// The roll a state would produce next, without advancing it.
  int peekRoll(GameState s) => s.rng.peek(_facesFor(s));

  // --- queries -------------------------------------------------------------

  /// Every legal move for the player on turn, given the pending roll.
  /// Empty while awaiting a roll, or when the roll cannot be played.
  /// How many sixes a seat may throw in a row under [SixRun.capped].
  ///
  /// Two, so the third never appears. Named because the roll and everything
  /// that predicts the roll have to agree on it.
  static const sixesInARow = 2;

  /// The faces available on the next throw.
  ///
  /// One short of the full die when a seat has already had its run of sixes:
  /// [DiceRng.roll] draws evenly across 1..n, so asking it for one fewer face
  /// is exactly "anything but a six", still even across the five that are
  /// left. The alternative — draw a six and then throw the turn away — is the
  /// rule this replaces, and from a chair it looked like the game skipping
  /// you: the number never even reached the board.
  int _facesFor(GameState s) =>
      s.rules.sixRun == SixRun.capped && s.consecutiveSixes >= sixesInARow
          ? s.rules.diceSides - 1
          : s.rules.diceSides;

  List<Move> legalMoves(GameState s) {
    final roll = s.dice;
    if (roll == null || s.isOver) return const [];

    final moves = <Move>[];
    final owners = s.movableOwners(s.turn);
    final handledPairs = <int>{};

    for (final owner in owners) {
      for (final token in s.tokensOf(owner)) {
        if (s.board.isFinished(token.progress)) continue;

        if (token.isPaired) {
          if (handledPairs.add(token.pairId)) {
            final m = _pairMove(s, token.pairId, roll);
            if (m != null) moves.add(m);
          }
          continue;
        }

        if (token.inYard) {
          final m = _enterMove(s, token, roll);
          if (m != null) moves.add(m);
        } else {
          final m = _advanceMove(s, token, roll);
          if (m != null) moves.add(m);
        }
      }
    }
    return moves;
  }

  /// Actions the player on turn may take right now.
  List<GameAction> legalActions(GameState s) {
    if (s.isOver) return const [];
    if (s.awaitingRoll) return const [RollDice()];
    final out = <GameAction>[
      for (final m in legalMoves(s)) PlayMove(m),
      ...pairActions(s),
    ];
    if (!out.any((a) => a is PlayMove)) out.add(const PassTurn());
    return out;
  }

  /// Pairing and unpairing available to the player on turn.
  List<GameAction> pairActions(GameState s) {
    final rules = s.rules;
    if (!rules.pairMove || s.awaitingRoll || s.isOver) return const [];
    final out = <GameAction>[];
    final owners = s.movableOwners(s.turn).toSet();

    // Break: only from a safe square while the lock rule is on.
    final seen = <int>{};
    for (final t in s.tokens) {
      if (!t.isPaired || !owners.contains(t.owner) || !seen.add(t.pairId)) {
        continue;
      }
      if (canBreakPair(s, t.pairId)) out.add(BreakPair(t.pairId));
    }

    // Form: two eligible tokens sharing a ring square.
    final byRing = <int, List<Token>>{};
    for (final t in s.tokens) {
      if (t.inYard || t.isPaired) continue;
      if (!_pairEligible(s, t.owner, owners)) continue;
      final ring = s.board.ringIndex(s.armOf(t.owner), t.progress);
      if (ring == null) continue; // home stretch — no pairing there
      byRing.putIfAbsent(ring, () => []).add(t);
    }
    for (final group in byRing.values) {
      for (var i = 0; i < group.length; i++) {
        for (var j = i + 1; j < group.length; j++) {
          final a = group[i], b = group[j];
          if (a.owner != b.owner && !rules.pairAcrossPartners) continue;
          if (a.owner != b.owner && !rules.sameSide(a.owner, b.owner)) continue;
          out.add(FormPair(a.id, b.id));
        }
      }
    }
    return out;
  }

  bool _pairEligible(GameState s, int owner, Set<int> movable) {
    if (movable.contains(owner)) return true;
    // A partner's token may join your pair, if the rules allow it.
    return s.rules.pairAcrossPartners &&
        movable.any((m) => s.rules.sameSide(m, owner));
  }

  /// A pair may only be broken on a star or in the home column, unless the
  /// lock rule is off.
  bool canBreakPair(GameState s, int pairId) {
    final members = s.pairMembers(pairId);
    if (members.isEmpty) return false;
    if (!s.rules.pairLockedUntilSafe) return true;
    final t = members.first;
    if (s.board.isOnHomeStretch(t.progress)) return true;
    final ring = s.board.ringIndex(s.armOf(t.owner), t.progress);
    return ring != null && s.safeRingSquares.contains(ring);
  }

  // --- move construction ---------------------------------------------------

  Move? _enterMove(GameState s, Token token, int roll) {
    final rules = s.rules;
    if (rules.entryRoll != 0 && roll != rules.entryRoll) return null;

    final arm = s.armOf(token.owner);
    final ring = s.board.startRing(arm);

    final captured = _capturesAt(s, token.owner, ring, moverIsPair: false);
    if (captured == null) return null; // occupied in a way we cannot land on

    return Move(
      kind: MoveKind.enter,
      tokenIds: [token.id],
      owner: token.owner,
      steps: 0,
      fromProgress: -1,
      toProgress: 0,
      capturedTokenIds: captured,
    );
  }

  Move? _advanceMove(GameState s, Token token, int roll) {
    final target = _targetProgress(s, token.progress, roll);
    if (target == null) return null;
    if (!_mayFinish(s, token.owner, target)) return null;

    final ring = s.board.ringIndex(s.armOf(token.owner), target);
    var captured = const <int>[];
    if (ring != null) {
      final c = _capturesAt(s, token.owner, ring, moverIsPair: false);
      if (c == null) return null;
      captured = c;
    }

    return Move(
      kind: MoveKind.advance,
      tokenIds: [token.id],
      owner: token.owner,
      steps: roll,
      fromProgress: token.progress,
      toProgress: target,
      capturedTokenIds: captured,
    );
  }

  Move? _pairMove(GameState s, int pairId, int roll) {
    final rules = s.rules;
    final members = s.pairMembers(pairId);
    if (members.length < 2) return null;

    // A locked pair sits still on an odd roll — you move something else.
    if (rules.pairMoveEvenOnly && roll.isOdd) return null;
    final steps = rules.pairMoveEvenOnly ? roll ~/ 2 : roll;
    if (steps <= 0) return null;

    // Members share a square, so one is enough to compute the path.
    final lead = members.first;
    final target = _targetProgress(s, lead.progress, steps);
    if (target == null) return null;
    for (final m in members) {
      if (!_mayFinish(s, m.owner, target)) return null;
    }

    final ring = s.board.ringIndex(s.armOf(lead.owner), target);
    var captured = const <int>[];
    if (ring != null) {
      final c = _capturesAt(s, lead.owner, ring,
          moverIsPair: true, ignore: members.map((m) => m.id).toSet());
      if (c == null) return null;
      captured = c;
    }

    return Move(
      kind: MoveKind.advancePair,
      tokenIds: [for (final m in members) m.id],
      owner: lead.owner,
      steps: steps,
      fromProgress: lead.progress,
      toProgress: target,
      pairId: pairId,
      capturedTokenIds: captured,
    );
  }

  /// Where a token lands, or null when the roll cannot be played by it.
  int? _targetProgress(GameState s, int from, int steps) {
    final finalP = s.board.finalProgress;
    final target = from + steps;
    if (target > finalP) {
      // Overshooting home. Only legal when an exact count is not required, and
      // then it stops on home rather than bouncing.
      return s.rules.exactHomeEntry ? null : finalP;
    }
    return target;
  }

  /// No token may finish before its owner has captured, when that rule is on.
  bool _mayFinish(GameState s, int owner, int target) {
    if (!s.rules.mustCaptureToWin) return true;
    if (target < s.board.finalProgress) return true;
    return s.captures[owner] > 0;
  }

  /// Tokens captured by landing on [ring], or null when landing is not legal.
  List<int>? _capturesAt(
    GameState s,
    int owner,
    int ring, {
    required bool moverIsPair,
    Set<int> ignore = const {},
  }) {
    final rules = s.rules;
    if (s.safeRingSquares.contains(ring)) {
      // Safe square: everyone may share it, nobody is sent home.
      return const [];
    }

    final victims = <int>[];
    final pairsSeen = <int>{};
    for (final t in s.tokensOnRing(ring)) {
      if (ignore.contains(t.id)) continue;
      if (rules.sameSide(t.owner, owner)) {
        if (t.owner != owner && !rules.partnersCanCapture) continue;
        if (t.owner == owner) continue;
      }
      if (t.isPaired) {
        if (!pairsSeen.add(t.pairId)) continue;
        switch (rules.pairCapture) {
          case PairCapture.never:
            return null; // cannot land here at all
          case PairCapture.pairOnly:
            if (!moverIsPair) return null;
          case PairCapture.anyone:
            break;
        }
        victims.addAll(s.pairMembers(t.pairId).map((m) => m.id));
        continue;
      }
      victims.add(t.id);
    }
    return victims;
  }

  // --- transitions ---------------------------------------------------------

  /// Applies an action, returning the next state. Throws
  /// [IllegalActionError] rather than silently ignoring a bad action — an
  /// online client must never be able to nudge the server off the rules.
  GameState apply(GameState s, GameAction action) {
    if (s.isOver) throw IllegalActionError('the game is already over');

    return switch (action) {
      RollDice() => _roll(s),
      PlayMove(move: final m) => _play(s, m),
      PassTurn() => _pass(s),
      FormPair(tokenA: final a, tokenB: final b) => _formPair(s, a, b),
      BreakPair(pairId: final id) => _breakPair(s, id),
    };
  }

  GameState _roll(GameState s) {
    if (!s.awaitingRoll) {
      throw IllegalActionError('already rolled a ${s.dice}');
    }
    final (next, value) = s.rng.roll(_facesFor(s));
    final sixes = value == s.rules.diceSides ? s.consecutiveSixes + 1 : 0;
    // Counted before anything is decided about it. A throw that forfeits the
    // turn is still a throw that seat made, and leaving those out is exactly
    // how a tally comes to disagree with what somebody watched happen.
    final tally = s.stats.withRoll(s.turn, value);

    return s.copyWith(
        rng: next, dice: value, consecutiveSixes: sixes, stats: tally);
  }

  GameState _play(GameState s, Move move) {
    if (s.awaitingRoll) throw IllegalActionError('roll first');
    final legal = legalMoves(s);
    final match = legal.where((m) =>
        m.kind == move.kind &&
        m.toProgress == move.toProgress &&
        _sameIds(m.tokenIds, move.tokenIds));
    if (match.isEmpty) throw IllegalActionError('$move is not legal here');
    final m = match.first;

    final tokens = [...s.tokens];
    for (final id in m.tokenIds) {
      tokens[id] = tokens[id].copyWith(progress: m.toProgress);
    }
    for (final id in m.capturedTokenIds) {
      tokens[id] = tokens[id].copyWith(progress: -1, pairId: -1);
    }

    final captures = [...s.captures];
    if (m.capturedTokenIds.isNotEmpty) {
      captures[s.turn] = captures[s.turn] + m.capturedTokenIds.length;
    }

    // Credited to the seat whose turn it is, not to the token's owner. In a
    // team game a player who is already home rolls and moves for a partner,
    // and those are that player's moves — they are the one making them.
    var tally = s.stats.withMove(s.turn);
    for (final id in m.capturedTokenIds) {
      tally = tally.withLosses(s.tokens[id].owner, 1);
    }

    var next = s.copyWith(tokens: tokens, captures: captures, stats: tally);
    next = _recordFinishes(next);

    if (next.isOver) return next.copyWith(dice: null);

    final rolledMax = s.dice == s.rules.diceSides;
    // Three ways to earn another throw, and the game is not the game without
    // all of them: the top face, knocking somebody off, and bringing a chip
    // home. The last one is checked against the board rather than the move,
    // because how far round "home" is depends on which board is being played.
    final broughtHome = s.board.isFinished(m.toProgress);
    final again = (rolledMax && s.rules.extraRollOnSix) ||
        (m.isCapture && s.rules.captureGrantsExtraRoll) ||
        (broughtHome && s.rules.finishGrantsExtraRoll);

    if (again) {
      // A roll earned by a capture or by a chip getting home starts a fresh
      // six-count; one earned by rolling the top face carries the count on, so
      // three sixes still forfeit.
      return next.copyWith(
          dice: null, consecutiveSixes: rolledMax ? s.consecutiveSixes : 0);
    }
    return _advanceTurn(next.copyWith(consecutiveSixes: 0));
  }

  GameState _pass(GameState s) {
    if (s.awaitingRoll) throw IllegalActionError('roll first');
    if (legalMoves(s).isNotEmpty) {
      throw IllegalActionError('you have a legal move; passing is not allowed');
    }
    // The turn goes on, whatever was rolled. A six buys another roll by being
    // *played* — it is the move that earns the extra throw, not the number. A
    // six with nowhere to go is a wasted six, and the board passes on, which is
    // what happens at a real table: you cannot sit there re-rolling a six you
    // are unable to use.
    return _advanceTurn(s.copyWith(consecutiveSixes: 0));
  }

  GameState _formPair(GameState s, int a, int b) {
    final legal = pairActions(s).whereType<FormPair>().where((f) =>
        (f.tokenA == a && f.tokenB == b) || (f.tokenA == b && f.tokenB == a));
    if (legal.isEmpty) {
      throw IllegalActionError('tokens $a and $b cannot be paired here');
    }
    final tokens = [...s.tokens];
    tokens[a] = tokens[a].copyWith(pairId: s.nextPairId);
    tokens[b] = tokens[b].copyWith(pairId: s.nextPairId);
    return s.copyWith(tokens: tokens, nextPairId: s.nextPairId + 1);
  }

  GameState _breakPair(GameState s, int pairId) {
    if (!canBreakPair(s, pairId)) {
      throw IllegalActionError(
          'pair $pairId is locked until it reaches a safe square');
    }
    final tokens = [
      for (final t in s.tokens) t.pairId == pairId ? t.copyWith(pairId: -1) : t
    ];
    return s.copyWith(tokens: tokens);
  }

  /// A token that reaches home leaves any pair behind it.
  GameState _recordFinishes(GameState s) {
    final tokens = [
      for (final t in s.tokens)
        t.isPaired && s.board.isFinished(t.progress)
            ? t.copyWith(pairId: -1)
            : t
    ];
    final order = [...s.finishOrder];
    for (var p = 0; p < s.rules.players; p++) {
      if (!order.contains(p) &&
          tokens
              .where((t) => t.owner == p)
              .every((t) => s.board.isFinished(t.progress))) {
        order.add(p);
      }
    }
    return s.copyWith(tokens: tokens, finishOrder: order);
  }

  /// Hands the turn to the next seat with something to do. A seat that is home
  /// keeps its turn only when it can still move for a partner.
  GameState _advanceTurn(GameState s) {
    var next = s.turn;
    for (var i = 0; i < s.rules.players; i++) {
      next = (next + 1) % s.rules.players;
      if (s.movableOwners(next).isNotEmpty) break;
    }
    return s.copyWith(turn: next, dice: null);
  }

  static bool _sameIds(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    final sa = [...a]..sort();
    final sb = [...b]..sort();
    for (var i = 0; i < sa.length; i++) {
      if (sa[i] != sb[i]) return false;
    }
    return true;
  }

  // --- auto-play -----------------------------------------------------------

  /// The move auto-play makes when the turn clock runs out — and the baseline
  /// the AI opponents build on.
  ///
  /// Order of preference: capture, finish a token, leave the yard, then the
  /// furthest-along token that ends up safe, then simply the furthest along.
  Move? bestMove(GameState s) {
    final moves = legalMoves(s);
    if (moves.isEmpty) return null;

    int score(Move m) {
      var v = 0;
      if (m.isCapture) v += 1000 + m.capturedTokenIds.length * 50;
      if (m.toProgress >= s.board.finalProgress) v += 800;
      if (m.kind == MoveKind.enter) v += 400;
      final ring = s.board.ringIndex(s.armOf(m.owner), m.toProgress);
      if (ring == null) {
        v += 200; // reached the home stretch, out of everyone's reach
      } else if (s.safeRingSquares.contains(ring)) {
        v += 120;
      }
      return v + m.toProgress;
    }

    var best = moves.first;
    var bestScore = score(best);
    for (final m in moves.skip(1)) {
      final sc = score(m);
      if (sc > bestScore) {
        best = m;
        bestScore = sc;
      }
    }
    return best;
  }

  /// Plays a whole turn without a human: roll, then move (or pass).
  GameState autoPlayTurn(GameState s) {
    var next = s.awaitingRoll ? apply(s, const RollDice()) : s;
    if (next.isOver || next.awaitingRoll) return next;
    final move = bestMove(next);
    return apply(next, move == null ? const PassTurn() : PlayMove(move));
  }
}
