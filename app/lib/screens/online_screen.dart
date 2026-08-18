import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_protocol/ludo_protocol.dart';

import '../net/connection.dart';
import '../net/online_session.dart';
import '../theme/seat_colors.dart';
import 'game_screen.dart';

/// Where the server lives. Overridable at build time so a debug build can
/// point at a laptop without editing code:
///
///   flutter run --dart-define=LUDO_SERVER=ws://192.168.1.20:8080/ws
const serverUri = String.fromEnvironment(
  'LUDO_SERVER',
  defaultValue: 'ws://localhost:8080/ws',
);

/// True when this build was never given a server to talk to.
///
/// The default points at localhost, which is right on a developer's machine
/// and meaningless anywhere else — a build published to a web host would sit
/// there trying to open a socket to the *player's own* computer and then
/// report a connection error, which reads as "this app is broken" rather than
/// "this copy has no server". Worth naming, so the screen can say the true
/// thing instead.
///
/// A browser also refuses a plain ws:// socket from a page served over https,
/// so on a hosted build this could not work even if something were listening.
bool get serverIsUnset {
  final target = Uri.tryParse(serverUri);
  final pointsAtThisMachine =
      target?.host == 'localhost' || target?.host == '127.0.0.1';
  final host = Uri.base.host;
  final runningHere =
      host.isEmpty || host == 'localhost' || host == '127.0.0.1';
  return pointsAtThisMachine && !runningHere;
}

/// Getting online, from tapping the button to sitting at a table.
///
/// Nothing here asks anyone to make an account. Connecting mints a guest id if
/// this device has never played before and reuses it if it has, which is the
/// whole of signing in — friends and profiles are built on top of that id
/// later, never in front of it.
class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  LudoConnection? _connection;
  OnlineSession? _session;

  String? _problem;
  bool _connecting = true;

  final _code = TextEditingController();
  int _players = 4;
  int _tokens = 4;
  bool _teams = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _code.dispose();
    _session?.dispose();
    _connection?.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (serverIsUnset) {
      // Don't open a socket that cannot succeed just to report the failure.
      setState(() {
        _connecting = false;
        _problem =
            'This build has no game server behind it.\n\n'
            'Everything else works: pass & play and playing the computer are '
            'entirely on your device. Online play needs the server running '
            'somewhere this app can reach.';
      });
      return;
    }
    setState(() {
      _connecting = true;
      _problem = null;
    });
    final connection = LudoConnection(uri: Uri.parse(serverUri));
    try {
      await connection.connect();
      if (!mounted) return;
      final session = OnlineSession(connection)..addListener(_changed);
      setState(() {
        _connection = connection;
        _session = session;
        _connecting = false;
      });
    } catch (e) {
      await connection.dispose();
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _problem = 'Could not reach the server at $serverUri.\n$e';
      });
    }
  }

  void _changed() {
    final session = _session;
    if (session == null || !mounted) return;

    // The match starting is the server's decision, not this screen's, so the
    // board opens when the first position arrives rather than when the host
    // taps anything.
    if (session.inMatch && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              GameScreen(rules: session.state!.rules, session: session),
        ),
      );
    }
    setState(() {});
  }

  RuleConfig get _rules => RuleConfig(
    name: 'Online',
    players: _players,
    tokensPerPlayer: _tokens,
    teams: _teams && (_players == 4 || _players == 6)
        ? [
            [for (var p = 0; p < _players; p += 2) p],
            [for (var p = 1; p < _players; p += 2) p],
          ]
        : null,
    // Off by default, matching the local setup screen.
    blockades: false,
    // Online, a turn that never ends is a table everyone else has to sit
    // and wait at, so the clock is on by default here: six dots of five
    // seconds each.
    turnTimerDots: 6,
  );

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(title: const Text('Play online')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: _connecting
                ? const Center(child: CircularProgressIndicator())
                : _problem != null
                ? _Problem(
                    message: _problem!,
                    // Nothing to retry when there is no server to reach.
                    onRetry: serverIsUnset ? null : _connect,
                  )
                : session!.room != null
                ? _Lobby(session: session, onLeave: _leaveRoom)
                : _entrance(session),
          ),
        ),
      ),
    );
  }

  void _leaveRoom() {
    _session?.leaveRoom();
    setState(() {});
  }

  Widget _entrance(OnlineSession session) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Playing as ${session.myName}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        const Text(
          'No account needed — this device is remembered, that is all.',
          style: TextStyle(fontSize: 12.5),
        ),
        const SizedBox(height: 24),

        const Text(
          'Join a friend',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Room code',
                  hintText: 'e.g. KTP4WQ',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (v) => session.joinRoom(v),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () => session.joinRoom(_code.text),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  vertical: 18,
                  horizontal: 20,
                ),
              ),
              child: const Text('Join'),
            ),
          ],
        ),
        if (session.error != null) ...[
          const SizedBox(height: 10),
          Text(
            session.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],

        const SizedBox(height: 30),
        const Text(
          'Or open a table',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        _Choice(
          label: 'Seats',
          options: const [2, 3, 4, 5, 6],
          value: _players,
          onChanged: (v) => setState(() {
            _players = v;
            if (v != 4 && v != 6) _teams = false;
          }),
        ),
        const SizedBox(height: 10),
        _Choice(
          label: 'Chips each',
          options: const [3, 4],
          value: _tokens,
          onChanged: (v) => setState(() => _tokens = v),
        ),
        if (_players == 4 || _players == 6)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _teams,
            onChanged: (v) => setState(() => _teams = v),
            title: const Text('Play as teams'),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () => session.createRoom(_rules),
          style: FilledButton.styleFrom(
            backgroundColor: seatColors[1],
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text(
            'Create room',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// The waiting room: who is here, and what the host may do about it.
class _Lobby extends StatelessWidget {
  const _Lobby({required this.session, required this.onLeave});

  final OnlineSession session;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final room = session.room!;
    final sitting = room.seats.where((s) => s.playerId != null || s.isComputer);
    final empty = room.seats.length - sitting.length;

    // Mirror what the server will actually accept, so the button is never
    // enabled into a refusal.
    final canStart =
        session.isHost &&
        sitting.length >= 2 &&
        (empty == 0 || room.fillEmptySeatsWithAI);
    final blocker = sitting.length < 2
        ? 'Waiting for one more player'
        : 'Fill the last $empty ${empty == 1 ? 'seat' : 'seats'} to start';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: ListTile(
            title: Text(
              room.code,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                letterSpacing: 5,
              ),
            ),
            subtitle: const Text(
              'Read this out, or send it — that is the invite',
            ),
            trailing: IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: room.code));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Room code copied')),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final seat in room.seats)
          _SeatRow(
            seat: seat,
            isYou: seat.playerId == session.playerId,
            // Filling an empty seat with a computer is the host's choice. A
            // table must never quietly decide that for them.
            onAddComputer: session.isHost && seat.playerId == null
                ? (level) => session.addComputer(seat.seat, level)
                : null,
          ),
        if (session.isHost &&
            room.seats.any((s) => s.playerId == null && !s.isComputer))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Fill the rest with computers',
                    style: TextStyle(fontSize: 13.5),
                  ),
                ),
                for (final level in AiLevel.values)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: OutlinedButton(
                      onPressed: () {
                        for (final seat in room.seats) {
                          if (seat.playerId == null && !seat.isComputer) {
                            session.addComputer(seat.seat, level);
                          }
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(level.name),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 18),
        if (session.error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              session.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (session.isHost)
          FilledButton(
            onPressed: canStart ? session.start : null,
            style: FilledButton.styleFrom(
              backgroundColor: seatColors[1],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              canStart ? 'Start the match' : blocker,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          )
        else
          const Center(child: Text('Waiting for the host to start…')),
        const SizedBox(height: 10),
        TextButton(onPressed: onLeave, child: const Text('Leave room')),
      ],
    );
  }
}

class _SeatRow extends StatelessWidget {
  const _SeatRow({required this.seat, required this.isYou, this.onAddComputer});

  final SeatInfo seat;
  final bool isYou;
  final void Function(AiLevel)? onAddComputer;

  @override
  Widget build(BuildContext context) {
    final empty = seat.playerId == null && !seat.isComputer;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: seatColors[seat.seat],
        radius: 14,
        child: seat.isComputer
            ? const Icon(Icons.smart_toy, size: 15, color: Colors.white)
            : null,
      ),
      title: Text(
        empty
            ? 'Empty seat'
            : '${seat.displayName ?? 'Player'}${isYou ? ' (you)' : ''}',
        style: TextStyle(
          fontWeight: isYou ? FontWeight.w700 : FontWeight.w400,
          color: empty ? Theme.of(context).disabledColor : null,
        ),
      ),
      subtitle: seat.connected || empty
          ? null
          : const Text('Reconnecting…', style: TextStyle(fontSize: 12)),
      trailing: onAddComputer == null
          ? null
          : PopupMenuButton<AiLevel>(
              tooltip: 'Add a computer player',
              onSelected: onAddComputer,
              itemBuilder: (_) => [
                for (final level in AiLevel.values)
                  PopupMenuItem(
                    value: level,
                    child: Text('Computer · ${level.name}'),
                  ),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text('Add computer'),
              ),
            ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 44),
          const SizedBox(height: 14),
          Text(message, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            const Text(
              'Everything except online play works without a server.',
              style: TextStyle(fontSize: 12.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<int> options;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Wrap(
            spacing: 6,
            children: [
              for (final option in options)
                ChoiceChip(
                  label: Text('$option'),
                  selected: option == value,
                  onSelected: (_) => onChanged(option),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
