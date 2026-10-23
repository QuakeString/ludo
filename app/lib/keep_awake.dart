import 'package:flutter/services.dart';

/// Keeps the screen from dimming and sleeping while a game is open.
///
/// Android only; anywhere else, and in tests, it quietly does nothing.
class KeepAwake {
  const KeepAwake._();

  static const _channel = MethodChannel('ludo/screen');

  static Future<void> set(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepOn', on);
    } catch (_) {
      // No Android side to ask: nothing to keep awake.
    }
  }
}
