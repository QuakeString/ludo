import 'dart:convert';

import 'package:ludo_engine/ludo_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A local game, as it stood the last time anything happened in it.
///
/// Closing the app, a phone call, the system killing it for memory — none of
/// those should cost anybody the game they were halfway through. So every
/// local game is written down after each roll and each move, and the front
/// page offers it back.
///
/// The dice go in with it. [GameState.toJson] keeps them off the wire for good
/// reason, but this file never leaves the device that owns the game, and a
/// resumed game that rolled from a different chain would not be the same game.
class SavedGame {
  const SavedGame({
    required this.state,
    this.aiSeats = const {},
    this.elapsed = Duration.zero,
  });

  final GameState state;

  /// Who was playing the computer, and how hard. Part of the table rather than
  /// part of the rules, so the engine's state does not carry it.
  final Map<int, AiLevel> aiSeats;

  /// Time already spent at the table, so the clock on the result sheet counts
  /// the whole game and not just the part after it was resumed.
  final Duration elapsed;

  /// Bumped if the shape below ever changes in a way an old save cannot be
  /// read through. A save from another version is dropped, not guessed at.
  static const version = 1;

  Map<String, Object?> toJson() => {
    'v': version,
    'state': state.toJson(withDice: true),
    'ai': {for (final e in aiSeats.entries) '${e.key}': e.value.name},
    'ms': elapsed.inMilliseconds,
  };

  /// Null for anything that is not a save this version wrote.
  static SavedGame? fromJson(Object? j) {
    if (j is! Map<String, Object?> || j['v'] != version) return null;
    final state = GameState.fromJson(j['state'] as Map<String, Object?>);
    final ai = <int, AiLevel>{};
    for (final e in (j['ai'] as Map? ?? const {}).entries) {
      ai[int.parse(e.key as String)] = AiLevel.values.byName(e.value as String);
    }
    return SavedGame(
      state: state,
      aiSeats: ai,
      elapsed: Duration(milliseconds: (j['ms'] as num?)?.toInt() ?? 0),
    );
  }
}

/// Where the one saved local game lives.
///
/// One slot, not a list. A table on one phone is one game; starting another
/// is starting over, and a list of half-finished games nobody will go back to
/// is clutter on the front page.
///
/// Every failure here is swallowed. Storage being unavailable means a game
/// cannot be picked up again later, which is a pity but not a reason for the
/// game being played right now to stop.
class SavedGameStore {
  const SavedGameStore._();

  static const _key = 'ludo.savedGame';

  static Future<SavedGame?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(_key);
      if (text == null) return null;
      final saved = SavedGame.fromJson(jsonDecode(text));
      // A finished game is nothing to continue. One should never have been
      // written, but a save is read back far more often than it is checked.
      if (saved == null || saved.state.isOver) {
        await prefs.remove(_key);
        return null;
      }
      return saved;
    } catch (_) {
      return null;
    }
  }

  /// Saves land in the order they were made, without any queue here:
  /// every call waits on the same shared instance and resumes in turn, and
  /// [SharedPreferences] updates its own copy synchronously before it writes
  /// to disk, so a later save can never be overtaken by an earlier one.
  static Future<void> save(SavedGame game) async {
    final text = jsonEncode(game.toJson());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, text);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
