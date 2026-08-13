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
    server = await startServer(port: 0, address: '127.0.0.1');
  });

  tearDown(() async => server.close());

  var seated = 0;

  /// One player at the table. Each gets a distinct guest id: two clients
  /// claiming the same id are the same person reconnecting, which is right for
  /// a phone coming back and wrong for two players in one test process.
  Future<OnlineSession> sitDown([String? name]) async {
    final connection = LudoConnection(uri: server.webSocketUri);
    await connection.connect(
      guestId: 'g-test-${seated++}',
      preferredName: name,
    );
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
