import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The player's own choices for this phone: sound and light or dark.
///
/// Each is a notifier, so the game screen's mute button and the settings
/// page are always showing the same thing, and the app's theme follows a
/// change at once.
class AppSettings {
  const AppSettings._();

  static const _soundKey = 'ludo.sound';
  static const _themeKey = 'ludo.theme';

  static final sound = ValueNotifier<bool>(true);
  static final theme = ValueNotifier<ThemeMode>(ThemeMode.system);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      sound.value = prefs.getBool(_soundKey) ?? true;
      final t = prefs.getString(_themeKey);
      theme.value = ThemeMode.values.firstWhere(
        (m) => m.name == t,
        orElse: () => ThemeMode.system,
      );
    } catch (_) {}
  }

  static Future<void> setSound(bool on) async {
    sound.value = on;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_soundKey, on);
    } catch (_) {}
  }

  static Future<void> setTheme(ThemeMode mode) async {
    theme.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeKey, mode.name);
    } catch (_) {}
  }
}
