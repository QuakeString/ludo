import 'package:flutter/foundation.dart';
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
    final typed = _typed;
    if (typed != null) return normalise(typed);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_key);
      if (saved != null && saved.isNotEmpty) return normalise(saved);
    } catch (_) {}
    if (built.isNotEmpty) return normalise(built);
    return kIsWeb ? servedFrom(Uri.base) : null;
  }

  /// The server a browser page was loaded from, when it was.
  ///
  /// The game server serves the web app itself at /play/, and a page loaded
  /// from there already knows where its server is: the same host and port,
  /// over `wss://` if the page came over HTTPS and `ws://` if not. Anywhere
  /// else — GitHub Pages, say — the page has no server of its own.
  static Uri? servedFrom(Uri page) {
    if (!page.hasAuthority || !page.path.startsWith('/play')) return null;
    return Uri(
      scheme: page.scheme == 'https' ? 'wss' : 'ws',
      host: page.host,
      port: page.hasPort ? page.port : null,
      path: '/ws',
    );
  }

  /// The address typed in this run of the app. Kept in memory as well as on
  /// disk, so a save that fails cannot send the player straight back to the
  /// "which server?" screen they have just answered.
  static String? _typed;

  static Future<void> save(String address) async {
    _typed = address.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, address.trim());
    } catch (_) {}
  }

  /// Turns whatever someone typed into a WebSocket address.
  ///
  ///   203.0.113.7               → ws://203.0.113.7:8091/ws
  ///   203.0.113.7:9000          → ws://203.0.113.7:9000/ws
  ///   https://203.0.113.7:8091/ → ws://203.0.113.7:8091/ws
  ///   http://203.0.113.7:8091/play/ → ws://203.0.113.7:8091/ws
  ///   ludo.example.com          → wss://ludo.example.com/ws
  ///   https://ludo.example.com  → wss://ludo.example.com/ws
  ///
  /// A bare name is assumed to sit behind HTTPS on the standard port, which is
  /// how the bundled Caddy setup serves it. An IP address is always the server
  /// itself on its own port, with no certificate — whatever scheme was typed
  /// in front of it. Nobody has a certificate for a bare IP, so `https://` on
  /// one can only ever fail, and it failed with nothing on screen to say why.
  /// The page's own path (the address bar of /play/, say) is not where the
  /// socket is, so the socket's path replaces it.
  static Uri? normalise(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'ws://$text';
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    final ip =
        RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(uri.host) ||
        uri.host == 'localhost';
    final typedScheme = raw.trim().contains('://');
    final String? scheme;
    if (ip) {
      scheme = const {'http', 'https', 'ws', 'wss'}.contains(uri.scheme)
          ? 'ws'
          : null;
    } else if (!typedScheme) {
      // A bare name with a port of its own is a server reached directly.
      scheme = uri.hasPort ? 'ws' : 'wss';
    } else {
      scheme = switch (uri.scheme) {
        'http' => 'ws',
        'https' => 'wss',
        'ws' || 'wss' => uri.scheme,
        _ => null,
      };
    }
    if (scheme == null) return null;
    return Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : (ip ? 8091 : null),
      path: '/ws',
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
