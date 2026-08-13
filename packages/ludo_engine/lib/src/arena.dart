import 'ai.dart';
import 'rules.dart';
import 'state.dart';

/// The outcome of one head-to-head run.
class ArenaResult {
  ArenaResult(this.a, this.b, this.aWins, this.bWins, this.games, this.turns);

  final AiLevel a;
  final AiLevel b;
  final int aWins;
  final int bWins;
  final int games;

  /// Total turns played, for a rough sense of game length.
  final int turns;

  double get aWinRate => games == 0 ? 0 : aWins / games;
  double get averageTurns => games == 0 ? 0 : turns / games;

  @override
  String toString() => '${a.name} vs ${b.name}: '
      '${(aWinRate * 100).toStringAsFixed(1)}% '
      '($aWins–$bWins over $games games, '
      '${averageTurns.toStringAsFixed(0)} turns average)';
}

/// Plays computer players against each other so their strength is a measured
/// number rather than a claim.
///
/// Ludo is dominated by the dice, so a stronger player wins by a modest margin,
/// not a landslide — and a handful of games proves nothing. Every pairing is
/// therefore run twice per seed with the seats swapped, which cancels out any
/// advantage in going first.
class AiArena {
  const AiArena();

  ArenaResult head2head(
    AiLevel a,
    AiLevel b, {
    int games = 100,
    RuleConfig rules = const RuleConfig(players: 2, tokensPerPlayer: 4),
    int hardDepth = 3,
    int turnCap = 4000,
  }) {
    assert(rules.players == 2, 'head to head needs a two-seat game');
    var aWins = 0;
    var bWins = 0;
    var played = 0;
    var turns = 0;

    for (var i = 0; i < games; i++) {
      // Alternate who sits first, so seat order cannot flatter either side.
      final aSeat = i.isEven ? 0 : 1;
      final winner = _play(
        rules,
        seed: 1 + i * 7919,
        levels: {aSeat: a, 1 - aSeat: b},
        hardDepth: hardDepth,
        turnCap: turnCap,
        onTurn: () => turns++,
      );
      if (winner == null) continue; // hit the cap; counts for nobody
      played++;
      if (winner == aSeat) {
        aWins++;
      } else {
        bWins++;
      }
    }
    return ArenaResult(a, b, aWins, bWins, played, turns);
  }

  /// Runs a single game between seated computer players; returns the winning
  /// seat, or null if it ran past [turnCap].
  int? _play(
    RuleConfig rules, {
    required int seed,
    required Map<int, AiLevel> levels,
    required int hardDepth,
    required int turnCap,
    void Function()? onTurn,
  }) {
    final players = {
      for (final entry in levels.entries)
        entry.key: LudoAi(level: entry.value, depth: hardDepth),
    };
    var s = GameState.newGame(rules, seed: seed);
    for (var t = 0; t < turnCap && !s.isOver; t++) {
      onTurn?.call();
      final ai = players[s.turn] ?? const LudoAi();
      final before = s.fingerprint();
      s = ai.playTurn(s);
      // A turn that changes nothing would spin forever; treat it as a draw.
      if (s.fingerprint() == before) return null;
    }
    return s.winner;
  }
}
