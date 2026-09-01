import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

/// Six players is not only three against three.
void main() {
  test('six seats split two ways, four seats one', () {
    expect(teamShapesFor(6).map((s) => s.label), ['3 v 3', '2 v 2 v 2']);
    expect(teamShapesFor(4).map((s) => s.label), ['2 v 2']);
  });

  test('counts a table cannot be divided offer nothing', () {
    for (final n in [2, 3, 5]) {
      expect(teamShapesFor(n), isEmpty, reason: '$n seats');
    }
  });

  test('every shape is a legal game the engine will actually run', () {
    for (final players in [4, 6]) {
      for (final shape in teamShapesFor(players)) {
        final rules = RuleConfig(players: players, teams: shape.groups);
        // Throws on anything malformed — a seat left out, a seat on two
        // sides, sides of different sizes.
        expect(rules.validate, returnsNormally, reason: shape.label);

        expect(shape.groups.expand((g) => g).toSet(),
            {for (var p = 0; p < players; p++) p},
            reason: '${shape.label}: not every seat is on a side');
        expect(shape.teamCount * shape.teamSize, players,
            reason: '${shape.label}: the label does not match the groups');

        // And it finishes. A three-team game ends when one team is home, not
        // when one player is, and that is a different question to ask of the
        // board.
        const engine = LudoEngine();
        var s = GameState.newGame(rules, seed: 11);
        for (var i = 0; i < 40000 && !s.isOver; i++) {
          if (s.awaitingRoll) {
            s = engine.apply(s, const RollDice());
            continue;
          }
          final legal = engine.legalMoves(s);
          s = legal.isEmpty
              ? engine.apply(s, const PassTurn())
              : engine.apply(s, PlayMove(legal.first));
        }
        expect(s.isOver, isTrue, reason: '${shape.label} never finished');
        expect(s.winningTeam, isNotNull, reason: '${shape.label}: no side won');
      }
    }
  });

  test('the label says how many sides there really are', () {
    final three = teamShapesFor(6).firstWhere((s) => s.teamCount == 3);
    expect(three.label, '2 v 2 v 2');
    expect(three.teamSize, 2);
    // Opposite, not adjacent: on a six-arm board seat 0 faces seat 3.
    expect(three.groups, [
      [0, 3],
      [1, 4],
      [2, 5],
    ]);
  });
}
