import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_protocol/ludo_protocol.dart';
import 'package:ludo_server/ludo_server.dart';
import 'package:test/test.dart';

class FakeClient implements Client {
  FakeClient(this.record);

  final PlayerRecord record;

  @override
  String get playerId => record.id;
  @override
  String get displayName => record.name;
  @override
  String? get avatar => record.avatar;

  final List<Envelope> inbox = [];

  @override
  void send(Envelope message) => inbox.add(message);

  T? last<T extends Envelope>() {
    for (final m in inbox.reversed) {
      if (m is T) return m;
    }
    return null;
  }

  ProfileInfo? get profile => last<ProfileUpdate>()?.profile;
}

class TestClock {
  DateTime now = DateTime.utc(2026, 1, 1);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  late LudoHub hub;
  late TestClock clock;
  late FakeClient ammu;
  late FakeClient rajat;

  FakeClient arrive(String name) {
    final (record, _) = hub.players.mint(name: name);
    final client = FakeClient(record);
    hub.connected(client);
    return client;
  }

  setUp(() {
    clock = TestClock();
    hub = LudoHub(random: Random(5), clock: clock.call);
    ammu = arrive('Ammu');
    rajat = arrive('Rajat');
  });

  void befriend() {
    hub.handle(ammu, AddFriend(rajat.record.friendCode));
    hub.handle(rajat, AnswerFriend(ammu.playerId, accept: true));
  }

  group('friend requests', () {
    test('are sent by friend code and seen on both sides', () {
      hub.handle(ammu, AddFriend(rajat.record.friendCode.toLowerCase()));
      expect(ammu.profile!.outgoing.single.name, 'Rajat');
      expect(rajat.profile!.incoming.single.name, 'Ammu');
      expect(rajat.profile!.friends, isEmpty);
    });

    test('accepted, make friends of both', () {
      befriend();
      expect(ammu.profile!.friends.single.name, 'Rajat');
      expect(rajat.profile!.friends.single.name, 'Ammu');
      expect(rajat.profile!.incoming, isEmpty);
      expect(ammu.profile!.outgoing, isEmpty);
    });

    test('crossing in the post are a yes both ways', () {
      hub.handle(ammu, AddFriend(rajat.record.friendCode));
      hub.handle(rajat, AddFriend(ammu.record.friendCode));
      expect(ammu.profile!.friends, hasLength(1));
      expect(rajat.profile!.friends, hasLength(1));
    });

    test('declined, leave nothing behind', () {
      hub.handle(ammu, AddFriend(rajat.record.friendCode));
      hub.handle(rajat, AnswerFriend(ammu.playerId, accept: false));
      expect(ammu.profile!.outgoing, isEmpty);
      expect(rajat.profile!.incoming, isEmpty);
      expect(ammu.profile!.friends, isEmpty);
    });

    test('to a code nobody has, or your own, are refused', () {
      hub.handle(ammu, const AddFriend('ZZZZZZ'));
      expect(ammu.last<Oops>()?.code, 'nofriend');
      hub.handle(ammu, AddFriend(ammu.record.friendCode));
      expect(ammu.last<Oops>()?.message, contains('own'));
    });
  });

  test('a friend can be removed, from both lists', () {
    befriend();
    hub.handle(ammu, RemoveFriend(rajat.playerId));
    expect(ammu.profile!.friends, isEmpty);
    expect(rajat.profile!.friends, isEmpty);
  });

  test('a nickname is only seen by whoever gave it', () {
    befriend();
    hub.handle(ammu, SetNickname(rajat.playerId, 'Bhaiya'));
    expect(ammu.profile!.friends.single.shownName, 'Bhaiya');
    expect(ammu.profile!.friends.single.name, 'Rajat');
    hub.handle(rajat, const GetProfile());
    expect(rajat.profile!.friends.single.nickname, isNull);
  });

  test('friends see each other come and go', () {
    befriend();
    expect(ammu.profile!.friends.single.online, isTrue);
    hub.disconnected(rajat.playerId);
    expect(ammu.profile!.friends.single.online, isFalse);
  });

  group('inviting a friend', () {
    test('sends them the table to join', () {
      befriend();
      hub.handle(ammu, const CreateRoom(rules: RuleConfig(players: 2)));
      final code = ammu.last<RoomUpdate>()!.room.code;
      hub.handle(ammu, InviteFriend(rajat.playerId));
      final invite = rajat.last<Invite>()!;
      expect(invite.code, code);
      expect(invite.from.name, 'Ammu');
    });

    test('needs a table, a friend, and the friend online', () {
      hub.handle(ammu, InviteFriend(rajat.playerId));
      expect(ammu.last<Oops>()?.message, contains('friends'));

      befriend();
      hub.handle(ammu, InviteFriend(rajat.playerId));
      expect(ammu.last<Oops>()?.message, contains('table'));

      hub.handle(ammu, const CreateRoom(rules: RuleConfig(players: 2)));
      hub.disconnected(rajat.playerId);
      hub.handle(ammu, InviteFriend(rajat.playerId));
      expect(ammu.last<Oops>()?.code, 'offline');
    });
  });

  group('a finished match', () {
    void playOut() {
      hub.handle(ammu, const CreateRoom(rules: RuleConfig(players: 2)));
      final code = ammu.last<RoomUpdate>()!.room.code;
      hub.handle(rajat, JoinRoom(code));
      hub.handle(ammu, const StartMatch());
      const engine = LudoEngine();
      var guard = 0;
      while (guard++ < 8000) {
        final state = hub.rooms[code]!.game!;
        if (state.isOver) return;
        final who = state.turn == 0 ? ammu : rajat;
        if (state.awaitingRoll) {
          hub.handle(who, Play.roll());
          continue;
        }
        final moves = engine.legalMoves(state);
        hub.handle(who, moves.isEmpty ? Play.pass() : Play.move(moves.first));
      }
      fail('the match never finished');
    }

    test('is written into both players\' records, once', () {
      playOut();
      final a = ammu.profile!;
      final r = rajat.profile!;
      expect(a.played, 1);
      expect(r.played, 1);
      expect(a.won + r.won, 1);
      final winner = a.won == 1 ? a : r;
      final loser = a.won == 1 ? r : a;
      expect(winner.history.single.place, 1);
      expect(loser.history.single.place, 2);
      expect(winner.xp, greaterThan(loser.xp));
      expect(winner.history.single.opponents, [loser.name]);
    });

    test('keeps only the most recent matches', () {
      final record = ammu.record;
      for (var i = 0; i < 25; i++) {
        record.addMatch(MatchSummary(
            at: DateTime.utc(2026, 1, 1, 0, i),
            players: 2,
            place: 1,
            won: true,
            xp: 50));
      }
      expect(record.history, hasLength(PlayerRecord.historyLength));
      expect(record.history.first.at.minute, 24);
    });
  });

  test('levels take a little more experience each time', () {
    expect(levelFor(0).level, 1);
    expect(levelFor(99).level, 1);
    expect(levelFor(100).level, 2);
    expect(levelFor(100 + 149).level, 2);
    expect(levelFor(100 + 150).level, 3);
    expect(levelFor(120).into, 20);
  });

  group('moving to another phone', () {
    test('a code made on one phone signs the other in as the same player', () {
      hub.handle(ammu, const MakeTransferCode());
      final code = ammu.last<TransferCode>()!.code;

      final hello = Hello(transfer: code).encode();
      final there = identify(hub, hello);
      expect(there, isA<Identified>());
      there as Identified;
      expect(there.player.id, ammu.playerId);
      expect(there.secret, isNotNull);
      expect(hub.players.verify(ammu.playerId, there.secret), isNotNull,
          reason: 'the new phone has a secret of its own');

      expect(identify(hub, hello), isA<BadTransfer>(),
          reason: 'a code works once');
    });

    test('a code goes stale', () {
      hub.handle(ammu, const MakeTransferCode());
      final code = ammu.last<TransferCode>()!.code;
      clock.advance(const Duration(minutes: 11));
      expect(identify(hub, Hello(transfer: code).encode()), isA<BadTransfer>());
    });
  });

  test('friends, progress and history survive a restart', () async {
    final dir = await Directory.systemTemp.createTemp('ludo-friends');
    final file = File('${dir.path}/players.json');
    final store = PlayerStore(file: file, random: Random(1));
    final (a, _) = store.mint(name: 'Ammu');
    final (b, _) = store.mint(name: 'Rajat');
    a
      ..friends[b.id] = 'Bhaiya'
      ..xp = 340
      ..played = 3
      ..won = 2
      ..addMatch(MatchSummary(
          at: DateTime.utc(2026), players: 4, place: 2, won: false, xp: 30));
    b.incoming.add('someone');
    await store.flush();

    final again = PlayerStore(file: file);
    await again.load();
    final a2 = again[a.id]!;
    expect(a2.friends, {b.id: 'Bhaiya'});
    expect(a2.xp, 340);
    expect(a2.won, 2);
    expect(a2.history.single.place, 2);
    expect(again[b.id]!.incoming, {'someone'});
    expect(again.byFriendCode(a.friendCode)?.id, a.id);
    expect(jsonDecode(await file.readAsString()), isA<Map>());
    await dir.delete(recursive: true);
  });

  test('an old data file with one secret per player still loads', () async {
    final dir = await Directory.systemTemp.createTemp('ludo-old');
    final file = File('${dir.path}/players.json');
    await file.writeAsString(jsonEncode({
      'players': [
        {
          'id': 'gold',
          'secret': PlayerStore.hashSecret('s3cret'),
          'name': 'Old',
          'chosen': true,
        }
      ]
    }));
    final store = PlayerStore(file: file);
    await store.load();
    expect(store.verify('gold', 's3cret')?.name, 'Old');
    expect(store['gold']!.friendCode, hasLength(6),
        reason: 'old players are given a friend code');
    await dir.delete(recursive: true);
  });
}
