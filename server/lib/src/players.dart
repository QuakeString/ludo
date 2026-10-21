import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Everything the server remembers about one player between visits.
///
/// No account and no email: a player is an id the server minted, proven by a
/// secret only their phone holds. The rest — the name they chose, how many
/// games they have played — hangs off that.
class PlayerRecord {
  PlayerRecord({
    required this.id,
    required this.secretHash,
    required this.name,
    this.chosenName = false,
  });

  final String id;

  /// SHA-256 of the secret, never the secret itself, so the data file on its
  /// own is not enough to become anybody.
  String secretHash;
  String name;
  bool chosenName;

  Map<String, Object?> toJson() => {
        'id': id,
        'secret': secretHash,
        'name': name,
        'chosen': chosenName,
      };

  factory PlayerRecord.fromJson(Map<String, Object?> j) => PlayerRecord(
        id: j['id'] as String,
        secretHash: j['secret'] as String,
        name: j['name'] as String? ?? 'Guest',
        chosenName: j['chosen'] as bool? ?? false,
      );
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
    );
    _players[record.id] = record;
    changed();
    return (record, secret);
  }

  /// The player whose id and secret these are, or null.
  PlayerRecord? verify(String? id, String? secret) {
    if (id == null || secret == null) return null;
    final record = _players[id];
    if (record == null) return null;
    final given = hashSecret(secret);
    // Compared in full whatever the first difference, so the time it takes
    // says nothing about how close a guess was.
    if (given.length != record.secretHash.length) return null;
    var diff = 0;
    for (var i = 0; i < given.length; i++) {
      diff |= given.codeUnitAt(i) ^ record.secretHash.codeUnitAt(i);
    }
    return diff == 0 ? record : null;
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
