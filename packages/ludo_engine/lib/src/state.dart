import 'board.dart';
import 'dice.dart';
import 'rules.dart';

/// One token. Immutable; moving produces a new instance.
class Token {
  const Token({
    required this.id,
    required this.owner,
    required this.progress,
    this.pairId = -1,
  });

  /// Stable index into [GameState.tokens].
  final int id;
  final int owner;

  /// -1 in the yard, else 0..[BoardSpec.finalProgress]. See [BoardSpec].
  final int progress;

  /// Pair group this token is linked into, or -1 when unlinked.
  final int pairId;

  bool get inYard => progress < 0;
  bool get isPaired => pairId >= 0;

  Token copyWith({int? progress, int? pairId}) => Token(
        id: id,
        owner: owner,
        progress: progress ?? this.progress,
        pairId: pairId ?? this.pairId,
      );

  Map<String, Object?> toJson() => {
        'i': id,
        'o': owner,
        'p': progress,
        if (isPaired) 'g': pairId,
      };

  factory Token.fromJson(Map<String, Object?> j) => Token(
        id: (j['i'] as num).toInt(),
        owner: (j['o'] as num).toInt(),
        progress: (j['p'] as num).toInt(),
        pairId: j['g'] == null ? -1 : (j['g'] as num).toInt(),
      );

  @override
  String toString() =>
      'Token($id, p$owner, ${inYard ? 'yard' : progress}${isPaired ? ', pair$pairId' : ''})';
}

/// The whole game, as one immutable value.
///
/// Same state + same action always produces the same next state, which is what
/// lets the client and the server run this identically.
class GameState {
  const GameState({
    required this.rules,
    required this.seatArms,
    required this.tokens,
    required this.turn,
    required this.dice,
    required this.consecutiveSixes,
    required this.captures,
    required this.nextPairId,
    required this.finishOrder,
    required this.rng,
  });

  /// A fresh game. [seed] fixes the dice sequence, so a game can be replayed
  /// exactly from its seed and action list.
  factory GameState.newGame(RuleConfig rules, {int seed = 1}) {
    rules.validate();
    final board = rules.board;
    final arms = board.seatArms(rules.players);
    final tokens = <Token>[];
    var id = 0;
    for (var p = 0; p < rules.players; p++) {
      for (var t = 0; t < rules.tokensPerPlayer; t++) {
        tokens.add(Token(id: id++, owner: p, progress: -1));
      }
    }
    return GameState(
      rules: rules,
      seatArms: List.unmodifiable(arms),
      tokens: List.unmodifiable(tokens),
      turn: 0,
      dice: null,
      consecutiveSixes: 0,
      captures: List.unmodifiable(List.filled(rules.players, 0)),
      nextPairId: 0,
      finishOrder: const [],
      rng: DiceRng.fromSeed(seed),
    );
  }

  final RuleConfig rules;

  /// Which arm of the board each seat plays from.
  final List<int> seatArms;
  final List<Token> tokens;
  final int turn;

  /// The pending roll. Null means the player on turn still has to roll.
  final int? dice;

  final int consecutiveSixes;

  /// Captures made by each seat — [RuleConfig.mustCaptureToWin] reads this.
  final List<int> captures;

  final int nextPairId;

  /// Seats that have brought every token home, earliest first.
  final List<int> finishOrder;

  /// Deterministic RNG cursor. Part of the state so replays are exact.
  /// The dice. Not a number anybody outside the engine should read — see
  /// [toJson], which keeps it off the wire on purpose.
  final DiceRng rng;

  BoardSpec get board => rules.board;
  bool get awaitingRoll => dice == null;

  int armOf(int player) => seatArms[player];

  Iterable<Token> tokensOf(int player) =>
      tokens.where((t) => t.owner == player);

  /// Tokens standing on a given ring square, whoever owns them.
  List<Token> tokensOnRing(int ringIndex) => [
        for (final t in tokens)
          if (!t.inYard &&
              board.ringIndex(armOf(t.owner), t.progress) == ringIndex)
            t
      ];

  List<Token> pairMembers(int pairId) => [
        for (final t in tokens)
          if (t.pairId == pairId) t
      ];

  bool hasFinished(int player) =>
      tokensOf(player).every((t) => board.isFinished(t.progress));

  Set<int> get safeRingSquares => board.safeRingSquares(rules.safeSquares);

  /// The seat that has won, or null. In a team game this is the first member
  /// of the winning team; use [winningTeam] for the team itself.
  int? get winner {
    if (rules.isTeamGame) {
      final team = winningTeam;
      if (team == null) return null;
      return rules.teams![team].first;
    }
    for (var p = 0; p < rules.players; p++) {
      if (hasFinished(p)) return p;
    }
    return null;
  }

  int? get winningTeam {
    if (!rules.isTeamGame) return null;
    final teams = rules.teams!;
    for (var i = 0; i < teams.length; i++) {
      if (teams[i].every(hasFinished)) return i;
    }
    return null;
  }

  bool get isOver => winner != null;

  /// Seats whose tokens this player may move on their turn. Normally just
  /// themselves; a player who is home keeps rolling for a partner.
  List<int> movableOwners(int player) {
    if (!hasFinished(player)) return [player];
    if (!rules.isTeamGame || !rules.finishedPlayerMovesPartner) return const [];
    return [
      for (final p in rules.partnersOf(player))
        if (!hasFinished(p)) p
    ];
  }

  GameState copyWith({
    List<Token>? tokens,
    int? turn,
    Object? dice = _unset,
    int? consecutiveSixes,
    List<int>? captures,
    int? nextPairId,
    List<int>? finishOrder,
    DiceRng? rng,
  }) {
    return GameState(
      rules: rules,
      seatArms: seatArms,
      tokens: tokens ?? this.tokens,
      turn: turn ?? this.turn,
      dice: identical(dice, _unset) ? this.dice : dice as int?,
      consecutiveSixes: consecutiveSixes ?? this.consecutiveSixes,
      captures: captures ?? this.captures,
      nextPairId: nextPairId ?? this.nextPairId,
      finishOrder: finishOrder ?? this.finishOrder,
      rng: rng ?? this.rng,
    );
  }

  static const _unset = Object();

  /// Compact, stable text form — handy for golden replay tests.
  String fingerprint() {
    final b = StringBuffer()
      ..write(
          't$turn/d${dice ?? '-'}/s$consecutiveSixes/c${captures.join(',')}|');
    for (final t in tokens) {
      b.write('${t.progress}${t.isPaired ? '*${t.pairId}' : ''};');
    }
    return b.toString();
  }

  /// The whole game as JSON.
  ///
  /// One shape serves three jobs: the save file that survives closing the app,
  /// the message the server broadcasts after every move, and the record a
  /// finished match is stored as. Keys are short because this crosses the wire
  /// on every turn.
  ///
  /// The dice are left out unless [withDice] is set, and that default is the
  /// point of the parameter. The generator's state is the whole future of the
  /// dice: anybody holding it can work out every roll the rest of the game
  /// will produce, exactly, with four lines of arithmetic. Broadcasting it to
  /// every player — which is what this used to do — handed each of them a
  /// perfect prediction of their own and everyone else's throws.
  ///
  /// A save file and a match record are for the machine that owns the game, so
  /// those pass [withDice]; the wire never does. A client that ends up with a
  /// diceless state loses nothing, because online it is the server that rolls
  /// and the server would reject anything else.
  Map<String, Object?> toJson({bool withDice = false}) => {
        'rules': rules.toJson(),
        'arms': seatArms,
        'tokens': [for (final t in tokens) t.toJson()],
        'turn': turn,
        if (dice != null) 'dice': dice,
        'sixes': consecutiveSixes,
        'caps': captures,
        'pair': nextPairId,
        'done': finishOrder,
        if (withDice) 'rng': rng.toJson(),
      };

  factory GameState.fromJson(Map<String, Object?> j) {
    List<int> ints(Object? v) =>
        [for (final x in (v as List? ?? const [])) (x as num).toInt()];
    return GameState(
      rules: RuleConfig.fromJson(j['rules'] as Map<String, Object?>),
      seatArms: List.unmodifiable(ints(j['arms'])),
      tokens: List.unmodifiable([
        for (final t in (j['tokens'] as List))
          Token.fromJson(t as Map<String, Object?>)
      ]),
      turn: (j['turn'] as num).toInt(),
      dice: j['dice'] == null ? null : (j['dice'] as num).toInt(),
      consecutiveSixes: (j['sixes'] as num?)?.toInt() ?? 0,
      captures: List.unmodifiable(ints(j['caps'])),
      nextPairId: (j['pair'] as num?)?.toInt() ?? 0,
      finishOrder: List.unmodifiable(ints(j['done'])),
      rng: DiceRng.fromJson(j['rng']),
    );
  }

  @override
  String toString() => 'GameState(turn: $turn, dice: $dice, '
      '${tokens.where((t) => board.isFinished(t.progress)).length} home)';
}
