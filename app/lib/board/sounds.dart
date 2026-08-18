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

  final Map<String, AudioPlayer> _players = {};

  Future<void> play(String name, {double volume = 1}) async {
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
}
