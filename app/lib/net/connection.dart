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

  /// Opens the socket and settles identity.
  ///
  /// No account, ever: the guest id from last time is offered, and if there
  /// isn't one the server mints a fresh one and we keep it. That is the whole
  /// of "logging in" — online play included.
  ///
  /// [guestId] overrides the identity saved on this device. Two clients that
  /// claim the same id are treated as the same person coming back, so anything
  /// running more than one player from one device — tests, two windows — has to
  /// say which is which.
  Future<Welcome> connect({String? preferredName, String? guestId}) async {
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
          _remember(message.playerId, message.displayName);
          if (!welcomed.isCompleted) welcomed.complete(message);
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

    final saved = await _saved();
    send(
      Hello(
        guestId: guestId ?? saved.$1,
        displayName: preferredName ?? saved.$2,
      ),
    );

    return welcomed.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('the server did not answer'),
    );
  }

  void send(Envelope message) => _channel?.sink.add(message.encode());

  Future<void> close() async {
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

  Future<(String?, String?)> _saved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getString(_idKey), prefs.getString(_nameKey));
    } catch (_) {
      // Storage being unavailable means playing as somebody new, which is a
      // worse experience but not a broken one.
      return (null, null);
    }
  }

  Future<void> _remember(String id, String name) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_idKey, id);
      await prefs.setString(_nameKey, name);
    } catch (_) {
      // Same again: not remembering is survivable.
    }
  }
}
