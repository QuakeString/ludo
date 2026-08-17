import 'package:flutter/material.dart';
import 'package:ludo_engine/ludo_engine.dart';

import 'screens/game_screen.dart';
import 'screens/online_screen.dart';
import 'theme/seat_colors.dart';

void main() => runApp(const LudoApp());

class LudoApp extends StatelessWidget {
  const LudoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ludo',
      debugShowCheckedModeBanner: false,
      // Light and dark are both first class, following the system until the
      // player overrides it in settings.
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const SetupScreen(),
    );
  }
}

/// Seat count, then format, then rules — in that order, because the seat count
/// decides the board shape and whether teams are possible at all.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _players = 4;
  int _tokens = 4;
  bool _teams = false;
  bool _pairMove = false;
  bool _blockades = true;

  /// How many seats the computer takes, and how hard it plays. Seat 0 is
  /// always yours; the computer fills from the last seat backwards.
  int _computerSeats = 0;
  AiLevel _level = AiLevel.normal;

  Map<int, AiLevel> get _aiSeats => {
    for (var i = 0; i < _computerSeats; i++) _players - 1 - i: _level,
  };

  bool get _teamsPossible => _players == 4 || _players == 6;

  RuleConfig get _rules {
    final teams = _teams && _teamsPossible
        ? [
            [for (var p = 0; p < _players; p += 2) p],
            [for (var p = 1; p < _players; p += 2) p],
          ]
        : null;
    return RuleConfig(
      name: _teams ? 'Teams' : 'Pass & Play',
      players: _players,
      tokensPerPlayer: _tokens,
      teams: teams,
      pairMove: _pairMove,
      blockades: _blockades,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // Top-aligned and freely scrolling: the options list grows with the
        // seat count, and on a short screen it has to be reachable.
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < 4; i++)
                      Text(
                        'LUDO'[i],
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                          color: seatColors[i],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    'Roll. Chase. Bring them home.',
                    style: TextStyle(fontSize: 13.5),
                  ),
                ),
                const SizedBox(height: 26),
                _Section(
                  title: 'How many seats',
                  child: SegmentedButton<int>(
                    segments: [
                      for (var n = 2; n <= 6; n++)
                        ButtonSegment(value: n, label: Text('$n')),
                    ],
                    selected: {_players},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => setState(() {
                      _players = s.first;
                      if (!_teamsPossible) _teams = false;
                      if (_computerSeats > _players - 1) {
                        _computerSeats = _players - 1;
                      }
                    }),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 4),
                  child: Text(
                    _players <= 4
                        ? 'The classic cross — 52 squares.'
                        : 'The hexagon — 78 squares, twelve-sided board.',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                const SizedBox(height: 18),
                _Section(
                  title: 'Chips per player',
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 3, label: Text('3')),
                      ButtonSegment(value: 4, label: Text('4')),
                    ],
                    selected: {_tokens},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _tokens = s.first),
                  ),
                ),
                const SizedBox(height: 18),
                _Section(
                  title: 'Computer players',
                  child: SegmentedButton<int>(
                    segments: [
                      for (var n = 0; n < _players; n++)
                        ButtonSegment(value: n, label: Text('$n')),
                    ],
                    selected: {_computerSeats},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _computerSeats = s.first),
                  ),
                ),
                if (_computerSeats > 0) ...[
                  const SizedBox(height: 10),
                  _Section(
                    title: 'How hard they play',
                    child: SegmentedButton<AiLevel>(
                      segments: const [
                        ButtonSegment(value: AiLevel.easy, label: Text('Easy')),
                        ButtonSegment(
                          value: AiLevel.normal,
                          label: Text('Normal'),
                        ),
                        ButtonSegment(value: AiLevel.hard, label: Text('Hard')),
                      ],
                      selected: {_level},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          setState(() => _level = s.first),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4),
                    child: Text(switch (_level) {
                      AiLevel.easy => 'Mostly random — misses captures, leaves chips in danger.',
                      AiLevel.normal => 'Takes the best move on the board, but cannot see what it exposes.',
                      AiLevel.hard => 'Searches several turns ahead, weighing the risk of every square.',
                    }, style: const TextStyle(fontSize: 12.5)),
                  ),
                ],
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _teams,
                  onChanged: _teamsPossible
                      ? (v) => setState(() => _teams = v)
                      : null,
                  title: const Text('Play as teams'),
                  subtitle: Text(
                    _teamsPossible
                        ? _players == 6
                              ? '3 v 3 — partners seated alternately'
                              : '2 v 2 — partners sit opposite'
                        : 'Needs 4 or 6 seats',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _blockades,
                  onChanged: (v) => setState(() => _blockades = v),
                  title: const Text('Blockades'),
                  subtitle: const Text(
                    'Two chips of one player on a square make a wall nobody '
                    'can pass. Turn it off and chips travel through each '
                    'other freely',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _pairMove,
                  onChanged: (v) => setState(() => _pairMove = v),
                  title: const Text('Pair move'),
                  subtitle: const Text(
                    'Two chips on a square link and travel as one on an '
                    'even roll, at half the pips',
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          GameScreen(rules: _rules, aiSeats: _aiSeats),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: seatColors[1],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Start game',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Rule code  ${_rules.toRuleCode()}',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const OnlineScreen()),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.public),
                  label: const Text('Play online'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, child: child),
    ],
  );
}
