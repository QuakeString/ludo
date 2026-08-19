import 'package:ludo_engine/ludo_engine.dart';
void main() {
  const engine = LudoEngine();
  // Face counts over a long run from one seed.
  final counts = List.filled(7, 0);
  var s = GameState.newGame(const RuleConfig(), seed: 12345);
  for (var i = 0; i < 60000; i++) {
    s = engine.apply(s, const RollDice());
    counts[s.dice ?? 0]++;
    s = s.copyWith(dice: null); // roll again without playing
  }
  print('faces 1..6: ${counts.sublist(1)}');
  // Low-bit behaviour: is the parity of consecutive rolls independent?
  var same = 0;
  var prev = 0;
  s = GameState.newGame(const RuleConfig(), seed: 999);
  for (var i = 0; i < 60000; i++) {
    s = engine.apply(s, const RollDice());
    final v = s.dice!;
    if (i > 0 && v.isEven == prev.isEven) same++;
    prev = v;
    s = s.copyWith(dice: null);
  }
  print('consecutive same parity: ${(same / 60000 * 100).toStringAsFixed(2)}% (50% is independent)');
}
