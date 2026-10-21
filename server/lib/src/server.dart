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

  /// Who is connected right now, by player id.
  final Map<String, Client> online = {};

  /// One-time codes for carrying a player to another phone.
  final Map<String, ({String playerId, DateTime expires})> _transfers = {};

  static const transferLife = Duration(minutes: 10);

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
      // Holding a seat in a match still being played is enough: right after
      // a phone reconnects, the server may not have noticed the old
      // connection is dead yet, so the seat is not marked as held.
      rejoin: room != null &&
              room.phase == RoomPhase.playing &&
              room.holds(player.id)
          ? room.code
          : null,
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
        room.onFinished = _recordResult;
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

      case SwapSeats(a: final a, b: final b):
        _withRoom(client, (room) => room.swapSeats(client.playerId, a, b));

      case StartMatch():
        _withRoom(client, (room) => room.start(client.playerId));

      case Play():
        _withRoom(client, (room) => room.play(client.playerId, message));

      case Rematch():
        _withRoom(client, (room) => room.rematch(client.playerId));

      case React(index: final index):
        _withRoom(client, (room) => room.react(client.playerId, index));

      case Say(text: final text):
        _withRoom(client, (room) => room.say(client.playerId, text));

      case GetProfile():
        _sendProfile(client.playerId);

      case AddFriend(code: final code):
        final me = players[client.playerId];
        final them = players.byFriendCode(code);
        if (me == null || them == null) {
          client.send(
              const Oops('Nobody has that friend code.', code: 'nofriend'));
          return;
        }
        if (them.id == me.id) {
          client.send(
              const Oops('That is your own friend code.', code: 'nofriend'));
          return;
        }
        if (me.friends.containsKey(them.id)) {
          _sendProfile(me.id);
          return;
        }
        if (me.incoming.contains(them.id)) {
          _befriend(me, them); // they asked first: that is a yes both ways
        } else {
          me.outgoing.add(them.id);
          them.incoming.add(me.id);
        }
        players.changed();
        _sendProfile(me.id);
        _sendProfile(them.id);

      case AnswerFriend(playerId: final id, accept: final accept):
        final me = players[client.playerId];
        final them = players[id];
        if (me == null || them == null || !me.incoming.contains(id)) {
          client.send(const Oops('There is no such request.'));
          return;
        }
        if (accept) {
          _befriend(me, them);
        } else {
          me.incoming.remove(id);
          them.outgoing.remove(me.id);
        }
        players.changed();
        _sendProfile(me.id);
        _sendProfile(them.id);

      case RemoveFriend(playerId: final id):
        final me = players[client.playerId];
        final them = players[id];
        if (me == null) return;
        me.friends.remove(id);
        me.outgoing.remove(id);
        me.incoming.remove(id);
        them?.friends.remove(me.id);
        them?.incoming.remove(me.id);
        them?.outgoing.remove(me.id);
        players.changed();
        _sendProfile(me.id);
        if (them != null) _sendProfile(them.id);

      case SetNickname(playerId: final id, nickname: final nickname):
        final me = players[client.playerId];
        if (me == null || !me.friends.containsKey(id)) {
          client.send(const Oops('You can only name your friends.'));
          return;
        }
        me.friends[id] = PlayerStore.cleanName(nickname);
        players.changed();
        _sendProfile(me.id);

      case InviteFriend(playerId: final id):
        final me = players[client.playerId];
        final room = _roomOf[client.playerId];
        if (me == null || !me.friends.containsKey(id)) {
          client.send(const Oops('You can only invite your friends.'));
          return;
        }
        if (room == null || room.phase != RoomPhase.lobby) {
          client.send(const Oops('Open a table first, then invite friends to '
              'it.'));
          return;
        }
        final friend = online[id];
        if (friend == null) {
          client.send(
              const Oops('They are not online right now.', code: 'offline'));
          return;
        }
        final them = players[id];
        friend.send(Invite(
          from: _friendInfo(me, nickname: them?.friends[me.id]),
          code: room.code,
        ));

      case MakeTransferCode():
        _transfers.removeWhere((_, t) => !_now().isBefore(t.expires));
        var code = _transferToken();
        while (_transfers.containsKey(code)) {
          code = _transferToken();
        }
        _transfers[code] =
            (playerId: client.playerId, expires: _now().add(transferLife));
        client.send(TransferCode(code: code, minutes: transferLife.inMinutes));

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
        _sendProfile(record.id);
        _tellFriends(record.id);

      case Hello() ||
            Welcome() ||
            RoomUpdate() ||
            MatchUpdate() ||
            QueueUpdate() ||
            ProfileUpdate() ||
            Invite() ||
            TransferCode() ||
            Reaction() ||
            Said() ||
            Oops() ||
            Pong():
        client.send(const Oops('the server does not accept that message'));
    }
  }

  // --- profiles and friends ----------------------------------------------

  /// A player redeeming a transfer code made on their other phone. The code
  /// works once.
  PlayerRecord? redeemTransfer(String code) {
    final t = _transfers.remove(code.trim().toUpperCase().replaceAll('-', ''));
    if (t == null || !_now().isBefore(t.expires)) return null;
    return players[t.playerId];
  }

  String _transferToken() {
    const alphabet = 'BCDFGHJKLMNPQRSTVWXZ23456789';
    return List.generate(8, (_) => alphabet[_random.nextInt(alphabet.length)])
        .join();
  }

  void _befriend(PlayerRecord a, PlayerRecord b) {
    a.incoming.remove(b.id);
    a.outgoing.remove(b.id);
    b.incoming.remove(a.id);
    b.outgoing.remove(a.id);
    a.friends.putIfAbsent(b.id, () => null);
    b.friends.putIfAbsent(a.id, () => null);
  }

  FriendInfo _friendInfo(PlayerRecord p, {String? nickname}) => FriendInfo(
        playerId: p.id,
        name: p.name,
        nickname: nickname,
        online: online.containsKey(p.id),
        level: p.level,
      );

  ProfileInfo? profileFor(String playerId) {
    final me = players[playerId];
    if (me == null) return null;
    List<FriendInfo> people(Iterable<String> ids) => [
          for (final id in ids)
            if (players[id] case final p?)
              _friendInfo(p, nickname: me.friends[id]),
        ];
    final friends = people(me.friends.keys)
      ..sort((a, b) {
        if (a.online != b.online) return a.online ? -1 : 1;
        return a.shownName.toLowerCase().compareTo(b.shownName.toLowerCase());
      });
    return ProfileInfo(
      playerId: me.id,
      name: me.name,
      friendCode: me.friendCode,
      xp: me.xp,
      played: me.played,
      won: me.won,
      friends: friends,
      incoming: people(me.incoming),
      outgoing: people(me.outgoing),
      history: me.history,
    );
  }

  void _sendProfile(String playerId) {
    final client = online[playerId];
    final profile = profileFor(playerId);
    if (client != null && profile != null) {
      client.send(ProfileUpdate(profile));
    }
  }

  /// Friends who are online see a change in [playerId]: coming or going, a
  /// new name, a new level.
  void _tellFriends(String playerId) {
    final me = players[playerId];
    if (me == null) return;
    for (final id in me.friends.keys) {
      if (online.containsKey(id)) _sendProfile(id);
    }
  }

  /// Experience for a finished match: something for turning up, more for
  /// finishing higher, most for winning.
  static int xpFor(
          {required int place, required int players, required bool won}) =>
      20 + (won ? 30 : 0) + (players - place) * 5;

  /// Writes a finished match into the record of every person who played it.
  void _recordResult(Room room) {
    final state = room.game;
    if (state == null || !state.isOver) return;
    final team = state.winningTeam;
    final order = [
      ...state.finishOrder,
      for (var s = 0; s < state.rules.players; s++)
        if (!state.finishOrder.contains(s)) s,
    ];
    String nameAt(Seat seat) =>
        seat.client?.displayName ??
        seat.heldName ??
        (seat.isComputer ? 'Computer' : 'Player');

    for (final seat in room.seats) {
      final id = seat.client?.playerId ?? seat.heldFor;
      final record = id == null ? null : players[id];
      if (record == null) continue;
      final won = team != null
          ? state.rules.teams![team].contains(seat.index)
          : state.winner == seat.index;
      final place =
          team != null ? (won ? 1 : 2) : order.indexOf(seat.index) + 1;
      final xp = xpFor(place: place, players: state.rules.players, won: won);
      final levelBefore = record.level;
      record
        ..xp += xp
        ..played += 1
        ..won += won ? 1 : 0
        ..addMatch(MatchSummary(
          at: _now().toUtc(),
          players: state.rules.players,
          place: place,
          won: won,
          xp: xp,
          opponents: [
            for (final other in room.seats)
              if (other != seat) nameAt(other),
          ],
        ));
      _sendProfile(record.id);
      if (record.level != levelBefore) _tellFriends(record.id);
    }
    players.changed();
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
    room.onFinished = _recordResult;
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
  /// A player has a live connection. Their friends see them come online.
  void connected(Client client) {
    online[client.playerId] = client;
    _tellFriends(client.playerId);
  }

  void disconnected(String playerId) {
    if (online.remove(playerId) != null) _tellFriends(playerId);
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

/// A transfer code that is wrong, used, or out of date. Answered rather than
/// quietly minting somebody new, so the player knows to make another.
class BadTransfer extends Identity {}

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

  // Carried over from another phone: the same player, with a secret of its
  // own for this one.
  final transfer = hello.transfer;
  if (transfer != null) {
    final carried = hub.redeemTransfer(transfer);
    if (carried != null) {
      return Identified(carried, secret: hub.players.addDevice(carried));
    }
    return BadTransfer();
  }

  final known = hub.players.verify(hello.guestId?.trim(), hello.secret);
  if (known != null) return Identified(known);
  final (fresh, secret) = hub.players.mint(name: hello.displayName);
  return Identified(fresh, secret: secret);
}

/// Convenience for tests and tooling: JSON-encode any envelope.
String encode(Envelope e) => e.encode();

/// Pretty-prints a room for logs.
String describe(Room room) => jsonEncode(room.toInfo().toJson());
