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
    await hub.players.flush();
  }
}

/// Starts the server.
///
/// Split out of `main` so a test can boot a real one on an ephemeral port and
/// talk to it over a real socket — the wiring between sockets, identity and
/// the hub is exactly the part that unit tests with fake clients cannot cover.
Future<RunningServer> startServer({
  int port = 8091,
  String address = '0.0.0.0',
  LudoHub? hub,
  RateLimiter Function()? limits,
}) async {
  final theHub = hub ?? LudoHub();
  await theHub.players.load();
  final clients = <String, SocketClient>{};

  // The turn clock lives here, not on the client: a phone must not be able to
  // grant itself more thinking time by lying about its own stopwatch.
  final ticker =
      Timer.periodic(const Duration(seconds: 1), (_) => theHub.tick());

  final sockets = webSocketHandler((WebSocketChannel socket, _) {
    String? playerId;
    // This socket's own client. A player who reconnects has a new socket and a
    // new client before the old one is noticed to be dead, so the old socket
    // must only ever speak for, and clean up after, itself.
    SocketClient? me;
    final limiter = (limits ?? RateLimiter.new)();

    socket.stream.listen(
      (raw) {
        final text = raw is String ? raw : raw.toString();

        // Nothing a player sends is anywhere near this big; a frame that is
        // is somebody trying to make the server read a lot.
        if (text.length > maxFrameLength) {
          socket.sink.close(1009, 'message too big');
          return;
        }

        if (playerId == null) {
          // The first frame settles who this is. An account is never required:
          // a returning player proves who they are with the secret they were
          // given, and a new one has an identity minted here.
          switch (identify(theHub, text)) {
            case TooOld():
              socket.sink.add(const Oops(
                'This copy of Ludo is out of date. Update the app to play '
                'online.',
                code: 'update',
              ).encode());
              socket.sink.close(1000, 'update');
            case BadTransfer():
              socket.sink.add(const Oops(
                'That code did not work. Codes work once, for ten minutes; '
                'make a new one on your other phone.',
                code: 'transfer',
              ).encode());
              socket.sink.close(1000, 'transfer');
            case Identified(player: final player, secret: final secret):
              playerId = player.id;
              final client =
                  SocketClient(player: player, sink: socket.sink.add);
              me = client;
              clients[player.id] = client;
              client.send(theHub.welcomeFor(player, secret: secret));
              theHub.connected(client);
          }
          return;
        }

        final client = me;
        if (client == null) return;
        switch (limiter.take(DateTime.now())) {
          case Allowance.ok:
            final message = decodeOrComplain(text, client);
            if (message != null) theHub.handle(client, message);
          case Allowance.warn:
            client.send(const Oops('slow down', code: 'slow'));
          case Allowance.drop:
            break;
          case Allowance.disconnect:
            socket.sink.close(1008, 'too many messages');
        }
      },
      onDone: () => _gone(theHub, clients, me),
      onError: (_) => _gone(theHub, clients, me),
      cancelOnError: true,
    );
  });

  final handler = Cascade()
      .add((Request request) {
        if (request.url.path == 'health') return Response.ok('ok');
        final invite =
            RegExp(r'^r/([A-Za-z0-9-]{4,12})$').firstMatch(request.url.path);
        if (invite != null) {
          return Response.ok(invitePage(invite.group(1)!),
              headers: {'content-type': 'text/html; charset=utf-8'});
        }
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

/// Where the Android app can be downloaded, for invite pages opened on a
/// phone that does not have it yet.
const appDownload =
    'https://github.com/QuakeString/ludo/releases/download/phone/ludo.apk';

/// The page an invite link opens.
///
/// A link in a chat opens in the browser, which cannot join a game by itself,
/// so this page hands over to the app with a `ludo://join/CODE` link, and
/// offers the app to anyone who does not have it yet. The code is shown as
/// well, for typing in by hand when nothing else works.
String invitePage(String rawCode) {
  final code = rawCode.toUpperCase().replaceAll('-', '');
  return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Join my Ludo game</title>
<meta property="og:title" content="Join my Ludo game">
<meta property="og:description" content="Room code $code. Tap to join.">
<style>
  :root { color-scheme: light dark; --bg: #f6f3ec; --fg: #1d1b16; --muted: #5d5a52; --accent: #1f6f43; }
  @media (prefers-color-scheme: dark) { :root { --bg: #15140f; --fg: #f2efe6; --muted: #b5b1a5; --accent: #4fbf7f; } }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: var(--bg); color: var(--fg);
         font: 16px/1.5 system-ui, -apple-system, Segoe UI, Roboto, sans-serif; padding: 16px; box-sizing: border-box; }
  main { max-width: 360px; width: 100%; text-align: center; }
  .code { font-size: 40px; font-weight: 800; letter-spacing: 6px; margin: 8px 0 20px; }
  a.button { display: block; padding: 14px; border-radius: 12px; text-decoration: none; font-weight: 700; margin: 10px 0; }
  .primary { background: var(--accent); color: #fff; }
  .secondary { border: 1.5px solid var(--accent); color: var(--accent); }
  p { color: var(--muted); font-size: 14px; }
</style>
</head>
<body>
<main>
  <h1>You're invited to Ludo</h1>
  <div class="code">$code</div>
  <a class="button primary" href="ludo://join/$code">Open in Ludo</a>
  <a class="button secondary" href="$appDownload">Get the app (Android)</a>
  <p>Already in the app? Choose Play online, then type the code above.</p>
</main>
</body>
</html>
''';
}

/// The longest frame the server will read, in characters. A full match update
/// for six seats is a few kilobytes; nothing a client sends comes close.
const maxFrameLength = 16 * 1024;

enum Allowance { ok, warn, drop, disconnect }

/// How many messages one connection may send.
///
/// A bucket of [burst] that refills at [perSecond]. A person tapping as fast
/// as they can is a few messages a second; a script is hundreds. The first
/// message over the limit is answered with a warning, later ones are dropped,
/// and a connection that keeps going after [patience] drops is closed.
class RateLimiter {
  RateLimiter({this.burst = 30, this.perSecond = 10, this.patience = 200});

  final int burst;
  final int perSecond;
  final int patience;

  double _tokens = -1;
  DateTime? _last;
  int _dropped = 0;

  Allowance take(DateTime now) {
    if (_tokens < 0) _tokens = burst.toDouble();
    final last = _last;
    if (last != null) {
      final seconds = now.difference(last).inMicroseconds / 1e6;
      _tokens = (_tokens + seconds * perSecond).clamp(0, burst.toDouble());
    }
    _last = now;
    if (_tokens >= 1) {
      _tokens -= 1;
      _dropped = 0;
      return Allowance.ok;
    }
    _dropped++;
    if (_dropped == 1) return Allowance.warn;
    if (_dropped > patience) return Allowance.disconnect;
    return Allowance.drop;
  }
}

void _gone(LudoHub hub, Map<String, SocketClient> clients, SocketClient? me) {
  if (me == null) return;
  // Already replaced by a newer connection for the same player: that one is
  // sitting in the seat now, and this socket going away changes nothing.
  if (clients[me.playerId] != me) return;
  hub.disconnected(me.playerId);
  clients.remove(me.playerId);
}
