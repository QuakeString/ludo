import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_protocol/ludo_protocol.dart';
import 'package:share_plus/share_plus.dart';

import '../net/connection.dart';
import '../net/online_session.dart';
import '../theme/seat_colors.dart';
import 'game_screen.dart';
import 'profile_screen.dart';

/// Where the server lives: the hosted one, unless a build says otherwise. A
/// debug build can point at a laptop without editing code:
///
///   flutter run --dart-define=LUDO_SERVER=ws://192.168.1.20:8080/ws
const serverUri = String.fromEnvironment(
  'LUDO_SERVER',
  defaultValue: 'wss://$serverHost/ws',
);

/// The hosted server's address, also used for invite links. Set in `fly.toml`.
const serverHost = 'quakestring-ludo.fly.dev';

/// The link that invites somebody to [code]: a page on the server that opens
/// the app, or offers it to a phone that does not have it yet.
String inviteLink(String code) => 'https://$serverHost/r/$code';

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
  const OnlineScreen({super.key, this.joinCode, this.quick = false});

  /// A room to go straight to, from an invite link.
  final String? joinCode;

  /// Matched with strangers, rather than opening a table for friends.
  final bool quick;

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  LudoConnection? _connection;
  OnlineSession? _session;

  String? _problem;
  bool _connecting = true;

  StreamSubscription<Invite>? _inviteSub;

  /// Asking for a name before anything else, the first time online. Everyone
  /// at a table sees it, and `Guest_4821` tells a friend nothing.
  bool _askName = false;

  final _code = TextEditingController();
  int _players = 4;
  int _quickPlayers = 4;
  int _tokens = 4;
  bool _teams = false;
  int _shape = 0;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _inviteSub?.cancel();
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
      final session = OnlineSession(connection)
        ..addListener(_changed)
        ..refreshProfile();
      _inviteSub = session.invites.listen(_invited);
      setState(() {
        _connection = connection;
        _session = session;
        _connecting = false;
        _askName = !session.hasChosenName;
      });
      if (!_askName) _followInvite();
    } catch (e) {
      await connection.dispose();
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _problem = connection.outOfDate
            ? 'This copy of Ludo is out of date. Install the latest version '
                  'to play online.'
            : 'Could not reach the game server. Check your connection and '
                  'try again.\n\n($e)';
      });
    }
  }

  /// A friend asks this player to their table.
  Future<void> _invited(Invite invite) async {
    final session = _session;
    if (session == null || !mounted) return;
    // Mid-game, an invitation is not worth interrupting a turn for.
    if (session.inMatch) return;
    final join = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${invite.from.shownName} invites you'),
        content: Text('Join their table, room ${invite.code}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (join == true && mounted) {
      if (session.searching) session.cancelQuickMatch();
      session.joinRoom(invite.code);
    }
  }

  void _openProfile() {
    final session = _session;
    if (session == null) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ProfileScreen(session: session)));
  }

  /// Goes to the room an invite link named, once there is a name to go as.
  void _followInvite() {
    final code = widget.joinCode;
    if (code != null) _session?.joinRoom(code);
  }

  void _named(String? name) {
    if (name != null) _session?.setName(name);
    setState(() => _askName = false);
    _followInvite();
  }

  Future<void> _rename() async {
    final session = _session;
    if (session == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initial: session.myName),
    );
    if (name != null && name.trim().isNotEmpty) session.setName(name);
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

  List<TeamShape> get _shapes => teamShapesFor(_players);
  TeamShape? get _chosenShape => _teams && _shapes.isNotEmpty
      ? _shapes[_shape.clamp(0, _shapes.length - 1)]
      : null;

  RuleConfig get _rules => RuleConfig(
    name: 'Online',
    players: _players,
    tokensPerPlayer: _tokens,
    teams: _chosenShape?.groups,
    // Online, a turn that never ends is a table everyone else has to sit
    // and wait at, so the clock is on by default here: six dots of five
    // seconds each.
    turnTimerDots: 6,
  );

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.quick ? 'Online' : 'Play with friends'),
        actions: [
          if (session != null && !_askName)
            IconButton(
              tooltip: 'Profile and friends',
              onPressed: _openProfile,
              icon: Badge(
                isLabelVisible: (session.profile?.incoming.length ?? 0) > 0,
                label: Text('${session.profile?.incoming.length ?? 0}'),
                child: const Icon(Icons.account_circle_outlined),
              ),
            ),
        ],
      ),
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
                : _askName
                ? _NamePrompt(
                    suggestion: session!.myName,
                    invited: widget.joinCode != null,
                    onDone: _named,
                  )
                : session!.room != null
                ? _Lobby(session: session, onLeave: _leaveRoom)
                : widget.quick
                ? _quickEntrance(session)
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

  /// Who this device is playing as, and any game it can go back to.
  List<Widget> _whoAmI(OnlineSession session) => [
    Row(
      children: [
        Expanded(
          child: Text(
            'Playing as ${session.myName}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        TextButton.icon(
          onPressed: _rename,
          icon: const Icon(Icons.edit, size: 16),
          label: const Text('Change'),
        ),
      ],
    ),
    const Text(
      'No account needed — this device is remembered, that is all.',
      style: TextStyle(fontSize: 12.5),
    ),
    if (session.rejoinCode != null) ...[
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          leading: const Icon(Icons.replay_rounded),
          title: const Text('Your game is still going'),
          subtitle: Text(
            'Room ${session.rejoinCode} is keeping your seat. The '
            'computer is playing it until you are back.',
          ),
          trailing: FilledButton(
            onPressed: () => session.joinRoom(session.rejoinCode!),
            child: const Text('Rejoin'),
          ),
        ),
      ),
    ],
  ];

  Widget _quickEntrance(OnlineSession session) {
    final queue = session.queue;
    final error = session.error;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ..._whoAmI(session),
        const SizedBox(height: 28),
        if (queue != null && queue.searching) ...[
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 18),
          Text(
            'Looking for players',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            '${queue.found} of ${queue.players} found',
            textAlign: TextAlign.center,
          ),
          if (queue.secondsToFill != null && queue.found < queue.players)
            Text(
              queue.secondsToFill! > 0
                  ? 'Computers take the empty seats in '
                        '${queue.secondsToFill} s'
                  : 'Dealing the table…',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: session.cancelQuickMatch,
            child: const Text('Cancel'),
          ),
        ] else ...[
          const Text(
            'Play with whoever is looking for a game',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Classic rules, four chips each, a turn clock. If not enough '
            'people turn up within 20 seconds, computers fill the empty seats.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 14),
          _Choice(
            label: 'Players',
            options: quickMatchSizes,
            value: _quickPlayers,
            onChanged: (v) => setState(() => _quickPlayers = v),
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () => session.quickMatch(_quickPlayers),
            style: FilledButton.styleFrom(
              backgroundColor: seatColors[3],
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              'Find a game',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
  }

  Widget _entrance(OnlineSession session) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ..._whoAmI(session),
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
            _shape = 0;
            if (_shapes.isEmpty) _teams = false;
          }),
        ),
        const SizedBox(height: 10),
        _Choice(
          label: 'Chips each',
          options: const [3, 4],
          value: _tokens,
          onChanged: (v) => setState(() => _tokens = v),
        ),
        if (_shapes.isNotEmpty) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _teams,
            onChanged: (v) => setState(() => _teams = v),
            title: const Text('Play as teams'),
            subtitle: Text(
              _chosenShape?.description ??
                  'Sides win together — everybody home, not just you',
            ),
          ),
          // Six seats divide two ways, and the two are different games.
          if (_teams && _shapes.length > 1)
            _Choice(
              label: 'Sides',
              options: [for (var i = 0; i < _shapes.length; i++) i],
              value: _shape.clamp(0, _shapes.length - 1),
              labelOf: (i) => _shapes[i].label,
              onChanged: (v) => setState(() => _shape = v),
            ),
        ],
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

  void _invite(BuildContext context, String code) {
    final link = inviteLink(code);
    final text =
        'Join my Ludo game! Tap $link to open it, or type the room code '
        '$code under Play with friends.';
    SharePlus.instance.share(ShareParams(text: text, subject: 'Ludo'));
  }

  /// Friends who are online, to ask to this table directly.
  Future<void> _pickFriend(BuildContext context) async {
    final friends = session.profile?.friends ?? const <FriendInfo>[];
    final chosen = await showModalBottomSheet<FriendInfo>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Ask a friend to this table',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final f in friends)
              ListTile(
                enabled: f.online,
                leading: Icon(
                  Icons.circle,
                  size: 12,
                  color: f.online ? const Color(0xFF2E9E5B) : Colors.grey,
                ),
                title: Text(f.shownName),
                subtitle: Text(f.online ? 'Online' : 'Offline'),
                onTap: () => Navigator.of(context).pop(f),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    session.inviteFriend(chosen.playerId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Asked ${chosen.shownName} to join')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = session.room!;
    final sitting = room.seats.where((s) => s.playerId != null || s.isComputer);
    final people = room.seats.where((s) => s.playerId != null).length;
    final empty = room.seats.length - sitting.length;
    final host = room.seats.where((s) => s.playerId == room.hostId);
    final hostName = host.isEmpty ? 'the host' : host.first.displayName;

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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Room code', style: TextStyle(fontSize: 12.5)),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        room.code,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 5,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy the code',
                      icon: const Icon(Icons.copy),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: room.code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Room code copied')),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _invite(context, room.code),
                      icon: const Icon(Icons.share),
                      label: const Text('Invite friends'),
                    ),
                    if (session.profile?.friends.isNotEmpty ?? false)
                      OutlinedButton.icon(
                        onPressed: () => _pickFriend(context),
                        icon: const Icon(Icons.people_alt_outlined),
                        label: const Text('Ask a friend'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Send the link in any chat. It opens this room in the app, '
                  'or offers the app to anyone who does not have it.',
                  style: TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '$people of ${room.seats.length} seats taken'
          '${sitting.length > people ? ', ${sitting.length - people} by the computer' : ''}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        for (final seat in room.seats)
          _SeatRow(
            seat: seat,
            isYou: seat.playerId == session.playerId,
            isHost: seat.playerId != null && seat.playerId == room.hostId,
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
          Center(child: Text('Waiting for $hostName to start…')),
        const SizedBox(height: 10),
        TextButton(onPressed: onLeave, child: const Text('Leave room')),
      ],
    );
  }
}

class _SeatRow extends StatelessWidget {
  const _SeatRow({
    required this.seat,
    required this.isYou,
    this.isHost = false,
    this.onAddComputer,
  });

  final SeatInfo seat;
  final bool isYou;
  final bool isHost;
  final void Function(AiLevel)? onAddComputer;

  @override
  Widget build(BuildContext context) {
    final empty = seat.playerId == null && !seat.isComputer;
    final notes = [
      if (isHost) 'Host',
      if (!seat.connected && !empty) 'Reconnecting…',
    ];
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: seatColors[seat.seat],
        radius: 14,
        child: seat.isComputer
            ? const Icon(Icons.smart_toy, size: 15, color: Colors.white)
            : isHost
            ? const Icon(Icons.star_rounded, size: 16, color: Colors.white)
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
      subtitle: notes.isEmpty
          ? null
          : Text(notes.join(' · '), style: const TextStyle(fontSize: 12)),
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

/// The first time online: what should everybody else call you?
class _NamePrompt extends StatefulWidget {
  const _NamePrompt({
    required this.suggestion,
    required this.invited,
    required this.onDone,
  });

  final String suggestion;
  final bool invited;

  /// The name chosen, or null to carry on as the guest name.
  final ValueChanged<String?> onDone;

  @override
  State<_NamePrompt> createState() => _NamePromptState();
}

class _NamePromptState extends State<_NamePrompt> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    widget.onDone(name.length >= 2 ? name : null);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 20),
        const Icon(Icons.badge_outlined, size: 44),
        const SizedBox(height: 14),
        Text(
          widget.invited
              ? 'You are invited to a game'
              : 'What should we call you?',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Everyone at the table sees this name. You can change it later.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: 16,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Your name',
            hintText: widget.suggestion,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(widget.invited ? 'Join the game' : 'Continue'),
        ),
        TextButton(
          onPressed: () => widget.onDone(null),
          child: Text('Skip and play as ${widget.suggestion}'),
        ),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});
  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your name'),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 16,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_name.text),
          child: const Text('Save'),
        ),
      ],
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
    this.labelOf,
  });

  final String label;
  final List<int> options;
  final int value;
  final ValueChanged<int> onChanged;

  /// What each option is called, when the number is an index into something
  /// rather than the thing itself.
  final String Function(int)? labelOf;

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
                  label: Text(labelOf?.call(option) ?? '$option'),
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
