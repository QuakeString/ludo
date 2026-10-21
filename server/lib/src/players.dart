import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:ludo_protocol/ludo_protocol.dart';

/// Everything the server remembers about one player between visits.
///
/// No account and no email: a player is an id the server minted, proven by a
/// secret only their phone holds. The rest — the name they chose, how many
/// games they have played — hangs off that.
class PlayerRecord {
  PlayerRecord({
    required this.id,
    required String secretHash,
    required this.name,
    this.chosenName = false,
    this.friendCode = '',
    this.xp = 0,
    this.played = 0,
    this.won = 0,
    Map<String, String?>? friends,
    Set<String>? incoming,
    Set<String>? outgoing,
    List<MatchSummary>? history,
    this.avatar,
  })  : secretHashes = [if (secretHash.isNotEmpty) secretHash],
        friends = friends ?? {},
        incoming = incoming ?? {},
        outgoing = outgoing ?? {},
        history = history ?? [];

  final String id;

  /// SHA-256 of each secret that proves this player, never the secrets
  /// themselves, so the data file on its own is not enough to become anybody.
  /// One per phone the player has carried their identity to.
  final List<String> secretHashes;
  String name;
  bool chosenName;

  /// Their picture, as [Avatar] writes it, or null for none.
  String? avatar;

  /// What a friend types to send a request. Separate from [id], which every
  /// table shows.
  String friendCode;

  int xp;
  int played;
  int won;

  /// Friends, by id, with the nickname this player gave them (or null).
  final Map<String, String?> friends;

  /// Friend requests waiting on this player, and ones they sent.
  final Set<String> incoming;
  final Set<String> outgoing;

  /// The last [historyLength] matches, most recent first.
  final List<MatchSummary> history;

  static const historyLength = 20;

  /// The most phones one player can be on at once. Carrying them to another
  /// beyond that forgets the oldest.
  static const maxDevices = 5;

  int get level => levelFor(xp).level;

  void addSecretHash(String hash) {
    secretHashes.add(hash);
    while (secretHashes.length > maxDevices) {
      secretHashes.removeAt(0);
    }
  }

  void addMatch(MatchSummary match) {
    history.insert(0, match);
    if (history.length > historyLength) {
      history.removeRange(historyLength, history.length);
    }
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'secrets': secretHashes,
        'name': name,
        'chosen': chosenName,
        'code': friendCode,
        'xp': xp,
        'played': played,
        'won': won,
        'friends': friends,
        'in': incoming.toList(),
        'out': outgoing.toList(),
        'history': [for (final m in history) m.toJson()],
        if (avatar != null) 'avatar': avatar,
      };

  factory PlayerRecord.fromJson(Map<String, Object?> j) {
    final record = PlayerRecord(
      id: j['id'] as String,
      // Files from before a player could be on two phones hold one secret.
      secretHash: j['secret'] as String? ?? '',
      name: j['name'] as String? ?? 'Guest',
      chosenName: j['chosen'] as bool? ?? false,
      avatar: j['avatar'] as String?,
      friendCode: j['code'] as String? ?? '',
      xp: (j['xp'] as num?)?.toInt() ?? 0,
      played: (j['played'] as num?)?.toInt() ?? 0,
      won: (j['won'] as num?)?.toInt() ?? 0,
      friends: {
        for (final e in (j['friends'] as Map? ?? const {}).entries)
          e.key as String: e.value as String?
      },
      incoming: {for (final i in (j['in'] as List? ?? const [])) i as String},
      outgoing: {for (final i in (j['out'] as List? ?? const [])) i as String},
      history: [
        for (final m in (j['history'] as List? ?? const []))
          MatchSummary.fromJson(m as Map<String, Object?>)
      ],
    );
    for (final h in (j['secrets'] as List? ?? const [])) {
      if (!record.secretHashes.contains(h))
        record.secretHashes.add(h as String);
    }
    return record;
  }
}

/// Where players live.
///
/// One JSON file on disk, written a few seconds after anything changes and once
/// more on shutdown. That is deliberately small: a player is a few hundred
/// bytes, so even a very successful game is megabytes, and one file on a
/// mounted volume needs no database server to run, back up or pay for. With no
/// [file] the store is memory only, which is what the tests use.
class PlayerStore {
  PlayerStore(
      {this.file, Random? random, this.writeDelay = const Duration(seconds: 3)})
      : _random = random ?? Random.secure();

  final File? file;
  final Duration writeDelay;
  final Random _random;
  final Map<String, PlayerRecord> _players = {};
  final Map<String, String> _byFriendCode = {};
  Timer? _pending;

  int get length => _players.length;
  PlayerRecord? operator [](String id) => _players[id];
  Iterable<PlayerRecord> get all => _players.values;

  /// Reads the file if there is one. A missing file is a first run; a broken
  /// one is kept aside rather than overwritten, so nothing is lost to a bug.
  Future<void> load() async {
    final f = file;
    if (f == null || !await f.exists()) return;
    try {
      final data = jsonDecode(await f.readAsString()) as Map<String, Object?>;
      for (final p in (data['players'] as List? ?? const [])) {
        final record = PlayerRecord.fromJson(p as Map<String, Object?>);
        _players[record.id] = record;
      }
      // Players from before friend codes existed are given one now.
      for (final record in _players.values) {
        if (record.friendCode.isEmpty ||
            _byFriendCode.containsKey(record.friendCode)) {
          record.friendCode = _newFriendCode();
          changed();
        }
        _byFriendCode[record.friendCode] = record.id;
      }
    } catch (e) {
      final aside =
          File('${f.path}.broken-${DateTime.now().millisecondsSinceEpoch}');
      await f.copy(aside.path);
      stderr.writeln(
          'could not read ${f.path} ($e); kept a copy at ${aside.path}');
    }
  }

  /// A brand-new player, and the secret that proves it is them. The secret is
  /// returned once and never stored.
  (PlayerRecord, String) mint({String? name}) {
    final id = _token(9);
    final secret = _token(24);
    final record = PlayerRecord(
      id: 'g$id',
      secretHash: hashSecret(secret),
      name: cleanName(name) ?? guestName(),
      chosenName: cleanName(name) != null,
      friendCode: _newFriendCode(),
    );
    _players[record.id] = record;
    _byFriendCode[record.friendCode] = record.id;
    changed();
    return (record, secret);
  }

  /// The player whose id and secret these are, or null.
  PlayerRecord? verify(String? id, String? secret) {
    if (id == null || secret == null) return null;
    final record = _players[id];
    if (record == null) return null;
    final given = hashSecret(secret);
    var match = false;
    for (final known in record.secretHashes) {
      // Compared in full whatever the first difference, so the time it takes
      // says nothing about how close a guess was.
      if (given.length != known.length) continue;
      var diff = 0;
      for (var i = 0; i < given.length; i++) {
        diff |= given.codeUnitAt(i) ^ known.codeUnitAt(i);
      }
      match |= diff == 0;
    }
    return match ? record : null;
  }

  /// The player handing out [code], if anybody is.
  PlayerRecord? byFriendCode(String code) {
    final id = _byFriendCode[code.trim().toUpperCase().replaceAll('-', '')];
    return id == null ? null : _players[id];
  }

  /// A new secret for [record], for another phone. The old ones keep working.
  String addDevice(PlayerRecord record) {
    final secret = _token(24);
    record.addSecretHash(hashSecret(secret));
    changed();
    return secret;
  }

  /// Six letters and digits, in the same easy-to-read alphabet as room codes.
  String _newFriendCode() {
    const alphabet = 'BCDFGHJKLMNPQRSTVWXZ23456789';
    String make() =>
        List.generate(6, (_) => alphabet[_random.nextInt(alphabet.length)])
            .join();
    var code = make();
    while (_byFriendCode.containsKey(code)) {
      code = make();
    }
    return code;
  }

  /// Marks the store as needing a write, and schedules one.
  void changed() {
    if (file == null) return;
    _pending ??= Timer(writeDelay, () {
      _pending = null;
      flush();
    });
  }

  /// Writes now. To a temporary file first and then renamed over the old one,
  /// so a crash halfway through a write cannot leave half a file behind.
  Future<void> flush() async {
    _pending?.cancel();
    _pending = null;
    final f = file;
    if (f == null) return;
    final text = jsonEncode({
      'players': [for (final p in _players.values) p.toJson()],
    });
    await f.parent.create(recursive: true);
    final temp = File('${f.path}.tmp');
    await temp.writeAsString(text, flush: true);
    await temp.rename(f.path);
  }

  String guestName() => 'Guest_${1000 + _random.nextInt(9000)}';

  static String hashSecret(String secret) =>
      sha256.convert(utf8.encode(secret)).toString();

  /// Letters, digits, spaces and a little punctuation; 2 to 16 characters
  /// after trimming. Null when there is nothing usable left.
  static String? cleanName(String? raw) {
    if (raw == null) return null;
    final kept = raw
        .replaceAll(RegExp(r"[^\p{L}\p{N} _.'-]", unicode: true), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (kept.length < 2) return null;
    return kept.length > 16 ? kept.substring(0, 16).trim() : kept;
  }

  static const _alphabet =
      'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  String _token(int length) =>
      List.generate(length, (_) => _alphabet[_random.nextInt(_alphabet.length)])
          .join();
}
