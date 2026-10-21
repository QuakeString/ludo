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
        // Coming back to the table you are already at is not leaving it.
        if (_roomOf[client.playerId] != room) _leaveCurrent(client.playerId);
        final refused = room.join(client);
        if (refused != null) {
          client.send(Oops(refused, code: 'full'));
          return;
        }
        _roomOf[client.playerId] = room;

      case LeaveRoom():
        _leaveCurrent(client.playerId);

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
            Reaction() ||
            Oops() ||
            Pong():
        client.send(const Oops('the server does not accept that message'));
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
    // A seat given up to the computer is no longer that player's, and a table
    // with nobody left at it is finished with.
    _roomOf.removeWhere((id, room) => !room.holds(id));
    rooms.removeWhere((_, room) =>
        !room.seats.any((s) => s.client != null || s.heldFor != null));
  }
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
