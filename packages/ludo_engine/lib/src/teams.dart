/// The ways a table can be split into sides.
///
/// Gathered here rather than written out at each screen because they were
/// written out at each screen, and both copies said the same wrong thing: that
/// six players can only be three against three. Six splits two ways — two big
/// sides, or three pairs — and a game of three teams is a different game, not
/// a variant of the same one.
class TeamShape {
  const TeamShape({
    required this.label,
    required this.description,
    required this.groups,
  });

  /// How the split is said out loud: "3 v 3", "2 v 2 v 2".
  final String label;

  /// Where the partners actually sit, which is the part that decides how the
  /// game plays and the part nobody can work out from the label.
  final String description;

  /// Seats, grouped. Ready to hand to [RuleConfig.teams].
  final List<List<int>> groups;

  int get teamCount => groups.length;
  int get teamSize => groups.isEmpty ? 0 : groups.first.length;
}

/// Every way [players] seats can be divided into equal sides.
///
/// Empty when there is no sensible split, which is every odd count and two —
/// two players are already two sides.
///
/// Partners are seated as far apart as the shape allows. That is not
/// decoration: a side whose members sit next to each other owns one stretch of
/// the board and nothing else, while a side seated opposite has somebody in
/// reach wherever the play goes. Alternating is the way partnership games are
/// laid out at a real table for exactly that reason.
List<TeamShape> teamShapesFor(int players) {
  switch (players) {
    case 4:
      return const [
        TeamShape(
          label: '2 v 2',
          description: 'Partners sit opposite each other',
          groups: [
            [0, 2],
            [1, 3],
          ],
        ),
      ];
    case 6:
      return const [
        TeamShape(
          label: '3 v 3',
          description: 'Two sides of three, seated alternately',
          groups: [
            [0, 2, 4],
            [1, 3, 5],
          ],
        ),
        TeamShape(
          label: '2 v 2 v 2',
          description: 'Three pairs, each sitting opposite its partner',
          groups: [
            [0, 3],
            [1, 4],
            [2, 5],
          ],
        ),
      ];
    default:
      return const [];
  }
}
