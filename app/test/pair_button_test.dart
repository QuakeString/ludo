import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/board/chip_layout.dart';
import 'package:ludo_app/saved_game.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// With pair move on, nothing sits on the board waiting to be hit. Tapping a
/// chip that could link opens a choice under it: move one, or move the pair.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  GameState twoOnASafeSquare(int dice) {
    const rules = RuleConfig(players: 2, tokensPerPlayer: 2, pairMove: true);
    var s = GameState.newGame(rules, seed: 5);
    // A safe square some way round, past the start.
    final safe = [
      for (var p = 2; p < 40; p++)
        if (s.safeRingSquares.contains(s.board.ringIndex(s.armOf(0), p))) p,
    ].first;
    final tokens = [...s.tokens];
    tokens[0] = tokens[0].copyWith(progress: safe);
    tokens[1] = tokens[1].copyWith(progress: safe);
    return s.copyWith(tokens: tokens, turn: 0, dice: dice);
  }

  GameState shown(WidgetTester tester) {
    final finder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is BoardPainter,
    );
    return (tester.widget<CustomPaint>(finder.first).painter as BoardPainter)
        .state;
  }

  Future<void> tapChip(WidgetTester tester, GameState s, int token) async {
    final finder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is BoardPainter,
    );
    final rect = tester.getRect(finder.first);
    final side = rect.shortestSide;
    final origin = Offset(
      rect.left + (rect.width - side) / 2,
      rect.top + (rect.height - side) / 2,
    );
    final at = chipLayout(s, BoardGeometry.forSpec(s.board))[token]!;
    await tester.tapAt(origin + Offset(at.x * side, at.y * side));
    await tester.pump();
  }

  Future<void> open(WidgetTester tester, GameState s) async {
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: GameScreen.resumed(SavedGame(state: s))),
    );
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('no link button waits on the board', (tester) async {
    await open(tester, twoOnASafeSquare(4));
    expect(find.byKey(const ValueKey('pair-0-1')), findsNothing);
    expect(find.byKey(const ValueKey('pair-both')), findsNothing);

    // The pairing is still a choice, so the turn waits for a tap.
    await tester.pump(const Duration(seconds: 3));
    expect(shown(tester).dice, 4);
    await close(tester);
  });

  testWidgets('Move pair links the two and moves them together', (
    tester,
  ) async {
    final s = twoOnASafeSquare(4);
    await open(tester, s);
    await tapChip(tester, s, 0);
    expect(find.text('Move pair'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pair-both')));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final after = shown(tester);
    expect(after.tokens[0].progress, after.tokens[1].progress);
    expect(after.tokens[0].progress, isNot(s.tokens[0].progress));
    await close(tester);
  });

  testWidgets('Move 1 moves only the tapped chip', (tester) async {
    final s = twoOnASafeSquare(4);
    await open(tester, s);
    await tapChip(tester, s, 0);
    await tester.tap(find.byKey(const ValueKey('pair-one')));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final after = shown(tester);
    expect(after.tokens[0].progress, isNot(after.tokens[1].progress));
    expect(after.tokens.where((t) => t.isPaired), isEmpty);
    await close(tester);
  });

  testWidgets('a press held a moment still picks Move 1', (tester) async {
    // A finger rests on the button longer than a quick tap; the board
    // underneath must not close the choice first.
    final s = twoOnASafeSquare(4);
    await open(tester, s);
    await tapChip(tester, s, 0);
    final button = find.byKey(const ValueKey('pair-one'));
    final press = await tester.startGesture(tester.getCenter(button));
    await tester.pump(const Duration(milliseconds: 300));
    expect(button, findsOneWidget);
    await press.up();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(shown(tester).tokens[0].progress, isNot(s.tokens[0].progress));
    await close(tester);
  });

  testWidgets('a tap elsewhere closes the choice', (tester) async {
    final s = twoOnASafeSquare(4);
    await open(tester, s);
    await tapChip(tester, s, 0);
    expect(find.byKey(const ValueKey('pair-both')), findsOneWidget);
    await tester.tapAt(const Offset(210, 400));
    await tester.pump();
    // Either the tap missed every chip or it landed on one; both close it.
    expect(find.byKey(const ValueKey('pair-both')), findsNothing);
    expect(shown(tester).tokens[0].progress, s.tokens[0].progress);
    await close(tester);
  });

  testWidgets('on a roll a pair cannot use, the tapped chip just moves', (
    tester,
  ) async {
    // Two chips on a safe square and a 1: no pair can move on it, so there is
    // nothing to choose and nothing to link. The tapped chip goes on alone.
    final s = twoOnASafeSquare(1);
    await open(tester, s);
    await tapChip(tester, s, 0);
    expect(find.byKey(const ValueKey('pair-both')), findsNothing);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final after = shown(tester);
    expect(after.tokens[0].progress, s.tokens[0].progress + 1);
    expect(after.tokens[1].progress, s.tokens[1].progress);
    expect(after.tokens.where((t) => t.isPaired), isEmpty);
    await close(tester);
  });
}
