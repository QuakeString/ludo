import 'dart:io';

import 'package:shelf/shelf.dart';

/// The browser build of the app, served by the game server itself at /play/.
///
/// GitHub Pages serves the same build, but over HTTPS, and a page loaded over
/// HTTPS is not allowed to open a plain `ws://` socket. A server reached by its
/// bare IP address has no certificate, so the Pages build cannot talk to it.
/// Served from here, the page and the socket share one origin and one scheme,
/// and playing online in a browser needs nothing more than the address.
class WebApp {
  WebApp(this.root);

  /// Where the built files are. Not having any is normal — a server built
  /// without the web app simply does not offer it.
  final Directory root;

  /// The path the build was made for, with `--base-href /play/`.
  static const mount = 'play';

  bool get available => File('${root.path}/index.html').existsSync();

  static const _types = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'json': 'application/json',
    'css': 'text/css; charset=utf-8',
    'wasm': 'application/wasm',
    'png': 'image/png',
    'ico': 'image/x-icon',
    'svg': 'image/svg+xml',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
    'woff2': 'font/woff2',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'ogg': 'audio/ogg',
  };

  /// Answers a request under /play/, or null for anything else.
  Response? handle(Request request) {
    final path = request.url.path;
    if (path != mount && !path.startsWith('$mount/')) return null;
    if (!available) {
      return Response.notFound('This server was built without the web app.\n');
    }
    // The app's relative asset paths only resolve under the trailing slash.
    if (path == mount) {
      return Response.found(request.requestedUri.replace(path: '/$mount/'));
    }

    final rest = path.substring(mount.length + 1);
    final segments = rest.split('/');
    // Nothing outside the build: no "..", no hidden files.
    if (segments.any((s) => s == '..' || s.startsWith('.'))) {
      return Response.notFound('not found');
    }
    var file = File('${root.path}/${rest.isEmpty ? 'index.html' : rest}');
    // A path the app routes itself, not a file: the page is the answer.
    if (!file.existsSync()) file = File('${root.path}/index.html');

    final ext = file.path.split('.').last.toLowerCase();
    final html = ext == 'html';
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': _types[ext] ?? 'application/octet-stream',
        'content-length': '${file.lengthSync()}',
        // The page is small and must never be stale after an upgrade; the
        // files it loads are fetched fresh on each new page anyway.
        'cache-control': html ? 'no-cache' : 'public, max-age=300',
      },
    );
  }
}
