/// What each seat actually did, counted as the game goes.
///
/// A development instrument first: the dice have been accused of favouritism
/// twice, and both times the only way to answer was to instrument a build and
/// play a hundred games. Counting as we go makes the answer available from
/// inside a real game, which is where the suspicion is formed.
///
/// It is also the honest form of the accusation. "That player keeps getting
/// sixes" is a claim about a distribution, and a distribution is a table of
/// counts — so the table is what the game should be able to show.
class MatchStats {
  const MatchStats({
    required this.rolls,
    required this.moves,
    required this.lost,
  });

  /// A fresh sheet: [players] seats, each with a bin per die face.
  factory MatchStats.blank(int players, int diceSides) => MatchStats(
        rolls: List.unmodifiable([
          for (var p = 0; p < players; p++)
            List<int>.unmodifiable(List.filled(diceSides, 0))
        ]),
        moves: List.unmodifiable(List.filled(players, 0)),
        lost: List.unmodifiable(List.filled(players, 0)),
      );

  /// `rolls[seat][face - 1]` — how many times that seat threw that number.
  ///
  /// Indexed from zero while dice are numbered from one, which is the sort of
  /// thing that goes wrong silently, so [rollsOf] exists to be used instead.
  final List<List<int>> rolls;

  /// Moves actually played, per seat. Not the same as rolls: a throw with
  /// nowhere to go is a roll without a move, and a six is a roll that buys
  /// another roll.
  final List<int> moves;

  /// Chips knocked back to the yard, per seat — the other side of
  /// [GameState.captures], which counts the knocking rather than the being
  /// knocked. Both halves are wanted: one seat's good afternoon is another's
  /// bad one, and the pair together says whether a game was a brawl or a race.
  final List<int> lost;

  int get players => moves.length;
  int get diceSides => rolls.isEmpty ? 0 : rolls.first.length;

  /// How many times [seat] rolled [face], counting faces from one.
  int rollsOf(int seat, int face) => rolls[seat][face - 1];

  /// Every throw [seat] has made.
  int throwsBy(int seat) => rolls[seat].fold(0, (a, b) => a + b);

  int get totalThrows {
    var n = 0;
    for (var p = 0; p < players; p++) {
      n += throwsBy(p);
    }
    return n;
  }

  int get totalMoves => moves.fold(0, (a, b) => a + b);

  int get totalLosses => lost.fold(0, (a, b) => a + b);

  /// A copy with one more throw of [face] recorded against [seat].
  MatchStats withRoll(int seat, int face) {
    // Out of range rather than an assertion: a stats sheet must never be the
    // reason a game stops. If the rules changed under it, the counting is
    // wrong and the game is still fine.
    if (seat < 0 || seat >= players || face < 1 || face > diceSides) return this;
    final next = [
      for (var p = 0; p < players; p++)
        p == seat
            ? List<int>.unmodifiable([
                for (var f = 0; f < diceSides; f++)
                  rolls[p][f] + (f == face - 1 ? 1 : 0)
              ])
            : rolls[p]
    ];
    return MatchStats(
        rolls: List.unmodifiable(next), moves: moves, lost: lost);
  }

  /// A copy with one more move recorded against [seat].
  MatchStats withMove(int seat) {
    if (seat < 0 || seat >= players) return this;
    return MatchStats(
      rolls: rolls,
      moves: List.unmodifiable([
        for (var p = 0; p < players; p++) moves[p] + (p == seat ? 1 : 0)
      ]),
      lost: lost,
    );
  }

  /// A copy with [n] more chips recorded as knocked off [seat].
  MatchStats withLosses(int seat, int n) {
    if (seat < 0 || seat >= players || n <= 0) return this;
    return MatchStats(
      rolls: rolls,
      moves: moves,
      lost: List.unmodifiable([
        for (var p = 0; p < players; p++) lost[p] + (p == seat ? n : 0)
      ]),
    );
  }

  Map<String, Object?> toJson() => {
        'r': [for (final row in rolls) row],
        'm': moves,
        'l': lost,
      };

  /// Rebuilt from JSON, or blank when there is none.
  ///
  /// Blank rather than absent, because a game saved before this existed is
  /// still a perfectly good game — it just has nothing to show.
  factory MatchStats.fromJson(Object? j, int players, int diceSides) {
    if (j is! Map) return MatchStats.blank(players, diceSides);
    List<int> ints(Object? v, int len) {
      final xs = [for (final x in (v as List? ?? const [])) (x as num).toInt()];
      return List<int>.unmodifiable([
        for (var i = 0; i < len; i++) i < xs.length ? xs[i] : 0
      ]);
    }

    final rows = (j['r'] as List?) ?? const [];
    return MatchStats(
      rolls: List.unmodifiable([
        for (var p = 0; p < players; p++)
          ints(p < rows.length ? rows[p] : null, diceSides)
      ]),
      moves: ints(j['m'], players),
      lost: ints(j['l'], players),
    );
  }
}
