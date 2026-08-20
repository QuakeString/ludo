import 'dart:math';

import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_protocol/ludo_protocol.dart';

/// Anything that can be sent a message — a live socket in production, a list
/// in tests. Keeping the room ignorant of sockets is what lets a whole match be
/// tested without opening a port.
abstract class Client {
  String get playerId;
  String get displayName;
  void send(Envelope message);
}

/// A seat at a table.
class Seat {
  Seat(this.index);

  final int index;
  Client? client;
  AiLevel? computer;
  bool ready = false;

  /// Set when a player drops; their seat is held rather than freed.
  DateTime? droppedAt;

  bool get isComputer => computer != null;
  bool get isEmpty => client == null && computer == null;
  bool get connected => client != null;

  SeatInfo toInfo() => SeatInfo(
        seat: index,
        playerId: client?.playerId,
        displayName: client?.displayName ?? (isComputer ? 'Computer' : null),
        isComputer: isComputer,
        connected: connected || isComputer,
        ready: ready || isComputer,
      );
}

/// One table: a lobby that becomes a match.
///
/// The room is the authority. Clients send what they *want* to do; the room
/// asks the same engine the app uses whether that is legal, applies it, and
/// broadcasts the result. A client cannot send a state, only an intent, so
/// there is nothing for a modified app to lie about.
class Room {
  Room({
    required this.code,
    required this.rules,
    required this.hostId,
    this.fillEmptySeatsWithAI = true,
    int? seed,
    DateTime Function()? clock,
  })  : _seed = seed ?? Random.secure().nextInt(0x7FFFFFFF) + 1,
        _now = clock ?? DateTime.now {
    for (var i = 0; i < rules.players; i++) {
      seats.add(Seat(i));
    }
  }

  static const engine = LudoEngine();

  /// How long a dropped player's seat is held before the seat is given up.
  static const reconnectWindow = Duration(minutes: 5);

  final String code;
  final RuleConfig rules;
  final String hostId;
  final bool fillEmptySeatsWithAI;
  final int _seed;
  final DateTime Function() _now;

  final List<Seat> seats = [];
  RoomPhase phase = RoomPhase.lobby;
  GameState? game;
  Move? lastMove;

  /// When the seat on turn started thinking, for the turn clock.
  DateTime? turnStartedAt;
  bool lastWasAutoPlay = false;

  Iterable<Client> get _clients =>
      seats.map((s) => s.client).whereType<Client>();

  RoomInfo toInfo() => RoomInfo(
        code: code,
        phase: phase,
        rules: rules,
        seats: [for (final s in seats) s.toInfo()],
        hostId: hostId,
        fillEmptySeatsWithAI: fillEmptySeatsWithAI,
      );

  // --- lobby ---------------------------------------------------------------

  /// Seats a player, or returns why not. A player already in the room is
  /// reconnecting and gets their own seat back.
  String? join(Client client) {
    final existing = seats.where((s) => s.client?.playerId == client.playerId);
    if (existing.isNotEmpty) {
      existing.first
        ..client = client
        ..droppedAt = null;
      broadcastRoom();
      _sendMatchTo(existing.first);
      return null;
    }

    final held = seats.where(
        (s) => s.droppedAt != null && s.client == null && s.computer == null);
    // Prefer a seat this player was holding; otherwise take a free one.
    final free = seats.where((s) => s.isEmpty && s.droppedAt == null);
    final target =
        free.isNotEmpty ? free.first : (held.isNotEmpty ? held.first : null);
    if (target == null) return 'that room is full';
    if (phase == RoomPhase.playing && free.isEmpty && held.isEmpty) {
      return 'that match has already started';
    }

    target
      ..client = client
      ..droppedAt = null;
    broadcastRoom();
    if (phase == RoomPhase.playing) _sendMatchTo(target);
    return null;
  }

  void leave(String playerId) {
    for (final seat in seats) {
      if (seat.client?.playerId != playerId) continue;
      if (phase == RoomPhase.playing) {
        // Hold the seat: the game carries on with the computer covering, and
        // the player takes it back mid-match if they return in time.
        seat
          ..client = null
          ..droppedAt = _now();
      } else {
        seat
          ..client = null
          ..ready = false
          ..droppedAt = null;
      }
    }
    broadcastRoom();
  }

  String? setReady(String playerId, bool ready) {
    for (final seat in seats) {
      if (seat.client?.playerId == playerId) seat.ready = ready;
    }
    broadcastRoom();
    return null;
  }

  String? addComputer(String playerId, int seatIndex, AiLevel level) {
    if (playerId != hostId) return 'only the host can add computer players';
    if (phase != RoomPhase.lobby) return 'the match has already started';
    if (seatIndex < 0 || seatIndex >= seats.length) return 'no such seat';
    final seat = seats[seatIndex];
    if (seat.client != null) return 'somebody is sitting there';
    seat.computer = level;
    broadcastRoom();
    return null;
  }

  String? start(String playerId) {
    if (playerId != hostId) return 'only the host can start the match';
    if (phase != RoomPhase.lobby) return 'the match has already started';

    final humans = seats.where((s) => s.client != null).length;
    if (humans + seats.where((s) => s.isComputer).length < 2) {
      return 'a match needs at least two players';
    }
    if (fillEmptySeatsWithAI) {
      for (final seat in seats.where((s) => s.isEmpty)) {
        seat.computer = AiLevel.normal;
      }
    } else if (seats.any((s) => s.isEmpty)) {
      // Playing a seat short is allowed, but the rules have to match the
      // number actually sitting down. Name the way out that the lobby actually
      // offers — telling a host to change a setting they cannot reach from
      // here is a dead end, not an error message.
      return 'some seats are still empty — add computer players to fill them, '
          'or wait for more people';
    }

    phase = RoomPhase.playing;
    game = GameState.newGame(rules, seed: _seed);
    turnStartedAt = _now();
    broadcastRoom();
    broadcastMatch();
    driveComputers();
    return null;
  }

  // --- the match -----------------------------------------------------------

  /// Applies an intent from [playerId], or returns why it was refused.
  String? play(String playerId, Play intent) {
    final state = game;
    if (state == null || phase != RoomPhase.playing) return 'no match running';

    final seat = seats.where((s) => s.client?.playerId == playerId);
    if (seat.isEmpty) return 'you are not in this match';
    if (seat.first.index != state.turn) return 'it is not your turn';

    final action = _actionFor(state, intent);
    if (action == null) return 'that move is not available';

    try {
      game = engine.apply(state, action);
    } on IllegalActionError catch (e) {
      return e.message;
    }
    _afterMove(action);
    return null;
  }

  GameAction? _actionFor(GameState s, Play intent) {
    switch (intent.action) {
      case 'roll':
        return const RollDice();
      case 'pass':
        return const PassTurn();
      case 'breakPair':
        return intent.pairId == null ? null : BreakPair(intent.pairId!);
      case 'move':
        // Match the intent against what the engine actually offers rather than
        // trusting the numbers that arrived.
        final wanted = engine.legalMoves(s).where((m) =>
            m.tokenId == intent.tokenId && m.toProgress == intent.toProgress);
        return wanted.isEmpty ? null : PlayMove(wanted.first);
      default:
        return null;
    }
  }

  void _afterMove(GameAction action) {
    lastMove = action is PlayMove ? action.move : null;
    turnStartedAt = _now();
    if (game!.isOver) phase = RoomPhase.finished;
    broadcastMatch();
    lastWasAutoPlay = false;
    if (!game!.isOver) driveComputers();
  }

  /// Plays out every consecutive computer turn, and covers for anyone who has
  /// dropped. Called after each human move, so a table never waits on a seat
  /// nobody is sitting in.
  void driveComputers({int guard = 60}) {
    var steps = 0;
    while (phase == RoomPhase.playing && !game!.isOver && steps++ < guard) {
      final seat = seats[game!.turn];
      final level = seat.computer ??
          (seat.client == null && seat.droppedAt != null
              ? AiLevel.normal // covering for an absent player
              : null);
      if (level == null) return;

      final ai = LudoAi(level: level);
      final before = game!;
      game = ai.playTurn(before);
      if (identical(game, before) ||
          game!.fingerprint() == before.fingerprint()) {
        return; // nothing changed; do not spin
      }
      lastMove = null;
      turnStartedAt = _now();
      if (game!.isOver) phase = RoomPhase.finished;
      broadcastMatch();
    }
  }

  /// The turn clock. Call periodically; when the seat on turn has run out of
  /// time the server plays for them and moves the game on.
  void tick() {
    // Reclaiming an abandoned seat is not the turn clock's job — a table with
    // no clock still must not hold a place for a player who is never coming
    // back.
    _reclaimAbandonedSeats();

    if (phase != RoomPhase.playing || game == null || game!.isOver) return;
    final limit = rules.turnSeconds;
    if (limit <= 0) return;
    final started = turnStartedAt;
    if (started == null) return;
    if (_now().difference(started).inSeconds < limit) return;

    final before = game!;
    game = const LudoAi(level: AiLevel.normal).playTurn(before);
    lastWasAutoPlay = true;
    lastMove = null;
    turnStartedAt = _now();
    if (game!.isOver) phase = RoomPhase.finished;
    broadcastMatch();
    if (!game!.isOver) driveComputers();
  }

  /// A seat held past its window is given up to the computer, so a dead client
  /// cannot keep a place at the table for ever.
  void _reclaimAbandonedSeats() {
    var changed = false;
    for (final seat in seats) {
      final dropped = seat.droppedAt;
      if (dropped == null) continue;
      if (_now().difference(dropped) <= reconnectWindow) continue;
      seat
        ..droppedAt = null
        ..computer = phase == RoomPhase.playing ? AiLevel.normal : null;
      changed = true;
    }
    if (changed) {
      broadcastRoom();
      if (phase == RoomPhase.playing) driveComputers();
    }
  }

  /// Seconds left on the current turn, or null when the clock is off.
  int? get secondsLeft {
    final limit = rules.turnSeconds;
    if (limit <= 0 || turnStartedAt == null) return null;
    final gone = _now().difference(turnStartedAt!).inSeconds;
    return (limit - gone).clamp(0, limit);
  }

  // --- sending -------------------------------------------------------------

  void broadcastRoom() {
    final message = RoomUpdate(toInfo());
    for (final c in _clients) {
      c.send(message);
    }
  }

  void broadcastMatch() {
    for (final seat in seats) {
      _sendMatchTo(seat);
    }
  }

  void _sendMatchTo(Seat seat) {
    final state = game;
    final client = seat.client;
    if (state == null || client == null) return;
    client.send(MatchUpdate(
      state: state,
      yourSeat: seat.index,
      lastMove: lastMove,
      secondsLeft: secondsLeft,
      autoPlayed: lastWasAutoPlay,
    ));
  }
}
