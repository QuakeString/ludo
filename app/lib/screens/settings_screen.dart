import 'package:flutter/material.dart';

import '../app_update.dart';
import '../settings.dart';
import '../theme/seat_colors.dart';

/// Sound, light or dark, and which version this is, with a way to look for
/// a newer one by hand.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checking = false;
  bool _installing = false;

  /// What the last check found, in words.
  String? _found;

  /// Set when the last check found a newer build.
  bool _canUpdate = false;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _found = null;
      _canUpdate = false;
    });
    try {
      final latest = await AppUpdate.latest();
      if (!mounted) return;
      setState(() {
        _canUpdate = latest > AppUpdate.build;
        _found = _canUpdate
            ? 'Version $latest is ready to install.'
            : 'You have the latest version.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _found = 'Could not check. Are you online?');
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _install() async {
    setState(() => _installing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await installAppUpdate(messenger);
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final version = AppUpdate.build > 0
        ? 'Version ${AppUpdate.build}'
        : 'Development build';
    return Scaffold(
      backgroundColor: palette.felt,
      appBar: AppBar(
        backgroundColor: palette.felt,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: AppSettings.sound,
            builder: (context, on, _) => SwitchListTile(
              key: const ValueKey('settings-sound'),
              secondary: Icon(
                on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              ),
              title: const Text('Sound'),
              subtitle: const Text('Dice, moves, captures and wins'),
              value: on,
              onChanged: AppSettings.setSound,
            ),
          ),
          const Divider(),
          const _Heading('Appearance'),
          ValueListenableBuilder<ThemeMode>(
            valueListenable: AppSettings.theme,
            builder: (context, mode, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<ThemeMode>(
                key: const ValueKey('settings-theme'),
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    label: Text('Phone'),
                    icon: Icon(Icons.brightness_auto_rounded),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('Light'),
                    icon: Icon(Icons.light_mode_rounded),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('Dark'),
                    icon: Icon(Icons.dark_mode_rounded),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (s) => AppSettings.setTheme(s.first),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Divider(),
          const _Heading('Updates'),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(version),
            subtitle: _found == null ? null : Text(_found!),
            trailing: _canUpdate
                ? FilledButton(
                    key: const ValueKey('settings-install'),
                    onPressed: _installing || !AppUpdate.supported
                        ? null
                        : _install,
                    child: _installing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Update'),
                  )
                : OutlinedButton(
                    key: const ValueKey('settings-check'),
                    onPressed: _checking ? null : _check,
                    child: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Check'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: BoardPalette.of(context).faint,
      ),
    ),
  );
}

/// Downloads the newest build and opens Android's installer, telling the
/// player through [messenger] when it needs their permission first or fails.
Future<void> installAppUpdate(ScaffoldMessengerState messenger) async {
  try {
    final outcome = await AppUpdate.install();
    if (outcome == 'permission') {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Allow LUDO Time to install updates, then try again.'),
        ),
      );
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('The update did not download ($e)')),
    );
  }
}
