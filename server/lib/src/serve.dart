import 'dart:async';
import 'dart:io';

import 'package:ludo_protocol/ludo_protocol.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'server.dart';

/// A running game server.
class RunningServer {
  RunningServer(this._http, this._ticker, this.hub);

  final HttpServer _http;
  final Timer _ticker;
  final LudoHub hub;

  int get port => _http.port;
  Uri get webSocketUri => Uri.parse('ws://127.0.0.1:$port/ws');

  Future<void> close() async {
    _ticker.cancel();
    await _http.close(force: true);
  }
}

/// Starts the server.
///
/// Split out of `main` so a test can boot a real one on an ephemeral port and
/// talk to it over a real socket — the wiring between sockets, identity and
/// the hub is exactly the part that unit tests with fake clients cannot cover.
Future<RunningServer> startServer({
  int port = 8080,
  String address = '0.0.0.0',
  LudoHub? hub,
}) async {
  final theHub = hub ?? LudoHub();
  final clients = <String, SocketClient>{};

  // The turn clock lives here, not on the client: a phone must not be able to
  // grant itself more thinking time by lying about its own stopwatch.
  final ticker =
      Timer.periodic(const Duration(seconds: 1), (_) => theHub.tick());

  final sockets = webSocketHandler((WebSocketChannel socket, _) {
    String? playerId;

    socket.stream.listen(
      (raw) {
        final text = raw is String ? raw : raw.toString();

        if (playerId == null) {
          // The first frame settles who this is. An account is never required:
          // a returning player sends the guest id they were given, and a new
          // one has theirs minted here.
          final who = identify(theHub, text);
          playerId = who.playerId;
          final client = SocketClient(
            playerId: who.playerId,
            displayName: who.displayName,
            sink: socket.sink.add,
          );
          clients[who.playerId] = client;
          client.send(
              Welcome(playerId: who.playerId, displayName: who.displayName));
          return;
        }

        final client = clients[playerId];
        if (client == null) return;
        final message = decodeOrComplain(text, client);
        if (message != null) theHub.handle(client, message);
      },
      onDone: () => _gone(theHub, clients, playerId),
      onError: (_) => _gone(theHub, clients, playerId),
      cancelOnError: true,
    );
  });

  final handler = Cascade()
      .add((Request request) {
        if (request.url.path == 'health') return Response.ok('ok');
        if (request.url.path.isEmpty) {
          return Response.ok('Ludo server. Connect a WebSocket to /ws.\n'
              'Rooms live: ${theHub.rooms.length}\n');
        }
        return Response.notFound('not found');
      })
      .add(sockets)
      .handler;

  final http = await io.serve(handler, address, port);
  return RunningServer(http, ticker, theHub);
}

void _gone(LudoHub hub, Map<String, SocketClient> clients, String? playerId) {
  if (playerId == null) return;
  hub.disconnected(playerId);
  clients.remove(playerId);
}
