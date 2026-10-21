import 'dart:convert';
import 'dart:math';

import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_protocol/ludo_protocol.dart';

import 'players.dart';
import 'room.dart';

/// Holds every live room and routes messages to the right one.
///
/// Deliberately free of sockets: the whole thing can be driven from a test with
/// fake clients, which is how the match flow is covered without opening a port.
class LudoHub {
  LudoHub({Random? random, DateTime Function()? clock, PlayerStore? players})
      : _random = random ?? Random.secure(),
        _now = clock ?? DateTime.now,
        players = players ?? PlayerStore(random: random);

  final Random _random;

  /// Everyone who has ever connected, and the secret that proves it.
  final PlayerStore players;
  final DateTime Function() _now;

  final Map<String, Room> rooms = {};
  final Map<String, Room> _roomOf = {}; // playerId -> room

  /// People looking for a game, by the size of table they want, longest
  /// waiting first.
  final Map<int, List<_Waiting>> queues = {
    for (final n in quickMatchSizes) n: [],
  };

  /// Players who walked out of a matched game, and when they may queue again.
  final Map<String, DateTime> _cooldown = {};

  /// How long the queue waits for people before dealing computers into the
  /// empty seats. Long enough for a friend to join; short enough that
  /// nobody gives up.
  static const fillAfter = Duration(seconds: 20);

  /// How long someone who leaves a matched game mid-match must wait before
  /// being matched again. Leaving strangers a seat short is not free.
  static const abandonCooldown = Duration(minutes: 2);

  /// Every matched table plays the same rules, so nobody is surprised.
  static RuleConfig quickRules(int players) => RuleConfig(
        name: 'Quick match',
        players: players,
        tokensPerPlayer: 4,
        turnTimerDots: 6,
      );

  /// Codes people read aloud and type on a phone: no 0/O or 1/I to confuse,
  /// and no vowels, so a random code cannot spell something unfortunate.
  static const _codeAlphabet = 'BCDFGHJKLMNPQRSTVWXZ23456789';

  String _newCode() {
    String make() => List.generate(
        6, (_) => _codeAlphabet[_random.nextInt(_codeAlphabet.length)]).join();
    var code = make();
    while (rooms.containsKey(code)) {
      code = make();
    }
    return code;
  }

  Room? roomOf(String playerId) => _roomOf[playerId];

  /// What a player is told on arriving: who they are, and whether there is a
  /// match they dropped out of that is still keeping their seat.
  Welcome welcomeFor(PlayerRecord player, {String? secret}) {
    final room = _roomOf[player.id];
    return Welcome(
      playerId: player.id,
      displayName: player.name,
      secret: secret,
      chosenName: player.chosenName,
      rejoin: room != null && room.isHeldFor(player.id) ? room.code : null,
    );
  }

  /// Handles one message from one client. Returns nothing — everything the
  /// client learns comes back as a broadcast, so there is a single path for
  /// state to travel and no chance of the two disagreeing.
  void handle(Client client, Envelope message) {
    switch (message) {
      case Ping():
        client.send(const Pong());

      case CreateRoom(rules: final rules, fillEmptySeatsWithAI: final fill):
        try {
          rules.validate();
        } on RuleConfigError catch (e) {
          client.send(Oops(e.message, code: 'rules'));
          return;
        }
        _unqueue(client.playerId);
        _leaveCurrent(client.playerId);
        final room = Room(
          code: _newCode(),
          rules: rules,
          hostId: client.playerId,
          fillEmptySeatsWithAI: fill,
          // The dice seed comes from the hub's own source, so a test that seeds
          // the hub gets a reproducible match and not just reproducible codes.
          seed: _random.nextInt(0x7FFFFFFF) + 1,
          random: Random(_random.nextInt(0x7FFFFFFF)),
          clock: _now,
        );
        rooms[room.code] = room;
        _roomOf[client.playerId] = room;
        final refused = room.join(client);
        if (refused != null) client.send(Oops(refused));

      case JoinRoom(code: final code):
        final room = rooms[code.toUpperCase().replaceAll('-', '')];
        if (room == null) {
          client.send(const Oops('no room with that code', code: 'noroom'));
          return;
        }
        _unqueue(client.playerId);
        // Coming back to the table you are already at is not leaving it.
        if (_roomOf[client.playerId] != room) _leaveCurrent(client.playerId);
        final refused = room.join(client);
        if (refused != null) {
          client.send(Oops(refused, code: 'full'));
          return;
        }
        _roomOf[client.playerId] = room;

      case LeaveRoom():
        _walkOut(client.playerId);

      case QuickMatch(players: final players):
        if (!quickMatchSizes.contains(players)) {
          client
              .send(Oops('quick matches are for ${quickMatchSizes.join(' or ')}'
                  ' players'));
          return;
        }
        // Looking for a new game in the middle of a matched one is walking
        // out of it.
        _walkOut(client.playerId);
        final until = _cooldown[client.playerId];
        if (until != null && _now().isBefore(until)) {
          final seconds = until.difference(_now()).inSeconds + 1;
          client.send(Oops(
              'You left your last match early, so you can look for another '
              'in $seconds seconds.',
              code: 'cooldown'));
          return;
        }
        _unqueue(client.playerId);
        queues[players]!.add(_Waiting(client, _now()));
        _matchUp(players);

      case CancelMatch():
        final size = _unqueue(client.playerId);
        client
            .send(QueueUpdate(players: size ?? 0, found: 0, searching: false));

      case SetReady(ready: final ready):
        _withRoom(client, (room) => room.setReady(client.playerId, ready));

      case AddComputer(seat: final seat, level: final level):
        _withRoom(
            client, (room) => room.addComputer(client.playerId, seat, level));

      case StartMatch():
        _withRoom(client, (room) => room.start(client.playerId));

      case Play():
        _withRoom(client, (room) => room.play(client.playerId, message));

      case Rematch():
        _withRoom(client, (room) => room.rematch(client.playerId));

      case React(index: final index):
        _withRoom(client, (room) => room.react(client.playerId, index));

      case SetName(name: final name):
        final record = players[client.playerId];
        final cleaned = PlayerStore.cleanName(name);
        if (record == null || cleaned == null) {
          client.send(const Oops('A name is 2 to 16 letters or numbers.',
              code: 'name'));
          return;
        }
        record
          ..name = cleaned
          ..chosenName = true;
        players.changed();
        client.send(welcomeFor(record));
        _roomOf[client.playerId]?.broadcastRoom();

      case Hello() ||
            Welcome() ||
            RoomUpdate() ||
            MatchUpdate() ||
            QueueUpdate() ||
            Reaction() ||
            Oops() ||
            Pong():
        client.send(const Oops('the server does not accept that message'));
    }
  }

  /// Leaves the current table on purpose. From a matched game still being
  /// played, that earns a wait before the next one.
  void _walkOut(String playerId) {
    final room = _roomOf[playerId];
    if (room != null && room.matchmade && room.phase == RoomPhase.playing) {
      _cooldown[playerId] = _now().add(abandonCooldown);
    }
    _leaveCurrent(playerId);
  }

  /// Takes [playerId] out of whichever queue they are in. Returns the size of
  /// table they were waiting for, or null if they were not waiting.
  int? _unqueue(String playerId) {
    for (final entry in queues.entries) {
      final before = entry.value.length;
      entry.value.removeWhere((w) => w.client.playerId == playerId);
      if (entry.value.length != before) {
        _tellQueue(entry.key);
        return entry.key;
      }
    }
    return null;
  }

  /// Deals a table when there are enough people for one, or when the longest
  /// waiting has waited long enough and computers make up the rest.
  void _matchUp(int players) {
    final queue = queues[players]!;
    while (queue.length >= players) {
      _deal(players, queue.sublist(0, players));
      queue.removeRange(0, players);
    }
    if (queue.isNotEmpty && _now().difference(queue.first.since) >= fillAfter) {
      _deal(players, List.of(queue));
      queue.clear();
    }
    _tellQueue(players);
  }

  void _deal(int players, List<_Waiting> who) {
    final host = who.first.client;
    final room = Room(
      code: _newCode(),
      rules: quickRules(players),
      hostId: host.playerId,
      fillEmptySeatsWithAI: true,
      matchmade: true,
      seed: _random.nextInt(0x7FFFFFFF) + 1,
      random: Random(_random.nextInt(0x7FFFFFFF)),
      clock: _now,
    );
    rooms[room.code] = room;
    for (final w in who) {
      w.client.send(
          QueueUpdate(players: players, found: who.length, searching: false));
      _roomOf[w.client.playerId] = room;
      room.join(w.client);
    }
    room.start(host.playerId);
  }

  /// Tells everyone in a queue how it is going.
  void _tellQueue(int players) {
    final queue = queues[players]!;
    if (queue.isEmpty) return;
    final waited = _now().difference(queue.first.since);
    final left = (fillAfter - waited).inSeconds.clamp(0, fillAfter.inSeconds);
    for (final w in queue) {
      w.client.send(QueueUpdate(
        players: players,
        found: queue.length,
        secondsToFill: left,
      ));
    }
  }

  void _withRoom(Client client, String? Function(Room) action) {
    final room = _roomOf[client.playerId];
    if (room == null) {
      client.send(const Oops('you are not in a room', code: 'noroom'));
      return;
    }
    final refused = action(room);
    if (refused != null) client.send(Oops(refused));
  }

  void _leaveCurrent(String playerId) {
    final room = _roomOf.remove(playerId);
    if (room == null) return;
    room.leave(playerId);
    _reapIfEmpty(room);
  }

  /// A client's socket dropped. During a match their seat is held; in a lobby
  /// it is freed straight away.
  void disconnected(String playerId) {
    _unqueue(playerId);
    final room = _roomOf[playerId];
    if (room == null) return;
    room.leave(playerId);
    if (room.phase != RoomPhase.playing) {
      _roomOf.remove(playerId);
      _reapIfEmpty(room);
    }
    // Someone dropping must not stall the table.
    room.driveComputers();
  }

  void _reapIfEmpty(Room room) {
    final anyone = room.seats.any((s) => s.client != null);
    if (!anyone) rooms.remove(room.code);
  }

  /// Advances every room's turn clock. Called once a second by the server.
  void tick() {
    for (final room in rooms.values.toList()) {
      room.tick();
    }
    for (final size in quickMatchSizes) {
      if (queues[size]!.isNotEmpty) _matchUp(size);
    }
    _cooldown.removeWhere((_, until) => !_now().isBefore(until));
    // A seat given up to the computer is no longer that player's, and a table
    // with nobody left at it is finished with.
    _roomOf.removeWhere((id, room) => !room.holds(id));
    rooms.removeWhere((_, room) =>
        !room.seats.any((s) => s.client != null || s.heldFor != null));
  }
}

/// Somebody in a matchmaking queue, and since when.
class _Waiting {
  _Waiting(this.client, this.since);
  final Client client;
  final DateTime since;
}

/// A client backed by a real socket.
class SocketClient implements Client {
  SocketClient({
    required this.player,
    required void Function(String) sink,
  }) : _sink = sink;

  final PlayerRecord player;
  final void Function(String) _sink;

  @override
  String get playerId => player.id;

  /// Read from the record each time, so a rename shows at once.
  @override
  String get displayName => player.name;

  @override
  void send(Envelope message) {
    try {
      _sink(message.encode());
    } catch (_) {
      // A dead socket is not an error worth unwinding a game over; the hub
      // notices the disconnect separately.
    }
  }
}

/// Decodes a raw frame, answering with a readable error rather than dropping
/// the connection when a client sends something malformed.
Envelope? decodeOrComplain(String raw, Client client) {
  try {
    return Envelope.decode(raw);
  } on FormatException catch (e) {
    client.send(Oops('could not read that message: ${e.message}'));
    return null;
  } catch (e) {
    client.send(Oops('could not read that message'));
    return null;
  }
}

/// The oldest [protocolVersion] this server still talks to.
const minimumProtocol = 2;

/// Who a connection turned out to be, from its opening [Hello].
sealed class Identity {}

/// A known player, or a new one minted just now — in which case [secret] is
/// set and must reach the app, because it is the only copy.
class Identified extends Identity {
  Identified(this.player, {this.secret});
  final PlayerRecord player;
  final String? secret;
}

/// An app too old to talk to.
class TooOld extends Identity {}

/// Reads the opening [Hello] and settles on an identity.
///
/// An account is never required. A returning player sends the id and secret
/// they were given; anything else — a first visit, a reinstalled app, an id
/// somebody copied off a lobby screen without its secret — gets a fresh
/// identity rather than someone else's.
Identity identify(LudoHub hub, String? raw) {
  Hello hello = const Hello(version: 1);
  if (raw != null) {
    try {
      final decoded = Envelope.decode(raw);
      if (decoded is Hello) hello = decoded;
    } catch (_) {
      // Fall through: not a hello, so treated as an old client.
    }
  }
  if (hello.version < minimumProtocol) return TooOld();

  final known = hub.players.verify(hello.guestId?.trim(), hello.secret);
  if (known != null) return Identified(known);
  final (fresh, secret) = hub.players.mint(name: hello.displayName);
  return Identified(fresh, secret: secret);
}

/// Convenience for tests and tooling: JSON-encode any envelope.
String encode(Envelope e) => e.encode();

/// Pretty-prints a room for logs.
String describe(Room room) => jsonEncode(room.toInfo().toJson());
