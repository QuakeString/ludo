import 'dart:io';

import 'package:ludo_server/ludo_server.dart';
import 'package:test/test.dart';

/// The browser build, served by the game server at /play/.
void main() {
  late Directory web;
  late RunningServer server;
  late HttpClient http;

  Future<(int, String, HttpHeaders)> get(String path,
      {bool follow = true}) async {
    final request = await http.get('127.0.0.1', server.port, path);
    request.followRedirects = follow;
    final response = await request.close();
    final body = await response.transform(SystemEncoding().decoder).join();
    return (response.statusCode, body, response.headers);
  }

  setUp(() async {
    web = await Directory.systemTemp.createTemp('ludo-web');
    File('${web.path}/index.html').writeAsStringSync('<html>the app</html>');
    File('${web.path}/main.dart.js').writeAsStringSync('console.log(1)');
    Directory('${web.path}/assets').createSync();
    File('${web.path}/assets/x.png').writeAsBytesSync([1, 2, 3]);
    server = await startServer(port: 0, address: '127.0.0.1', webRoot: web);
    http = HttpClient();
  });

  tearDown(() async {
    http.close(force: true);
    await server.close();
    await web.delete(recursive: true);
  });

  test('serves the page and its files with the right types', () async {
    final (status, body, headers) = await get('/play/');
    expect(status, 200);
    expect(body, contains('the app'));
    expect(headers.contentType?.mimeType, 'text/html');

    final (_, js, jsHeaders) = await get('/play/main.dart.js');
    expect(js, 'console.log(1)');
    expect(jsHeaders.contentType?.mimeType, 'text/javascript');

    final (_, _, pngHeaders) = await get('/play/assets/x.png');
    expect(pngHeaders.contentType?.mimeType, 'image/png');
  });

  test('the bare address and /play both land on the app', () async {
    final (rootStatus, _, rootHeaders) = await get('/', follow: false);
    expect(rootStatus, HttpStatus.found);
    expect(rootHeaders.value('location'), endsWith('/play/'));

    final (playStatus, _, playHeaders) = await get('/play', follow: false);
    expect(playStatus, HttpStatus.found);
    expect(playHeaders.value('location'), endsWith('/play/'));
  });

  test('an unknown path under /play is the app, which routes it', () async {
    final (status, body, _) = await get('/play/join/KTP4WQ');
    expect(status, 200);
    expect(body, contains('the app'));
  });

  test('nothing outside the build can be reached', () async {
    File('${web.parent.path}/secret.txt').writeAsStringSync('no');
    addTearDown(() => File('${web.parent.path}/secret.txt').deleteSync());
    final (_, body, _) = await get('/play/%2E%2E/secret.txt');
    expect(body, isNot('no'));
    final (_, hidden, _) = await get('/play/.env');
    expect(hidden, isNot(contains('no')));
  });

  test('the invite page offers the browser too', () async {
    final (_, body, _) = await get('/r/ktp-4wq');
    expect(body, contains('/play/#/join/KTP4WQ'));
    expect(body, contains('ludo://join/KTP4WQ'));
  });

  test('without a build, there is no browser offer', () {
    expect(invitePage('KTP4WQ'), isNot(contains('/play/')));
    expect(WebApp(Directory('/nonexistent')).available, isFalse);
  });

  test('the game socket still works beside it', () async {
    final (status, body, _) = await get('/health');
    expect(status, 200);
    expect(body, 'ok');
  });
}
