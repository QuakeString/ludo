import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/board_painter.dart';
import 'package:ludo_app/net/connection.dart';
import 'package:ludo_app/net/online_session.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_protocol/ludo_protocol.dart' show MatchUpdate;
import 'package:shared_preferences/shared_preferences.dart';

/// A session fed by the test instead of a socket.
class _Fed extends OnlineSession {
  _Fed(GameState start)
    : super(LudoConnection(uri: Uri.parse('ws://127.0.0.1:1/ws'))) {
    state = start;
    yourSeat = 1;
  }

  final feed = StreamController<MatchUpdate>.broadcast();

  @override
  Stream<MatchUpdate> get matches => feed.stream;
}

/// Positions that arrive while a move is still playing are taken afterwards,
/// all of them and in order. One left behind in the queue used to be taken
/// much later, sending the board back in time and throwing the die again.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('every position sent during a move is taken, in order', (
    tester,
  ) async {
    const engine = LudoEngine();
    const rules = RuleConfig(players: 2, tokensPerPlayer: 2);
    var s0 = GameState.newGame(rules, seed: 3);
    final tokens = [...s0.tokens];
    tokens[0] = tokens[0].copyWith(progress: 5);
    s0 = s0.copyWith(tokens: tokens, turn: 0, dice: null);

    Move advance(GameState s) => engine
        .legalMoves(s)
        .firstWhere((m) => m.kind == MoveKind.advance && m.tokenId == 0);
    final rolled6 = s0.copyWith(dice: 6);
    final m1 = advance(rolled6);
    final a1 = engine.apply(rolled6, PlayMove(m1));
    expect(a1.turn, 0, reason: 'a six rolls again');
    final rolled2 = a1.copyWith(dice: 2);
    final m2 = advance(rolled2);
    final a2 = engine.apply(rolled2, PlayMove(m2));
    expect(a2.turn, 1);

    final session = _Fed(s0);
    await tester.binding.setSurfaceSize(const Size(420, 860));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(rules: rules, session: session),
      ),
    );
    await tester.pump();

    MatchUpdate say(GameState s, [Move? m]) =>
        MatchUpdate(state: s, yourSeat: 1, lastMove: m);
    session.feed.add(say(rolled6));
    await tester.pump();
    session.feed.add(say(a1, m1));
    await tester.pump(const Duration(milliseconds: 50));
    // The first move is still walking when the next roll and move arrive.
    session.feed.add(say(rolled2));
    session.feed.add(say(a2, m2));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final painter =
        tester
                .widget<CustomPaint>(
                  find
                      .byWidgetPredicate(
                        (w) => w is CustomPaint && w.painter is BoardPainter,
                      )
                      .first,
                )
                .painter
            as BoardPainter;
    expect(painter.state.tokens[0].progress, a2.tokens[0].progress);
    expect(painter.state.turn, 1);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
  });
}
