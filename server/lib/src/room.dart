import 'dart:math';

import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_protocol/ludo_protocol.dart';

/// Anything that can be sent a message — a live socket in production, a list
/// in tests. Keeping the room ignorant of sockets is what lets a whole match be
/// tested without opening a port.
abstract class Client {
  String get playerId;
  String get displayName;

  /// The player's picture, as [Avatar] writes it, or null.
  String? get avatar;
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

  /// Who the held seat belongs to, and what they were called, so the seat goes
  /// back to them and nobody else, and the table still shows whose it is.
  String? heldFor;
  String? heldName;
  String? heldAvatar;

  /// When this seat last sent a reaction, so one player cannot fill everyone
  /// else's screen with them.
  DateTime? reactedAt;

  /// When this seat last said something, for the same reason.
  DateTime? saidAt;

  /// Turns running that the clock has played for this player, who was there
  /// but did not play them.
  int missed = 0;

  /// Trades who sits here with [other]. The seat numbers stay put; the
  /// people, and everything about them, move.
  void swapWith(Seat other) {
    final c = client, ai = computer, r = ready, d = droppedAt;
    final hf = heldFor, hn = heldName, ha = heldAvatar;
    final ra = reactedAt, sa = saidAt;
    client = other.client;
    computer = other.computer;
    ready = other.ready;
    droppedAt = other.droppedAt;
    heldFor = other.heldFor;
    heldName = other.heldName;
    heldAvatar = other.heldAvatar;
    reactedAt = other.reactedAt;
    saidAt = other.saidAt;
    final m = missed;
    missed = other.missed;
    other.missed = m;
    other
      ..client = c
      ..computer = ai
      ..ready = r
      ..droppedAt = d
      ..heldFor = hf
      ..heldName = hn
      ..heldAvatar = ha
      ..reactedAt = ra
      ..saidAt = sa;
  }

  bool get isComputer => computer != null;
  bool get isEmpty => client == null && computer == null;
  bool get connected => client != null;

  SeatInfo toInfo() => SeatInfo(
        seat: index,
        playerId: client?.playerId ?? heldFor,
        displayName:
            client?.displayName ?? heldName ?? (isComputer ? 'Computer' : null),
        isComputer: isComputer,
        connected: connected || isComputer,
        ready: ready || isComputer,
        avatar: client?.avatar ?? heldAvatar,
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
    this.matchmade = false,
    int? seed,
    Random? random,
    DateTime Function()? clock,
  })  : _seed = seed ?? Random.secure().nextInt(0x7FFFFFFF) + 1,
        _random = random ?? Random.secure(),
        _now = clock ?? DateTime.now {
    for (var i = 0; i < rules.players; i++) {
      seats.add(Seat(i));
    }
  }

  static const engine = LudoEngine();

  /// How long a dropped player's seat is held before the seat is given up.
  static const reconnectWindow = Duration(minutes: 5);

  /// How often one seat may send a reaction.
  static const reactionGap = Duration(milliseconds: 1500);

  /// How often one seat may send a line of chat.
  static const chatGap = Duration(milliseconds: 800);

  final String code;
  final RuleConfig rules;

  /// Who may start the match and call a rematch. Passed on to the next person
  /// at the table when the host leaves, so a table is never stuck without one.
  String hostId;
  final bool fillEmptySeatsWithAI;

  /// Dealt by matchmaking, among strangers, rather than opened by a host for
  /// friends. Walking out of one of these mid-game has a cost.
  final bool matchmade;
  final int _seed;

  /// Called once when each game here ends, to write it into the players'
  /// records.
  void Function(Room room)? onFinished;

  /// Told when a player is taken off the table for missing turns, with the
  /// connection they were on, so the hub can let them go.
  void Function(Client client)? onKicked;

  /// Runs [then] after [delay]. Set by the server, so computers take their
  /// turns at a pace people can follow: the roll is seen, then the move.
  /// Left unset — as in most tests — computers play at once.
  void Function(Duration delay, void Function() then)? schedule;

  /// How long a computer waits before rolling, and then before moving. Long
  /// enough for the last move to finish walking and the die to be read.
  static const computerRollPause = Duration(milliseconds: 1100);
  static const computerMovePause = Duration(milliseconds: 1500);

  /// A paced computer step is waiting to run.
  bool _computerWaiting = false;

  /// How many turns running a player may let the clock play before the host
  /// is asked whether they stay, and how long the host has to answer.
  static const missLimit = 5;
  static const kickAskTime = Duration(seconds: 10);

  /// The seat the host is being asked about, and when silence means no.
  ({int seat, DateTime deadline})? kickPending;
  bool _reported = false;

  /// Seeds every game after the first, so a rematch is not a replay.
  final Random _random;
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
    // Their own seat first: already sitting in it on another connection, or
    // held for them since they dropped.
    final own = seats.where((s) =>
        s.client?.playerId == client.playerId || s.heldFor == client.playerId);
    if (own.isNotEmpty) {
      own.first
        ..client = client
        ..droppedAt = null
        ..heldFor = null
        ..heldName = null
        ..heldAvatar = null;
      broadcastRoom();
      _sendMatchTo(own.first);
      return null;
    }

    // A held seat is somebody's, even while they are away, so only a seat
    // nobody has is offered to a newcomer.
    if (phase != RoomPhase.lobby) return 'that match has already started';
    final free = seats.where((s) => s.isEmpty && s.heldFor == null);
    if (free.isEmpty) return 'that room is full';

    free.first
      ..client = client
      ..droppedAt = null;
    broadcastRoom();
    return null;
  }

  void leave(String playerId) {
    for (final seat in seats) {
      if (seat.client?.playerId != playerId) continue;
      if (phase == RoomPhase.playing) {
        // Hold the seat: the game carries on with the computer covering, and
        // the player takes it back mid-match if they return in time.
        seat
          ..heldFor = playerId
          ..heldName = seat.client?.displayName
          ..heldAvatar = seat.client?.avatar
          ..client = null
          ..droppedAt = _now();
      } else {
        seat
          ..client = null
          ..ready = false
          ..droppedAt = null;
      }
    }
    if (playerId == hostId) _passHost();
    broadcastRoom();
  }

  /// Hands the host's job to whoever is still here. Nobody being here leaves
  /// it where it is: the room is about to be closed anyway.
  void _passHost() {
    final here = seats.where((s) => s.client != null);
    if (here.isNotEmpty) hostId = here.first.client!.playerId;
  }

  /// Whether [playerId] still has a place here: a seat, or one held for them.
  bool holds(String playerId) =>
      seats.any((s) => s.client?.playerId == playerId || s.heldFor == playerId);

  /// Whether [playerId] dropped out of this match and can still come back.
  bool isHeldFor(String playerId) =>
      phase == RoomPhase.playing && seats.any((s) => s.heldFor == playerId);

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

  /// Moves the occupants of two seats past each other, before the match.
  /// In a team game the seats make the teams, so this is how the host pairs
  /// people up once everyone is in.
  String? swapSeats(String playerId, int a, int b) {
    if (playerId != hostId) return 'only the host can move players';
    if (phase != RoomPhase.lobby) return 'the match has already started';
    if (a < 0 || b < 0 || a >= seats.length || b >= seats.length) {
      return 'no such seat';
    }
    if (a == b) return null;
    seats[a].swapWith(seats[b]);
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

  /// Another game at the same table. The same seats, the same rules, fresh
  /// dice; anyone who has gone is played by the computer this time.
  String? rematch(String playerId) {
    if (playerId != hostId) return 'only the host can start a rematch';
    if (phase != RoomPhase.finished) return 'the match is not over yet';
    for (final seat in seats) {
      if (seat.client == null && !seat.isComputer) {
        seat.computer = AiLevel.normal;
      }
      seat
        ..droppedAt = null
        ..heldFor = null
        ..heldName = null
        ..heldAvatar = null;
    }
    phase = RoomPhase.playing;
    _reported = false;
    game = GameState.newGame(rules, seed: _random.nextInt(0x7FFFFFFF) + 1);
    lastMove = null;
    lastWasAutoPlay = false;
    turnStartedAt = _now();
    broadcastRoom();
    broadcastMatch();
    driveComputers();
    return null;
  }

  /// Passes one of the fixed [reactions] round the table.
  String? react(String playerId, int index) {
    if (index < 0 || index >= reactions.length) return 'no such reaction';
    final mine = seats.where((s) => s.client?.playerId == playerId);
    if (mine.isEmpty) return 'you are not at this table';
    final seat = mine.first;
    final last = seat.reactedAt;
    // Too soon is dropped without a complaint: a second tap is not worth an
    // error message.
    if (last != null && _now().difference(last) < reactionGap) return null;
    seat.reactedAt = _now();
    final message = Reaction(seat: seat.index, index: index);
    for (final c in _clients) {
      c.send(message);
    }
    return null;
  }

  /// Shows the whole table one of the [throwables] flying from this player
  /// to the seat [to]. Shares the reaction's pace, so it cannot be spammed.
  String? throwAt(String playerId, int to, int index) {
    if (index < 0 || index >= throwables.length) return 'no such throw';
    if (to < 0 || to >= seats.length) return 'no such seat';
    final mine = seats.where((s) => s.client?.playerId == playerId);
    if (mine.isEmpty) return 'you are not at this table';
    final seat = mine.first;
    if (seat.index == to) return null;
    final last = seat.reactedAt;
    if (last != null && _now().difference(last) < reactionGap) return null;
    seat.reactedAt = _now();
    final message = Thrown(from: seat.index, to: to, index: index);
    for (final c in _clients) {
      c.send(message);
    }
    return null;
  }

  /// Passes a line of chat round the table, tidied: control characters and
  /// runs of space go, and it is cut to [chatLimit] characters.
  String? say(String playerId, String text) {
    final mine = seats.where((s) => s.client?.playerId == playerId);
    if (mine.isEmpty) return 'you are not at this table';
    final line = tidyChat(text);
    if (line.isEmpty) return null;
    final seat = mine.first;
    final last = seat.saidAt;
    if (last != null && _now().difference(last) < chatGap) return null;
    seat.saidAt = _now();
    final message = Said(seat: seat.index, text: line);
    for (final c in _clients) {
      c.send(message);
    }
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
    seat.first.missed = 0;

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
      case 'formPair':
        // Only a pairing the engine offers right now.
        final a = intent.tokenId, b = intent.withToken;
        for (final action in engine.pairActions(s)) {
          if (action is FormPair &&
              {action.tokenA, action.tokenB}.containsAll([a, b])) {
            return action;
          }
        }
        return null;
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
    if (schedule != null) {
      _paceComputer();
      return;
    }
    var steps = 0;
    while (phase == RoomPhase.playing && !game!.isOver && steps++ < guard) {
      final level = _computerOnTurn();
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

  /// How well the seat on turn plays, when a computer is playing it: a
  /// computer seat, or one covering for an absent player. Null for a person.
  AiLevel? _computerOnTurn() {
    final seat = seats[game!.turn];
    return seat.computer ??
        (seat.client == null && seat.droppedAt != null
            ? AiLevel.normal // covering for an absent player
            : null);
  }

  /// One computer action at a time, each after a pause and each sent to the
  /// table on its own: the roll, so everyone sees the die, then the move, so
  /// the chip walks instead of jumping.
  void _paceComputer() {
    if (_computerWaiting) return;
    if (phase != RoomPhase.playing || game == null || game!.isOver) return;
    if (_computerOnTurn() == null) return;
    final before = game!;
    _computerWaiting = true;
    schedule!(
      before.awaitingRoll ? computerRollPause : computerMovePause,
      () {
        _computerWaiting = false;
        // Anything could have happened meanwhile: a move, a kick, a rematch.
        if (!identical(game, before) || phase != RoomPhase.playing) {
          driveComputers();
          return;
        }
        final level = _computerOnTurn();
        if (level == null) return;
        final Move? move;
        if (before.awaitingRoll) {
          move = null;
          game = engine.apply(before, const RollDice());
        } else {
          move = LudoAi(level: level).chooseMove(before);
          game = engine.apply(
              before, move == null ? const PassTurn() : PlayMove(move));
        }
        lastMove = move;
        lastWasAutoPlay = false;
        turnStartedAt = _now();
        if (game!.isOver) phase = RoomPhase.finished;
        broadcastMatch();
        driveComputers();
      },
    );
  }

  /// The turn clock. Call periodically; when the seat on turn has run out of
  /// time the server plays for them and moves the game on.
  void tick() {
    // Reclaiming an abandoned seat is not the turn clock's job — a table with
    // no clock still must not hold a place for a player who is never coming
    // back.
    _reclaimAbandonedSeats();

    if (phase != RoomPhase.playing || game == null || game!.isOver) return;
    final pending = kickPending;
    if (pending != null && !_now().isBefore(pending.deadline)) {
      _kick(pending.seat);
      if (game!.isOver) return;
    }
    final limit = rules.turnSeconds;
    if (limit <= 0) return;
    final started = turnStartedAt;
    if (started == null) return;
    if (_now().difference(started).inSeconds < limit) return;

    final before = game!;
    final late = seats[before.turn];
    game = const LudoAi(level: AiLevel.normal).playTurn(before);
    lastWasAutoPlay = true;
    if (late.client != null) {
      late.missed++;
      if (late.missed >= missLimit && kickPending == null) _askAbout(late);
    }
    lastMove = null;
    turnStartedAt = _now();
    if (game!.isOver) phase = RoomPhase.finished;
    broadcastMatch();
    if (!game!.isOver) driveComputers();
  }

  /// Puts the question to the host: does this player stay? A host who is the
  /// one missing turns, or who is not there to ask, cannot answer, so the
  /// player goes.
  void _askAbout(Seat seat) {
    final host = seats.where((s) => s.client?.playerId == hostId);
    if (host.isEmpty || identical(host.first, seat)) {
      _kick(seat.index);
      return;
    }
    kickPending = (seat: seat.index, deadline: _now().add(kickAskTime));
    host.first.client!.send(KickAsk(
      seat: seat.index,
      name: seat.client!.displayName,
      missed: seat.missed,
      seconds: kickAskTime.inSeconds,
    ));
  }

  /// The host's answer. Yes gives the player another [missLimit] chances.
  String? answerKick(String playerId, int seatIndex, bool keep) {
    if (playerId != hostId) return 'only the host decides that';
    final pending = kickPending;
    if (pending == null || pending.seat != seatIndex) return null;
    if (keep) {
      kickPending = null;
      seats[seatIndex].missed = 0;
    } else {
      _kick(seatIndex);
    }
    return null;
  }

  /// Takes the player in [seatIndex] off the table for good; the computer
  /// plays the seat from here on.
  void _kick(int seatIndex) {
    if (kickPending?.seat == seatIndex) kickPending = null;
    final seat = seats[seatIndex];
    final client = seat.client;
    if (client == null) return;
    seat
      ..client = null
      ..computer = AiLevel.normal
      ..ready = true
      ..heldFor = null
      ..heldName = null
      ..heldAvatar = null
      ..droppedAt = null
      ..missed = 0;
    if (client.playerId == hostId) _passHost();
    client.send(const Oops(
      'You missed too many turns and were taken off the table.',
      code: 'kicked',
    ));
    onKicked?.call(client);
    broadcastRoom();
    broadcastMatch();
    if (game != null && !game!.isOver) driveComputers();
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
        ..heldFor = null
        ..heldName = null
        ..heldAvatar = null
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
    // Every path to a finished game ends in a broadcast, so this is the one
    // place that cannot miss it.
    if (game?.isOver == true && !_reported) {
      _reported = true;
      onFinished?.call(this);
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

/// [text] made fit to show: no control characters, no runs of space, at most
/// [chatLimit] characters. Counted in code points, so an emoji is never cut
/// in half.
String tidyChat(String text) {
  final flat = text
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final runes = flat.runes.toList();
  if (runes.length <= chatLimit) return flat;
  return String.fromCharCodes(runes.take(chatLimit)).trim();
}
