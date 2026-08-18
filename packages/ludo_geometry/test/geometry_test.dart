import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';
import 'package:test/test.dart';

/// Largest gap between the centres of consecutive track squares, in cell
/// widths. Orthogonal neighbours are 1 apart; a diagonal corner turn is 1.42.
double worstStep(BoardGeometry g) {
  final n = g.spec.trackLength;
  var worst = 0.0;
  for (var i = 0; i < n; i++) {
    final a = g.ringCell(i).centre;
    final b = g.ringCell((i + 1) % n).centre;
    final gap = (b - a).length / g.cellSize;
    if (gap > worst) worst = gap;
  }
  return worst;
}

void main() {
  group('cross board', () {
    final g = CrossGeometry(BoardSpec.cross);

    test('the track is a closed loop of touching squares', () {
      expect(worstStep(g), lessThan(1.45),
          reason: 'consecutive squares must touch, edge-on or corner-on');
    });

    test('every ring square is distinct', () {
      final seen = <String>{};
      for (var i = 0; i < BoardSpec.cross.trackLength; i++) {
        final c = g.ringCell(i).centre;
        expect(seen.add('${c.x},${c.y}'), isTrue, reason: 'square $i repeats');
      }
    });

    test('each seat starts beside its own yard', () {
      for (var arm = 0; arm < 4; arm++) {
        final start = g.ringCell(BoardSpec.cross.startRing(arm)).centre;
        final slots = g.yardSlots(arm);
        final nearest = slots
            .map((s) => (s - start).length / g.cellSize)
            .reduce((a, b) => a < b ? a : b);
        expect(nearest, lessThan(4.0),
            reason: 'arm $arm starts far from its own yard');
      }
    });

    test('a seat turns into its home column from the square before its start',
        () {
      const b = BoardSpec.cross;
      for (var arm = 0; arm < 4; arm++) {
        final turnIn = g.turnInCell(arm).centre;
        final firstHome = g.homeCell(arm, 0).centre;
        expect((firstHome - turnIn).length / g.cellSize, lessThan(1.45),
            reason: 'arm $arm cannot reach its home column');
        // And that turn-in square is where progress trackLength-2 lands.
        final lastRing =
            g.ringCell(b.ringIndex(arm, b.trackLength - 2)!).centre;
        expect(lastRing, turnIn);
      }
    });

    test('home columns are five squares marching inward to the centre', () {
      for (var arm = 0; arm < 4; arm++) {
        var previous = g.turnInCell(arm).centre;
        for (var i = 0; i < BoardSpec.cross.homeColumn; i++) {
          final cell = g.homeCell(arm, i).centre;
          expect((cell - previous).length / g.cellSize, closeTo(1.0, 0.01),
              reason: 'arm $arm home square $i is not adjacent to the last');
          previous = cell;
        }
        // The last home square sits right against the centre triangle, which
        // is three squares wide — so its centre is two squares out.
        expect((previous - const Pt(0.5, 0.5)).length / g.cellSize,
            closeTo(2.0, 0.05),
            reason: 'arm $arm home column does not end at the centre');
      }
    });

    test('home columns never touch the shared ring', () {
      final ring = {
        for (var i = 0; i < BoardSpec.cross.trackLength; i++)
          '${g.ringCell(i).centre.x},${g.ringCell(i).centre.y}'
      };
      for (var arm = 0; arm < 4; arm++) {
        for (var i = 0; i < BoardSpec.cross.homeColumn; i++) {
          final c = g.homeCell(arm, i).centre;
          expect(ring.contains('${c.x},${c.y}'), isFalse,
              reason: 'arm $arm home square $i sits on the ring');
        }
      }
    });

    test('everything stays inside the board', () {
      void inside(Pt p, String what) {
        expect(p.x, inInclusiveRange(0, 1), reason: what);
        expect(p.y, inInclusiveRange(0, 1), reason: what);
      }

      for (var i = 0; i < BoardSpec.cross.trackLength; i++) {
        inside(g.ringCell(i).centre, 'ring $i');
      }
      for (var arm = 0; arm < 4; arm++) {
        for (final s in g.yardSlots(arm)) {
          inside(s, 'yard slot $arm');
        }
      }
    });

    test('a token in the yard, on the track and home all resolve', () {
      const b = BoardSpec.cross;
      expect(g.tokenAt(0, -1), g.yardSlots(0).first);
      expect(g.tokenAt(0, 0), g.ringCell(b.startRing(0)).centre);
      expect(g.tokenAt(0, b.finalProgress), isNot(const Pt(0.5, 0.5)),
          reason: 'a finished chip rests in its own wedge, not the middle');
    });

    test('each seat finishes in its own wedge of the centre', () {
      const b = BoardSpec.cross;
      final rests = [
        for (var arm = 0; arm < 4; arm++) g.tokenAt(arm, b.finalProgress)
      ];

      // Four seats, four distinct resting places — chips that are home must
      // still show whose they are.
      expect(rests.toSet(), hasLength(4));

      for (var arm = 0; arm < 4; arm++) {
        final wedge = g.centreWedges()[arm];
        expect(_inside(wedge, rests[arm]), isTrue,
            reason: 'arm $arm rests outside its own wedge');
        // And near the middle of the board, not out on the track.
        expect((rests[arm] - const Pt(0.5, 0.5)).length, lessThan(0.12));
      }
    });

    test('stars sit on the ring, one per arm', () {
      final stars = g.starRingIndices();
      expect(stars, hasLength(4));
      expect(stars.toSet(), hasLength(4));
    });
  });

  group('hexagon board', () {
    final g = HexGeometry(BoardSpec.hexagon);

    test('the track is a closed loop of touching squares', () {
      expect(worstStep(g), lessThan(1.45),
          reason: 'consecutive squares must touch, edge-on or corner-on');
    });

    test('every ring square is distinct', () {
      final seen = <String>{};
      for (var i = 0; i < BoardSpec.hexagon.trackLength; i++) {
        final c = g.ringCell(i).centre;
        final key = '${c.x.toStringAsFixed(4)},${c.y.toStringAsFixed(4)}';
        expect(seen.add(key), isTrue, reason: 'square $i repeats');
      }
    });

    test('each seat starts beside its own yard', () {
      for (var arm = 0; arm < 6; arm++) {
        final start = g.ringCell(BoardSpec.hexagon.startRing(arm)).centre;
        final nearest = g
            .yardSlots(arm)
            .map((s) => (s - start).length / g.cellSize)
            .reduce((a, b) => a < b ? a : b);
        expect(nearest, lessThan(4.0),
            reason: 'arm $arm starts far from its own yard');
      }
    });

    test('home columns march inward and end at the centre', () {
      for (var arm = 0; arm < 6; arm++) {
        var previous = g.turnInCell(arm).centre;
        for (var i = 0; i < BoardSpec.hexagon.homeColumn; i++) {
          final cell = g.homeCell(arm, i).centre;
          expect((cell - previous).length / g.cellSize, closeTo(1.0, 0.02),
              reason: 'arm $arm home square $i is not adjacent to the last');
          previous = cell;
        }
      }
    });

    test('each home base apex meets a corner of the centre', () {
      final corners = g.centreOutline();
      for (var arm = 0; arm < 6; arm++) {
        final apex = g.yardShape(arm).a;
        final nearest = corners
            .map((c) => (c - apex).length / g.cellSize)
            .reduce((a, b) => a < b ? a : b);
        expect(nearest, lessThan(0.05),
            reason: 'arm $arm apex does not land on a corner of the centre');
      }
    });

    test('each home base reaches the rim of the plate', () {
      final plate = g.plateOutline();
      for (var arm = 0; arm < 6; arm++) {
        final tri = g.yardShape(arm);
        // The base is two adjacent corners of the plate, so the house runs
        // corner to corner along the board's own edge with nothing left over.
        for (final corner in [tri.b, tri.c]) {
          final nearest = plate
              .map((c) => (c - corner).length / g.cellSize)
              .reduce((a, b) => a < b ? a : b);
          expect(nearest, lessThan(0.001),
              reason: 'arm $arm does not reach the plate edge');
        }
        expect(tri.b, isNot(tri.c));
      }
    });

    test('a home base never runs over the track', () {
      for (var arm = 0; arm < 6; arm++) {
        final tri = g.yardShape(arm);
        for (var i = 0; i < BoardSpec.hexagon.trackLength; i++) {
          expect(_inside(tri, g.ringCell(i).centre), isFalse,
              reason: 'arm $arm home base swallows track square $i');
        }
      }
    });

    test('every chip in a home base stands inside it', () {
      for (var arm = 0; arm < 6; arm++) {
        final tri = g.yardShape(arm);
        for (final slot in g.yardSlots(arm)) {
          expect(_inside(tri, slot), isTrue,
              reason: 'arm $arm has a resting place outside its own house');
        }
      }
    });

    test('the plate has twelve sides', () {
      expect(g.plateOutline(), hasLength(12));
    });

    test('a house is an equilateral triangle', () {
      for (var arm = 0; arm < 6; arm++) {
        final sides = _sides(g.yardShape(arm), g);
        final longest = sides.reduce((a, b) => a > b ? a : b);
        final shortest = sides.reduce((a, b) => a < b ? a : b);
        expect(longest - shortest, lessThan(0.1),
            reason: 'arm $arm is not equilateral: $sides');
      }
    });

    test('the plate is short across a path and long across a house', () {
      final v = g.plateOutline();
      // Even edges face an arm, odd edges face a house — see plateOutline.
      final path = <double>[], house = <double>[];
      for (var i = 0; i < 12; i++) {
        final len = (v[(i + 1) % 12] - v[i]).length / g.cellSize * 30;
        (i.isEven ? path : house).add(len);
      }
      // A path side is exactly the three squares behind it, no more.
      for (final p in path) {
        expect(p, closeTo(90, 0.01), reason: 'a path side is not three wide');
      }
      // And a house side is half as wide again, which is what lets the house
      // be a proper triangle rather than a spike.
      for (final h in house) {
        expect(h, closeTo(181.03, 0.05));
      }
      expect(house.first / path.first, greaterThan(1.9));
    });

    test('everything stays inside the board', () {
      for (var i = 0; i < BoardSpec.hexagon.trackLength; i++) {
        final p = g.ringCell(i).centre;
        expect(p.x, inInclusiveRange(0, 1));
        expect(p.y, inInclusiveRange(0, 1));
      }
      for (var arm = 0; arm < 6; arm++) {
        for (final s in g.yardSlots(arm)) {
          expect(s.x, inInclusiveRange(0, 1));
          expect(s.y, inInclusiveRange(0, 1));
        }
      }
    });
  });
}

/// Whether a point lies inside a triangle, by the sign of the three edges.
bool _inside(Tri t, Pt p) {
  double side(Pt a, Pt b) =>
      (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x);
  final d1 = side(t.a, t.b), d2 = side(t.b, t.c), d3 = side(t.c, t.a);
  final anyNeg = d1 < 0 || d2 < 0 || d3 < 0;
  final anyPos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(anyNeg && anyPos);
}

/// The length of a triangle's three sides, in board units of the given board.
List<double> _sides(Tri t, BoardGeometry g) => [
      (t.b - t.a).length / g.cellSize * 30,
      (t.c - t.b).length / g.cellSize * 30,
      (t.a - t.c).length / g.cellSize * 30,
    ];
