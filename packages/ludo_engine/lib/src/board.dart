/// Board topology. Pure numbers — no pixels, no rendering.
///
/// A board has `arms` arms (4 for the classic cross, 6 for the hexagon) and a
/// ring track of `arms * squaresPerArm` squares. Every seat owns one arm.
///
/// A token's position is a single integer, `progress`:
///
/// ```
///   -1                     in its yard
///   0 .. trackLength-2     on the ring, at (startRing + progress) % trackLength
///   trackLength-1 .. +hc-1 in its home column, at progress - (trackLength-1)
///   finalProgress          home (finished)
/// ```
///
/// Using one integer for the whole journey means move generation is arithmetic
/// rather than a graph walk, and it makes states trivially comparable.
class BoardSpec {
  const BoardSpec({
    required this.arms,
    this.squaresPerArm = 13,
    this.homeColumn = 5,
    this.starOffset = 8,
  });

  /// The classic cross: four arms, 52 ring squares. Used for 2–4 seats.
  static const cross = BoardSpec(arms: 4);

  /// The hexagon: six arms, 78 ring squares. Used for 5–6 seats.
  static const hexagon = BoardSpec(arms: 6);

  /// Picks the board a given number of players is dealt onto.
  factory BoardSpec.forPlayers(int playerCount) =>
      playerCount <= 4 ? cross : hexagon;

  final int arms;
  final int squaresPerArm;
  final int homeColumn;

  /// How far past its start square a seat's safe star sits.
  final int starOffset;

  int get trackLength => arms * squaresPerArm;

  /// Progress value that means "home". A token needs exactly this many steps
  /// from its start square to finish.
  int get finalProgress => trackLength - 1 + homeColumn;

  /// The ring square a seat enters the board on.
  int startRing(int arm) => arm * squaresPerArm;

  /// The ring square holding this arm's safe star.
  int starRing(int arm) => (arm * squaresPerArm + starOffset) % trackLength;

  /// Ring square for a progress value, or null when the token is in its yard,
  /// in a home column, or finished — none of which live on the shared ring.
  int? ringIndex(int arm, int progress) {
    if (progress < 0 || progress > trackLength - 2) return null;
    return (startRing(arm) + progress) % trackLength;
  }

  /// Home-column index (0-based) for a progress value, or null if not in one.
  int? homeIndex(int progress) {
    if (progress < trackLength - 1 || progress >= finalProgress) return null;
    return progress - (trackLength - 1);
  }

  bool isFinished(int progress) => progress >= finalProgress;
  bool isInYard(int progress) => progress < 0;

  /// True when `progress` sits in the home column or on the home slot — the
  /// stretch no opponent can ever reach.
  bool isOnHomeStretch(int progress) => progress >= trackLength - 1;

  /// Seats are spread as evenly as the arms allow, so two players sit opposite
  /// each other rather than side by side.
  /// The corner the first seat plays from: bottom-left, on both boards.
  ///
  /// Where a person expects to be sitting. Seats are dealt round the board
  /// from here, so a game against the computer puts you bottom-left and a game
  /// of two seats the pair of you diagonally opposite — which on both boards
  /// is red against yellow.
  int get firstSeatArm => 3;

  List<int> seatArms(int playerCount) {
    if (playerCount < 2 || playerCount > arms) {
      throw ArgumentError(
          '$playerCount players do not fit on a $arms-arm board');
    }
    final used = <int>{};
    final out = <int>[];
    for (var i = 0; i < playerCount; i++) {
      var arm = (firstSeatArm + ((i * arms) / playerCount).round()) % arms;
      while (!used.add(arm)) {
        arm = (arm + 1) % arms;
      }
      out.add(arm);
    }
    return out;
  }

  /// Ring squares that are safe for everyone, given which flavour of safety
  /// the rules asked for.
  Set<int> safeRingSquares(SafeSquares mode) {
    switch (mode) {
      case SafeSquares.none:
        return const {};
      case SafeSquares.stars:
        return {for (var a = 0; a < arms; a++) starRing(a)};
      case SafeSquares.startsAndStars:
        return {
          for (var a = 0; a < arms; a++) ...[startRing(a), starRing(a)]
        };
    }
  }

  @override
  String toString() => 'BoardSpec(arms: $arms, track: $trackLength)';
}

/// Which squares protect a token from capture.
enum SafeSquares { none, stars, startsAndStars }
