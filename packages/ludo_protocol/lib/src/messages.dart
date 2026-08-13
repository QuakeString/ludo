import 'dart:convert';

import 'package:ludo_engine/ludo_engine.dart';

/// What a room is doing right now.
enum RoomPhase { lobby, playing, finished }

/// One seat in a room, as everyone else sees it.
class SeatInfo {
  const SeatInfo({
    required this.seat,
    this.playerId,
    this.displayName,
    this.isComputer = false,
    this.connected = true,
    this.ready = false,
    this.level = 1,
  });

  final int seat;

  /// Null when the seat is empty.
  final String? playerId;
  final String? displayName;
  final bool isComputer;

  /// False while a player is away; their seat is held rather than freed.
  final bool connected;
  final bool ready;
  final int level;

  bool get isEmpty => playerId == null && !isComputer;

  Map<String, Object?> toJson() => {
        'seat': seat,
        if (playerId != null) 'playerId': playerId,
        if (displayName != null) 'name': displayName,
        'ai': isComputer,
        'connected': connected,
        'ready': ready,
        'level': level,
      };

  factory SeatInfo.fromJson(Map<String, Object?> j) => SeatInfo(
        seat: (j['seat'] as num).toInt(),
        playerId: j['playerId'] as String?,
        displayName: j['name'] as String?,
        isComputer: j['ai'] as bool? ?? false,
        connected: j['connected'] as bool? ?? true,
        ready: j['ready'] as bool? ?? false,
        level: (j['level'] as num?)?.toInt() ?? 1,
      );
}

/// Everything the client needs to draw a lobby.
class RoomInfo {
  const RoomInfo({
    required this.code,
    required this.phase,
    required this.rules,
    required this.seats,
    required this.hostId,
    this.fillEmptySeatsWithAI = true,
  });

  final String code;
  final RoomPhase phase;
  final RuleConfig rules;
  final List<SeatInfo> seats;
  final String hostId;
  final bool fillEmptySeatsWithAI;

  Map<String, Object?> toJson() => {
        'code': code,
        'phase': phase.name,
        'rules': rules.toJson(),
        'seats': [for (final s in seats) s.toJson()],
        'host': hostId,
        'fillAi': fillEmptySeatsWithAI,
      };

  factory RoomInfo.fromJson(Map<String, Object?> j) => RoomInfo(
        code: j['code'] as String,
        phase: RoomPhase.values.firstWhere((p) => p.name == j['phase'],
            orElse: () => RoomPhase.lobby),
        rules: RuleConfig.fromJson(j['rules'] as Map<String, Object?>),
        seats: [
          for (final s in (j['seats'] as List))
            SeatInfo.fromJson(s as Map<String, Object?>)
        ],
        hostId: j['host'] as String? ?? '',
        fillEmptySeatsWithAI: j['fillAi'] as bool? ?? true,
      );
}

/// Base of everything that crosses the wire, in both directions.
///
/// One sealed family shared by the app and the server, so the two cannot drift
/// apart: a new message has to be added here, and both sides then fail to
/// compile until they handle it.
sealed class Envelope {
  const Envelope();

  String get type;
  Map<String, Object?> payload();

  String encode() => jsonEncode({'t': type, ...payload()});

  static Envelope decode(String raw) {
    final j = jsonDecode(raw) as Map<String, Object?>;
    final t = j['t'] as String?;
    return switch (t) {
      'hello' => Hello.fromJson(j),
      'welcome' => Welcome.fromJson(j),
      'createRoom' => CreateRoom.fromJson(j),
      'joinRoom' => JoinRoom.fromJson(j),
      'leaveRoom' => const LeaveRoom(),
      'setReady' => SetReady.fromJson(j),
      'addComputer' => AddComputer.fromJson(j),
      'startMatch' => const StartMatch(),
      'play' => Play.fromJson(j),
      'room' => RoomUpdate.fromJson(j),
      'match' => MatchUpdate.fromJson(j),
      'oops' => Oops.fromJson(j),
      'ping' => const Ping(),
      'pong' => const Pong(),
      _ => throw FormatException('unknown message "$t"'),
    };
  }
}

// --- app to server ---------------------------------------------------------

/// First thing a client sends. [guestId] returns an existing anonymous
/// identity; leaving it out asks the server to mint one.
class Hello extends Envelope {
  const Hello({this.guestId, this.displayName});
  final String? guestId;
  final String? displayName;

  @override
  String get type => 'hello';
  @override
  Map<String, Object?> payload() => {
        if (guestId != null) 'guestId': guestId,
        if (displayName != null) 'name': displayName,
      };

  factory Hello.fromJson(Map<String, Object?> j) => Hello(
        guestId: j['guestId'] as String?,
        displayName: j['name'] as String?,
      );
}

class CreateRoom extends Envelope {
  const CreateRoom({required this.rules, this.fillEmptySeatsWithAI = true});
  final RuleConfig rules;

  /// The host's choice, never automatic — an empty seat may simply stay empty.
  final bool fillEmptySeatsWithAI;

  @override
  String get type => 'createRoom';
  @override
  Map<String, Object?> payload() =>
      {'rules': rules.toJson(), 'fillAi': fillEmptySeatsWithAI};

  factory CreateRoom.fromJson(Map<String, Object?> j) => CreateRoom(
        rules: RuleConfig.fromJson(j['rules'] as Map<String, Object?>),
        fillEmptySeatsWithAI: j['fillAi'] as bool? ?? true,
      );
}

class JoinRoom extends Envelope {
  const JoinRoom(this.code);
  final String code;

  @override
  String get type => 'joinRoom';
  @override
  Map<String, Object?> payload() => {'code': code};

  factory JoinRoom.fromJson(Map<String, Object?> j) =>
      JoinRoom(j['code'] as String);
}

class LeaveRoom extends Envelope {
  const LeaveRoom();
  @override
  String get type => 'leaveRoom';
  @override
  Map<String, Object?> payload() => const {};
}

class SetReady extends Envelope {
  const SetReady(this.ready);
  final bool ready;

  @override
  String get type => 'setReady';
  @override
  Map<String, Object?> payload() => {'ready': ready};

  factory SetReady.fromJson(Map<String, Object?> j) =>
      SetReady(j['ready'] as bool? ?? false);
}

/// Host fills an empty seat with a computer player.
class AddComputer extends Envelope {
  const AddComputer({required this.seat, this.level = AiLevel.normal});
  final int seat;
  final AiLevel level;

  @override
  String get type => 'addComputer';
  @override
  Map<String, Object?> payload() => {'seat': seat, 'level': level.name};

  factory AddComputer.fromJson(Map<String, Object?> j) => AddComputer(
        seat: (j['seat'] as num).toInt(),
        level: AiLevel.values.firstWhere((l) => l.name == j['level'],
            orElse: () => AiLevel.normal),
      );
}

class StartMatch extends Envelope {
  const StartMatch();
  @override
  String get type => 'startMatch';
  @override
  Map<String, Object?> payload() => const {};
}

/// A move intent. The client never sends a resulting state — only what it
/// wants to do — so it cannot talk the server out of the rules.
class Play extends Envelope {
  const Play(
      {required this.action, this.tokenId, this.toProgress, this.pairId});

  /// One of: roll, move, pass, formPair, breakPair.
  final String action;
  final int? tokenId;
  final int? toProgress;
  final int? pairId;

  @override
  String get type => 'play';
  @override
  Map<String, Object?> payload() => {
        'a': action,
        if (tokenId != null) 'token': tokenId,
        if (toProgress != null) 'to': toProgress,
        if (pairId != null) 'pair': pairId,
      };

  factory Play.fromJson(Map<String, Object?> j) => Play(
        action: j['a'] as String,
        tokenId: (j['token'] as num?)?.toInt(),
        toProgress: (j['to'] as num?)?.toInt(),
        pairId: (j['pair'] as num?)?.toInt(),
      );

  static Play roll() => const Play(action: 'roll');
  static Play pass() => const Play(action: 'pass');
  static Play move(Move m) => Play(
        action: 'move',
        tokenId: m.tokenId,
        toProgress: m.toProgress,
      );
}

// --- server to app ---------------------------------------------------------

class Welcome extends Envelope {
  const Welcome({required this.playerId, required this.displayName});
  final String playerId;
  final String displayName;

  @override
  String get type => 'welcome';
  @override
  Map<String, Object?> payload() => {'playerId': playerId, 'name': displayName};

  factory Welcome.fromJson(Map<String, Object?> j) => Welcome(
        playerId: j['playerId'] as String,
        displayName: j['name'] as String,
      );
}

class RoomUpdate extends Envelope {
  const RoomUpdate(this.room);
  final RoomInfo room;

  @override
  String get type => 'room';
  @override
  Map<String, Object?> payload() => {'room': room.toJson()};

  factory RoomUpdate.fromJson(Map<String, Object?> j) =>
      RoomUpdate(RoomInfo.fromJson(j['room'] as Map<String, Object?>));
}

/// The authoritative position after something happened.
///
/// [yourSeat] saves the client working out which of the seats is theirs, and
/// [secondsLeft] drives the turn clock without the client having to trust its
/// own idea of when the turn started.
class MatchUpdate extends Envelope {
  const MatchUpdate({
    required this.state,
    required this.yourSeat,
    this.lastMove,
    this.secondsLeft,
    this.autoPlayed = false,
  });

  final GameState state;
  final int yourSeat;

  /// What just happened, so the client can animate it rather than snap.
  final Move? lastMove;
  final int? secondsLeft;

  /// True when the clock ran out and the server moved for someone.
  final bool autoPlayed;

  @override
  String get type => 'match';
  @override
  Map<String, Object?> payload() => {
        'state': state.toJson(),
        'seat': yourSeat,
        if (lastMove != null)
          'move': {
            'kind': lastMove!.kind.name,
            'tokens': lastMove!.tokenIds,
            'owner': lastMove!.owner,
            'from': lastMove!.fromProgress,
            'to': lastMove!.toProgress,
            'captured': lastMove!.capturedTokenIds,
          },
        if (secondsLeft != null) 'secs': secondsLeft,
        'auto': autoPlayed,
      };

  factory MatchUpdate.fromJson(Map<String, Object?> j) {
    final m = j['move'] as Map<String, Object?>?;
    return MatchUpdate(
      state: GameState.fromJson(j['state'] as Map<String, Object?>),
      yourSeat: (j['seat'] as num).toInt(),
      lastMove: m == null
          ? null
          : Move(
              kind: MoveKind.values.firstWhere((k) => k.name == m['kind'],
                  orElse: () => MoveKind.advance),
              tokenIds: [
                for (final t in (m['tokens'] as List)) (t as num).toInt()
              ],
              owner: (m['owner'] as num).toInt(),
              steps: 0,
              fromProgress: (m['from'] as num).toInt(),
              toProgress: (m['to'] as num).toInt(),
              capturedTokenIds: [
                for (final c in (m['captured'] as List? ?? const []))
                  (c as num).toInt()
              ],
            ),
      secondsLeft: (j['secs'] as num?)?.toInt(),
      autoPlayed: j['auto'] as bool? ?? false,
    );
  }
}

/// Something was refused. Carrying the reason matters: the client shows it
/// rather than silently doing nothing.
class Oops extends Envelope {
  const Oops(this.message, {this.code});
  final String message;
  final String? code;

  @override
  String get type => 'oops';
  @override
  Map<String, Object?> payload() =>
      {'msg': message, if (code != null) 'code': code};

  factory Oops.fromJson(Map<String, Object?> j) =>
      Oops(j['msg'] as String, code: j['code'] as String?);
}

class Ping extends Envelope {
  const Ping();
  @override
  String get type => 'ping';
  @override
  Map<String, Object?> payload() => const {};
}

class Pong extends Envelope {
  const Pong();
  @override
  String get type => 'pong';
  @override
  Map<String, Object?> payload() => const {};
}
