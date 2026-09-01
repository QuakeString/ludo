import 'package:flutter/material.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../theme/seat_colors.dart';
import 'game_screen.dart';

/// Which of the two on-this-device games is being set up.
///
/// The controls are the same either way — it is one board with seats round it,
/// and who is sitting in them is a setting rather than a different game. What
/// the mode changes is where the dial starts: choosing "play the computer" and
/// then being handed a table of nothing but humans is the app not having
/// listened.
enum LocalMode {
  passAndPlay('Pass & play', 'Everyone plays on this device, in turn'),
  computer('Play the computer', 'You against as many computers as you like');

  const LocalMode(this.title, this.blurb);

  final String title;
  final String blurb;
}

/// Seat count, then format, then rules — in that order, because the seat count
/// decides the board shape and whether teams are possible at all.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.mode = LocalMode.passAndPlay});

  final LocalMode mode;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _players = 4;
  int _tokens = 4;
  bool _teams = false;
  int _shape = 0;
  bool _pairMove = false;

  /// How many seats the computer takes, and how hard it plays. Seat 0 is
  /// always yours; the computer fills from the last seat backwards.
  late int _computerSeats = widget.mode == LocalMode.computer
      ? _players - 1
      : 0;
  AiLevel _level = AiLevel.normal;

  Map<int, AiLevel> get _aiSeats => {
    for (var i = 0; i < _computerSeats; i++) _players - 1 - i: _level,
  };

  List<TeamShape> get _shapes => teamShapesFor(_players);
  bool get _teamsPossible => _shapes.isNotEmpty;
  TeamShape? get _chosenShape =>
      _teams && _teamsPossible ? _shapes[_shape.clamp(0, _shapes.length - 1)] : null;

  RuleConfig get _rules {
    final shape = _chosenShape;
    return RuleConfig(
      name: shape != null ? 'Teams ${shape.label}' : widget.mode.title,
      players: _players,
      tokensPerPlayer: _tokens,
      teams: shape?.groups,
      pairMove: _pairMove,
    );
  }

  void _setPlayers(int n) => setState(() {
    _players = n;
    _shape = 0;
    if (!_teamsPossible) _teams = false;
    // Playing the computer means the rest of the table is computers unless
    // that is changed; passing and playing means it is not.
    if (widget.mode == LocalMode.computer) {
      _computerSeats = _players - 1;
    } else if (_computerSeats > _players - 1) {
      _computerSeats = _players - 1;
    }
  });

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    return Scaffold(
      backgroundColor: palette.felt,
      appBar: AppBar(
        backgroundColor: palette.felt,
        title: Text(widget.mode.title),
      ),
      body: SafeArea(
        // Top-aligned and freely scrolling: the options list grows with the
        // seat count, and on a short screen it has to be reachable.
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                Text(
                  widget.mode.blurb,
                  style: TextStyle(fontSize: 13, color: palette.faint),
                ),
                const SizedBox(height: 22),
                _Section(
                  title: 'How many seats',
                  child: SegmentedButton<int>(
                    segments: [
                      for (var n = 2; n <= 6; n++)
                        ButtonSegment(value: n, label: Text('$n')),
                    ],
                    selected: {_players},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) => _setPlayers(s.first),
                  ),
                ),
                _Note(
                  _players <= 4
                      ? 'The classic cross — 52 squares.'
                      : 'The hexagon — 78 squares, twelve-sided board.',
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
                  _Note(switch (_level) {
                    AiLevel.easy =>
                      'Mostly random — misses captures, leaves chips in danger.',
                    AiLevel.normal =>
                      'Takes the best move on the board, but cannot see what '
                          'it exposes.',
                    AiLevel.hard =>
                      'Searches several turns ahead, weighing the risk of '
                          'every square.',
                  }),
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
                        ? _chosenShape?.description ??
                              'Sides win together — everybody home, not just you'
                        : 'Needs 4 or 6 seats',
                  ),
                ),
                // Six seats divide two ways, and the two are different games:
                // two big sides, or three pairs. Only shown when there is
                // actually a choice to make.
                if (_teams && _shapes.length > 1) ...[
                  const SizedBox(height: 6),
                  _Section(
                    title: 'Sides',
                    child: SegmentedButton<int>(
                      segments: [
                        for (var i = 0; i < _shapes.length; i++)
                          ButtonSegment(value: i, label: Text(_shapes[i].label)),
                      ],
                      selected: {_shape.clamp(0, _shapes.length - 1)},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          setState(() => _shape = s.first),
                    ),
                  ),
                ],
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
                    style: TextStyle(fontSize: 11.5, color: palette.faint),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, top: 4),
    child: Text(
      text,
      style: TextStyle(fontSize: 12.5, color: BoardPalette.of(context).faint),
    ),
  );
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
