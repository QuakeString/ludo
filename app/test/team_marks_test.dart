import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

/// In a team game the board has to say who is partnered with whom.
///
/// Four colours round a board look exactly the same whether they are four
/// players or two pairs, and which they were had to be remembered from the
/// setup screen. Each house now carries its side's letter.
///
/// Checked in pixels, because the first attempt drew the letters perfectly and
/// showed none of them: they went down with the board's furniture, and the
/// breathing house border is painted over that — so the mark vanished from
/// whichever house was on turn, which is precisely the house being looked at.
void main() {
  test('nothing is marked when there are no sides to tell apart', () {
    expect(const RuleConfig(players: 4).isTeamGame, isFalse);
  });

  for (final (name, rules) in [
    (
      'four seats, two pairs',
      RuleConfig(players: 4, teams: teamShapesFor(4).first.groups),
    ),
    (
      'six seats, two sides of three',
      RuleConfig(players: 6, teams: teamShapesFor(6).first.groups),
    ),
    (
      'six seats, three pairs',
      RuleConfig(players: 6, teams: teamShapesFor(6).last.groups),
    ),
  ]) {
    testWidgets('every house is marked — $name', (tester) async {
      tester.view.physicalSize = const Size(460, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(home: GameScreen(rules: rules, seed: 11)),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // The finished picture, as actually composited — the house's breathing
      // border included, since that is what hid the marks the first time.
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      final image = (await tester.runAsync(() => boundary.toImage()))!;
      final pixels = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!
          .buffer
          .asUint8List();

      final board = tester.getRect(
        find.byWidgetPredicate(
          (w) => w is CustomPaint && w.painter is BoardPainter,
        ).first,
      );
      final side = board.shortestSide;
      final origin = board.topLeft +
          Offset((board.width - side) / 2, (board.height - side) / 2);

      final state = GameState.newGame(rules);
      final geometry = BoardGeometry.forSpec(state.board);
      final cell = geometry.cellSize;

      double? lumaAt(double bx, double by) {
        final x = (origin.dx + bx * side).round();
        final y = (origin.dy + by * side).round();
        if (x < 0 || y < 0 || x >= image.width || y >= image.height) return null;
        final i = (y * image.width + x) * 4;
        return 0.2126 * pixels[i] +
            0.7152 * pixels[i + 1] +
            0.0722 * pixels[i + 2];
      }

      for (var seat = 0; seat < rules.players; seat++) {
        final arm = state.armOf(seat);

        // The house's coloured band, and only that: inside the house, outside
        // the pale middle the chips stand on. Sweeping the middle as well
        // would let a chip's own shadow pass this test.
        late final bool Function(double, double) onBand;
        late final Rect area;
        if (geometry is CrossGeometry) {
          final (tl, br) = geometry.yardSquare(arm);
          final outer = Rect.fromLTRB(tl.x, tl.y, br.x, br.y);
          final inner = outer.deflate(cell);
          area = outer;
          onBand = (x, y) =>
              outer.contains(Offset(x, y)) && !inner.contains(Offset(x, y));
        } else {
          final tri = geometry.yardShape(arm);
          final centre = Offset(
            (tri.a.x + tri.b.x + tri.c.x) / 3,
            (tri.a.y + tri.b.y + tri.c.y) / 3,
          );
          final inner = _shrunk(tri, centre);
          area = Rect.fromLTRB(
            [tri.a.x, tri.b.x, tri.c.x].reduce((a, b) => a < b ? a : b),
            [tri.a.y, tri.b.y, tri.c.y].reduce((a, b) => a < b ? a : b),
            [tri.a.x, tri.b.x, tri.c.x].reduce((a, b) => a > b ? a : b),
            [tri.a.y, tri.b.y, tri.c.y].reduce((a, b) => a > b ? a : b),
          );
          onBand = (x, y) =>
              _inside(tri, x, y) && !_inside(inner, x, y);
        }

        var darkest = double.infinity;
        var total = 0.0;
        var samples = 0;
        final step = 1 / side; // one screen pixel
        for (var x = area.left; x <= area.right; x += step) {
          for (var y = area.top; y <= area.bottom; y += step) {
            if (!onBand(x, y)) continue;
            final l = lumaAt(x, y);
            if (l == null) continue;
            if (l < darkest) darkest = l;
            total += l;
            samples++;
          }
        }

        expect(samples, greaterThan(200), reason: 'seat $seat: band not found');
        expect(
          darkest,
          lessThan(total / samples - 25),
          reason: 'seat $seat has no mark standing out from its own house band',
        );
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });
  }
}

/// The house's pale middle: its outline pulled in toward the centre by the
/// same amount the board draws it.
Tri _shrunk(Tri t, Offset centre) {
  Pt pull(Pt p) => Pt(
    centre.dx + (p.x - centre.dx) * houseInset,
    centre.dy + (p.y - centre.dy) * houseInset,
  );
  return Tri(pull(t.a), pull(t.b), pull(t.c));
}

bool _inside(Tri t, double px, double py) {
  double edge(Pt a, Pt b) =>
      (b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x);
  final d1 = edge(t.a, t.b), d2 = edge(t.b, t.c), d3 = edge(t.c, t.a);
  return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0));
}
