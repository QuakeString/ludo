import 'dart:async';

import 'package:ludo_protocol/ludo_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The socket to the game server, and nothing else.
///
/// Deliberately thin: it knows how to connect, how to say who it is, and how to
/// pass envelopes both ways. What those envelopes *mean* is [OnlineSession]'s
/// problem, which keeps the part that touches the network small enough to
/// reason about when it misbehaves.
class LudoConnection {
  LudoConnection({required this.uri});

  final Uri uri;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  final _incoming = StreamController<Envelope>.broadcast();

  /// Everything the server says.
  Stream<Envelope> get messages => _incoming.stream;

  bool get isOpen => _channel != null;

  /// Who the server thinks we are. Null until [Welcome] arrives.
  String? playerId;
  String? displayName;

  /// Whether [displayName] is one the player picked, not a `Guest_1234`.
  bool chosenName = false;

  /// Set when the server says this copy of the app is too old to play online.
  bool outOfDate = false;

  /// A match this player dropped out of that is still holding their seat, by
  /// room code. Cleared once they are back in it.
  String? rejoin;

  /// The secret that goes with [playerId], kept in memory as well as on disk,
  /// so reconnecting after a dropped signal is the same player even when the
  /// identity was never saved (a [fresh] one, in tests or a second window).
  String? _secret;

  /// Keeps an idle socket from being closed by a proxy along the way. Hosting
  /// platforms cut connections that say nothing for a minute or so, and a
  /// player thinking about a move says nothing.
  Timer? _keepAlive;

  /// Opens the socket and settles identity.
  ///
  /// No account, ever: the guest id from last time is offered, and if there
  /// isn't one the server mints a fresh one and we keep it. That is the whole
  /// of "logging in" — online play included.
  ///
  /// [fresh] ignores the identity saved on this device and asks for a new one.
  /// Two clients with the same identity are the same person coming back, so
  /// anything running more than one player from one device — tests, two
  /// windows — needs this.
  ///
  /// [transfer] is a code made on another phone: this device becomes that
  /// player, and remembers it in place of whoever it was before.
  Future<Welcome> connect({
    String? preferredName,
    bool fresh = false,
    String? transfer,
  }) async {
    if (_channel != null) await close();

    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    _channel = channel;

    final welcomed = Completer<Welcome>();
    _sub = channel.stream.listen(
      (raw) {
        final Envelope message;
        try {
          message = Envelope.decode(raw is String ? raw : raw.toString());
        } catch (_) {
          // A frame we cannot read is the server's problem to have sent, not a
          // reason to tear down a working connection.
          return;
        }
        if (message is Welcome) {
          playerId = message.playerId;
          displayName = message.displayName;
          chosenName = message.chosenName;
          rejoin = message.rejoin;
          if (message.secret != null) _secret = message.secret;
          if (!fresh) {
            _remember(message.playerId, message.displayName, message.secret);
          }
          if (!welcomed.isCompleted) welcomed.complete(message);
        }
        if (message is Oops && message.code == 'transfer') {
          if (!welcomed.isCompleted) {
            welcomed.completeError(StateError(message.message));
          }
        }
        if (message is Oops && message.code == 'update') {
          outOfDate = true;
          if (!welcomed.isCompleted) {
            welcomed.completeError(StateError(message.message));
          }
        }
        _incoming.add(message);
      },
      onDone: () {
        _channel = null;
        if (!welcomed.isCompleted) {
          welcomed.completeError(
            StateError('the server closed the connection before saying hello'),
          );
        }
        _incoming.add(const Oops('lost the connection', code: 'closed'));
      },
      onError: (Object e) {
        if (!welcomed.isCompleted) welcomed.completeError(e);
        _incoming.add(Oops('connection error: $e', code: 'closed'));
      },
      cancelOnError: true,
    );

    // Already somebody on this connection, from before it dropped: be them
    // again. Otherwise whoever this device remembers, unless told not to.
    final known = transfer == null && playerId != null && _secret != null;
    final saved = known || fresh || transfer != null
        ? (null, null, null)
        : await _saved();
    if (!known) _secret = saved.$3;
    send(
      Hello(
        guestId: known ? playerId : saved.$1,
        secret: known ? _secret : saved.$3,
        displayName: preferredName ?? (known ? displayName : saved.$2),
        transfer: transfer?.trim().toUpperCase().replaceAll('-', ''),
      ),
    );
    _keepAlive?.cancel();
    _keepAlive = Timer.periodic(
      const Duration(seconds: 25),
      (_) => send(const Ping()),
    );

    return welcomed.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('the server did not answer'),
    );
  }

  void send(Envelope message) => _channel?.sink.add(message.encode());

  Future<void> close() async {
    _keepAlive?.cancel();
    _keepAlive = null;
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
  }

  Future<void> dispose() async {
    await close();
    await _incoming.close();
  }

  // --- the guest identity --------------------------------------------------

  static const _idKey = 'ludo.guestId';
  static const _nameKey = 'ludo.displayName';
  static const _secretKey = 'ludo.secret';

  Future<(String?, String?, String?)> _saved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (
        prefs.getString(_idKey),
        prefs.getString(_nameKey),
        prefs.getString(_secretKey),
      );
    } catch (_) {
      // Storage being unavailable means playing as somebody new, which is a
      // worse experience but not a broken one.
      return (null, null, null);
    }
  }

  /// Keeps the identity. The secret only arrives when the server mints a new
  /// player, and it is the one thing that makes this phone that player — so
  /// an id is only ever saved together with the secret that goes with it.
  Future<void> _remember(String id, String name, String? secret) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (secret != null) {
        await prefs.setString(_idKey, id);
        await prefs.setString(_secretKey, secret);
      }
      await prefs.setString(_nameKey, name);
    } catch (_) {
      // Same again: not remembering is survivable.
    }
  }
}
