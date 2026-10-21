import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// What the installed app is allowed to do on Android.
///
/// Flutter's template grants the network only to debug and profile builds, so
/// a release APK built from it cannot open a socket: every attempt to reach
/// the game server failed on the phone while working fine everywhere else.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();

  test('the release build may use the network', () {
    expect(manifest, contains('android.permission.INTERNET'));
  });

  test('a bare IP address may be reached without TLS', () {
    expect(manifest, contains('android:usesCleartextTraffic="true"'));
  });
}
