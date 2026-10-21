import 'package:shared_preferences/shared_preferences.dart';

/// Where the game server is.
///
/// The server runs wherever its owner put it — a VPS, a box at home — so the
/// address is not baked into the app. A build can still be given one:
///
///   flutter build apk --dart-define=LUDO_SERVER=wss://ludo.example.com/ws
///
/// and otherwise the player types it in once, the first time they go online,
/// and it is remembered.
class ServerAddress {
  const ServerAddress._();

  static const _key = 'ludo.server';

  /// The address this build was given, if any.
  static const built = String.fromEnvironment('LUDO_SERVER');

  /// The WebSocket address to connect to, or null when nobody has said yet.
  static Future<Uri?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null && saved.isNotEmpty) return normalise(saved);
    } catch (_) {}
    return built.isEmpty ? null : normalise(built);
  }

  static Future<void> save(String address) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, address.trim());
    } catch (_) {}
  }

  /// Turns whatever someone typed into a WebSocket address.
  ///
  ///   203.0.113.7          → ws://203.0.113.7:8091/ws
  ///   203.0.113.7:9000     → ws://203.0.113.7:9000/ws
  ///   ludo.example.com     → wss://ludo.example.com/ws
  ///   https://ludo.example.com → wss://ludo.example.com/ws
  ///
  /// A bare name is assumed to sit behind HTTPS on the standard port, which is
  /// how the bundled Caddy setup serves it; a bare IP address is assumed to be
  /// the server itself on its own port, with no certificate.
  static Uri? normalise(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) {
      final host = text.split('/').first.split(':').first;
      final isIp =
          RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) ||
          host == 'localhost';
      final hasPort = text.split('/').first.contains(':');
      text = isIp || hasPort
          ? 'ws://${hasPort ? text : '$text:8091'}'
          : 'wss://$text';
    }
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    final scheme = switch (uri.scheme) {
      'http' => 'ws',
      'https' => 'wss',
      'ws' || 'wss' => uri.scheme,
      _ => null,
    };
    if (scheme == null) return null;
    return uri.replace(
      scheme: scheme,
      path: uri.path.isEmpty || uri.path == '/' ? '/ws' : uri.path,
    );
  }

  /// The web address of the invite page for [code] on the server at [ws].
  static String inviteLink(Uri ws, String code) {
    final web = ws.replace(
      scheme: ws.scheme == 'wss' ? 'https' : 'http',
      path: '/r/$code',
    );
    return web.toString();
  }
}
