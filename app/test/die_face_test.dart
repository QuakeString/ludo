import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/die.dart';

/// The number on the die is the number that was rolled.
///
/// The most basic promise a die makes, and it was broken for two of the six
/// faces: rolling a 2 drew a 5 and rolling a 5 drew a 2, so the chip moved a
/// different distance from the one the player could see.
void main() {
  _throwTests();
  test('every face shows the number that was rolled', () {
    for (var value = 1; value <= 6; value++) {
      expect(
        faceShownFor(value),
        value,
        reason: 'rolling $value drew ${faceShownFor(value)}',
      );
    }
  });
}

/// The throw is meant to look like the die left the table.
void _throwTests() {
  test('the die is bigger in the air than on the table', () {
    const box = 54.0;
    final resting = dieHalfEdge(box, 1);
    final launched = dieHalfEdge(box, 0);
    final airborne = dieHalfEdge(box, 0.5);

    expect(
      resting,
      closeTo(launched, 0.001),
      reason: 'a die starts and finishes a throw on its place',
    );
    expect(
      airborne,
      greaterThan(resting * 1.15),
      reason: 'it never comes off the table',
    );
    // And it comes back down rather than staying big.
    expect(dieHalfEdge(box, 0.9), lessThan(airborne));
  });
}
