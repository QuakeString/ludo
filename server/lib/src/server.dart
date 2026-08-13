import 'dart:convert';
import 'dart:math';

import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_protocol/ludo_protocol.dart';

import 'room.dart';

/// Holds every live room and routes messages to the right one.
///
/// Deliberately free of sockets: the whole thing can be driven from a test with
/// fake clients, which is how the match flow is covered without opening a port.
class LudoHub {
  LudoHub({Random? random, DateTime Function()? clock})
      : _random = random ?? Random(),
        _now = clock ?? DateTime.now;

  final Random _random;
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

  String newGuestId() =>
      'g${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_random.nextInt(0xFFFF).toRadixString(16)}';

  String guestName(String playerId) =>
      'Guest_${playerId.hashCode.abs() % 9000 + 1000}';

  Room? roomOf(String playerId) => _roomOf[playerId];

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
        _leaveCurrent(client.playerId);
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

      case Hello() ||
            Welcome() ||
            RoomUpdate() ||
            MatchUpdate() ||
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
  }
}

/// A client backed by a real socket.
class SocketClient implements Client {
  SocketClient({
    required this.playerId,
    required this.displayName,
    required void Function(String) sink,
  }) : _sink = sink;

  @override
  final String playerId;
  @override
  final String displayName;
  final void Function(String) _sink;

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

/// Reads the opening [Hello] and settles on an identity.
///
/// An account is never required. A client that has played before sends the
/// guest id it was given; a new one gets a fresh one minted here.
({String playerId, String displayName}) identify(LudoHub hub, String? raw) {
  Hello hello = const Hello();
  if (raw != null) {
    try {
      final decoded = Envelope.decode(raw);
      if (decoded is Hello) hello = decoded;
    } catch (_) {
      // Fall through to a fresh guest.
    }
  }
  final id = hello.guestId?.trim().isNotEmpty == true
      ? hello.guestId!.trim()
      : hub.newGuestId();
  final name = hello.displayName?.trim().isNotEmpty == true
      ? hello.displayName!.trim()
      : hub.guestName(id);
  return (playerId: id, displayName: name);
}

/// Convenience for tests and tooling: JSON-encode any envelope.
String encode(Envelope e) => e.encode();

/// Pretty-prints a room for logs.
String describe(Room room) => jsonEncode(room.toInfo().toJson());
