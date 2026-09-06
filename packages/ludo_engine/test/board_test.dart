import 'package:ludo_engine/ludo_engine.dart';
import 'package:test/test.dart';

void main() {
  group('BoardSpec', () {
    test('cross and hexagon have the expected track lengths', () {
      expect(BoardSpec.cross.trackLength, 52);
      expect(BoardSpec.hexagon.trackLength, 78);
    });

    test('players 2-4 get the cross, 5-6 get the hexagon', () {
      for (var p = 2; p <= 4; p++) {
        expect(BoardSpec.forPlayers(p).arms, 4, reason: '$p players');
      }
      for (var p = 5; p <= 6; p++) {
        expect(BoardSpec.forPlayers(p).arms, 6, reason: '$p players');
      }
    });

    test('a token needs exactly finalProgress steps to come home', () {
      // 51 ring squares from its start, then a 5-square home column.
      expect(BoardSpec.cross.finalProgress, 51 + 5);
      expect(BoardSpec.hexagon.finalProgress, 77 + 5);
    });

    test('two players sit opposite each other, four fill every arm', () {
      // Dealt from the bottom-left corner, which is where a person expects
      // to be sitting — so two seats come out diagonally opposite and four
      // fill the board going round from there.
      expect(BoardSpec.cross.seatArms(2), [3, 1]);
      expect(BoardSpec.cross.seatArms(4), [3, 0, 1, 2]);
      expect(BoardSpec.cross.seatArms(2).first, BoardSpec.cross.firstSeatArm);
      expect(BoardSpec.hexagon.seatArms(6).first, BoardSpec.hexagon.firstSeatArm);
    });

    test('six players fill the hexagon and never share an arm', () {
      final arms = BoardSpec.hexagon.seatArms(6);
      expect(arms.toSet().length, 6);
      expect(arms.length, 6);
    });

    test('five players on the hexagon get distinct, spread arms', () {
      final arms = BoardSpec.hexagon.seatArms(5);
      expect(arms.toSet().length, 5, reason: 'no two seats share an arm');
    });

    test('more players than arms is rejected', () {
      expect(() => BoardSpec.cross.seatArms(5), throwsArgumentError);
    });

    test('ring positions wrap around the track', () {
      const b = BoardSpec.cross;
      // Seat on arm 3 starts at 39 and wraps past 51 back to 0.
      expect(b.ringIndex(3, 0), 39);
      expect(b.ringIndex(3, 12), 51);
      expect(b.ringIndex(3, 13), 0);
      expect(b.ringIndex(3, 50), 37);
    });

    test('the home stretch is off the shared ring', () {
      const b = BoardSpec.cross;
      expect(b.ringIndex(0, b.trackLength - 1), isNull);
      expect(b.homeIndex(b.trackLength - 1), 0);
      expect(b.homeIndex(b.finalProgress - 1), b.homeColumn - 1);
      expect(b.isFinished(b.finalProgress), isTrue);
    });

    test('safe squares follow the chosen mode', () {
      const b = BoardSpec.cross;
      expect(b.safeRingSquares(SafeSquares.none), isEmpty);
      expect(b.safeRingSquares(SafeSquares.stars), {8, 21, 34, 47});
      expect(b.safeRingSquares(SafeSquares.startsAndStars),
          {0, 8, 13, 21, 26, 34, 39, 47});
    });

    test('every arm has exactly one start and one star', () {
      for (final b in [BoardSpec.cross, BoardSpec.hexagon]) {
        final starts = {for (var a = 0; a < b.arms; a++) b.startRing(a)};
        final stars = {for (var a = 0; a < b.arms; a++) b.starRing(a)};
        expect(starts.length, b.arms);
        expect(stars.length, b.arms);
        expect(starts.intersection(stars), isEmpty,
            reason: 'a start square must not double as a star');
      }
    });
  });
}
