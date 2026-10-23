import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/move_animation.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

/// A partner's chip left alone at the turn-in square beside an opponent is
/// taken, and walks home like any captured chip rather than jumping there.
void main() {
  test('a partner left behind walks home', () {
    const rules = RuleConfig(
      players: 4,
      pairMove: true,
      teams: [
        [0, 2],
        [1, 3],
      ],
    );
    var s = GameState.newGame(rules);
    final turnIn = s.board.trackLength - 2;
    final ring = s.board.ringIndex(s.armOf(0), turnIn)!;
    int on(int player) =>
        (ring - s.board.startRing(s.armOf(player)) + s.board.trackLength) %
        s.board.trackLength;
    final tokens = [...s.tokens];
    tokens[0] = tokens[0].copyWith(progress: turnIn, pairId: 0);
    tokens[8] = tokens[8].copyWith(progress: on(2), pairId: 0);
    tokens[4] = tokens[4].copyWith(progress: on(1));
    s = s.copyWith(tokens: tokens, turn: 0, dice: 3, nextPairId: 1);

    const engine = LudoEngine();
    final move = engine
        .legalMoves(s)
        .singleWhere((m) => m.kind == MoveKind.advance);
    expect(move.isCapture, isFalse, reason: 'the mover itself takes nobody');

    final animation = MoveAnimation(
      move: move,
      before: s,
      geometry: BoardGeometry.forSpec(s.board),
    );
    expect(animation.sentHome, [8]);
    expect(animation.captureMillis, greaterThan(0));
    final start = animation.capturedAt(0, 8)!.ground;
    final middle = animation.capturedAt(0.8, 8)!.ground;
    final end = animation.capturedAt(1, 8)!.ground;
    expect(middle, isNot(start), reason: 'it is on its way');
    expect(middle, isNot(end), reason: 'and not there yet');
  });
}
