@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/net/connection.dart';
import 'package:ludo_app/net/online_session.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_server/ludo_server.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app talking to a real server over a real socket.
///
/// The unit tests either side of this one prove the server is right and the
/// board draws correctly. Only this one proves the two ends actually meet —
/// which is the difference between "online multiplayer is implemented" and
/// "you can play online".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RunningServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    server = await startServer(
      port: 0,
      address: '127.0.0.1',
      // This test plays a whole match as fast as the socket allows, far
      // quicker than any person could, so it gets a limit no person reaches.
      limits: () => RateLimiter(burst: 100000, perSecond: 100000),
    );
  });

  tearDown(() async => server.close());

  /// One player at the table. Each asks for a fresh identity: two clients
  /// with the same one are the same person reconnecting, which is right for a
  /// phone coming back and wrong for two players in one test process.
  Future<OnlineSession> sitDown([String? name]) async {
    final connection = LudoConnection(uri: server.webSocketUri);
    await connection.connect(fresh: true, preferredName: name);
    return OnlineSession(connection);
  }

  /// Waits for something to become true, driven by the session's own updates
  /// rather than by sleeping and hoping.
  Future<void> until(
    OnlineSession session,
    bool Function() done, {
    String what = 'that',
  }) async {
    if (done()) return;
    final finished = Completer<void>();
    void check() {
      if (done() && !finished.isCompleted) finished.complete();
    }

    session.addListener(check);
    try {
      await finished.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('waited for $what'),
      );
    } finally {
      session.removeListener(check);
    }
  }

  test('a guest gets an identity without ever making an account', () async {
    final session = await sitDown();
    expect(session.playerId, isNotEmpty);
    expect(
      session.myName,
      startsWith('Guest_'),
      reason: 'a name is given, not asked for',
    );
    session.dispose();
    await session.connection.dispose();
  });

  test('two people meet by room code and play a real match', () async {
    final host = await sitDown();
    final guest = await sitDown();

    host.createRoom(const RuleConfig(players: 2, tokensPerPlayer: 2));
    await until(host, () => host.room != null, what: 'the room');
    final code = host.room!.code;
    expect(code, hasLength(6));
    expect(host.isHost, isTrue);

    guest.joinRoom(code);
    await until(
      guest,
      () => guest.room != null,
      what: 'the guest to be seated',
    );
    await until(
      host,
      () => host.room!.seats.where((s) => s.playerId != null).length == 2,
      what: 'the host to see the guest',
    );
    expect(guest.isHost, isFalse);

    host.start();
    await until(host, () => host.state != null, what: 'the match to start');
    await until(
      guest,
      () => guest.state != null,
      what: 'the guest\'s position',
    );

    expect(host.yourSeat, 0);
    expect(guest.yourSeat, 1);
    expect(
      host.state!.fingerprint(),
      guest.state!.fingerprint(),
      reason: 'both ends must see one position, not two',
    );
    expect(host.isMyTurn, isTrue);
    expect(guest.isMyTurn, isFalse);

    // The dice are the server's.
    expect(host.state!.dice, isNull);
    host.roll();
    await until(host, () => host.state!.dice != null, what: 'the roll');
    // The guest is a separate socket, so it learns a moment later — wait for
    // it rather than assuming the two arrive together.
    await until(
      guest,
      () => guest.state!.dice != null,
      what: 'the roll to reach the other player',
    );
    expect(
      guest.state!.dice,
      host.state!.dice,
      reason: 'a roll is seen by everyone at the table',
    );

    host.dispose();
    guest.dispose();
    await host.connection.dispose();
    await guest.connection.dispose();
  });

  test('the game plays through to a winner over the wire', () async {
    final host = await sitDown();
    final guest = await sitDown();

    host.createRoom(const RuleConfig(players: 2, tokensPerPlayer: 2));
    await until(host, () => host.room != null, what: 'the room');
    guest.joinRoom(host.room!.code);
    await until(guest, () => guest.room != null, what: 'a seat');
    host.start();
    await until(host, () => host.state != null, what: 'the match');
    await until(guest, () => guest.state != null, what: 'the match');

    const engine = LudoEngine();
    var guard = 0;
    while (guard++ < 4000 && !host.state!.isOver) {
      final onTurn = host.isMyTurn ? host : guest;
      final before = onTurn.state!.fingerprint();
      if (onTurn.state!.awaitingRoll) {
        onTurn.roll();
      } else {
        final moves = engine.legalMoves(onTurn.state!);
        moves.isEmpty ? onTurn.pass() : onTurn.move(moves.first);
      }
      await until(
        onTurn,
        () => onTurn.state!.fingerprint() != before,
        what: 'the server to answer',
      );
    }

    expect(host.state!.isOver, isTrue, reason: 'the match never finished');
    // The winning move reaches the two sockets a moment apart, so let the
    // other player catch up before comparing — the point of the check is that
    // they agree, not that they are notified in lockstep.
    await until(
      guest,
      () => guest.state!.isOver,
      what: 'the guest to see the end',
    );
    expect(
      guest.state!.fingerprint(),
      host.state!.fingerprint(),
      reason: 'both ends must finish on one position',
    );
    expect(guest.state!.winner, host.state!.winner);

    host.dispose();
    guest.dispose();
    await host.connection.dispose();
    await guest.connection.dispose();
  });

  test('a chosen name is the one the table sees', () async {
    final host = await sitDown();
    expect(host.hasChosenName, isFalse);
    host.createRoom(const RuleConfig(players: 2, tokensPerPlayer: 2));
    await until(host, () => host.room != null, what: 'the room');

    host.setName('Mozammel');
    await until(
      host,
      () => host.room!.seats.first.displayName == 'Mozammel',
      what: 'the new name at the table',
    );
    expect(host.myName, 'Mozammel');
    expect(host.hasChosenName, isTrue);

    host.dispose();
    await host.connection.dispose();
  });

  test('a reaction reaches the rest of the table', () async {
    final host = await sitDown();
    final guest = await sitDown();
    host.createRoom(const RuleConfig(players: 2, tokensPerPlayer: 2));
    await until(host, () => host.room != null, what: 'the room');
    guest.joinRoom(host.room!.code);
    await until(guest, () => guest.room != null, what: 'a seat');

    final heard = host.reactions.first;
    guest.react(4);
    final reaction = await heard.timeout(const Duration(seconds: 5));
    expect(reaction.seat, 1);
    expect(reaction.emoji, '🎉');

    host.dispose();
    guest.dispose();
    await host.connection.dispose();
    await guest.connection.dispose();
  });

  test('connecting again is the same player, and finds their seat', () async {
    final host = await sitDown();
    final guest = await sitDown();
    host.createRoom(const RuleConfig(players: 2, tokensPerPlayer: 2));
    await until(host, () => host.room != null, what: 'the room');
    final code = host.room!.code;
    guest.joinRoom(code);
    await until(guest, () => guest.room != null, what: 'a seat');
    host.start();
    await until(guest, () => guest.state != null, what: 'the match');

    final id = guest.playerId;
    await guest.connection.close();
    await until(
      host,
      () => !host.room!.seats[1].connected,
      what: 'the host to see the guest drop',
    );

    final welcome = await guest.connection.connect();
    expect(
      welcome.playerId,
      id,
      reason: 'a dropped signal is not a new player',
    );
    expect(welcome.rejoin, code, reason: 'the seat is still theirs');

    guest.joinRoom(code);
    await until(
      host,
      () => host.room!.seats[1].connected,
      what: 'the guest to be back',
    );
    expect(guest.yourSeat, 1);

    host.dispose();
    guest.dispose();
    await host.connection.dispose();
    await guest.connection.dispose();
  });

  test('two strangers looking for a game are matched', () async {
    final a = await sitDown();
    final b = await sitDown();
    a.quickMatch(2);
    await until(a, () => a.queue?.found == 1, what: 'the queue');
    expect(a.searching, isTrue);

    b.quickMatch(2);
    await until(a, () => a.state != null, what: 'a match for the first');
    await until(b, () => b.state != null, what: 'a match for the second');
    expect(a.searching, isFalse);
    expect({a.yourSeat, b.yourSeat}, {0, 1});
    expect(a.room!.code, b.room!.code);

    a.dispose();
    b.dispose();
    await a.connection.dispose();
    await b.connection.dispose();
  });

  test('two players become friends and one asks the other over', () async {
    final a = await sitDown('Ammu');
    final b = await sitDown('Rajat');
    a.refreshProfile();
    b.refreshProfile();
    await until(a, () => a.profile != null, what: 'a profile');
    await until(b, () => b.profile != null, what: 'a profile');

    a.addFriend(b.profile!.friendCode);
    await until(
      b,
      () => b.profile!.incoming.isNotEmpty,
      what: 'the request to arrive',
    );
    b.answerFriend(a.playerId!, accept: true);
    await until(a, () => a.profile!.friends.isNotEmpty, what: 'the friendship');
    expect(a.profile!.friends.single.name, 'Rajat');
    expect(a.profile!.friends.single.online, isTrue);

    a.createRoom(const RuleConfig(players: 2, tokensPerPlayer: 2));
    await until(a, () => a.room != null, what: 'the room');
    final invited = b.invites.first;
    a.inviteFriend(b.playerId!);
    final invite = await invited.timeout(const Duration(seconds: 5));
    expect(invite.code, a.room!.code);
    expect(invite.from.name, 'Ammu');

    a.dispose();
    b.dispose();
    await a.connection.dispose();
    await b.connection.dispose();
  });

  test('a transfer code carries a player to another phone', () async {
    final first = await sitDown('Ammu');
    first.makeTransferCode();
    await until(first, () => first.transferCode != null, what: 'a code');

    final second = await sitDown();
    expect(second.playerId, isNot(first.playerId));
    await second.useTransferCode(first.transferCode!.code);
    expect(second.playerId, first.playerId);
    expect(second.myName, 'Ammu');

    await expectLater(
      second.useTransferCode(first.transferCode!.code),
      throwsA(anything),
      reason: 'a code works once',
    );
    expect(
      second.playerId,
      first.playerId,
      reason: 'a refused code leaves this phone as it was',
    );

    first.dispose();
    second.dispose();
    await first.connection.dispose();
    await second.connection.dispose();
  });

  test('a player cannot move on somebody else\'s turn', () async {
    final host = await sitDown();
    final guest = await sitDown();

    host.createRoom(const RuleConfig(players: 2, tokensPerPlayer: 2));
    await until(host, () => host.room != null, what: 'the room');
    guest.joinRoom(host.room!.code);
    await until(guest, () => guest.room != null, what: 'a seat');
    host.start();
    await until(guest, () => guest.state != null, what: 'the match');

    guest.roll(); // not their turn
    await until(guest, () => guest.error != null, what: 'the refusal');
    expect(guest.error, contains('not your turn'));
    expect(guest.state!.dice, isNull, reason: 'nothing may have happened');

    host.dispose();
    guest.dispose();
    await host.connection.dispose();
    await guest.connection.dispose();
  });

  test(
    'the host decides whether an empty seat is filled by a computer',
    () async {
      final host = await sitDown();

      host.createRoom(const RuleConfig(players: 2, tokensPerPlayer: 2));
      await until(host, () => host.room != null, what: 'the room');
      expect(
        host.room!.seats[1].isComputer,
        isFalse,
        reason: 'a seat must not fill itself',
      );

      host.addComputer(1, AiLevel.hard);
      await until(
        host,
        () => host.room!.seats[1].isComputer,
        what: 'the computer',
      );

      host.start();
      await until(host, () => host.state != null, what: 'the match');
      expect(host.yourSeat, 0);

      host.dispose();
      await host.connection.dispose();
    },
  );
}
