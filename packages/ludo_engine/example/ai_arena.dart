// Measures the computer players against each other.
//
//   dart run example/ai_arena.dart
//   dart run example/ai_arena.dart --games=400 --depth=3

import 'package:ludo_engine/ludo_engine.dart';

void main(List<String> args) {
  var games = 120;
  var depth = 3;
  for (final a in args) {
    if (a.startsWith('--games=')) games = int.parse(a.substring(8));
    if (a.startsWith('--depth=')) depth = int.parse(a.substring(8));
  }

  const arena = AiArena();
  final started = DateTime.now();
  print('$games games per pairing, hard searching $depth plies.\n');
  for (final pair in [
    (AiLevel.hard, AiLevel.easy),
    (AiLevel.hard, AiLevel.normal),
    (AiLevel.normal, AiLevel.easy),
  ]) {
    final r = arena.head2head(pair.$1, pair.$2, games: games, hardDepth: depth);
    print('  $r');
  }
  print('\nTook ${DateTime.now().difference(started).inSeconds}s.');
}
