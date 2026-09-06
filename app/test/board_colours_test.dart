import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_app/theme/seat_colors.dart';
import 'package:ludo_engine/ludo_engine.dart';

/// Which colour sits where, and who sits in which corner.
void main() {
  /// The colour opposite [arm], on a board with [arms] of them.
  Object across(int arm, int arms) => colourOfArm((arm + arms ~/ 2) % arms, arms);

  test('the four-arm board reads clockwise from green at the top left', () {
    expect(colourOfArm(0, 4), ludoGreen, reason: 'top left');
    expect(colourOfArm(1, 4), ludoYellow, reason: 'top right');
    expect(colourOfArm(2, 4), ludoBlue, reason: 'bottom right');
    expect(colourOfArm(3, 4), ludoRed, reason: 'bottom left');
  });

  test('four arms: green faces blue and yellow faces red', () {
    expect(across(0, 4), ludoBlue);
    expect(across(1, 4), ludoRed);
  });

  test('six arms: red faces yellow, blue faces green, orange faces magenta',
      () {
    final pairs = {
      for (var arm = 0; arm < 3; arm++)
        {colourOfArm(arm, 6), across(arm, 6)},
    };
    expect(pairs, {
      {ludoRed, ludoYellow},
      {ludoBlue, ludoGreen},
      {ludoOrange, ludoMagenta},
    });
  });

  test('red is bottom-left on both boards, and so is the first seat', () {
    // The two boards number their arms differently and cannot share one
    // colour order — a single list gives four arms green against red, which
    // is not a pair either board wants. What they do share is this corner.
    const bottomLeft = 3;
    expect(colourOfArm(bottomLeft, 4), ludoRed);
    expect(colourOfArm(bottomLeft, 6), ludoRed);

    for (final board in [BoardSpec.cross, BoardSpec.hexagon]) {
      expect(board.firstSeatArm, bottomLeft);
      for (var players = 2; players <= board.arms; players++) {
        expect(
          board.seatArms(players).first,
          bottomLeft,
          reason: '$players seats: the first player is not bottom-left',
        );
      }
    }
  });

  test('two seats sit opposite each other, red against yellow', () {
    for (final board in [BoardSpec.cross, BoardSpec.hexagon]) {
      final arms = board.seatArms(2);
      expect(
        (arms[1] - arms[0]).abs() % board.arms,
        board.arms ~/ 2,
        reason: 'the two seats are not opposite on a ${board.arms}-arm board',
      );
      expect(colourOfArm(arms[0], board.arms), ludoRed);
      expect(colourOfArm(arms[1], board.arms), ludoYellow);
    }
  });

  test('every arm has its own colour and its own name', () {
    for (final arms in [4, 6]) {
      final colours = {for (var a = 0; a < arms; a++) colourOfArm(a, arms)};
      final names = {for (var a = 0; a < arms; a++) nameOfArm(a, arms)};
      expect(colours, hasLength(arms), reason: '$arms arms share a colour');
      expect(names, hasLength(arms), reason: '$arms arms share a name');
    }
    expect(nameOfArm(3, 4), 'Red');
    expect(nameOfArm(4, 6), 'Magenta');
  });
}
