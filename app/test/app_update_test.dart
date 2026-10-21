import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/app_update.dart';

/// The app finds out about a newer build by reading one small file.
void main() {
  test('a higher build number is an update', () {
    expect(AppUpdate.newerThan(40, '{"build": 41}'), 41);
  });

  test('the same or an older build is not', () {
    expect(AppUpdate.newerThan(41, '{"build": 41}'), isNull);
    expect(AppUpdate.newerThan(41, '{"build": 12}'), isNull);
  });

  test('a file it cannot read is not an update', () {
    expect(AppUpdate.newerThan(1, 'Not Found'), isNull);
    expect(AppUpdate.newerThan(1, '{"build": "x"}'), isNull);
  });

  test('a build made outside the release pipeline never asks', () async {
    expect(AppUpdate.build, 0);
    expect(AppUpdate.supported, isFalse);
    expect(await AppUpdate.newer(), isNull);
  });
}
