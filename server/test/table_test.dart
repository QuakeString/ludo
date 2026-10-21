import 'dart:math';

import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_protocol/ludo_protocol.dart';
import 'package:ludo_server/ludo_server.dart';
import 'package:test/test.dart';

/// Records what it is sent. The same idea as in match_test, kept separate so
/// each file reads on its own.
class FakeClient implements Client {
  FakeClient(this.playerId, this.displayName);

  @override
  final String playerId;
  @override
  String displayName;

  @override
  String? avatar;

  final List<Envelope> inbox = [];

  @override
  void send(Envelope message) => inbox.add(message);

  T? last<T extends Envelope>() {
    for (final m in inbox.reversed) {
      if (m is T) return m;
    }
    return null;
  }
}

class TestClock {
  DateTime now = DateTime.utc(2026, 1, 1);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  const twoSeats = RuleConfig(players: 2, tokensPerPlayer: 2);
  const engine = LudoEngine();

  late LudoHub hub;
  late TestClock clock;
  late FakeClient host;
  late FakeClient guest;

  setUp(() {
    clock = TestClock();
    hub = LudoHub(random: Random(9), clock: clock.call);
    host = FakeClient('p-host', 'Rajat');
    guest = FakeClient('p-guest', 'Ammu');
  });

  String startTwo({RuleConfig rules = twoSeats}) {
    hub.handle(host, CreateRoom(rules: rules));
    final code = host.last<RoomUpdate>()!.room.code;
    hub.handle(guest, JoinRoom(code));
    hub.handle(host, const StartMatch());
    return code;
  }

  void playOut(String code) {
    var guard = 0;
    while (guard++ < 4000) {
      final state = hub.rooms[code]!.game!;
      if (state.isOver) return;
      final who = state.turn == 0 ? host : guest;
      if (state.awaitingRoll) {
        hub.handle(who, Play.roll());
        continue;
      }
      final moves = engine.legalMoves(state);
      hub.handle(who, moves.isEmpty ? Play.pass() : Play.move(moves.first));
    }
  }

  group('a dropped seat', () {
    test('goes back to its owner and nobody else', () {
      final code = startTwo();
      hub.disconnected('p-guest');

      final stranger = FakeClient('p-stranger', 'Sagor');
      hub.handle(stranger, JoinRoom(code));
      expect(stranger.last<Oops>()?.code, 'full');
      expect(hub.rooms[code]!.seats[1].client, isNull);

      final back = FakeClient('p-guest', 'Ammu');
      hub.handle(back, JoinRoom(code));
      expect(hub.rooms[code]!.seats[1].client?.playerId, 'p-guest');
      expect(back.last<MatchUpdate>()?.yourSeat, 1);
    });

    test('still shows whose it is while they are away', () {
      final code = startTwo();
      hub.disconnected('p-guest');
      final seat = host.last<RoomUpdate>()!.room.seats[1];
      expect(seat.displayName, 'Ammu');
      expect(seat.connected, isFalse);
      expect(hub.rooms[code], isNotNull);
    });

    test('is offered back on arrival while it is held', () {
      final code = startTwo();
      hub.disconnected('p-guest');
      final record = PlayerRecord(id: 'p-guest', secretHash: '', name: 'Ammu');
      expect(hub.welcomeFor(record).rejoin, code);

      clock.advance(const Duration(minutes: 6));
      hub.tick();
      expect(hub.welcomeFor(record).rejoin, isNull,
          reason: 'once the computer has the seat there is nothing to rejoin');
      expect(hub.roomOf('p-guest'), isNull);
    });

    test('survives every human dropping at once', () {
      final code = startTwo();
      hub.disconnected('p-host');
      hub.disconnected('p-guest');
      hub.tick();
      expect(hub.rooms[code], isNotNull);

      final back = FakeClient('p-host', 'Rajat');
      hub.handle(back, JoinRoom(code));
      expect(hub.rooms[code]!.seats[0].client?.playerId, 'p-host',
          reason: 'coming back to the only table you are at must not close it');
    });
  });

  group('rematch', () {
    test('only once the match is over, and only for the host', () {
      final code = startTwo();
      hub.handle(host, const Rematch());
      expect(host.last<Oops>()?.message, contains('not over'));

      playOut(code);
      expect(hub.rooms[code]!.phase, RoomPhase.finished);
      hub.handle(guest, const Rematch());
      expect(guest.last<Oops>()?.message, contains('host'));
    });

    test('deals a fresh game to the same seats', () {
      final code = startTwo();
      playOut(code);
      final first = hub.rooms[code]!.game!;

      hub.handle(host, const Rematch());
      final room = hub.rooms[code]!;
      expect(room.phase, RoomPhase.playing);
      expect(room.game!.isOver, isFalse);
      expect(room.game!.fingerprint(), isNot(first.fingerprint()));
      expect(host.last<MatchUpdate>()!.yourSeat, 0);
      expect(guest.last<MatchUpdate>()!.yourSeat, 1);
      expect(guest.last<MatchUpdate>()!.state.isOver, isFalse);
    });

    test('gives a seat whose player has gone to the computer', () {
      final code = startTwo();
      playOut(code);
      hub.handle(guest, const LeaveRoom());
      hub.handle(host, const Rematch());
      expect(hub.rooms[code]!.seats[1].isComputer, isTrue);
    });

    test('passes to whoever is left when the host goes', () {
      final code = startTwo();
      playOut(code);
      hub.handle(host, const LeaveRoom());
      expect(hub.rooms[code]!.hostId, 'p-guest');
      hub.handle(guest, const Rematch());
      expect(hub.rooms[code]!.phase, RoomPhase.playing);
    });
  });

  group('reactions', () {
    test('reach everyone at the table, from the right seat', () {
      startTwo();
      hub.handle(guest, const React(2));
      final heard = host.last<Reaction>();
      expect(heard?.seat, 1);
      expect(heard?.emoji, reactions[2]);
    });

    test('cannot be sent faster than one a moment', () {
      startTwo();
      hub.handle(guest, const React(0));
      hub.handle(guest, const React(1));
      expect(host.inbox.whereType<Reaction>(), hasLength(1));

      clock.advance(const Duration(seconds: 2));
      hub.handle(guest, const React(1));
      expect(host.inbox.whereType<Reaction>(), hasLength(2));
    });

    test('outside the fixed set are refused', () {
      startTwo();
      hub.handle(guest, const React(99));
      expect(guest.last<Oops>(), isNotNull);
      expect(host.inbox.whereType<Reaction>(), isEmpty);
    });
  });

  group('pairing up', () {
    const fours = RuleConfig(
      players: 4,
      tokensPerPlayer: 2,
      teams: [
        [0, 2],
        [1, 3],
      ],
    );

    test('the host moves people between seats, and so between teams', () {
      hub.handle(host, const CreateRoom(rules: fours));
      final code = host.last<RoomUpdate>()!.room.code;
      hub.handle(guest, JoinRoom(code));
      expect(host.last<RoomUpdate>()!.room.seats[1].playerId, 'p-guest');

      // Host in seat 0, guest in 1: opponents. Move the guest opposite.
      hub.handle(host, const SwapSeats(1, 2));
      final seats = guest.last<RoomUpdate>()!.room.seats;
      expect(seats[1].playerId, isNull);
      expect(seats[2].playerId, 'p-guest');
      expect(
          hub.rooms[code]!.rules.teamOf(0), hub.rooms[code]!.rules.teamOf(2));

      // And the match deals the guest in at their new seat.
      hub.handle(host, const AddComputer(seat: 1));
      hub.handle(host, const AddComputer(seat: 3));
      hub.handle(host, const StartMatch());
      expect(guest.last<MatchUpdate>()!.yourSeat, 2);
    });

    test('only the host, and only before the start', () {
      hub.handle(host, const CreateRoom(rules: fours));
      final code = host.last<RoomUpdate>()!.room.code;
      hub.handle(guest, JoinRoom(code));
      hub.handle(guest, const SwapSeats(0, 1));
      expect(guest.last<Oops>(), isNotNull);
      expect(hub.rooms[code]!.seats[0].client?.playerId, 'p-host');
    });
  });

  group('pictures', () {
    test('a player\'s picture shows on their seat at the table', () {
      final (record, _) = hub.players.mint();
      final me = FakeClient(record.id, record.name);
      hub.handle(me, const SetAvatar('a:5'));
      expect(record.avatar, 'a:5');
      me.avatar = record.avatar;
      hub.handle(me, const CreateRoom(rules: twoSeats));
      expect(me.last<RoomUpdate>()!.room.seats[0].avatar, 'a:5');
    });

    test('anything that is not a picture is refused', () {
      final (record, _) = hub.players.mint();
      final me = FakeClient(record.id, record.name);
      hub.handle(me, const SetAvatar('p:<img onerror=alert(1)>'));
      expect(me.last<Oops>(), isNotNull);
      expect(record.avatar, isNull);
    });
  });

  group('chat', () {
    test('reaches everyone at the table, from the right seat', () {
      startTwo();
      hub.handle(guest, const Say('  nice   one 🎉 '));
      final heard = host.last<Said>();
      expect(heard?.seat, 1);
      expect(heard?.text, 'nice one 🎉');
      expect(guest.last<Said>()?.text, 'nice one 🎉');
    });

    test('is cut to length and never sent empty', () {
      startTwo();
      hub.handle(guest, const Say('   '));
      expect(host.inbox.whereType<Said>(), isEmpty);
      hub.handle(guest, Say('😂' * 400));
      expect(host.last<Said>()!.text.runes, hasLength(chatLimit));
    });

    test('cannot be sent faster than a line a moment', () {
      startTwo();
      hub.handle(guest, const Say('one'));
      hub.handle(guest, const Say('two'));
      expect(host.inbox.whereType<Said>(), hasLength(1));
      clock.advance(const Duration(seconds: 1));
      hub.handle(guest, const Say('three'));
      expect(host.inbox.whereType<Said>(), hasLength(2));
    });
  });

  group('names', () {
    test('a chosen name is tidied, kept, and shown at the table', () {
      final (record, _) = hub.players.mint();
      final me = FakeClient(record.id, record.name);
      hub.handle(me, const CreateRoom(rules: twoSeats));
      hub.handle(me, const SetName('  Mozammel!! '));

      final welcome = me.last<Welcome>()!;
      expect(welcome.displayName, 'Mozammel');
      expect(welcome.chosenName, isTrue);
      expect(hub.players[record.id]!.name, 'Mozammel');
    });

    test('an unusable name is refused', () {
      final (record, _) = hub.players.mint();
      final me = FakeClient(record.id, record.name);
      hub.handle(me, const SetName('!'));
      expect(me.last<Oops>()?.code, 'name');
      expect(hub.players[record.id]!.chosenName, isFalse);
    });
  });

  test('the invite page hands over to the app and offers it', () {
    final page = invitePage('ktp-4wq');
    expect(page, contains('ludo://join/KTP4WQ'));
    expect(page, contains(appDownload));
  });
}
