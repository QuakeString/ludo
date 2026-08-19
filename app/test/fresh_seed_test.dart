import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/fresh_seed.dart';

/// Every local game gets its own dice.
///
/// It did not. GameScreen's seed defaulted to 1 and the setup screen never
/// passed one, so every game played on a device rolled the identical sequence,
/// and "New game" was that sequence shifted by exactly one.
void main() {
  test('two games do not get the same dice', () {
    final seeds = {for (var i = 0; i < 40; i++) freshSeed()};
    expect(
      seeds.length,
      greaterThan(35),
      reason: 'fresh games are being handed the same seed',
    );
    for (final s in seeds) {
      expect(s, greaterThan(0), reason: 'zero is not a seed xorshift can use');
    }
  });
}
