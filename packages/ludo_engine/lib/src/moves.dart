/// What a move does, beyond simply advancing.
enum MoveKind {
  /// Leaving the yard onto the start square.
  enter,

  /// A single token advancing along its path.
  advance,

  /// A linked pair advancing together, by half the roll.
  advancePair,
}

/// A legal move, with everything the UI needs to preview it.
class Move {
  const Move({
    required this.kind,
    required this.tokenIds,
    required this.owner,
    required this.steps,
    required this.fromProgress,
    required this.toProgress,
    this.pairId = -1,
    this.capturedTokenIds = const [],
  });

  final MoveKind kind;

  /// One token, or both members of a pair.
  final List<int> tokenIds;

  /// Whose token this is — not always the player on turn, since a finished
  /// player moves a partner's tokens.
  final int owner;

  final int steps;
  final int fromProgress;
  final int toProgress;
  final int pairId;

  /// Tokens this move sends back to their yard.
  final List<int> capturedTokenIds;

  bool get isCapture => capturedTokenIds.isNotEmpty;

  int get tokenId => tokenIds.first;

  @override
  String toString() {
    final what = kind == MoveKind.advancePair
        ? 'pair$pairId'
        : 'token${tokenIds.join('+')}';
    return 'Move(${kind.name}, $what, $fromProgress→$toProgress'
        '${isCapture ? ', captures ${capturedTokenIds.join(',')}' : ''})';
  }
}

/// Everything a player can do, not just movement.
sealed class GameAction {
  const GameAction();
}

/// Roll the dice. The value comes from the state's own RNG, so the server and
/// the client produce identical sequences from identical seeds.
class RollDice extends GameAction {
  const RollDice();
  @override
  String toString() => 'RollDice()';
}

/// Play one of the moves returned by `legalMoves`.
class PlayMove extends GameAction {
  const PlayMove(this.move);
  final Move move;
  @override
  String toString() => 'PlayMove($move)';
}

/// Give up the turn — only legal when the roll produced no legal move.
class PassTurn extends GameAction {
  const PassTurn();
  @override
  String toString() => 'PassTurn()';
}

/// Link two tokens sharing a square into a pair. Free action during your turn.
class FormPair extends GameAction {
  const FormPair(this.tokenA, this.tokenB);
  final int tokenA;
  final int tokenB;
  @override
  String toString() => 'FormPair($tokenA, $tokenB)';
}

/// Unlink a pair. Illegal while the pair is locked away from a safe square.
class BreakPair extends GameAction {
  const BreakPair(this.pairId);
  final int pairId;
  @override
  String toString() => 'BreakPair($pairId)';
}

/// Raised when an action is not legal in the given state. Carrying the reason
/// matters: the server rejects with it, and the client shows it.
class IllegalActionError implements Exception {
  IllegalActionError(this.message);
  final String message;
  @override
  String toString() => 'IllegalActionError: $message';
}
