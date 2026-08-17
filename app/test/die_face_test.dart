import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/die.dart';

/// The number on the die is the number that was rolled.
///
/// The most basic promise a die makes, and it was broken for two of the six
/// faces: rolling a 2 drew a 5 and rolling a 5 drew a 2, so the chip moved a
/// different distance from the one the player could see.
void main() {
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
