import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../theme/seat_colors.dart';

/// The numbers behind a finished game.
///
/// A development instrument, and it says so on the page. It exists because the
/// dice have twice been accused of favouritism and neither accusation could be
/// answered from inside the game — the first time the answer took an
/// instrumented build and a hundred thousand rolls, and the second turned out
/// to be a fixed seed rather than the generator at all. Both would have been
/// obvious in ten seconds against a table like this one.
///
/// Which is also why every row shows its throws as counts and not as
/// percentages: the question being asked is "did that really happen", and
/// counts answer it. A percentage of eleven throws answers nothing.
class MatchStatsSheet extends StatelessWidget {
  const MatchStatsSheet({
    super.key,
    required this.state,
    required this.aiSeats,
    required this.elapsed,
    this.nameOf,
  });

  final GameState state;
  final Map<int, AiLevel> aiSeats;

  /// Wall-clock time the game took. Zero when nobody was counting.
  final Duration elapsed;
  final String Function(int seat)? nameOf;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final stats = state.stats;
    final sides = state.rules.diceSides;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: palette.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 620),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Match stats',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  _Headline(
                    label: 'Played for',
                    value: formatSpan(elapsed),
                    palette: palette,
                  ),
                  _Headline(
                    label: 'Throws',
                    value: '${stats.totalThrows}',
                    palette: palette,
                  ),
                  _Headline(
                    label: 'Moves',
                    value: '${stats.totalMoves}',
                    palette: palette,
                  ),
                  _Headline(
                    label: 'Knockouts',
                    value: '${stats.totalLosses}',
                    palette: palette,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              // Two directions, because a six-seat game with a six-sided die
              // is wider than a phone and taller than it too.
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: _Table(
                    state: state,
                    aiSeats: aiSeats,
                    palette: palette,
                    sides: sides,
                    nameOf: nameOf,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'For development. Counts every throw made, including ones with '
                'no legal move behind them.',
                style: TextStyle(fontSize: 11.5, color: palette.faint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Minutes and seconds, or hours when a game has run that long.
///
/// Its own function because it is the one thing on this page that is easy to
/// get subtly wrong and impossible to notice: a game lasting an hour and four
/// minutes must not read as "1:04".
String formatSpan(Duration d) {
  final s = d.inSeconds;
  final mm = (s ~/ 60) % 60;
  final ss = s % 60;
  final hh = s ~/ 3600;
  String two(int n) => n.toString().padLeft(2, '0');
  return hh > 0 ? '$hh:${two(mm)}:${two(ss)}' : '$mm:${two(ss)}';
}

class _Headline extends StatelessWidget {
  const _Headline({
    required this.label,
    required this.value,
    required this.palette,
  });

  final String label;
  final String value;
  final BoardPalette palette;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: TextStyle(fontSize: 11, color: palette.faint)),
      Text(
        value,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

class _Table extends StatelessWidget {
  const _Table({
    required this.state,
    required this.aiSeats,
    required this.palette,
    required this.sides,
    required this.nameOf,
  });

  final GameState state;
  final Map<int, AiLevel> aiSeats;
  final BoardPalette palette;
  final int sides;
  final String Function(int seat)? nameOf;

  static const _seat = 132.0;
  static const _face = 40.0;
  static const _wide = 62.0;

  @override
  Widget build(BuildContext context) {
    final stats = state.stats;
    final head = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: palette.faint,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(width: _seat, child: Text('PLAYER', style: head)),
            for (var f = 1; f <= sides; f++)
              SizedBox(
                width: _face,
                child: Text('$f', style: head, textAlign: TextAlign.center),
              ),
            SizedBox(
              width: _wide,
              child: Text('ROLLS', style: head, textAlign: TextAlign.center),
            ),
            SizedBox(
              width: _wide,
              child: Text('MOVES', style: head, textAlign: TextAlign.center),
            ),
            SizedBox(
              width: _wide,
              child: Text('K/O', style: head, textAlign: TextAlign.center),
            ),
            SizedBox(
              width: _wide,
              child: Text('LOST', style: head, textAlign: TextAlign.center),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (var seat = 0; seat < state.rules.players; seat++)
          _SeatRow(
            state: state,
            seat: seat,
            palette: palette,
            sides: sides,
            robot: aiSeats.containsKey(seat),
            name: nameOf?.call(seat) ?? nameOfArm(state.armOf(seat)),
          ),
        const Divider(height: 18),
        // The column totals, which are the row the argument is usually about:
        // across the whole table every face should come up about as often as
        // every other one.
        Row(
          children: [
            SizedBox(
              width: _seat,
              child: Text('All seats', style: head),
            ),
            for (var f = 1; f <= sides; f++)
              SizedBox(
                width: _face,
                child: _Cell(
                  value: [
                    for (var p = 0; p < state.rules.players; p++)
                      stats.rollsOf(p, f),
                  ].fold(0, (a, b) => a + b),
                  bold: true,
                  palette: palette,
                ),
              ),
            SizedBox(
              width: _wide,
              child: _Cell(
                value: stats.totalThrows,
                bold: true,
                palette: palette,
              ),
            ),
            SizedBox(
              width: _wide,
              child: _Cell(
                value: stats.totalMoves,
                bold: true,
                palette: palette,
              ),
            ),
            SizedBox(
              width: _wide,
              child: _Cell(
                value: state.captures.fold(0, (a, b) => a + b),
                bold: true,
                palette: palette,
              ),
            ),
            SizedBox(
              width: _wide,
              child: _Cell(
                value: stats.totalLosses,
                bold: true,
                palette: palette,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SeatRow extends StatelessWidget {
  const _SeatRow({
    required this.state,
    required this.seat,
    required this.palette,
    required this.sides,
    required this.robot,
    required this.name,
  });

  final GameState state;
  final int seat;
  final BoardPalette palette;
  final int sides;
  final bool robot;
  final String name;

  @override
  Widget build(BuildContext context) {
    final colour = colourOfArm(state.armOf(seat));
    final stats = state.stats;
    final throws = stats.throwsBy(seat);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: _Table._seat,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 9,
                  backgroundColor: colour,
                  child: Icon(
                    robot ? Icons.smart_toy : Icons.person,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var f = 1; f <= sides; f++)
            SizedBox(
              width: _Table._face,
              child: _Cell(
                value: stats.rollsOf(seat, f),
                palette: palette,
                tint: _tint(colour, stats.rollsOf(seat, f), throws, sides),
              ),
            ),
          SizedBox(
            width: _Table._wide,
            child: _Cell(value: throws, palette: palette),
          ),
          SizedBox(
            width: _Table._wide,
            child: _Cell(value: stats.moves[seat], palette: palette),
          ),
          SizedBox(
            width: _Table._wide,
            child: _Cell(value: state.captures[seat], palette: palette),
          ),
          SizedBox(
            width: _Table._wide,
            child: _Cell(value: stats.lost[seat], palette: palette),
          ),
        ],
      ),
    );
  }
}


/// A wash behind a count that is further from fair than chance easily explains.
///
/// Measured in standard errors, not in percent, and that is the whole point of
/// it. Over forty throws a face coming up ten times instead of the expected
/// six-and-a-bit is unremarkable; over four hundred, the same *proportion* is
/// nearly impossible. Shading against a flat percentage says the two are the
/// same, so a fresh game came out covered in alarm colours and the shading
/// taught you to ignore it before it ever had something true to say.
///
/// So: nothing below one and a half standard errors, ramping to full at three.
/// That leaves a fair game mostly plain, with the occasional pale cell — which
/// is what a fair game genuinely looks like — and makes a real lean obvious.
Color? _tint(Color colour, int count, int throws, int sides) {
  if (throws < 20 || sides < 2) return null;
  final expected = throws / sides;
  // Binomial: each throw either is this face or is not.
  final sd = math.sqrt(throws * (1 / sides) * (1 - 1 / sides));
  if (sd <= 0) return null;
  final z = (count - expected).abs() / sd;
  if (z < 1.5) return null;
  return colour.withValues(alpha: (0.06 + (z - 1.5) / 1.5 * 0.20).clamp(0.0, 0.26));
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.value,
    required this.palette,
    this.bold = false,
    this.tint,
  });

  final int value;
  final BoardPalette palette;
  final bool bold;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: tint == null
          ? null
          : BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(5),
            ),
      child: Text(
        '$value',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          color: value == 0 ? palette.faint : null,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
