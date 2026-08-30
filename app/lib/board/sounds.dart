import 'package:audioplayers/audioplayers.dart';

/// The game's sounds, and the one place that knows how to fail quietly.
///
/// A browser that has not had a gesture yet, a machine with no audio device, a
/// widget test — none of them is a reason for the game to stop, so every
/// failure here is swallowed. A missing sound is a missing sound.
///
/// One player is kept per sound rather than one for everything: a chip landing
/// while the die is still rattling should not cut the die off, and a capture
/// should not wait its turn.
class Sfx {
  Sfx._();

  static final Sfx instance = Sfx._();

  /// Off for previews and tests.
  static bool muted = false;

  /// Set by a test to record what the game asked for instead of playing it.
  /// The sounds are the only record that a capture or an arrival happened at
  /// all — nothing else about those two moments is visible from outside.
  static void Function(String name)? spy;

  final Map<String, AudioPlayer> _players = {};

  Future<void> play(String name, {double volume = 1}) async {
    final watcher = spy;
    if (watcher != null) {
      watcher(name);
      return;
    }
    if (muted) return;
    try {
      final player = _players.putIfAbsent(name, AudioPlayer.new);
      await player.stop();
      await player.play(AssetSource('sounds/$name.wav'), volume: volume);
    } catch (_) {
      // See above.
    }
  }

  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
  }
}

/// The sounds the game makes. Named, so a typo is a compile error.
abstract final class Sound {
  static const die = 'dice_roll';
  static const step = 'chip_step';
  static const home = 'chip_home';
  static const capture = 'capture';
  static const safe = 'safe';
  static const victory = 'victory';
}
