import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/main.dart';
import 'package:ludo_app/screens/online_screen.dart';

void main() {
  test('the app link and the web link both carry the room code', () {
    expect(inviteCodeIn('ludo://join/KTP4WQ'), 'KTP4WQ');
    expect(inviteCodeIn('ludo://join/ktp-4wq/'), 'KTP4WQ');
    expect(inviteCodeIn(inviteLink('KTP4WQ')), 'KTP4WQ');
    expect(
      inviteCodeIn('https://quakestring-ludo.fly.dev/r/KTP4WQ?x=1'),
      'KTP4WQ',
    );
  });

  test('an ordinary start is not an invite', () {
    expect(inviteCodeIn('/'), isNull);
    expect(inviteCodeIn('ludo://join/'), isNull);
  });
}
