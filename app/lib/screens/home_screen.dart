import 'package:flutter/material.dart';

import '../app_update.dart';
import '../saved_game.dart';
import '../theme/seat_colors.dart';
import 'game_screen.dart';
import 'history_screen.dart';
import 'online_screen.dart';
import 'settings_screen.dart';
import 'setup_screen.dart';

/// The front door: four ways to play, and nothing else.
///
/// It used to open straight onto the settings — seat counts, chip counts,
/// difficulty — which asks the wrong question first. Nobody opens a Ludo app
/// wanting to decide how many chips each player gets; they want to play, and
/// how they want to play (alone against the machine, round one phone, with
/// friends who are elsewhere) decides which settings even apply. So the mode
/// comes first and every dial moves behind it.
///
/// The one exception is a game left unfinished on this device, which goes
/// above all four: somebody who closed the app mid-game and opens it again
/// almost always wants that game back.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  SavedGame? _saved;

  /// A newer build than this one, once the check has found one.
  int? _update;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _lookForSavedGame();
    _lookForUpdate();
  }

  Future<void> _lookForUpdate() async {
    final newer = await AppUpdate.newer();
    if (mounted && newer != null) setState(() => _update = newer);
  }

  Future<void> _installUpdate() async {
    setState(() => _updating = true);
    try {
      await installAppUpdate(ScaffoldMessenger.of(context));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  /// Read again every time this page comes back into view: the game just left
  /// may have ended, or a new one may have taken its place.
  Future<void> _lookForSavedGame() async {
    final saved = await SavedGameStore.load();
    if (mounted) setState(() => _saved = saved);
  }

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final saved = _saved;

    return Scaffold(
      backgroundColor: palette.felt,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    key: const ValueKey('open-settings'),
                    tooltip: 'Settings',
                    icon: const Icon(Icons.settings_rounded),
                    onPressed: () => _go(context, const SettingsScreen()),
                  ),
                ),
                const _Wordmark(),
                const SizedBox(height: 8),
                Text(
                  'Roll. Chase. Bring them home.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13.5, color: palette.faint),
                ),
                const SizedBox(height: 30),
                if (_update != null) ...[
                  _UpdateCard(busy: _updating, onUpdate: _installUpdate),
                  const SizedBox(height: 12),
                ],
                if (saved != null) ...[
                  _ContinueCard(
                    saved: saved,
                    onTap: () => _go(context, GameScreen.resumed(saved)),
                  ),
                  const SizedBox(height: 12),
                ],
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
                        onTap: () =>
                            _go(context, const OnlineScreen(quick: true)),
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
                const SizedBox(height: 18),
                Center(
                  child: TextButton.icon(
                    onPressed: () => _go(context, const HistoryScreen()),
                    icon: const Icon(Icons.history_rounded),
                    label: const Text('Recent matches'),
                  ),
                ),
                const SizedBox(height: 10),
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

  Future<void> _go(BuildContext context, Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    _lookForSavedGame();
  }
}

/// The game left unfinished on this device, and whose turn it is in it.
class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.saved, required this.onTap});

  final SavedGame saved;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final state = saved.state;
    final arm = state.armOf(state.turn);
    final colour = colourOfArm(arm, state.board.arms);
    final who = saved.aiSeats.containsKey(state.turn)
        ? 'the computer'
        : nameOfArm(arm, state.board.arms);

    return Material(
      color: palette.panel,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            // Edged in the colour on turn, so it reads as the game itself
            // rather than as a fifth way to start one.
            border: Border.all(color: colour, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.play_arrow_rounded, size: 26, color: colour),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Continue game',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${state.rules.name} · ${state.rules.players} seats · '
                      '${who[0].toUpperCase()}${who.substring(1)} to play',
                      style: TextStyle(
                        fontSize: 12,
                        color: palette.faint,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: palette.faint),
            ],
          ),
        ),
      ),
    );
  }
}

/// A newer version is out: one tap fetches it and opens the installer.
class _UpdateCard extends StatelessWidget {
  const _UpdateCard({required this.busy, required this.onUpdate});

  final bool busy;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    return Material(
      color: palette.panel,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: seatColors[1], width: 1.5),
        ),
        child: Row(
          children: [
            Icon(Icons.system_update_rounded, color: seatColors[1]),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'A new version of Ludo is ready',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton(
              key: const ValueKey('update-app'),
              onPressed: busy ? null : onUpdate,
              child: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }
}

/// LUDO, a letter per seat colour.
/// LUDO in the four board colours, and Time written by hand beside it.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: 'LUDO Time',
      excludeSemantics: true,
      // Shrinks rather than overflows on the narrowest phones.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            for (var i = 0; i < 4; i++)
              Text(
                'LUDO'[i],
                style: TextStyle(
                  fontFamily: 'Fredoka',
                  fontSize: 50,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: seatColors[i],
                ),
              ),
            const SizedBox(width: 10),
            Transform.rotate(
              angle: -0.1,
              child: Text(
                'Time',
                style: TextStyle(
                  fontFamily: 'Pacifico',
                  fontSize: 36,
                  color: ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.title,
    required this.blurb,
    required this.icon,
    required this.colour,
    required this.onTap,
    required this.wide,
  });

  final String title;
  final String blurb;
  final IconData icon;
  final Color colour;
  final VoidCallback onTap;

  /// Laid out as a row rather than a column, for a one-column screen.
  final bool wide;

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
                    Icon(Icons.chevron_right_rounded, color: palette.faint),
                  ],
                )
              else
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [badge, const SizedBox(height: 12), words],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
