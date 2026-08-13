import 'engine.dart';
import 'moves.dart';
import 'state.dart';

/// How hard the computer plays.
///
/// One engine, deliberately weakened — not three separate opponents. That way
/// there is only ever one piece of judgement to get right, and the easy levels
/// are wrong in ways a person recognises rather than wrong in ways that feel
/// broken.
enum AiLevel {
  /// Mostly random. Misses captures, leaves chips in danger — a beginner.
  easy,

  /// One move ahead: takes the best move on the board right now, but cannot
  /// see what it exposes next turn.
  normal,

  /// Expectimax search: looks several plies ahead, averaging over all six dice
  /// faces at each opponent's turn. It weighs what a square costs you as well
  /// as what it gains.
  hard,
}

/// A computer player.
///
/// Deterministic by construction: no wall clock, no `Random`. Given the same
/// state it always chooses the same move, so a game stays exactly replayable
/// from its seed even with computer seats at the table.
class LudoAi {
  const LudoAi({
    this.level = AiLevel.normal,
    this.depth = 3,
    this.nodeBudget = 40000,
  });

  final AiLevel level;

  /// Plies of lookahead for [AiLevel.hard]. One ply is one player's turn.
  final int depth;

  /// Ceiling on states examined per decision, so a crowded board cannot make a
  /// phone stutter. Search returns its best-so-far when it runs out.
  final int nodeBudget;

  static const _engine = LudoEngine();

  /// The move this player would make, or null when there is nothing to play.
  Move? chooseMove(GameState s) {
    final moves = _engine.legalMoves(s);
    if (moves.isEmpty) return null;
    if (moves.length == 1) return moves.first;

    return switch (level) {
      AiLevel.easy => _easy(s, moves),
      AiLevel.normal => _engine.bestMove(s),
      AiLevel.hard => _hard(s, moves),
    };
  }

  /// Plays a whole turn: roll, then move or pass.
  GameState playTurn(GameState s) {
    if (s.isOver) return s;
    var next = s.awaitingRoll ? _engine.apply(s, const RollDice()) : s;
    if (next.isOver || next.awaitingRoll) return next;
    final move = chooseMove(next);
    return _engine.apply(
        next, move == null ? const PassTurn() : PlayMove(move));
  }

  // --- easy ----------------------------------------------------------------

  /// Random, but not oblivious: roughly a third of the time it plays the
  /// obvious move, so it is beatable without looking broken.
  Move _easy(GameState s, List<Move> moves) {
    final r = _hash(s);
    if (r % 100 < 35) return _engine.bestMove(s) ?? moves.first;
    return moves[r % moves.length];
  }

  /// A stable pseudo-random number drawn from the position itself, so the easy
  /// player is unpredictable to a human but identical on replay — and, being
  /// separate from the game's dice cursor, it cannot disturb the roll sequence.
  static int _hash(GameState s) {
    var h = 0x811c9dc5 ^ s.rngState;
    h = (h * 16777619) & 0x3FFFFFFF;
    h ^= s.turn * 2654435761;
    for (final t in s.tokens) {
      h = ((h * 31) + t.progress + 2) & 0x3FFFFFFF;
    }
    return h & 0x3FFFFFFF;
  }

  // --- hard ----------------------------------------------------------------

  Move _hard(GameState s, List<Move> moves) {
    final me = s.turn;
    var budget = nodeBudget;

    Move? best;
    var bestValue = double.negativeInfinity;
    for (final move in moves) {
      final after = _engine.apply(s, PlayMove(move));
      final value = _value(after, me, depth - 1, () => budget-- > 0);
      if (value > bestValue) {
        bestValue = value;
        best = move;
      }
    }
    return best ?? moves.first;
  }

  /// Expectimax. Chance nodes average over the dice; decision nodes maximise
  /// for our side and minimise for everyone else.
  ///
  /// [s] always arrives awaiting a roll, which is exactly where the dice
  /// uncertainty lives — so every level of the search is a chance node
  /// followed by a decision.
  double _value(GameState s, int me, int depth, bool Function() spend) {
    if (s.isOver || depth <= 0 || !spend()) return _evaluate(s, me);

    final faces = s.rules.diceSides;
    var total = 0.0;
    for (var face = 1; face <= faces; face++) {
      final rolled = s.copyWith(dice: face);
      final moves = _engine.legalMoves(rolled);

      if (moves.isEmpty) {
        // Nothing playable: the turn passes (or a top face buys another roll).
        total += _evaluate(rolled, me);
        continue;
      }

      final ours = s.rules.sameSide(s.turn, me);
      var branchBest = ours ? double.negativeInfinity : double.infinity;
      for (final move in moves) {
        final after = _engine.apply(rolled, PlayMove(move));
        final v = _value(after, me, depth - 1, spend);
        branchBest = ours
            ? (v > branchBest ? v : branchBest)
            : (v < branchBest ? v : branchBest);
      }
      total += branchBest;
    }
    return total / faces;
  }

  /// How good this position is for [me] — and, in a team game, for my side.
  ///
  /// The term that makes the hard player feel different is the last one: it
  /// prices the risk of every square a chip is standing on, so it will decline
  /// a longer move that parks a chip six squares in front of an opponent.
  double _evaluate(GameState s, int me) {
    final board = s.board;
    final safe = s.safeRingSquares;
    var score = 0.0;

    for (final token in s.tokens) {
      final ours = s.rules.sameSide(token.owner, me);
      final sign = ours ? 1.0 : -1.0;

      if (board.isFinished(token.progress)) {
        score += sign * 120;
        continue;
      }
      if (token.inYard) {
        score += sign * -10;
        continue;
      }

      score += sign * token.progress * 0.7;

      if (board.isOnHomeStretch(token.progress)) {
        score += sign * 30; // beyond anyone's reach
        continue;
      }
      final ring = board.ringIndex(s.armOf(token.owner), token.progress);
      if (ring != null && safe.contains(ring)) {
        score += sign * 12;
      } else if (ring != null) {
        score += sign * -34 * _threat(s, token, ring);
      }
    }
    return score;
  }

  /// Rough chance this chip is captured on the next opposing turn: the share
  /// of dice faces that would bring some opponent onto its square.
  double _threat(GameState s, Token victim, int ring) {
    final board = s.board;
    final faces = s.rules.diceSides;
    final threatening = <int>{};

    for (final hunter in s.tokens) {
      if (hunter.inYard || s.rules.sameSide(hunter.owner, victim.owner)) {
        continue;
      }
      if (board.isOnHomeStretch(hunter.progress)) continue;

      for (var face = 1; face <= faces; face++) {
        final target = hunter.progress + face;
        if (target > board.finalProgress) break;
        if (board.ringIndex(s.armOf(hunter.owner), target) == ring) {
          threatening.add(face);
        }
      }
    }
    return threatening.length / faces;
  }
}
