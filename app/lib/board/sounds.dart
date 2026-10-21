import 'package:audioplayers/audioplayers.dart';

/// The game's sounds, and the one place that knows how to fail quietly.
///
/// A browser that has not had a gesture yet, a machine with no audio device, a
/// widget test — none of them is a reason for the game to stop, so every
/// failure here is swallowed. A missing sound is a missing sound.
///
/// Every sound is short, so each is played the low-latency way: loaded once
/// into the system's sound pool and fired from memory. Played the ordinary way
/// (a media player per sound, stopped and started again for every tap) a
/// phone has to reopen and re-prepare the file each time, which takes longer
/// than the gap between two steps of a chip. The requests queued up behind
/// each other, the steps came late, and after a few of them they stopped
/// coming at all.
///
/// A few voices are kept per sound and taken in turn, so a step does not have
/// to stop the step before it, and a chip landing does not cut off the die.
class Sfx {
  Sfx._();

  static final Sfx instance = Sfx._();

  /// Off for previews and tests.
  static bool muted = false;

  /// Set by a test to record what the game asked for instead of playing it.
  /// The sounds are the only record that a capture or an arrival happened at
  /// all — nothing else about those two moments is visible from outside.
  static void Function(String name)? spy;

  /// How many of one sound can be heard at once.
  static const voices = 3;

  final Map<String, _Voices> _bank = {};

  _Voices _voices(String name) => _bank.putIfAbsent(name, () => _Voices(name));

  Future<void> play(String name, {double volume = 1}) async {
    final watcher = spy;
    if (watcher != null) {
      watcher(name);
      return;
    }
    if (muted) return;
    try {
      // The first sound of a game loads all the others alongside it, so a
      // chip's first step is not also the moment its sound is read from
      // storage.
      if (_bank.isEmpty) Sound.all.forEach(_voices);
      await _voices(name).play(volume);
    } catch (_) {
      // See above.
    }
  }

  void dispose() {
    for (final v in _bank.values) {
      v.dispose();
    }
    _bank.clear();
  }
}

/// The players for one sound, each loaded with it once.
class _Voices {
  _Voices(String name) {
    _ready = _loadAll(name);
    // A sound that cannot load is silent, not an error on every play.
    _ready.catchError((_) {});
  }

  /// One after another: a second player for the same file borrows the
  /// first one's loaded copy, and there is nothing to borrow until the
  /// first has finished loading.
  Future<void> _loadAll(String name) async {
    for (var i = 0; i < Sfx.voices; i++) {
      _players.add(await _load(name));
    }
  }

  final List<AudioPlayer> _players = [];
  late final Future<void> _ready;
  var _next = 0;

  static Future<AudioPlayer> _load(String name) async {
    final player = AudioPlayer();
    await player.setPlayerMode(PlayerMode.lowLatency);
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setSource(AssetSource('sounds/$name.wav'));
    return player;
  }

  Future<void> play(double volume) async {
    await _ready;
    if (_players.isEmpty) return;
    final player = _players[_next];
    _next = (_next + 1) % _players.length;
    // A pool stream that has finished is still the player's stream, and
    // "start" on it only resumes what has already ended. Stopping first is
    // what makes the next start a fresh play.
    await player.stop();
    await player.setVolume(volume);
    await player.resume();
  }

  void dispose() {
    for (final p in _players) {
      p.dispose();
    }
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

  /// Fireworks under the fanfare on the game-over screen. A second sound
  /// rather than one longer one, because they are two different things: the
  /// fanfare says the game is finished, and this says the room is pleased
  /// about it. Kept separate they can also be levelled against each other.
  static const crackers = 'crackers';

  static const all = [die, step, home, capture, safe, victory, crackers];
}
