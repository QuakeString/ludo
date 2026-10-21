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
}
