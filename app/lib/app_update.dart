import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Newer builds of the app, offered from inside it.
///
/// The phone build is side-loaded, so no store will ever tell it that a new
/// one exists. Every published build carries its number, and a small file
/// next to the download says which number is the newest. When that is ahead
/// of this one, the front page offers an update; tapping it fetches the APK
/// and hands it to Android's installer, which asks before installing.
class AppUpdate {
  const AppUpdate._();

  /// This build's number, given by the build that made it. Zero for a build
  /// made anywhere else, which never looks for updates.
  static const build = int.fromEnvironment('LUDO_BUILD');

  static const _release =
      'https://github.com/QuakeString/ludo/releases/download/phone';
  static const apkUrl = '$_release/ludo.apk';
  static const versionUrl = '$_release/version.json';

  static const _channel = MethodChannel('ludo/update');

  /// Only the Android build installs itself; a browser simply reloads.
  static bool get supported =>
      build > 0 && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// The newest published build number, when it is newer than this one.
  /// Null when there is nothing newer, or the check could not be made.
  static Future<int?> newer({http.Client? client}) async {
    if (!supported) return null;
    final c = client ?? http.Client();
    try {
      final res = await c
          .get(Uri.parse(versionUrl))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return newerThan(build, res.body);
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }

  /// Asked for by hand, from Settings: the newest published build number.
  /// Throws when the check cannot be made, so the player hears about it
  /// rather than being told they are up to date.
  static Future<int> latest({http.Client? client}) async {
    final c = client ?? http.Client();
    try {
      final res = await c
          .get(Uri.parse(versionUrl))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) {
        throw Exception('the server answered ${res.statusCode}');
      }
      final latest = (jsonDecode(res.body) as Map)['build'];
      if (latest is! int) throw const FormatException('no build number');
      return latest;
    } finally {
      if (client == null) c.close();
    }
  }

  /// The build number in [versionJson], if it is ahead of [current].
  static int? newerThan(int current, String versionJson) {
    try {
      final latest = (jsonDecode(versionJson) as Map)['build'];
      if (latest is int && latest > current) return latest;
    } catch (_) {}
    return null;
  }

  /// Downloads the newest APK and opens the installer.
  ///
  /// Returns 'started' once the installer is showing, or 'permission' when
  /// Android first needs the player to allow this app to install updates —
  /// the settings page is opened for them, and Update works after that.
  static Future<String> install() async {
    final result = await _channel.invokeMethod<String>('install', {
      'url': apkUrl,
    });
    return result ?? 'started';
  }
}
