import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

/// Turning the board so a seat plays from the bottom-left corner changes the
/// picture and nothing else.
void main() {
  const engine = LudoEngine();

  test('puts the chosen seat in the first-seat corner', () {
    for (final players in [2, 3, 4, 5, 6]) {
      final s = GameState.newGame(RuleConfig(players: players), seed: 1);
      for (var seat = 0; seat < players; seat++) {
        final turned = s.turnedFor(seat);
        expect(turned.armOf(seat), s.board.firstSeatArm);
        expect(turned.seatArms.toSet(), hasLength(players),
            reason: 'two seats ended up on one arm');
      }
    }
  });

  test('every move is the same move, all game long', () {
    for (final players in [2, 3, 4, 6]) {
      for (final pairMove in [false, true]) {
        final rules = RuleConfig(players: players, pairMove: pairMove);
        var s = GameState.newGame(rules, seed: players * 7);
        for (var i = 0; i < 3000 && !s.isOver; i++) {
          for (var seat = 0; seat < players; seat++) {
            final turned = s.turnedFor(seat);
            if (s.awaitingRoll) continue;
            expect('${engine.legalMoves(turned)}', '${engine.legalMoves(s)}',
                reason: '$players seats, step $i, seen from seat $seat');
          }
          if (s.awaitingRoll) {
            s = engine.apply(s, const RollDice());
            continue;
          }
          final moves = engine.legalMoves(s);
          s = engine.apply(
              s, moves.isEmpty ? const PassTurn() : PlayMove(moves.last));
        }
      }
    }
  });
}
