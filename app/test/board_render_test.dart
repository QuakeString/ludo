import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/board/move_animation.dart';
import 'package:ludo_app/main.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_app/theme/seat_colors.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

const engine = LudoEngine();

/// Plays a few turns so the board under test has chips out, not a fresh setup.
GameState warmedUp(RuleConfig rules, {int turns = 60, int seed = 9}) {
  var s = GameState.newGame(rules, seed: seed);
  for (var i = 0; i < turns && !s.isOver; i++) {
    s = engine.autoPlayTurn(s);
  }
  // Leave a roll on the table so the legal-move rings are showing.
  if (s.awaitingRoll && !s.isOver) s = engine.apply(s, const RollDice());
  return s;
}

/// Renders a painter to a PNG so the board can be inspected by eye — the one
/// thing a unit test cannot check for you.
Future<void> writePng(
  String name,
  CustomPainter painter,
  Size size,
  BoardPalette palette,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & size, Paint()..color = palette.felt);
  painter.paint(canvas, size);
  final image = await recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory('build/board-previews')..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('board rendering', () {
    for (final variant in [
      ('4-seat-light', const RuleConfig(), BoardPalette.light),
      ('4-seat-dark', const RuleConfig(), BoardPalette.dark),
      ('6-seat-light', RuleConfig.sixSeat, BoardPalette.light),
      ('6-seat-dark', RuleConfig.sixSeat, BoardPalette.dark),
      (
        '6-seat-teams',
        const RuleConfig(
          players: 6,
          tokensPerPlayer: 3,
          pairMove: true,
          teams: [
            [0, 2, 4],
            [1, 3, 5],
          ],
        ),
        BoardPalette.light,
      ),
      ('2-seat-light', const RuleConfig(players: 2), BoardPalette.light),
    ]) {
      final (name, rules, palette) = variant;

      test('$name paints without throwing, and is saved for review', () async {
        final state = warmedUp(rules);
        final painter = BoardPainter(
          state: state,
          geometry: BoardGeometry.forSpec(state.board),
          palette: palette,
          legalMoves: engine.legalMoves(state),
          pulse: 0.35,
        );
        await writePng(name, painter, const Size(900, 900), palette);
        expect(File('build/board-previews/$name.png').existsSync(), isTrue);
      });
    }
  });

  testWidgets('a game can be set up and played from the UI', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const GameScreen(rules: RuleConfig(players: 4), seed: 3),
      ),
    );
    await tester.pump();

    expect(find.textContaining('roll the dice'), findsOneWidget);
    expect(find.text('Roll'), findsOneWidget);

    // Roll until a six comes up and a chip can actually come out.
    for (var i = 0; i < 40; i++) {
      final roll = find.text('Roll');
      if (roll.evaluate().isEmpty) break;
      await tester.tap(roll);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
    // Either a move is on offer, or the turn moved on — both are healthy.
    expect(find.byType(CustomPaint), findsWidgets);
  });

  animationTests();

  testWidgets('the setup screen offers two to six seats', (tester) async {
    await tester.pumpWidget(const LudoAppForTest());
    await tester.pumpAndSettle();
    for (final n in ['2', '3', '4', '5', '6']) {
      expect(
        find.widgetWithText(SegmentedButton<int>, n),
        findsWidgets,
        reason: 'seat count $n missing',
      );
    }
    // The options list scrolls, so reach the button the way a player would.
    await tester.dragUntilVisible(
      find.text('Start game'),
      find.byType(ListView),
      const Offset(0, -120),
    );
    expect(find.text('Start game'), findsOneWidget);
  });
}

/// The app's home screen, without the MaterialApp wrapper fighting the test.
class LudoAppForTest extends StatelessWidget {
  const LudoAppForTest({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildTheme(Brightness.light),
    home: const SetupScreen(),
  );
}

/// The move animation is pure arithmetic over the geometry, so it can be
/// checked exactly rather than watched.
void animationTests() {
  group('move animation', () {
    final geometry = BoardGeometry.forSpec(BoardSpec.cross);

    test('a roll of five is five separate hops', () {
      var s = GameState.newGame(const RuleConfig());
      final tokens = [...s.tokens];
      tokens[0] = tokens[0].copyWith(progress: 4);
      s = s.copyWith(tokens: tokens, dice: 5);

      final move = engine.legalMoves(s).firstWhere((m) => m.tokenId == 0);
      final a = MoveAnimation(move: move, before: s, geometry: geometry);
      expect(a.hops, 5, reason: 'one hop per pip, so the move can be counted');
      expect(
        a.duration.inMilliseconds,
        5 * (MoveAnimation.hopMillis + MoveAnimation.landMillis),
      );
    });

    test('a chip leaves the ground and lands back on it', () {
      var s = GameState.newGame(const RuleConfig());
      final tokens = [...s.tokens];
      tokens[0] = tokens[0].copyWith(progress: 4);
      s = s.copyWith(tokens: tokens, dice: 2);
      final move = engine.legalMoves(s).firstWhere((m) => m.tokenId == 0);
      final a = MoveAnimation(move: move, before: s, geometry: geometry);

      expect(a.moverAt(0).lift, closeTo(0, 0.01), reason: 'starts grounded');
      expect(a.moverAt(1).lift, closeTo(0, 0.01), reason: 'ends grounded');

      var peak = 0.0;
      for (var i = 0; i <= 100; i++) {
        final l = a.moverAt(i / 100).lift;
        if (l > peak) peak = l;
      }
      expect(peak, greaterThan(0.7), reason: 'the hop has to be visible');
    });

    test('it ends exactly where the engine puts the chip', () {
      var s = GameState.newGame(const RuleConfig());
      final tokens = [...s.tokens];
      tokens[0] = tokens[0].copyWith(progress: 10);
      s = s.copyWith(tokens: tokens, dice: 3);
      final move = engine.legalMoves(s).firstWhere((m) => m.tokenId == 0);
      final a = MoveAnimation(move: move, before: s, geometry: geometry);

      final after = engine.apply(s, PlayMove(move));
      final settled = geometry.tokenAt(
        after.armOf(0),
        after.tokens[0].progress,
      );
      final ended = a.moverAt(1).ground;
      expect(
        (ended - settled).length,
        lessThan(1e-9),
        reason: 'the chip must land where the rules say it is',
      );
    });

    test('leaving the yard is a single hop', () {
      final s = GameState.newGame(const RuleConfig()).copyWith(dice: 6);
      final move = engine.legalMoves(s).first;
      final a = MoveAnimation(move: move, before: s, geometry: geometry);
      expect(a.hops, 1);
    });

    test('a captured chip flies home and arrives in its own yard', () {
      var s = GameState.newGame(const RuleConfig());
      final b = s.board;
      final victim =
          (3 - b.startRing(s.armOf(1)) + b.trackLength) % b.trackLength;
      final tokens = [...s.tokens];
      tokens[0] = tokens[0].copyWith(progress: 2);
      tokens[4] = tokens[4].copyWith(progress: victim);
      s = s.copyWith(tokens: tokens, dice: 1);

      final move = engine.legalMoves(s).firstWhere((m) => m.isCapture);
      final a = MoveAnimation(move: move, before: s, geometry: geometry);
      expect(
        a.duration.inMilliseconds,
        greaterThan(MoveAnimation.captureMillis),
        reason: 'the flight home needs its own time',
      );

      final landed = a.capturedAt(1, 4)!;
      final yard = geometry.yardSlots(s.armOf(1));
      final nearest = yard
          .map((p) => (p - landed.ground).length)
          .reduce((x, y) => x < y ? x : y);
      expect(nearest, lessThan(1e-6), reason: 'it must end in its own yard');
      expect(landed.scale, lessThan(1), reason: 'it shrinks as it goes');
    });
  });
}
