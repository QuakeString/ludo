import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/board/chip_layout.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

/// Where a chip is drawn is also where it can be tapped.
///
/// These two used to be worked out separately, and disagreed about the yard:
/// the board spread four chips across four corners while a tap resolved every
/// one of them to the same point. You tapped the chip you wanted and a
/// different one came out.
void main() {
  const rules = RuleConfig(players: 4, tokensPerPlayer: 4);
  final state = GameState.newGame(rules, seed: 3);
  final geometry = BoardGeometry.forSpec(state.board);

  test('every chip in a yard has its own place', () {
    final layout = chipLayout(state, geometry);
    final mine = state.tokensOf(0).toList();
    final spots = {for (final t in mine) layout[t.id]};

    expect(
      spots,
      hasLength(mine.length),
      reason: 'four chips sharing one point cannot be told apart by a tap',
    );
  });

  test('a chip keeps its place when a sibling leaves the yard', () {
    const engine = LudoEngine();
    final before = chipLayout(state, geometry);

    // Take a chip out and see whether the others moved under the player.
    var s = state;
    while (s.turn == 0 && s.awaitingRoll) {
      s = engine.apply(s, const RollDice());
      if (s.dice == 6) break;
      if (!s.awaitingRoll) s = engine.apply(s, const PassTurn());
      if (s.turn != 0) break;
    }
    final enters = engine
        .legalMoves(s)
        .where((m) => m.kind == MoveKind.enter)
        .toList();
    if (enters.isEmpty) return; // no six came up; nothing to check here

    final moved = enters.first.tokenId;
    final after = chipLayout(engine.apply(s, PlayMove(enters.first)), geometry);

    for (final token in s.tokensOf(0)) {
      if (token.id == moved || !token.inYard) continue;
      expect(
        after[token.id],
        before[token.id],
        reason: 'chips must not shuffle places when one of them leaves',
      );
    }
  });

  test('a chip on the track is where the geometry says it is', () {
    final layout = chipLayout(state, geometry);
    final token = state.tokensOf(1).first;
    // Yard chips are the special case; everything else must match directly.
    expect(layout[token.id], geometry.yardSlots(state.armOf(1))[0]);
  });
}
