import 'package:flutter/material.dart';
import 'package:ludo_engine/ludo_engine.dart';

import '../board/confetti.dart';
import '../theme/seat_colors.dart';
import 'match_stats.dart';

/// How a seat finished: where it placed, and what it did on the way.
class Placing {
  const Placing({
    required this.seat,
    required this.place,
    required this.home,
    required this.captures,
  });

  final int seat;

  /// 1 for the winner. Seats that never got everybody home share the places
  /// after those that did.
  final int place;
  final int home;
  final int captures;
}

/// The table, in the order it finished.
///
/// [GameState.finishOrder] only holds the seats that actually got every chip
/// home, which in most games is one — somebody wins and the rest stop. The
/// others still played, so they are ranked behind by what they managed:
/// chips home first, then chips knocked off.
List<Placing> placings(GameState state) {
  final seats = [for (var s = 0; s < state.rules.players; s++) s];
  final done = state.finishOrder;

  int homeOf(int seat) => state
      .tokensOf(seat)
      .where((t) => state.board.isFinished(t.progress))
      .length;

  final rest =
      [
        for (final s in seats)
          if (!done.contains(s)) s,
      ]..sort((a, b) {
        final byHome = homeOf(b).compareTo(homeOf(a));
        if (byHome != 0) return byHome;
        return state.captures[b].compareTo(state.captures[a]);
      });

  final order = [...done, ...rest];
  return [
    for (var i = 0; i < order.length; i++)
      Placing(
        seat: order[i],
        place: i + 1,
        home: homeOf(order[i]),
        captures: state.captures[order[i]],
      ),
  ];
}

/// What happens after the last chip goes home.
///
/// The game used to simply stop: the board sat there with "Game over" in the
/// corner, no word on who came second, and no way out but the system's back
/// button.
class GameOverSheet extends StatelessWidget {
  const GameOverSheet({
    super.key,
    required this.state,
    required this.aiSeats,
    required this.onPlayAgain,
    required this.onLeave,
    this.elapsed = Duration.zero,
    this.nameOf,
  });

  final GameState state;
  final Map<int, AiLevel> aiSeats;

  /// Null online, where a rematch is the room's business rather than this
  /// device's.
  final VoidCallback? onPlayAgain;
  final VoidCallback onLeave;

  /// How long the game took. Shown on the stats page rather than here: it is
  /// the one number on it that a player might actually want, but it is still
  /// not what anybody is looking for the moment they win.
  final Duration elapsed;
  final String Function(int seat)? nameOf;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final table = placings(state);
    final champion = table.first;
    final arms = state.board.arms;
    final colour = colourOfArm(state.armOf(champion.seat), arms);
    final name =
        nameOf?.call(champion.seat) ??
            nameOfArm(state.armOf(champion.seat), arms);

    return Stack(
      children: [
        // Everything behind goes quiet, so the board is still visible but is
        // plainly no longer the thing being looked at.
        Positioned.fill(
          child: ColoredBox(color: palette.felt.withValues(alpha: 0.86)),
        ),
        const Positioned.fill(child: Confetti()),
        Center(
          child: SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.all(20),
              constraints: const BoxConstraints(maxWidth: 420),
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
              decoration: BoxDecoration(
                color: palette.panel,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colour, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emoji_events, size: 46, color: colour),
                  const SizedBox(height: 8),
                  Text(
                    state.rules.isTeamGame
                        ? '$name\'s team wins'
                        : '$name wins',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: colour,
                    ),
                  ),
                  const SizedBox(height: 18),
                  for (final p in table) _Row(p: p, state: state, ai: aiSeats),
                  const SizedBox(height: 8),
                  // Behind a button on purpose. The counts are a development
                  // instrument — the answer to "are these dice fair", which
                  // has been asked twice — and putting a table of throw
                  // frequencies in front of somebody who just won a game of
                  // Ludo would be answering a question nobody asked.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => MatchStatsSheet(
                          state: state,
                          aiSeats: aiSeats,
                          elapsed: elapsed,
                          nameOf: nameOf,
                        ),
                      ),
                      icon: const Icon(Icons.query_stats, size: 18),
                      style: TextButton.styleFrom(foregroundColor: colour),
                      label: const Text('Stats'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (onPlayAgain != null) ...[
                        Expanded(
                          child: FilledButton(
                            onPressed: onPlayAgain,
                            style: FilledButton.styleFrom(
                              backgroundColor: colour,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Play again'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onLeave,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Leave'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.p, required this.state, required this.ai});

  final Placing p;
  final GameState state;
  final Map<int, AiLevel> ai;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final arm = state.armOf(p.seat);
    final colour = colourOfArm(arm, state.board.arms);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            // Wide enough for "1st" not to wrap onto two lines at any text
            // scale the platform is likely to hand us.
            width: 38,
            child: Text(
              _ordinal(p.place),
              maxLines: 1,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: p.place == 1 ? colour : palette.faint,
              ),
            ),
          ),
          CircleAvatar(
            radius: 12,
            backgroundColor: colour,
            child: Icon(
              ai.containsKey(p.seat) ? Icons.smart_toy : Icons.person,
              size: 13,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              nameOfArm(arm, state.board.arms),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          // The score, and in Ludo the score is these two numbers: how many
          // you got home and how many you knocked off on the way.
          _Tally(
            icon: Icons.home_rounded,
            value: '${p.home}/${state.rules.tokensPerPlayer}',
            colour: palette.faint,
          ),
          const SizedBox(width: 12),
          _Tally(
            icon: Icons.sports_martial_arts,
            value: '${p.captures}',
            colour: palette.faint,
          ),
        ],
      ),
    );
  }
}

class _Tally extends StatelessWidget {
  const _Tally({required this.icon, required this.value, required this.colour});

  final IconData icon;
  final String value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: colour),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            color: colour,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

String _ordinal(int n) => switch (n) {
  1 => '1st',
  2 => '2nd',
  3 => '3rd',
  _ => '${n}th',
};
