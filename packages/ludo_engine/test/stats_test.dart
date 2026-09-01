import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

/// The tally has to agree with the game it was counting.
///
/// A stats sheet that is merely plausible is worse than none at all: it is the
/// thing people will reach for to settle an argument about the dice, and it
/// has already been the subject of one — "that player always gets sixes" —
/// where the answer turned on numbers being right.
void main() {
  const engine = LudoEngine();
  const rules = RuleConfig(players: 4, tokensPerPlayer: 4);

  /// Plays a whole game, counting everything independently as it goes, and
  /// hands back both accounts to be compared.
  (GameState, List<List<int>>, List<int>, List<int>) playOut(int seed) {
    var s = GameState.newGame(rules, seed: seed);
    final rolls = [
      for (var p = 0; p < rules.players; p++) List.filled(rules.diceSides, 0)
    ];
    final moves = List.filled(rules.players, 0);
    final lost = List.filled(rules.players, 0);

    for (var step = 0; step < 20000 && !s.isOver; step++) {
      if (s.awaitingRoll) {
        final seat = s.turn;
        final face = engine.peekRoll(s);
        s = engine.apply(s, const RollDice());
        rolls[seat][face - 1]++;
        continue;
      }
      final legal = engine.legalMoves(s);
      if (legal.isEmpty) {
        s = engine.apply(s, const PassTurn());
        continue;
      }
      final seat = s.turn;
      final m = legal.first;
      for (final id in m.capturedTokenIds) {
        lost[s.tokens[id].owner]++;
      }
      s = engine.apply(s, PlayMove(m));
      moves[seat]++;
    }
    return (s, rolls, moves, lost);
  }

  test('the sheet matches the game it counted', () {
    for (final seed in [3, 19, 404]) {
      final (s, rolls, moves, lost) = playOut(seed);
      expect(s.isOver, isTrue, reason: 'seed $seed never finished');

      for (var p = 0; p < rules.players; p++) {
        for (var f = 1; f <= rules.diceSides; f++) {
          expect(s.stats.rollsOf(p, f), rolls[p][f - 1],
              reason: 'seed $seed, seat $p, face $f');
        }
        expect(s.stats.moves[p], moves[p], reason: 'seed $seed, seat $p moves');
        expect(s.stats.lost[p], lost[p], reason: 'seed $seed, seat $p losses');
      }

      // Every chip knocked off was knocked off by somebody.
      expect(s.stats.totalLosses, s.captures.fold(0, (a, b) => a + b),
          reason: 'seed $seed: captures and losses disagree');
    }
  });

  test('a forfeited third six is still counted as a throw', () {
    // Rolls that cost the turn are the ones a tally is most tempting to skip,
    // and skipping them is how the sheet comes to say fewer sixes than were
    // actually seen — which is precisely the thing it exists to answer.
    const strict = RuleConfig(players: 2, tripleSixForfeits: true);
    var s = GameState.newGame(strict, seed: 5).copyWith(consecutiveSixes: 2);
    for (var seed = 1; seed < 500; seed++) {
      final probe =
          GameState.newGame(strict, seed: seed).copyWith(consecutiveSixes: 2);
      if (engine.peekRoll(probe) == 6) {
        s = probe;
        break;
      }
    }
    expect(engine.peekRoll(s), 6, reason: 'no seed opened on a six');

    final before = s.stats.rollsOf(0, 6);
    final after = engine.apply(s, const RollDice());
    expect(after.turn, isNot(0), reason: 'the third six did not forfeit');
    expect(after.stats.rollsOf(0, 6), before + 1);
  });

  test('a sheet survives a save and a reload', () {
    final (s, _, _, _) = playOut(19);
    final back = GameState.fromJson(s.toJson(withDice: true));
    for (var p = 0; p < rules.players; p++) {
      expect(back.stats.rolls[p], s.stats.rolls[p]);
      expect(back.stats.moves[p], s.stats.moves[p]);
      expect(back.stats.lost[p], s.stats.lost[p]);
    }
  });

  test('a game saved before any of this existed still loads', () {
    final j = GameState.newGame(rules, seed: 2).toJson(withDice: true)
      ..remove('stat');
    final back = GameState.fromJson(j);
    expect(back.stats.totalThrows, 0);
    expect(back.stats.moves.length, rules.players);
    expect(back.stats.diceSides, rules.diceSides);
  });
}
