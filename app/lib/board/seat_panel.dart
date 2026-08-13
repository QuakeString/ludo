import 'package:flutter/material.dart';

import '../theme/seat_colors.dart';
import 'die.dart';

/// One player's place at the table: who they are, how many chips they have
/// home, and their own spot for the die.
///
/// Every seat has a die place; only the seat on turn has a die in it. That is
/// the whole of "the die travels to whoever is next" — no animation needed for
/// it to read correctly, because the empty places make it obvious where it went
/// and where it came from.
class SeatPanel extends StatelessWidget {
  const SeatPanel({
    super.key,
    required this.seat,
    required this.name,
    required this.home,
    required this.total,
    required this.onTurn,
    this.isComputer = false,
    this.dice,
    this.timerDots = 0,
    this.dotsLit = 0,
    this.connected = true,
    this.onRoll,
    this.compact = false,
  });

  final int seat;
  final String name;

  /// Chips finished, out of [total].
  final int home;
  final int total;

  final bool onTurn;

  /// Marked with a robot rather than spelled out in the name, which keeps the
  /// panel narrow enough for six of them to share a phone.
  final bool isComputer;

  /// The face showing, or null when this seat has not rolled.
  final int? dice;

  final int timerDots;
  final int dotsLit;
  final bool connected;

  /// Set when this seat may roll right now — the die itself is the button,
  /// which is the shortest path between "it is my turn" and doing something.
  final VoidCallback? onRoll;

  /// Six seats have to fit two rows of three on a phone.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final colour = seatColors[seat];
    final die = DieFace(
      value: dice ?? 0,
      seat: seat,
      size: compact ? 34 : 42,
      live: onTurn,
    );

    return Opacity(
      opacity: connected ? 1 : 0.45,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 9,
          vertical: compact ? 5 : 7,
        ),
        decoration: BoxDecoration(
          color: onTurn ? colour.withValues(alpha: 0.13) : palette.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: onTurn ? colour : palette.panelEdge,
            width: onTurn ? 1.6 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Avatar(seat: seat, compact: compact, robot: isComputer),
            SizedBox(width: compact ? 6 : 8),
            // Flexible, so a long name gives way rather than overflowing when
            // three panels share a phone's width at six seats.
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: compact ? 11 : 12.5,
                      fontWeight: onTurn ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$home/$total',
                        style: TextStyle(
                          fontSize: compact ? 10 : 11,
                          color: palette.faint,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (onTurn && timerDots > 0) ...[
                        const SizedBox(width: 6),
                        for (var i = 0; i < timerDots; i++)
                          Container(
                            margin: const EdgeInsets.only(right: 2.5),
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < dotsLit
                                  ? colour
                                  : colour.withValues(alpha: 0.2),
                            ),
                          ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: compact ? 6 : 9),
            onRoll == null
                ? die
                : GestureDetector(
                    onTap: onRoll,
                    behavior: HitTestBehavior.opaque,
                    child: die,
                  ),
          ],
        ),
      ),
    );
  }
}

/// A place for a photo. Until profiles exist it is the seat's colour with an
/// initial, which is still a face rather than a blank.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.seat,
    required this.compact,
    required this.robot,
  });

  final int seat;
  final bool compact;
  final bool robot;

  @override
  Widget build(BuildContext context) {
    final r = compact ? 12.0 : 14.0;
    return CircleAvatar(
      radius: r,
      backgroundColor: seatColors[seat],
      child: Icon(
        robot ? Icons.smart_toy : Icons.person,
        size: r * 1.05,
        color: Colors.white,
      ),
    );
  }
}
