import 'dart:math';

import 'package:ludo_protocol/ludo_protocol.dart';
import 'package:ludo_server/ludo_server.dart';
import 'package:test/test.dart';

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
}

class TestClock {
  DateTime now = DateTime.utc(2026, 1, 1);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  late LudoHub hub;
  late TestClock clock;
  final people = [for (var i = 0; i < 6; i++) FakeClient('p$i', 'P$i')];

  setUp(() {
    clock = TestClock();
    hub = LudoHub(random: Random(3), clock: clock.call);
    for (final p in people) {
      p.inbox.clear();
    }
  });

  test('two people looking for a two-seat game are dealt one at once', () {
    hub.handle(people[0], const QuickMatch(players: 2));
    expect(people[0].last<QueueUpdate>()?.found, 1);
    expect(hub.rooms, isEmpty);

    hub.handle(people[1], const QuickMatch(players: 2));
    expect(hub.rooms, hasLength(1));
    final room = hub.rooms.values.single;
    expect(room.matchmade, isTrue);
    expect(room.phase, RoomPhase.playing);
    expect(people[0].last<MatchUpdate>()?.yourSeat, 0);
    expect(people[1].last<MatchUpdate>()?.yourSeat, 1);
    expect(people[1].last<QueueUpdate>()?.searching, isFalse);
  });

  test('the queue says how many are waiting and how long is left', () {
    hub.handle(people[0], const QuickMatch(players: 4));
    clock.advance(const Duration(seconds: 5));
    hub.handle(people[1], const QuickMatch(players: 4));
    final update = people[0].last<QueueUpdate>()!;
    expect(update.found, 2);
    expect(update.secondsToFill, 15);
  });

  test('computers fill the empty seats once the wait is up', () {
    hub.handle(people[0], const QuickMatch(players: 4));
    hub.handle(people[1], const QuickMatch(players: 4));
    clock.advance(const Duration(seconds: 19));
    hub.tick();
    expect(hub.rooms, isEmpty);

    clock.advance(const Duration(seconds: 1));
    hub.tick();
    final room = hub.rooms.values.single;
    expect(room.seats.where((s) => s.client != null), hasLength(2));
    expect(room.seats.where((s) => s.isComputer), hasLength(2));
    expect(room.phase, RoomPhase.playing);
  });

  test('the two queues are kept apart', () {
    hub.handle(people[0], const QuickMatch(players: 2));
    hub.handle(people[1], const QuickMatch(players: 4));
    expect(hub.rooms, isEmpty);
  });

  test('cancelling leaves the queue', () {
    hub.handle(people[0], const QuickMatch(players: 2));
    hub.handle(people[0], const CancelMatch());
    expect(people[0].last<QueueUpdate>()?.searching, isFalse);
    hub.handle(people[1], const QuickMatch(players: 2));
    expect(hub.rooms, isEmpty, reason: 'nobody else was waiting');
  });

  test('dropping the connection leaves the queue too', () {
    hub.handle(people[0], const QuickMatch(players: 2));
    hub.disconnected('p0');
    expect(hub.queues[2], isEmpty);
  });

  test('an odd table size is refused', () {
    hub.handle(people[0], const QuickMatch(players: 3));
    expect(people[0].last<Oops>(), isNotNull);
    expect(hub.queues.values.every((q) => q.isEmpty), isTrue);
  });

  test('walking out of a matched game means waiting to be matched again', () {
    hub.handle(people[0], const QuickMatch(players: 2));
    hub.handle(people[1], const QuickMatch(players: 2));
    hub.handle(people[0], const LeaveRoom());

    hub.handle(people[0], const QuickMatch(players: 2));
    expect(people[0].last<Oops>()?.code, 'cooldown');
    expect(hub.queues[2], isEmpty);

    clock.advance(LudoHub.abandonCooldown);
    hub.tick();
    hub.handle(people[0], const QuickMatch(players: 2));
    expect(hub.queues[2], hasLength(1));
  });

  test('leaving a game among friends costs nothing', () {
    hub.handle(people[0], CreateRoom(rules: LudoHub.quickRules(2)));
    final code = people[0].last<RoomUpdate>()!.room.code;
    hub.handle(people[1], JoinRoom(code));
    hub.handle(people[0], const StartMatch());
    hub.handle(people[1], const LeaveRoom());

    hub.handle(people[1], const QuickMatch(players: 2));
    expect(people[1].last<Oops>(), isNull);
    expect(hub.queues[2], hasLength(1));
  });
}
