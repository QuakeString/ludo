import 'dart:convert';

import 'package:ludo_engine/ludo_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A finished game, kept so its numbers can be looked at again later.
///
/// The result sheet used to be the only place a game's stats ever appeared,
/// and it went the moment anybody pressed a button. So the final position is
/// written down with everything the stats page needs to draw it again: who
/// sat where, which seats were the computer, how long it took.
///
/// The position goes in without its dice. Nothing is ever played from it, so
/// the chain they were rolled from has no use here.
class MatchRecord {
  const MatchRecord({
    required this.state,
    required this.finishedAt,
    required this.elapsed,
    required this.names,
    this.aiSeats = const {},
    this.online = false,
  });

  final GameState state;
  final DateTime finishedAt;
  final Duration elapsed;

  /// What each seat was called at the table, in seat order.
  final List<String> names;
  final Map<int, AiLevel> aiSeats;
  final bool online;

  String nameOf(int seat) => seat < names.length ? names[seat] : '?';

  static const version = 1;

  Map<String, Object?> toJson() => {
    'v': version,
    'state': state.toJson(),
    'at': finishedAt.toUtc().toIso8601String(),
    'ms': elapsed.inMilliseconds,
    'names': names,
    'ai': {for (final e in aiSeats.entries) '${e.key}': e.value.name},
    'online': online,
  };

  /// Null for anything that is not a record this version wrote.
  static MatchRecord? fromJson(Object? j) {
    if (j is! Map<String, Object?> || j['v'] != version) return null;
    final ai = <int, AiLevel>{};
    for (final e in (j['ai'] as Map? ?? const {}).entries) {
      ai[int.parse(e.key as String)] = AiLevel.values.byName(e.value as String);
    }
    return MatchRecord(
      state: GameState.fromJson(j['state'] as Map<String, Object?>),
      finishedAt: DateTime.parse(j['at'] as String).toLocal(),
      elapsed: Duration(milliseconds: (j['ms'] as num?)?.toInt() ?? 0),
      names: [for (final n in j['names'] as List? ?? const []) '$n'],
      aiSeats: ai,
      online: j['online'] == true,
    );
  }
}

/// The last few finished games on this device, newest first.
///
/// Like [SavedGameStore], every failure is swallowed: a game that cannot be
/// written into the history is still a game that was played.
class MatchHistoryStore {
  const MatchHistoryStore._();

  static const _key = 'ludo.history';

  /// How many games are kept. Older ones drop off the end.
  static const keep = 10;

  static Future<List<MatchRecord>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(_key);
      if (text == null) return const [];
      final list = jsonDecode(text);
      if (list is! List) return const [];
      final out = <MatchRecord>[];
      for (final item in list) {
        // One unreadable entry costs that entry, not the whole history.
        try {
          final record = MatchRecord.fromJson(item);
          if (record != null) out.add(record);
        } catch (_) {}
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Puts [record] at the top, unless the same finished position is already
  /// there — an online table that is reopened after its game ended shows the
  /// same result again, and that is still one game.
  static Future<void> add(MatchRecord record) async {
    try {
      final current = await load();
      // The whole position with its stats, not just where the chips are: two
      // short games can easily end with every chip in the same place.
      String same(MatchRecord r) => jsonEncode(r.state.toJson());
      final mine = same(record);
      if (current.any((r) => same(r) == mine)) return;
      final next = [record, ...current].take(keep).toList();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode([for (final r in next) r.toJson()]),
      );
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
