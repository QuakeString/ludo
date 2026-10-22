import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/theme/seat_colors.dart';

/// At night the board's own colours step back so the chips stand out.
void main() {
  test('a light board paints seat colours a lighter shade', () {
    final painted = BoardPalette.light.painted(ludoRed);
    expect(painted, isNot(ludoRed));
    expect(painted.computeLuminance(), greaterThan(ludoRed.computeLuminance()));
  });

  test('a dark board holds its painted colours back', () {
    final painted = BoardPalette.dark.painted(ludoRed);
    expect(painted, isNot(ludoRed));
    expect(painted.computeLuminance(), lessThan(ludoRed.computeLuminance()));
  });
}
