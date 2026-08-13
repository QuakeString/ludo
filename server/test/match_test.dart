import 'dart:math';

import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_protocol/ludo_protocol.dart';
import 'package:ludo_server/ludo_server.dart';
import 'package:test/test.dart';

/// A client that records what it is sent, so a whole match can be played
/// without opening a socket.
class FakeClient implements Client {
  FakeClient(this.playerId, this.displayName);

  @override
  final String playerId;
  @override
  final String displayName;

  final List<Envelope> inbox = [];

  @override
  void send(Envelope message) => inbox.add(message);

  T? last<T extends Envelope>() {
    for (final m in inbox.reversed) {
      if (m is T) return m;
    }
    return null;
  }

  MatchUpdate? get match => last<MatchUpdate>();
  RoomUpdate? get room => last<RoomUpdate>();
  Oops? get lastError => last<Oops>();
  void clear() => inbox.clear();
}

/// A clock the test moves by hand, so turn-timer behaviour is exact rather
/// than a race against real seconds.
class TestClock {
  DateTime now = DateTime.utc(2026, 1, 1);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  const twoSeats = RuleConfig(players: 2, tokensPerPlayer: 2);

  late LudoHub hub;
  late TestClock clock;
  late FakeClient host;
  late FakeClient guest;

  setUp(() {
    clock = TestClock();
    hub = LudoHub(random: Random(4), clock: clock.call);
    host = FakeClient('p-host', 'Rajat');
    guest = FakeClient('p-guest', 'Ammu');
  });

  String openRoom({RuleConfig rules = twoSeats, bool fillAi = true}) {
    hub.handle(host, CreateRoom(rules: rules, fillEmptySeatsWithAI: fillAi));
    return host.room!.room.code;
  }

  group('rooms', () {
    test('a host creates a room and gets a readable code', () {
      final code = openRoom();
      expect(code, hasLength(6));
      expect(code, matches(RegExp(r'^[BCDFGHJKLMNPQRSTVWXZ2-9]+$')),
          reason: 'codes must avoid letters that look like digits');
      expect(host.room!.room.seats.first.playerId, 'p-host');
    });

    test('a second player joins by code and both see the room', () {
      final code = openRoom();
      hub.handle(guest, JoinRoom(code));
      expect(guest.room!.room.seats, hasLength(2));
      expect(host.room!.room.seats[1].playerId, 'p-guest');
    });

    test('the code is forgiving about case and dashes', () {
      final code = openRoom();
      hub.handle(
          guest,
          JoinRoom(
              '${code.substring(0, 3)}-${code.substring(3)}'.toLowerCase()));
      expect(guest.lastError, isNull);
      expect(guest.room, isNotNull);
    });

    test('a wrong code is refused with a reason', () {
      hub.handle(guest, const JoinRoom('ZZZZZZ'));
      expect(guest.lastError?.code, 'noroom');
    });

    test('a full room turns the next player away', () {
      final code = openRoom();
      hub.handle(guest, JoinRoom(code));
      final third = FakeClient('p3', 'Sagor');
      hub.handle(third, JoinRoom(code));
      expect(third.lastError?.code, 'full');
    });

    test('only the host may start the match', () {
      final code = openRoom();
      hub.handle(guest, JoinRoom(code));
      hub.handle(guest, const StartMatch());
      expect(guest.lastError?.message, contains('host'));
      expect(guest.match, isNull);
    });

    test('an invalid rule set is refused before a room exists', () {
      hub.handle(
          host,
          const CreateRoom(
              rules: RuleConfig(players: 4, teams: [
            [0, 1],
            [2]
          ])));
      expect(host.lastError?.code, 'rules');
      expect(hub.rooms, isEmpty);
    });
  });

  group('playing', () {
    test('both players are dealt the same position, from their own seat', () {
      final code = openRoom();
      hub.handle(guest, JoinRoom(code));
      hub.handle(host, const StartMatch());

      expect(host.match!.yourSeat, 0);
      expect(guest.match!.yourSeat, 1);
      expect(guest.match!.state.fingerprint(), host.match!.state.fingerprint(),
          reason: 'both sides must see one truth');
    });

    test('a player cannot move out of turn', () {
      final code = openRoom();
      hub.handle(guest, JoinRoom(code));
      hub.handle(host, const StartMatch());

      guest.clear();
      hub.handle(guest, Play.roll());
      expect(guest.lastError?.message, contains('not your turn'));
    });

    test('an invented move is refused', () {
      final code = openRoom();
      hub.handle(guest, JoinRoom(code));
      hub.handle(host, const StartMatch());
      hub.handle(host, Play.roll());

      host.clear();
      hub.handle(host, const Play(action: 'move', tokenId: 0, toProgress: 40));
      expect(host.lastError, isNotNull,
          reason: 'the server must not take the client\'s word for a move');
    });

    test('two clients can play a whole match through the server', () {
      final code = openRoom();
      hub.handle(guest, JoinRoom(code));
      hub.handle(host, const StartMatch());

      const engine = LudoEngine();
      var guard = 0;
      while (guard++ < 4000) {
        final room = hub.rooms[code]!;
        final state = room.game!;
        if (state.isOver) break;

        final who = state.turn == 0 ? host : guest;
        if (state.awaitingRoll) {
          hub.handle(who, Play.roll());
          continue;
        }
        final moves = engine.legalMoves(state);
        hub.handle(who, moves.isEmpty ? Play.pass() : Play.move(moves.first));
      }

      final room = hub.rooms[code]!;
      expect(room.game!.isOver, isTrue, reason: 'the match never finished');
      expect(room.phase, RoomPhase.finished);
      expect(host.match!.state.fingerprint(), guest.match!.state.fingerprint());
    });

    test('computer seats play themselves without anyone asking', () {
      hub.handle(host, const CreateRoom(rules: twoSeats));
      final code = host.room!.room.code;
      hub.handle(host, const AddComputer(seat: 1, level: AiLevel.normal));
      hub.handle(host, const StartMatch());

      final room = hub.rooms[code]!;
      // The computer's turns are taken as soon as they come round.
      const engine = LudoEngine();
      var guard = 0;
      while (guard++ < 4000 && !room.game!.isOver) {
        if (room.game!.turn != 0) break; // never left on the computer's turn
        if (room.game!.awaitingRoll) {
          hub.handle(host, Play.roll());
          continue;
        }
        final moves = engine.legalMoves(room.game!);
        hub.handle(host, moves.isEmpty ? Play.pass() : Play.move(moves.first));
      }
      expect(room.game!.isOver || room.game!.turn == 0, isTrue,
          reason: 'the table should never be left waiting on a computer seat');
    });
  });

  group('when somebody drops', () {
    test('their seat is held and the game carries on without them', () {
      final code = openRoom();
      hub.handle(guest, JoinRoom(code));
      hub.handle(host, const StartMatch());
      final room = hub.rooms[code]!;

      hub.disconnected('p-guest');
      expect(room.seats[1].connected, isFalse);
      expect(room.seats[1].droppedAt, isNotNull);
      expect(hub.rooms.containsKey(code), isTrue,
          reason: 'the room must outlive a dropped player');

      // The table keeps moving: the server covers the empty seat. The host only
      // ever plays their own turns, so if the absent seat were waited on rather
      // than played for, the game would stop dead on turn 1.
      final before = room.game!.tokens.where((t) => t.owner == 1).toList();
      const engine = LudoEngine();
      var guard = 0;
      while (guard++ < 400 && room.game!.turn == 0 && !room.game!.isOver) {
        if (room.game!.awaitingRoll) {
          hub.handle(host, Play.roll());
        } else {
          final moves = engine.legalMoves(room.game!);
          hub.handle(
              host, moves.isEmpty ? Play.pass() : Play.move(moves.first));
        }
      }

      final after = room.game!.tokens.where((t) => t.owner == 1).toList();
      expect(after.map((t) => t.progress).toList(),
          isNot(before.map((t) => t.progress).toList()),
          reason: 'the absent seat should be played for, not waited on');
      // Control came back to the host, unless the seat being covered went and
      // won the game — which is a perfectly good way for it to have been
      // played for.
      expect(room.game!.turn == 0 || room.game!.isOver, isTrue,
          reason: 'the table must not be left stuck on the absent seat');
      if (room.game!.isOver) expect(room.phase, RoomPhase.finished);
    });

    test('they get their own seat back on return', () {
      final code = openRoom();
      hub.handle(guest, JoinRoom(code));
      hub.handle(host, const StartMatch());

      hub.disconnected('p-guest');
      final returning = FakeClient('p-guest', 'Ammu');
      hub.handle(returning, JoinRoom(code));

      final room = hub.rooms[code]!;
      expect(room.seats[1].client?.playerId, 'p-guest');
      expect(room.seats[1].connected, isTrue);
      expect(returning.match, isNotNull,
          reason: 'a returning player needs the position straight away');
    });

    test('a seat held past five minutes is given to the computer', () {
      final code = openRoom();
      hub.handle(guest, JoinRoom(code));
      hub.handle(host, const StartMatch());
      hub.disconnected('p-guest');

      clock.advance(const Duration(minutes: 6));
      hub.tick();

      expect(hub.rooms[code]!.seats[1].isComputer, isTrue);
    });

    test('an empty lobby is cleaned up', () {
      final code = openRoom();
      hub.disconnected('p-host');
      expect(hub.rooms.containsKey(code), isFalse);
    });
  });

  group('the turn clock', () {
    const timed = RuleConfig(
      players: 2,
      tokensPerPlayer: 2,
      turnTimerDots: 6, // 30 seconds
    );

    test('is off unless the rules ask for it', () {
      final code = openRoom();
      hub.handle(guest, JoinRoom(code));
      hub.handle(host, const StartMatch());
      final before = hub.rooms[code]!.game!.fingerprint();
      clock.advance(const Duration(minutes: 5));
      hub.tick();
      expect(hub.rooms[code]!.game!.fingerprint(), before);
    });

    test('runs out and the server plays for you', () {
      hub.handle(host, const CreateRoom(rules: timed));
      final code = host.room!.room.code;
      hub.handle(guest, JoinRoom(code));
      hub.handle(host, const StartMatch());

      final room = hub.rooms[code]!;
      expect(room.secondsLeft, 30);
      final before = room.game!.fingerprint();

      clock.advance(const Duration(seconds: 31));
      hub.tick();

      expect(room.game!.fingerprint(), isNot(before),
          reason: 'the clock ran out and nothing happened');
      expect(host.match!.autoPlayed, isTrue);
    });

    test('counts down while you think', () {
      hub.handle(host, const CreateRoom(rules: timed));
      final code = host.room!.room.code;
      hub.handle(guest, JoinRoom(code));
      hub.handle(host, const StartMatch());

      clock.advance(const Duration(seconds: 12));
      expect(hub.rooms[code]!.secondsLeft, 18);
    });
  });
}
