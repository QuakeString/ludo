import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

/// Where every chip is actually drawn, keyed by token id.
///
/// Both the painter and the tap handler go through this. They used to work it
/// out separately, and disagreed: the painter spread a yard's chips across
/// four slots while hit-testing asked the geometry for "the" yard position,
/// which is slot 0 for all of them. Every chip in the yard therefore sat at
/// the same point as far as a tap was concerned, so tapping any of them moved
/// whichever the engine happened to list first.
Map<int, Pt> chipLayout(GameState state, BoardGeometry geometry) {
  final out = <int, Pt>{};
  final groups = <String, List<Token>>{};

  for (final token in state.tokens) {
    final arm = state.armOf(token.owner);
    final key = token.inYard
        ? 'yard-${token.owner}'
        : state.board.isFinished(token.progress)
        ? 'home-${token.owner}'
        : 'p-$arm-${token.progress}';
    groups.putIfAbsent(key, () => []).add(token);
  }

  for (final group in groups.values) {
    final first = group.first;
    final arm = state.armOf(first.owner);
    if (first.inYard) {
      final slots = geometry.yardSlots(arm);
      for (final token in group) {
        out[token.id] = slots[yardSlotOf(state, token) % slots.length];
      }
    } else {
      final at = geometry.tokenAt(arm, first.progress);
      for (final token in group) {
        out[token.id] = at;
      }
    }
  }
  return out;
}

/// Which resting place in its own yard a chip belongs to.
///
/// Fixed to the chip, not to how many of its siblings happen to be at home:
/// numbering by position in the group meant that when one chip left, the rest
/// shuffled into new places under the player's finger.
int yardSlotOf(GameState state, Token token) {
  final mine = state.tokensOf(token.owner).toList();
  final i = mine.indexWhere((t) => t.id == token.id);
  return i < 0 ? 0 : i;
}
