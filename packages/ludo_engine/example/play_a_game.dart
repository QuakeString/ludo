// Plays complete games with no UI at all, to show the engine works end to end.
//
//   dart run example/play_a_game.dart
//   dart run example/play_a_game.dart --rules=sixSeat --seed=42 --verbose

import 'package:ludo_engine/ludo_engine.dart';

const engine = LudoEngine();

const _presets = <String, RuleConfig>{
  'classic': RuleConfig.classic,
  'quick': RuleConfig.quick,
  'aggressive': RuleConfig.aggressive,
  'sixSeat': RuleConfig.sixSeat,
  'teams': RuleConfig(
    name: 'Teams 3v3',
    players: 6,
    tokensPerPlayer: 3,
    pairMove: true,
    turnTimerDots: 6,
    teams: [
      [0, 2, 4],
      [1, 3, 5]
    ],
  ),
};

void main(List<String> args) {
  var name = 'classic';
  var seed = 1;
  var verbose = false;
  for (final a in args) {
    if (a.startsWith('--rules=')) name = a.substring(8);
    if (a.startsWith('--seed=')) seed = int.parse(a.substring(7));
    if (a == '--verbose' || a == '-v') verbose = true;
  }

  final rules = _presets[name];
  if (rules == null) {
    print('Unknown rules "$name". Try one of: ${_presets.keys.join(', ')}');
    return;
  }

  print('${rules.name} — ${rules.players} seats, '
      '${rules.tokensPerPlayer} chips each, '
      '${rules.board.arms}-arm board (${rules.board.trackLength} squares)');
  if (rules.isTeamGame) print('Teams: ${rules.teams}');
  if (rules.pairMove) print('Pair move is on.');
  print('Rule code: ${rules.toRuleCode()}');
  print('');

  var s = GameState.newGame(rules, seed: seed);
  var turns = 0;
  var captures = 0;

  while (!s.isOver && turns < 50000) {
    final before = s;
    s = engine.autoPlayTurn(s);
    turns++;

    final took = s.captures.reduce((a, b) => a + b) -
        before.captures.reduce((a, b) => a + b);
    captures += took;

    if (verbose && took > 0) {
      print('turn $turns: seat ${before.turn} captured $took');
    }
  }

  print('Finished in $turns turns with $captures captures.');
  if (rules.isTeamGame) {
    print(
        'Winning team: ${s.winningTeam} — seats ${rules.teams![s.winningTeam!]}');
  } else {
    print('Winner: seat ${s.winner}');
  }
  print('Finish order: ${s.finishOrder}');
  print('');

  for (var p = 0; p < rules.players; p++) {
    final home =
        s.tokensOf(p).where((t) => s.board.isFinished(t.progress)).length;
    print('  seat $p (arm ${s.armOf(p)}): '
        '$home/${rules.tokensPerPlayer} home, ${s.captures[p]} captures');
  }
}
