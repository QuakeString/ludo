import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/board/chip_layout.dart';
import 'package:ludo_app/board/die.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

/// Tapping a chip moves *that* chip.
///
/// It did not. Hit-testing resolved every chip in a yard to the same point, so
/// with four chips eligible on a six, tapping any of them moved whichever the
/// engine listed first — you tapped top-left and bottom-right came out.
void main() {
  /// The board's square, in screen coordinates.
  (Offset, double) boardRect(WidgetTester tester) {
    final finder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is BoardPainter,
    );
    final rect = tester.getRect(finder.first);
    final side = rect.width < rect.height ? rect.width : rect.height;
    return (
      Offset(
        rect.left + (rect.width - side) / 2,
        rect.top + (rect.height - side) / 2,
      ),
      side,
    );
  }

  GameState currentState(WidgetTester tester) {
    final finder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is BoardPainter,
    );
    return (tester.widget<CustomPaint>(finder.first).painter as BoardPainter)
        .state;
  }

  Future<void> settle(WidgetTester tester, [int frames = 30]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the board does not resize when the dice come down', (
    tester,
  ) async {
    // Everything between the two seat rows is the board, so anything above or
    // below it that changes height resizes the board. Rolling swaps a line of
    // text for a Pass button, which is taller — and the board jumped.
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(
          rules: RuleConfig(players: 2, tokensPerPlayer: 4),
          seed: 11,
        ),
      ),
    );
    await tester.pump();

    final (_, before) = boardRect(tester);
    for (var i = 0; i < 12; i++) {
      final die = find.byKey(rollDieKey);
      if (die.evaluate().isEmpty) break;
      await tester.tap(die.first);
      await tester.pump(const Duration(milliseconds: 30));
      final (_, during) = boardRect(tester);
      expect(during, before, reason: 'the board changed size mid-roll');
      await settle(tester, 12);
      final (_, after) = boardRect(tester);
      expect(after, before, reason: 'the board changed size after the roll');
    }
  });

  testWidgets('the chip you tap is the chip that moves', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(
          rules: RuleConfig(players: 2, tokensPerPlayer: 4),
          seed: 5,
        ),
      ),
    );
    await tester.pump();

    // Roll until a six gives every chip in the yard a way out.
    var rolled = false;
    for (var i = 0; i < 60 && !rolled; i++) {
      final die = find.byKey(rollDieKey);
      if (die.evaluate().isEmpty) break;
      await tester.tap(die.first);
      await tester.pump(const Duration(milliseconds: 30));
      rolled = currentState(tester).dice == 6;
      if (!rolled) await settle(tester, 12);
    }
    expect(rolled, isTrue, reason: 'sixty rolls without a six is not a die');

    final state = currentState(tester);
    const engine = LudoEngine();
    final moves = engine.legalMoves(state);
    expect(
      moves.length,
      greaterThan(1),
      reason: 'a six with a full yard should offer several chips',
    );

    // Pick the chip drawn furthest from the others, so a sloppy hit test
    // cannot land on it by accident.
    final geometry = BoardGeometry.forSpec(state.board);
    final layout = chipLayout(state, geometry);
    final wanted = moves.last;
    final at = layout[wanted.tokenId]!;

    final (origin, side) = boardRect(tester);
    await tester.tapAt(origin + Offset(at.x * side, at.y * side));
    await settle(tester);

    final after = currentState(tester);
    expect(
      after.tokens[wanted.tokenId].inYard,
      isFalse,
      reason: 'the tapped chip should be the one that left',
    );

    // And nobody else went with it.
    for (final move in moves) {
      if (move.tokenId == wanted.tokenId) continue;
      expect(
        after.tokens[move.tokenId].inYard,
        isTrue,
        reason: 'only the tapped chip should have moved',
      );
    }
  });
}
