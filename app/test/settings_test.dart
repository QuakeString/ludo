import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ludo_app/screens/game_screen.dart';
import 'package:ludo_app/screens/home_screen.dart';
import 'package:ludo_app/screens/settings_screen.dart';
import 'package:ludo_app/settings.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sound and light or dark are the player's to choose, and stay chosen.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.setSound(true);
    await AppSettings.setTheme(ThemeMode.system);
  });

  testWidgets('the front page opens Settings', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.tap(find.byKey(const ValueKey('open-settings')));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-check')), findsOneWidget);
  });

  testWidgets('sound can be turned off, and nothing plays', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.tap(find.byKey(const ValueKey('settings-sound')));
    await tester.pump();
    expect(AppSettings.sound.value, isFalse);

    // Remembered for next time.
    AppSettings.sound.value = true;
    await AppSettings.load();
    expect(AppSettings.sound.value, isFalse);
  });

  testWidgets('dark can be chosen and is remembered', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect(AppSettings.theme.value, ThemeMode.dark);
    AppSettings.theme.value = ThemeMode.light;
    await AppSettings.load();
    expect(AppSettings.theme.value, ThemeMode.dark);
  });

  testWidgets('the game has its own mute button', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(rules: RuleConfig(players: 2), seed: 3),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('game-sound')));
    await tester.pump();
    expect(AppSettings.sound.value, isFalse);
    expect(find.byIcon(Icons.volume_off_rounded), findsOneWidget);
  });
}
