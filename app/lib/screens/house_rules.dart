import 'package:flutter/material.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../theme/seat_colors.dart';

/// The house rules a table can be set up with, and the board that shows them.
///
/// Whoever sets the table up picks them — the player starting a pass & play
/// game, or the host opening a room for friends — and from then on they are
/// the table's rules: every seat can read them on the rule board, and online
/// the server enforces exactly what the host chose.

/// Every house rule this table plays, in plain words, for the rule board.
List<String> ruleLines(RuleConfig r) => [
  '${r.players} players, ${r.tokensPerPlayer} '
      '${r.tokensPerPlayer == 1 ? 'chip' : 'chips'} each.',
  if (r.isTeamGame)
    'Teams: ${[for (final t in r.teams!) t.map((s) => 'seat ${s + 1}').join(' & ')].join(' against ')}. '
        'A side wins when all its chips are home.',
  r.entryRoll == 0
      ? 'Any number brings a chip out of the base.'
      : 'Only a ${r.entryRoll} brings a chip out of the base.',
  if (!r.extraRollOnSix)
    'A six does not give another roll.'
  else if (r.sixRun == SixRun.capped)
    'A six rolls again. After two sixes in a row, the next roll cannot be '
        'a six.'
  else
    'A six rolls again, as many times as sixes keep coming.',
  r.captureGrantsExtraRoll
      ? 'Knocking a chip back to its base rolls again.'
      : 'Knocking a chip back does not give another roll.',
  r.finishGrantsExtraRoll
      ? 'Bringing a chip home rolls again.'
      : 'Bringing a chip home does not give another roll.',
  switch (r.safeSquares) {
    SafeSquares.startsAndStars =>
      'Chips on start squares and stars cannot be knocked off.',
    SafeSquares.stars => 'Only stars are safe; start squares are not.',
    SafeSquares.none => 'No square is safe.',
  },
  r.exactHomeEntry
      ? 'A chip needs the exact number to reach home.'
      : 'A chip can reach home with any number big enough.',
  if (r.mustCaptureToWin)
    'A player has to knock off at least one chip before any of theirs can '
        'go home.',
  if (r.pairMove)
    'A chip that stops beside another of its side on an ordinary square '
        'pairs up with it; on a safe square, tap 🔗 to pair. A pair moves '
        'together on an even roll, at half the number, and splits by itself '
        'when it reaches a safe square.',
  if (r.turnTimerDots > 0)
    'Each turn has ${r.turnTimerDots * r.secondsPerDot} seconds; when time '
        'runs out the turn is played for you. Online, after 5 missed turns in '
        'a row the host decides whether that player stays; a host who misses '
        '5 leaves the table.'
  else
    'No turn timer.',
];

/// Opens the rule board: what this table is playing by.
Future<void> showRuleBoard(BuildContext context, RuleConfig rules) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: ListView(
          key: const ValueKey('rule-board'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          children: [
            Text(
              rules.name == 'Classic' ? 'Rules' : 'Rules · ${rules.name}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            for (final line in ruleLines(rules))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 6, right: 10),
                      child: Icon(Icons.circle, size: 6),
                    ),
                    Expanded(child: Text(line)),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// How many house rules differ from the classic game.
int changesFromClassic(RuleConfig r, {bool online = false}) {
  const c = RuleConfig();
  return [
    r.entryRoll != c.entryRoll,
    r.extraRollOnSix != c.extraRollOnSix,
    r.extraRollOnSix && r.sixRun != c.sixRun,
    r.captureGrantsExtraRoll != c.captureGrantsExtraRoll,
    r.finishGrantsExtraRoll != c.finishGrantsExtraRoll,
    r.safeSquares != c.safeSquares,
    r.exactHomeEntry != c.exactHomeEntry,
    r.mustCaptureToWin != c.mustCaptureToWin,
    r.pairMove != c.pairMove,
    if (online) r.turnTimerDots * r.secondsPerDot != 30,
  ].where((changed) => changed).length;
}

/// The house rules, folded away until someone wants to change them.
///
/// Only the rule fields are edited here; seats, chips and teams stay with the
/// screen that owns them, and come back in through [rules].
class RulesEditor extends StatelessWidget {
  const RulesEditor({
    super.key,
    required this.rules,
    required this.onChanged,
    this.online = false,
  });

  final RuleConfig rules;
  final ValueChanged<RuleConfig> onChanged;

  /// Online tables also have a turn clock to set.
  final bool online;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final changes = changesFromClassic(rules, online: online);
    final r = rules;

    Widget toggle(
      String key,
      String title,
      String subtitle,
      bool value,
      RuleConfig Function(bool) set,
    ) => SwitchListTile(
      key: ValueKey('rule-$key'),
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: value,
      onChanged: (v) => onChanged(set(v)),
      title: Text(title),
      subtitle: Text(subtitle),
    );

    Widget choice<T>(
      String key,
      String title,
      Map<T, String> options,
      T value,
      RuleConfig Function(T) set,
    ) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              key: ValueKey('rule-$key'),
              segments: [
                for (final e in options.entries)
                  ButtonSegment(value: e.key, label: Text(e.value)),
              ],
              selected: {value},
              showSelectedIcon: false,
              onSelectionChanged: (s) => onChanged(set(s.first)),
            ),
          ),
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      color: palette.panel,
      child: ExpansionTile(
        key: const ValueKey('custom-rules'),
        shape: const Border(),
        title: const Text(
          'Custom rules',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          changes == 0
              ? 'Classic rules'
              : '$changes ${changes == 1 ? 'change' : 'changes'} from classic',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          choice<int>(
            'entry',
            'To bring a chip out',
            const {6: 'Roll a 6', 0: 'Any number'},
            r.entryRoll == 0 ? 0 : 6,
            (v) => r.copyWith(entryRoll: v),
          ),
          toggle(
            'six',
            'A six rolls again',
            'Throw again after rolling a six',
            r.extraRollOnSix,
            (v) => r.copyWith(extraRollOnSix: v),
          ),
          if (r.extraRollOnSix)
            choice<SixRun>(
              'sixrun',
              'Sixes in a row',
              const {
                SixRun.capped: 'Two at most',
                SixRun.unlimited: 'No limit',
              },
              r.sixRun,
              (v) => r.copyWith(sixRun: v),
            ),
          toggle(
            'capture',
            'Knocking a chip off rolls again',
            'A capture earns another throw',
            r.captureGrantsExtraRoll,
            (v) => r.copyWith(captureGrantsExtraRoll: v),
          ),
          toggle(
            'finish',
            'Reaching home rolls again',
            'A chip arriving home earns another throw',
            r.finishGrantsExtraRoll,
            (v) => r.copyWith(finishGrantsExtraRoll: v),
          ),
          choice<SafeSquares>(
            'safe',
            'Safe squares',
            const {
              SafeSquares.startsAndStars: 'Starts & stars',
              SafeSquares.stars: 'Stars',
              SafeSquares.none: 'None',
            },
            r.safeSquares,
            (v) => r.copyWith(safeSquares: v),
          ),
          toggle(
            'exact',
            'Exact roll to reach home',
            'Overshooting home is not allowed',
            r.exactHomeEntry,
            (v) => r.copyWith(exactHomeEntry: v),
          ),
          toggle(
            'mustcapture',
            'Capture before going home',
            'Knock off at least one chip before any of yours can finish',
            r.mustCaptureToWin,
            (v) => r.copyWith(mustCaptureToWin: v),
          ),
          toggle(
            'pair',
            'Pair move',
            'Two chips on a square travel as one on an even roll, at half '
                'the pips',
            r.pairMove,
            (v) => r.copyWith(pairMove: v),
          ),
          if (online)
            choice<int>(
              'timer',
              'Time per turn',
              const {0: 'Off', 30: '30 s', 60: '60 s'},
              r.turnTimerDots == 0 ? 0 : r.turnTimerDots * r.secondsPerDot,
              (v) => v == 0
                  ? r.copyWith(turnTimerDots: 0)
                  : r.copyWith(turnTimerDots: 6, secondsPerDot: v ~/ 6),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: changes == 0
                  ? null
                  : () => onChanged(
                      const RuleConfig().copyWith(
                        name: r.name,
                        players: r.players,
                        tokensPerPlayer: r.tokensPerPlayer,
                        teams: r.teams,
                        turnTimerDots: online ? 6 : r.turnTimerDots,
                        secondsPerDot: online ? 5 : r.secondsPerDot,
                      ),
                    ),
              child: const Text('Back to classic'),
            ),
          ),
        ],
      ),
    );
  }
}
