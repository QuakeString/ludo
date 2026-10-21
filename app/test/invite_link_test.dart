import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/main.dart';
import 'package:ludo_app/net/server_address.dart';

void main() {
  test('the app link and the web link both carry the room code', () {
    expect(inviteCodeIn('ludo://join/KTP4WQ'), 'KTP4WQ');
    expect(inviteCodeIn('ludo://join/ktp-4wq/'), 'KTP4WQ');
    expect(
      inviteCodeIn(
        ServerAddress.inviteLink(
          Uri.parse('wss://ludo.example.com/ws'),
          'KTP4WQ',
        ),
      ),
      'KTP4WQ',
    );
    expect(inviteCodeIn('http://203.0.113.7:8091/r/KTP4WQ?x=1'), 'KTP4WQ');
  });

  test('an ordinary start is not an invite', () {
    expect(inviteCodeIn('/'), isNull);
    expect(inviteCodeIn('ludo://join/'), isNull);
  });

  test('whatever is typed becomes a WebSocket address', () {
    String? n(String s) => ServerAddress.normalise(s)?.toString();
    expect(n('203.0.113.7'), 'ws://203.0.113.7:8091/ws');
    expect(n(' 203.0.113.7:9000 '), 'ws://203.0.113.7:9000/ws');
    expect(n('ludo.example.com'), 'wss://ludo.example.com/ws');
    expect(n('https://ludo.example.com/'), 'wss://ludo.example.com/ws');
    expect(n('http://203.0.113.7:8091'), 'ws://203.0.113.7:8091/ws');
    expect(n('wss://ludo.example.com/ws'), 'wss://ludo.example.com/ws');
    expect(n('https://11.11.0.3:8091/'), 'ws://11.11.0.3:8091/ws');
    expect(n('https://11.11.0.3'), 'ws://11.11.0.3:8091/ws');
    expect(n('http://11.11.0.3:8091/play/'), 'ws://11.11.0.3:8091/ws');
    expect(n('wss://11.11.0.3:8091/ws'), 'ws://11.11.0.3:8091/ws');
    expect(n('ludo.example.com:8091'), 'ws://ludo.example.com:8091/ws');
    expect(n('https://ludo.example.com/play/'), 'wss://ludo.example.com/ws');
    expect(n(''), isNull);
    expect(n('ftp://x'), isNull);
  });

  test('the invite page lives on the same server, over the web', () {
    expect(
      ServerAddress.inviteLink(Uri.parse('ws://203.0.113.7:8091/ws'), 'AB12CD'),
      'http://203.0.113.7:8091/r/AB12CD',
    );
    expect(
      ServerAddress.inviteLink(
        Uri.parse('wss://ludo.example.com/ws'),
        'AB12CD',
      ),
      'https://ludo.example.com/r/AB12CD',
    );
  });

  test('a page served by the game server already knows where it is', () {
    String? from(String page) =>
        ServerAddress.servedFrom(Uri.parse(page))?.toString();
    expect(from('http://203.0.113.7:8091/play/'), 'ws://203.0.113.7:8091/ws');
    expect(
      from('http://203.0.113.7:8091/play/#/join/KTP4WQ'),
      'ws://203.0.113.7:8091/ws',
    );
    expect(from('https://ludo.example.com/play/'), 'wss://ludo.example.com/ws');
    // GitHub Pages has no game server behind it.
    expect(from('https://quakestring.github.io/ludo/'), isNull);
  });

  test('a browser opened on an invite goes to that room', () {
    expect(inviteCodeIn('/join/KTP4WQ'), 'KTP4WQ');
  });
}
