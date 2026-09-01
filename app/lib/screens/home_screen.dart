import 'package:flutter/material.dart';

import '../theme/seat_colors.dart';
import 'online_screen.dart';
import 'setup_screen.dart';

/// The front door: four ways to play, and nothing else.
///
/// It used to open straight onto the settings — seat counts, chip counts,
/// difficulty — which asks the wrong question first. Nobody opens a Ludo app
/// wanting to decide how many chips each player gets; they want to play, and
/// how they want to play (alone against the machine, round one phone, with
/// friends who are elsewhere) decides which settings even apply. So the mode
/// comes first and every dial moves behind it.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);

    return Scaffold(
      backgroundColor: palette.felt,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              children: [
                const _Wordmark(),
                const SizedBox(height: 8),
                Text(
                  'Roll. Chase. Bring them home.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: palette.faint),
                ),
                const SizedBox(height: 30),
                LayoutBuilder(
                  builder: (context, box) {
                    // Two across when there is room for two to be worth
                    // reading, one down when there is not. A phone held
                    // upright gets one column of wide cards rather than four
                    // squares too small to carry a sentence.
                    final columns = box.maxWidth >= 420 ? 2 : 1;
                    final cards = <Widget>[
                        _ModeCard(
                          title: 'Pass & play',
                          blurb: 'One device, round the table',
                          icon: Icons.people_alt_rounded,
                          colour: seatColors[0],
                          wide: columns == 1,
                          onTap: () => _go(
                            context,
                            const SetupScreen(mode: LocalMode.passAndPlay),
                          ),
                        ),
                        _ModeCard(
                          title: 'Play the computer',
                          blurb: 'Three levels, from careless to careful',
                          icon: Icons.smart_toy_rounded,
                          colour: seatColors[1],
                          wide: columns == 1,
                          onTap: () => _go(
                            context,
                            const SetupScreen(mode: LocalMode.computer),
                          ),
                        ),
                        _ModeCard(
                          title: 'Play with friends',
                          blurb: 'Open a table and send the code',
                          icon: Icons.group_add_rounded,
                          colour: seatColors[2],
                          wide: columns == 1,
                          onTap: () => _go(context, const OnlineScreen()),
                        ),
                        _ModeCard(
                          title: 'Online',
                          blurb: 'Matched with whoever is looking for a game',
                          icon: Icons.public_rounded,
                          colour: seatColors[3],
                          wide: columns == 1,
                          // Honest rather than hopeful. There is no
                          // matchmaking queue behind this yet — rooms exist
                          // and joining strangers does not — and a card that
                          // leads somewhere it cannot deliver is worse than
                          // one that says so.
                          soon: true,
                          onTap: () => ScaffoldMessenger.of(context)
                              .showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Not built yet — for now, open a table '
                                    'under Play with friends.',
                                  ),
                                ),
                              ),
                        ),
                    ];

                    // Squares in a grid across, but stacked down they are
                    // sized by what is in them. A fixed aspect ratio on a
                    // one-column list leaves a hand's width of empty card
                    // under two lines of text, and gets worse the moment the
                    // system font is turned up.
                    return columns == 2
                        ? GridView.count(
                            crossAxisCount: 2,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.05,
                            children: cards,
                          )
                        : Column(
                            children: [
                              for (final card in cards) ...[
                                if (card != cards.first)
                                  const SizedBox(height: 12),
                                card,
                              ],
                            ],
                          );
                  },
                ),
                const SizedBox(height: 22),
                Text(
                  'No account, ever. Pass & play and the computer work with '
                  'no connection at all.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: palette.faint),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _go(BuildContext context, Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => screen));
}

/// LUDO, a letter per seat colour.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < 4; i++)
        Text(
          'LUDO'[i],
          style: TextStyle(
            fontSize: 46,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
            color: seatColors[i],
          ),
        ),
    ],
  );
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.blurb,
    required this.icon,
    required this.colour,
    required this.onTap,
    required this.wide,
    this.soon = false,
  });

  final String title;
  final String blurb;
  final IconData icon;
  final Color colour;
  final VoidCallback onTap;

  /// Laid out as a row rather than a column, for a one-column screen.
  final bool wide;
  final bool soon;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);

    final badge = Container(
      width: wide ? 46 : 52,
      height: wide ? 46 : 52,
      decoration: BoxDecoration(
        // The card's own colour, held back to a wash. At full strength four
        // of these read as four buttons competing; as a tint they read as one
        // set with four members.
        color: colour.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: wide ? 24 : 27, color: colour),
    );

    final words = Column(
      crossAxisAlignment: wide
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 3),
        Text(
          blurb,
          textAlign: wide ? TextAlign.start : TextAlign.center,
          style: TextStyle(fontSize: 12, color: palette.faint, height: 1.25),
        ),
      ],
    );

    return Material(
      color: palette.panel,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Opacity(
          opacity: soon ? 0.62 : 1,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 16 : 14,
              vertical: wide ? 14 : 18,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.panelEdge),
            ),
            child: Stack(
              children: [
                if (wide)
                  Row(
                    children: [
                      badge,
                      const SizedBox(width: 14),
                      Expanded(child: words),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: palette.faint,
                      ),
                    ],
                  )
                else
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        badge,
                        const SizedBox(height: 12),
                        words,
                      ],
                    ),
                  ),
                if (soon)
                  Positioned(
                    top: 0,
                    right: wide ? 26 : 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: palette.panelEdge,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'SOON',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: palette.faint,
                        ),
                      ),
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
