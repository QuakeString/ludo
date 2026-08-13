import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_protocol/ludo_protocol.dart';
import 'package:ludo_server/ludo_server.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/io.dart';

/// A real client over a real socket, so the wiring between sockets, identity
/// and the hub is covered — the part fake clients in `match_test.dart` cannot
/// reach.
class Player {
  Player(this.channel) {
    _sub = channel.stream.listen((raw) {
      _queue.add(Envelope.decode(raw as String));
      _arrived?.complete();
      _arrived = null;
    });
  }

  final IOWebSocketChannel channel;

  /// Messages that have arrived and not yet been claimed. [next] takes from
  /// here, so a test can never be handed a stale update it already read.
  final List<Envelope> _queue = [];
  Completer<void>? _arrived;
  late final StreamSubscription<dynamic> _sub;

  void send(Envelope m) => channel.sink.add(m.encode());

  /// Waits for the next unclaimed message of a given kind, so tests read as a
  /// conversation rather than a pile of sleeps.
  Future<T> next<T extends Envelope>({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final i = _queue.indexWhere((m) => m is T);
      if (i >= 0) return _queue.removeAt(i) as T;

      final left = deadline.difference(DateTime.now());
      if (left.isNegative) {
        throw TimeoutException('waited for a $T that never came');
      }
      final waiter = _arrived ??= Completer<void>();
      await waiter.future.timeout(left, onTimeout: () {});
    }
  }

  bool get quiet => _queue.isEmpty;

  Future<void> close() async {
    await _sub.cancel();
    await channel.sink.close();
  }
}

Future<(Player, Welcome)> connect(RunningServer server,
    {String? guestId, String? name}) async {
  final channel = IOWebSocketChannel.connect(server.webSocketUri);
  await channel.ready;
  final player = Player(channel);
  player.send(Hello(guestId: guestId, displayName: name));
  return (player, await player.next<Welcome>());
}

void main() {
  late RunningServer server;

  setUp(() async {
    server = await startServer(port: 0, address: '127.0.0.1');
  });

  tearDown(() async => server.close());

  test('a client is welcomed with an anonymous identity, no account needed',
      () async {
    final channel = IOWebSocketChannel.connect(server.webSocketUri);
    await channel.ready;
    final player = Player(channel);
    player.send(const Hello());

    final welcome = await player.next<Welcome>();
    expect(welcome.playerId, isNotEmpty);
    expect(welcome.displayName, startsWith('Guest_'));
    await player.close();
  });

  test('a returning guest keeps the identity it was given', () async {
    final (first, welcome) =
        await connect(server, guestId: 'g-known', name: 'Rajat');
    expect(welcome.playerId, 'g-known');
    expect(welcome.displayName, 'Rajat');
    await first.close();

    final (again, second) =
        await connect(server, guestId: 'g-known', name: 'Rajat');
    expect(second.playerId, 'g-known',
        reason: 'coming back must not mint a new identity');
    await again.close();
  });

  test('two players meet in a room and play a move over the wire', () async {
    final (host, _) = await connect(server, guestId: 'g-host', name: 'Rajat');
    final (guest, _) = await connect(server, guestId: 'g-guest', name: 'Ammu');

    host.send(
        const CreateRoom(rules: RuleConfig(players: 2, tokensPerPlayer: 2)));
    final created = await host.next<RoomUpdate>();
    final code = created.room.code;
    expect(code, hasLength(6));

    guest.send(JoinRoom(code));
    final joined = await guest.next<RoomUpdate>();
    expect(joined.room.seats.where((s) => s.playerId != null), hasLength(2));

    host.send(const StartMatch());
    final hostView = await host.next<MatchUpdate>();
    final guestView = await guest.next<MatchUpdate>();
    expect(hostView.yourSeat, 0);
    expect(guestView.yourSeat, 1);
    expect(hostView.state.fingerprint(), guestView.state.fingerprint());

    host.send(Play.roll());
    final rolled = await host.next<MatchUpdate>();
    expect(rolled.state.dice, isNotNull,
        reason: 'the server rolls, not the client');

    await host.close();
    await guest.close();
  });

  test('the server refuses a move from the wrong player', () async {
    final (host, _) = await connect(server, guestId: 'g-h2');
    final (guest, _) = await connect(server, guestId: 'g-g2');

    host.send(
        const CreateRoom(rules: RuleConfig(players: 2, tokensPerPlayer: 2)));
    final code = (await host.next<RoomUpdate>()).room.code;
    guest.send(JoinRoom(code));
    await guest.next<RoomUpdate>();
    host.send(const StartMatch());
    await guest.next<MatchUpdate>();

    guest.send(Play.roll()); // not their turn
    final oops = await guest.next<Oops>();
    expect(oops.message, contains('not your turn'));

    await host.close();
    await guest.close();
  });

  test('a malformed frame is answered, not fatal', () async {
    final (player, _) = await connect(server, guestId: 'g-junk');
    player.channel.sink.add('this is not json');
    final oops = await player.next<Oops>();
    expect(oops.message, contains('could not read'));

    // The connection still works afterwards.
    player.send(const Ping());
    expect(await player.next<Pong>(), isA<Pong>());
    await player.close();
  });

  test('the health endpoint answers, so a container can watch it', () async {
    final client = HttpClient();
    try {
      final request = await client.get('127.0.0.1', server.port, '/health');
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(await response.transform(utf8.decoder).join(), 'ok');
    } finally {
      client.close();
    }
  });
}
