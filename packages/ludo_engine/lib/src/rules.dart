import 'dart:convert';

import 'board.dart';

/// Who may capture a linked pair.
enum PairCapture {
  /// Nobody — a pair is safe.
  never,

  /// Only an opposing pair, landing as a pair.
  pairOnly,

  /// Anyone; a single token landing on a pair captures both.
  anyone,
}

/// Every rule the engine understands, as data.
///
/// Nothing about a variant is hard-coded: presets, the rule-builder UI and the
/// shareable rule code all produce one of these, and the same object is
/// enforced on the client and on the server.
class RuleConfig {
  const RuleConfig({
    this.name = 'Classic',
    this.players = 4,
    this.tokensPerPlayer = 4,
    this.entryRoll = 6,
    this.extraRollOnSix = true,
    this.tripleSixForfeits = true,
    this.captureGrantsExtraRoll = true,
    this.finishGrantsExtraRoll = true,
    this.safeSquares = SafeSquares.startsAndStars,
    this.exactHomeEntry = true,
    this.mustCaptureToWin = false,
    this.diceSides = 6,
    this.turnTimerDots = 0,
    this.secondsPerDot = 5,
    this.teams,
    this.partnersCanCapture = false,
    this.finishedPlayerMovesPartner = true,
    this.pairMove = false,
    this.pairMoveEvenOnly = true,
    this.pairAcrossPartners = true,
    this.pairLockedUntilSafe = true,
    this.pairCapture = PairCapture.pairOnly,
    this.fillEmptySeatsWithAI = true,
  });

  final String name;

  /// Seats at the table, 2–6. Five or six moves the game to the hexagon board.
  final int players;

  /// 2, 3 or 4 — the table's choice at every seat count.
  final int tokensPerPlayer;

  /// Roll needed to leave the yard. 0 means any roll will do.
  final int entryRoll;

  final bool extraRollOnSix;
  final bool tripleSixForfeits;

  /// Knocking an opponent off buys another roll.
  final bool captureGrantsExtraRoll;

  /// Bringing a chip home buys another roll.
  ///
  /// Both of these are on by default, because both are how the game is
  /// actually played: a six, a capture and a chip home each earn another
  /// throw. The capture rule was here but switched off, and this one was
  /// missing altogether, so two of the three ways of earning a turn did
  /// nothing.
  final bool finishGrantsExtraRoll;
  final SafeSquares safeSquares;

  /// Home must be entered on an exact count; an overshoot is not a legal move.
  final bool exactHomeEntry;

  /// No token may finish until its owner has captured at least once.
  final bool mustCaptureToWin;

  final int diceSides;

  /// Turn clock, drawn as dots. 0 disables it (the offline default).
  final int turnTimerDots;
  final int secondsPerDot;

  /// Seat indices grouped into teams, or null for a free-for-all.
  final List<List<int>>? teams;

  final bool partnersCanCapture;

  /// A player whose tokens are all home keeps rolling, moving a partner's.
  final bool finishedPlayerMovesPartner;

  // --- pair move -----------------------------------------------------------

  /// Two tokens sharing a square may link and travel as one.
  final bool pairMove;

  /// A linked pair advances only on an even roll, by half the pips.
  final bool pairMoveEvenOnly;

  /// In team games a pair may join your token to a partner's.
  final bool pairAcrossPartners;

  /// Once linked, a pair cannot be broken until it stands on a safe square.
  final bool pairLockedUntilSafe;

  final PairCapture pairCapture;

  final bool fillEmptySeatsWithAI;

  bool get isTeamGame => teams != null && teams!.isNotEmpty;

  int get turnSeconds => turnTimerDots * secondsPerDot;

  BoardSpec get board => BoardSpec.forPlayers(players);

  /// The team index a seat belongs to, or the seat itself when there are no
  /// teams — so "same side" is always `teamOf(a) == teamOf(b)`.
  int teamOf(int player) {
    final t = teams;
    if (t == null) return player;
    for (var i = 0; i < t.length; i++) {
      if (t[i].contains(player)) return i;
    }
    return player;
  }

  bool sameSide(int a, int b) =>
      a == b || (isTeamGame && teamOf(a) == teamOf(b));

  /// Seats on the same team as [player], excluding [player].
  List<int> partnersOf(int player) {
    final t = teams;
    if (t == null) return const [];
    for (final group in t) {
      if (group.contains(player)) {
        return [
          for (final p in group)
            if (p != player) p
        ];
      }
    }
    return const [];
  }

  RuleConfig copyWith({
    String? name,
    int? players,
    int? tokensPerPlayer,
    int? entryRoll,
    bool? extraRollOnSix,
    bool? tripleSixForfeits,
    bool? captureGrantsExtraRoll,
    bool? finishGrantsExtraRoll,
    SafeSquares? safeSquares,
    bool? exactHomeEntry,
    bool? mustCaptureToWin,
    int? diceSides,
    int? turnTimerDots,
    int? secondsPerDot,
    Object? teams = _unset,
    bool? partnersCanCapture,
    bool? finishedPlayerMovesPartner,
    bool? pairMove,
    bool? pairMoveEvenOnly,
    bool? pairAcrossPartners,
    bool? pairLockedUntilSafe,
    PairCapture? pairCapture,
    bool? fillEmptySeatsWithAI,
  }) {
    return RuleConfig(
      name: name ?? this.name,
      players: players ?? this.players,
      tokensPerPlayer: tokensPerPlayer ?? this.tokensPerPlayer,
      entryRoll: entryRoll ?? this.entryRoll,
      extraRollOnSix: extraRollOnSix ?? this.extraRollOnSix,
      tripleSixForfeits: tripleSixForfeits ?? this.tripleSixForfeits,
      captureGrantsExtraRoll:
          captureGrantsExtraRoll ?? this.captureGrantsExtraRoll,
      finishGrantsExtraRoll:
          finishGrantsExtraRoll ?? this.finishGrantsExtraRoll,
      safeSquares: safeSquares ?? this.safeSquares,
      exactHomeEntry: exactHomeEntry ?? this.exactHomeEntry,
      mustCaptureToWin: mustCaptureToWin ?? this.mustCaptureToWin,
      diceSides: diceSides ?? this.diceSides,
      turnTimerDots: turnTimerDots ?? this.turnTimerDots,
      secondsPerDot: secondsPerDot ?? this.secondsPerDot,
      teams:
          identical(teams, _unset) ? this.teams : (teams as List<List<int>>?),
      partnersCanCapture: partnersCanCapture ?? this.partnersCanCapture,
      finishedPlayerMovesPartner:
          finishedPlayerMovesPartner ?? this.finishedPlayerMovesPartner,
      pairMove: pairMove ?? this.pairMove,
      pairMoveEvenOnly: pairMoveEvenOnly ?? this.pairMoveEvenOnly,
      pairAcrossPartners: pairAcrossPartners ?? this.pairAcrossPartners,
      pairLockedUntilSafe: pairLockedUntilSafe ?? this.pairLockedUntilSafe,
      pairCapture: pairCapture ?? this.pairCapture,
      fillEmptySeatsWithAI: fillEmptySeatsWithAI ?? this.fillEmptySeatsWithAI,
    );
  }

  static const _unset = Object();

  /// Throws [RuleConfigError] if this config could never produce a legal game.
  void validate() {
    void check(bool ok, String message) {
      if (!ok) throw RuleConfigError(message);
    }

    check(players >= 2 && players <= 6, 'players must be 2–6, got $players');
    check(tokensPerPlayer >= 1 && tokensPerPlayer <= 4,
        'tokensPerPlayer must be 1–4, got $tokensPerPlayer');
    check(diceSides >= 2, 'diceSides must be at least 2, got $diceSides');
    check(entryRoll >= 0 && entryRoll <= diceSides,
        'entryRoll must be 0 (any) or 1–$diceSides, got $entryRoll');
    check(turnTimerDots >= 0, 'turnTimerDots cannot be negative');
    check(secondsPerDot > 0, 'secondsPerDot must be positive');

    final t = teams;
    if (t != null) {
      final seen = <int>{};
      for (final group in t) {
        check(group.length >= 1, 'a team cannot be empty');
        for (final p in group) {
          check(
              p >= 0 && p < players,
              'team references seat $p, which does '
              'not exist in a $players-seat game');
          check(seen.add(p), 'seat $p appears in more than one team');
        }
      }
      check(seen.length == players,
          'every seat must be on a team; ${players - seen.length} left out');
      check(t.length >= 2, 'a team game needs at least two teams');
      final sizes = t.map((g) => g.length).toSet();
      check(
          sizes.length == 1,
          'teams must be the same size, got '
          '${t.map((g) => g.length).join(' v ')}');
    }

    if (pairMove && pairAcrossPartners) {
      check(isTeamGame || !pairAcrossPartners || t == null,
          'pairAcrossPartners needs a team game');
    }
  }

  // --- serialisation -------------------------------------------------------

  Map<String, Object?> toJson() => {
        'name': name,
        'players': players,
        'tokensPerPlayer': tokensPerPlayer,
        'entryRoll': entryRoll,
        'extraRollOnSix': extraRollOnSix,
        'tripleSixForfeits': tripleSixForfeits,
        'captureGrantsExtraRoll': captureGrantsExtraRoll,
        'finishGrantsExtraRoll': finishGrantsExtraRoll,
        'safeSquares': safeSquares.name,
        'exactHomeEntry': exactHomeEntry,
        'mustCaptureToWin': mustCaptureToWin,
        'diceSides': diceSides,
        'turnTimerDots': turnTimerDots,
        'secondsPerDot': secondsPerDot,
        if (teams != null) 'teams': teams,
        'partnersCanCapture': partnersCanCapture,
        'finishedPlayerMovesPartner': finishedPlayerMovesPartner,
        'pairMove': pairMove,
        'pairMoveEvenOnly': pairMoveEvenOnly,
        'pairAcrossPartners': pairAcrossPartners,
        'pairLockedUntilSafe': pairLockedUntilSafe,
        'pairCapture': pairCapture.name,
        'fillEmptySeatsWithAI': fillEmptySeatsWithAI,
      };

  factory RuleConfig.fromJson(Map<String, Object?> json) {
    T pick<T>(String key, T fallback) {
      final v = json[key];
      return v is T ? v : fallback;
    }

    const defaults = RuleConfig();
    final rawTeams = json['teams'];
    return RuleConfig(
      name: pick('name', defaults.name),
      players: pick('players', defaults.players),
      tokensPerPlayer: pick('tokensPerPlayer', defaults.tokensPerPlayer),
      entryRoll: pick('entryRoll', defaults.entryRoll),
      extraRollOnSix: pick('extraRollOnSix', defaults.extraRollOnSix),
      tripleSixForfeits: pick('tripleSixForfeits', defaults.tripleSixForfeits),
      captureGrantsExtraRoll:
          pick('captureGrantsExtraRoll', defaults.captureGrantsExtraRoll),
      finishGrantsExtraRoll:
          pick('finishGrantsExtraRoll', defaults.finishGrantsExtraRoll),
      safeSquares: SafeSquares.values.firstWhere(
        (s) => s.name == json['safeSquares'],
        orElse: () => defaults.safeSquares,
      ),
      exactHomeEntry: pick('exactHomeEntry', defaults.exactHomeEntry),
      mustCaptureToWin: pick('mustCaptureToWin', defaults.mustCaptureToWin),
      diceSides: pick('diceSides', defaults.diceSides),
      turnTimerDots: pick('turnTimerDots', defaults.turnTimerDots),
      secondsPerDot: pick('secondsPerDot', defaults.secondsPerDot),
      teams: rawTeams is List
          ? [
              for (final g in rawTeams)
                if (g is List) [for (final p in g) (p as num).toInt()]
            ]
          : null,
      partnersCanCapture:
          pick('partnersCanCapture', defaults.partnersCanCapture),
      finishedPlayerMovesPartner: pick(
          'finishedPlayerMovesPartner', defaults.finishedPlayerMovesPartner),
      pairMove: pick('pairMove', defaults.pairMove),
      pairMoveEvenOnly: pick('pairMoveEvenOnly', defaults.pairMoveEvenOnly),
      pairAcrossPartners:
          pick('pairAcrossPartners', defaults.pairAcrossPartners),
      pairLockedUntilSafe:
          pick('pairLockedUntilSafe', defaults.pairLockedUntilSafe),
      pairCapture: PairCapture.values.firstWhere(
        (p) => p.name == json['pairCapture'],
        orElse: () => defaults.pairCapture,
      ),
      fillEmptySeatsWithAI:
          pick('fillEmptySeatsWithAI', defaults.fillEmptySeatsWithAI),
    );
  }

  /// Short keys for the shareable code. Only what differs from the defaults
  /// is written, so a lightly-tweaked rule set stays short enough to paste
  /// into a chat message.
  static const _shortKeys = <String, String>{
    'name': 'n',
    'players': 'p',
    'tokensPerPlayer': 't',
    'entryRoll': 'e',
    'extraRollOnSix': 'x',
    'tripleSixForfeits': 'f',
    'captureGrantsExtraRoll': 'c',
    'finishGrantsExtraRoll': 'g',
    'safeSquares': 's',
    'exactHomeEntry': 'h',
    'mustCaptureToWin': 'm',
    'diceSides': 'd',
    'turnTimerDots': 'o',
    'secondsPerDot': 'q',
    'teams': 'T',
    'partnersCanCapture': 'P',
    'finishedPlayerMovesPartner': 'F',
    'pairMove': 'M',
    'pairMoveEvenOnly': 'E',
    'pairAcrossPartners': 'A',
    'pairLockedUntilSafe': 'L',
    'pairCapture': 'C',
    'fillEmptySeatsWithAI': 'I',
  };

  /// A short code friends can paste. Classic rules encode to a handful of
  /// characters because nothing needs saying.
  String toRuleCode() {
    final mine = toJson();
    final base = const RuleConfig().toJson();
    final diff = <String, Object?>{};
    for (final entry in mine.entries) {
      if (jsonEncode(entry.value) == jsonEncode(base[entry.key])) continue;
      diff[_shortKeys[entry.key] ?? entry.key] = entry.value;
    }
    final packed = base64Url.encode(utf8.encode(jsonEncode(diff)));
    return 'LUDO-${packed.replaceAll('=', '')}';
  }

  /// Parses a code produced by [toRuleCode]. Throws [RuleConfigError] on
  /// anything that is not a rule code we wrote.
  factory RuleConfig.fromRuleCode(String code) {
    final trimmed = code.trim().toUpperCase().startsWith('LUDO-')
        ? code.trim().substring(5)
        : code.trim();
    if (trimmed.isEmpty) throw RuleConfigError('empty rule code');
    try {
      final padded = trimmed.padRight((trimmed.length + 3) ~/ 4 * 4, '=');
      final decoded = jsonDecode(utf8.decode(base64Url.decode(padded)));
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('rule code did not contain an object');
      }
      final longKeys = {
        for (final e in _shortKeys.entries) e.value: e.key,
      };
      final json = <String, Object?>{
        for (final e in decoded.entries) longKeys[e.key] ?? e.key: e.value,
      };
      return RuleConfig.fromJson(json)..validate();
    } on RuleConfigError {
      rethrow;
    } catch (e) {
      throw RuleConfigError('that does not look like a rule code ($e)');
    }
  }

  @override
  String toString() => 'RuleConfig($name, ${players}p, '
      '${tokensPerPlayer} tokens${isTeamGame ? ', teams' : ''})';

  // --- presets -------------------------------------------------------------

  static const classic = RuleConfig();

  static const quick = RuleConfig(
    name: 'Quick',
    tokensPerPlayer: 2,
    entryRoll: 0,
  );

  static const aggressive = RuleConfig(
    name: 'Aggressive',
    captureGrantsExtraRoll: true,
    mustCaptureToWin: true,
    safeSquares: SafeSquares.stars,
  );

  /// Six seats, three tokens each, pairing on — the six-player default.
  static const sixSeat = RuleConfig(
    name: 'Six seats',
    players: 6,
    tokensPerPlayer: 3,
    pairMove: true,
  );

  static const presets = <RuleConfig>[classic, quick, aggressive, sixSeat];
}

class RuleConfigError implements Exception {
  RuleConfigError(this.message);
  final String message;
  @override
  String toString() => 'RuleConfigError: $message';
}
