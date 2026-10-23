import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';
import 'package:ludo_protocol/ludo_protocol.dart';

import '../board/board_painter.dart';
import '../board/chip_layout.dart';
import '../board/die.dart';
import '../board/house_flush.dart';
import '../board/move_animation.dart';
import '../board/sounds.dart';
import '../board/seat_panel.dart';
import '../board/turning_ring.dart';
import '../fresh_seed.dart';
import '../keep_awake.dart';
import '../match_history.dart';
import '../saved_game.dart';
import '../settings.dart';
import 'game_over.dart';
import 'avatars.dart';
import 'house_rules.dart';
import 'kick_banner.dart';
import 'table_chat.dart';
import 'throw_flight.dart';
import '../net/online_session.dart';
import '../theme/seat_colors.dart';

/// One device, two to six seats, any mix of people and computer players.
///
/// The screen holds no rules of its own. It asks the engine what is legal,
/// draws that, and sends back the move the player picked — an illegal move is
/// not something the UI has to guard against, it is something the engine will
/// not offer.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.rules,
    this.seed = 1,
    this.aiSeats = const {},
    this.session,
    this.resumeFrom,
  });

  /// Picks a saved local game up where it was left.
  GameScreen.resumed(SavedGame saved, {Key? key})
    : this(
        key: key,
        rules: saved.state.rules,
        aiSeats: saved.aiSeats,
        resumeFrom: saved,
      );

  final RuleConfig rules;
  final int seed;

  /// Seats played by the computer, and how hard each one plays.
  final Map<int, AiLevel> aiSeats;

  /// Set for an online match. When it is, this screen stops being a player of
  /// the game and becomes a view of one: taps turn into intents sent to the
  /// server, and the position only ever changes because the server said so.
  final OnlineSession? session;

  /// Set to carry on a local game instead of dealing a new one.
  final SavedGame? resumeFrom;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  static const engine = LudoEngine();

  /// How long a settled die is left on show before the game moves itself on.
  ///
  /// Both of these clear the tumble first — the number is not readable until
  /// the cube stops — and then hold. An early version held for 900ms in total
  /// against a 780ms tumble, so the face you were meant to read was up for a
  /// tenth of a second and the turn appeared to skip without showing a number.
  ///
  /// They differ because the two waits are doing different jobs. When a move
  /// follows, the chip setting off is itself the answer, so the pause only has
  /// to be long enough to read the number and no longer. When nothing follows,
  /// the number is the entire event — but players asked for the game to keep
  /// moving, so it only stays up for a glance before the die moves on.
  static const _autoMoveMillis = dieRollMillis + 100;
  static const _deadRollMillis = dieRollMillis + 200;

  /// A tap on the die that arrived before the die was ready.
  ///
  /// The die is only a button while it is actually your throw to make, and
  /// between turns there are stretches — a number being read, a chip walking,
  /// a knocked-off chip trudging home — where it is not. Tapping then used to
  /// do nothing at all, which reads as the game ignoring you rather than as
  /// the game being busy. The tap is kept and spent the moment it can be —
  /// but only for the seat that made it. A tap kept across a change of turn
  /// threw the next player's die for them, which on a shared phone, or with a
  /// friend online, looked like the die rolling by itself.
  ({DateTime at, int seat})? _wantsRoll;

  /// How long a waiting tap is worth honouring. Long enough to cover the die
  /// settling and a short hop; any longer and the throw it finally makes no
  /// longer looks like the tap that asked for it.
  static const _wantsRollFor = Duration(milliseconds: 1500);

  late GameState _state;
  late BoardGeometry _geometry;

  /// Turns the rings. Smooth, because it drives a rotation of a cached layer
  /// rather than a repaint — see [TurningRing].
  late final AnimationController _spin;
  late final AnimationController _mover;

  /// The move currently playing out. While it runs, [_state] is still the
  /// position *before* the move, and the travelling chips are drawn on top —
  /// so the board and the animation can never disagree.
  MoveAnimation? _playing;

  /// The wait between a die settling and the game acting on it.
  Timer? _scheduled;

  /// The computer's thinking beat, and the pause before it plays.
  ///
  /// Its own timer rather than the one above. They used to share a single
  /// slot, so whichever was scheduled second silently cancelled the first —
  /// and a cancelled computer beat is a board that never moves again.
  Timer? _thinking;

  /// One per square a chip is about to land on. A move is heard as it happens
  /// rather than announced once it is over.
  final List<Timer> _footsteps = [];
  String? _flash;

  /// The fanfare belongs to the moment the game ends, not to every rebuild
  /// after it.
  bool _celebrated = false;

  /// Online only: the position to settle into once the current animation has
  /// finished, and any updates that arrived while it was still running.
  GameState? _pendingState;
  final List<MatchUpdate> _queued = [];
  StreamSubscription<MatchUpdate>? _matchSub;
  StreamSubscription<Reaction>? _reactionSub;
  StreamSubscription<Said>? _chatSub;
  StreamSubscription<Thrown>? _throwSub;

  /// Reactions on screen right now, newest last. Each goes after a moment.
  final List<_Bubble> _bubbles = [];
  int _bubbleCount = 0;

  OnlineSession? get _session => widget.session;
  bool get _online => _session != null;

  /// How long this game has been on the screen.
  ///
  /// Kept here and not in the engine, which has no clock and must not get one:
  /// the whole point of that code is that a seed and a list of actions replay
  /// a game exactly, and a wall clock is the one thing that cannot be replayed.
  /// So the rules count throws and moves, and the screen counts minutes.
  final Stopwatch _clock = Stopwatch();

  /// Time spent at this table before it was last opened — a resumed game's
  /// clock carries on from where it stopped rather than starting again.
  Duration _clockBefore = Duration.zero;
  Duration get _elapsed => _clockBefore + _clock.elapsed;

  @override
  void initState() {
    super.initState();
    KeepAwake.set(true);
    final session = _session;
    final saved = session == null ? widget.resumeFrom : null;
    final online = session?.state;
    _state =
        (online == null ? null : _seen(online)) ??
        saved?.state ??
        GameState.newGame(widget.rules, seed: widget.seed);
    _clockBefore = saved?.elapsed ?? Duration.zero;
    _geometry = BoardGeometry.forSpec(_state.board);
    _clock.start();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );
    _mover = AnimationController(vsync: this, duration: Duration.zero)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _settle();
      });

    if (session != null) {
      _matchSub = session.matches.listen(_serverSaid);
      _reactionSub = session.reactions.listen(_reacted);
      _chatSub = session.chat.listen(_chatted);
      _throwSub = session.throws.listen(_thrown);
      session.addListener(_sessionChanged);
    } else if (saved != null) {
      // Saved games can stop between a roll and its move. Pick the turn up
      // exactly where it was: a roll with nothing to choose plays itself,
      // and a computer on turn carries on.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_autoAdvance()) _maybeTakeComputerTurn();
      });
    } else {
      // A new table replaces whatever game was saved before it, at once
      // rather than on the first roll, so the front page never offers back
      // a game this one has already taken the place of.
      _autosave();
      _maybeTakeComputerTurn();
    }
  }

  @override
  void dispose() {
    // The others may play on after you are home, and nobody waits for that
    // before leaving. A game you finished still goes into recent matches.
    if (!_celebrated && _youFinished) _recordResult();
    KeepAwake.set(false);
    _scheduled?.cancel();
    _thinking?.cancel();
    _silence();
    _matchSub?.cancel();
    _reactionSub?.cancel();
    _chatSub?.cancel();
    _throwSub?.cancel();
    for (final b in _bubbles) {
      b.timer.cancel();
    }
    _session?.removeListener(_sessionChanged);
    _spin.dispose();
    _mover.dispose();
    super.dispose();
  }

  List<Move> get _legalMoves =>
      _playing != null ? const [] : engine.legalMoves(_state);

  bool get _busy => _playing != null;
  bool _isComputer(int seat) => widget.aiSeats.containsKey(seat);

  /// Whether this device may act right now. Offline that means any seat a
  /// person is sitting at; online it means your seat and no other.
  /// The moves whose chips are ringed. Online, everyone at the table sees
  /// which chips the player on turn can move, not only that player; only
  /// they can tap one. The computer moves at once, so its are never shown.
  List<Move> get _shownMoves {
    if (_myMove) return _legalMoves;
    if (_session == null || _busy || _state.isOver) return const [];
    return _legalMoves;
  }

  bool get _myMove {
    if (_busy || _state.isOver) return false;
    final session = _session;
    if (session != null) return session.isMyTurn;
    return !_isComputer(_state.turn);
  }

  // --- turn flow -----------------------------------------------------------

  void _apply(GameAction action) {
    try {
      setState(() {
        _state = engine.apply(_state, action);
        _flash = null;
      });
      _autosave();
    } on IllegalActionError catch (e) {
      setState(() => _flash = e.message);
    }
  }

  /// Writes a local game down so it survives the app closing.
  ///
  /// Called after every change to the position, never during one: a move
  /// that is still walking is saved as the roll before it, so a game killed
  /// mid-walk comes back asking for the same choice again. A finished game is
  /// not kept, since there is nothing left in it to continue.
  void _autosave() {
    if (_online) return;
    if (_state.isOver) {
      SavedGameStore.clear();
    } else {
      SavedGameStore.save(
        SavedGame(state: _state, aiSeats: widget.aiSeats, elapsed: _elapsed),
      );
    }
  }

  /// Whether a player at this device has brought every chip home.
  bool get _youFinished {
    final session = _session;
    if (session != null) {
      final me = session.yourSeat;
      return me != null && me >= 0 && _state.hasFinished(me);
    }
    return [
      for (var s = 0; s < _state.rules.players; s++)
        if (!_isComputer(s)) s,
    ].any(_state.hasFinished);
  }

  /// Puts the finished game into this device's recent matches, so its stats
  /// can be opened again after the result sheet has gone.
  void _recordResult() {
    final seats = _session?.room?.seats;
    final computers = <int, AiLevel>{
      ...widget.aiSeats,
      // Online the computer's seats are the server's, not this screen's; the
      // level is not known here and only the robot on the avatar uses it.
      if (seats != null)
        for (final s in seats)
          if (s.isComputer) s.seat: AiLevel.normal,
    };
    MatchHistoryStore.add(
      MatchRecord(
        state: _state,
        finishedAt: DateTime.now(),
        elapsed: _elapsed,
        names: [for (var s = 0; s < _state.rules.players; s++) _nameOf(s)],
        aiSeats: computers,
        online: _online,
      ),
    );
  }

  // --- online: the server talks, the board listens -------------------------

  /// The server's position, turned so this player's own seat is in the
  /// bottom-left corner, where they would sit at a real table. Only the
  /// picture turns: who plays after whom, and every move, are unchanged.
  GameState _seen(GameState state) {
    final me = _session?.yourSeat;
    if (me == null || me < 0 || me >= state.rules.players) return state;
    return state.turnedFor(me);
  }

  void _sessionChanged() {
    if (!mounted) return;
    final session = _session;
    if (session != null && session.kicked && !_leftForKick) {
      _leftForKick = true;
      session.kicked = false;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Taken off the table'),
          content: const Text(
            'You missed too many turns in a row, so the computer is playing '
            'your seat for the rest of this game.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      ).then((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return;
    }
    setState(() {});
  }

  bool _leftForKick = false;

  void _reacted(Reaction r) => _bubble(r.seat, emoji: r.emoji);

  /// A line of chat stays up long enough to read; a reaction is a glance.
  void _chatted(Said s) => _bubble(
    s.seat,
    text: s.text,
    stay: Duration(milliseconds: 4000 + 40 * s.text.length),
  );

  void _bubble(
    int seat, {
    String? emoji,
    String? text,
    Duration stay = const Duration(milliseconds: 2600),
  }) {
    if (!mounted) return;
    final id = _bubbleCount++;
    final bubble = _Bubble(
      id: id,
      who: seat == _session?.yourSeat ? 'You' : _nameOf(seat),
      seat: seat,
      emoji: emoji,
      text: text,
      timer: Timer(stay, () {
        if (mounted) setState(() => _bubbles.removeWhere((b) => b.id == id));
      }),
    );
    setState(() {
      _bubbles.add(bubble);
      // Three at a time is plenty; the oldest makes way.
      while (_bubbles.length > 3) {
        _bubbles.removeAt(0).timer.cancel();
      }
    });
  }

  /// A new position from the server.
  ///
  /// It is never applied straight away when it came from a move: the chips are
  /// walked from where they were to where the server says they are now, so a
  /// remote player's move reads the same as your own instead of teleporting.
  void _serverSaid(MatchUpdate update) {
    if (!mounted) return;
    if (update.state.dice != null) _rollAskedAt = null;
    // The server agreeing to the move this board is already playing: take
    // its position, without walking the chip a second time.
    final ahead = _ahead;
    final last = update.lastMove;
    if (ahead != null &&
        last != null &&
        last.tokenId == ahead.tokenId &&
        last.fromProgress == ahead.fromProgress &&
        last.toProgress == ahead.toProgress) {
      _ahead = null;
      if (_busy) {
        _pendingState = _seen(update.state);
      } else {
        setState(() => _state = _seen(update.state));
        _autoAdvance();
      }
      return;
    }
    _ahead = null;
    if (_busy) {
      _queued.add(update); // finish the current move first
      return;
    }

    final move = update.lastMove;
    final playable =
        move != null &&
        move.tokenId >= 0 &&
        move.tokenId < _state.tokens.length &&
        _state.tokens[move.tokenId].progress == move.fromProgress;

    if (!playable) {
      // A rematch: the same table, dealt again. Everything that belonged to
      // the last game — the fanfare, the clock — starts over with it.
      if (_state.isOver && !update.state.isOver) {
        _celebrated = false;
        _clockBefore = Duration.zero;
        _clock
          ..reset()
          ..start();
      }
      setState(() {
        _state = _seen(update.state);
        _flash = update.autoPlayed
            ? 'Time ran out — played automatically'
            : null;
      });
      if (_moveAfterLink != null) {
        _moveLinkedPair();
        return;
      }
      _autoAdvance();
      return;
    }

    _pendingState = _seen(update.state);
    final animation = MoveAnimation(
      move: move,
      before: _state,
      geometry: _geometry,
    );
    setState(() {
      _playing = animation;
      _flash = update.autoPlayed ? 'Time ran out — played automatically' : null;
    });
    _scheduleMoveSounds(animation);
    _mover
      ..duration = animation.duration
      ..forward(from: 0);
  }

  void _roll() {
    // Not ready is not the same as not wanted. Remember it and spend it the
    // moment the board is free.
    if (_busy || !_state.awaitingRoll || _state.isOver) {
      if (!_state.isOver) {
        _wantsRoll = (at: DateTime.now(), seat: _state.turn);
      }
      return;
    }
    _wantsRoll = null;

    final session = _session;
    if (session != null) {
      // Online the dice are the server's. The die starts tumbling now, and
      // lands on whatever number comes back.
      if (session.isMyTurn) {
        session.roll();
        setState(() => _rollAskedAt = DateTime.now());
        Timer(_rollPatience, () {
          if (mounted) setState(() {});
        });
      }
      return;
    }
    _apply(const RollDice());
    if (_state.isOver) return;
    if (_autoAdvance()) return;
    _maybeTakeComputerTurn();
  }

  /// Carries the turn on by itself when the roll left nothing to decide.
  ///
  /// Two cases, and they are the same case: a roll with no legal move, and a
  /// roll with exactly one. Neither asks the player a question, so neither
  /// should wait for an answer — hunting for the single chip that happens to
  /// be movable is busywork, and tapping Pass to acknowledge a dead roll is
  /// worse than busywork.
  ///
  /// The pause before acting is the point of the thing rather than a delay to
  /// be trimmed: the player has to see the number that caused it. It runs from
  /// the moment the die is thrown, so it covers the tumble and then leaves the
  /// face standing for the better part of a second.
  ///
  /// Returns whether it took the turn over.
  bool _autoAdvance() {
    if (!_myMove || _state.awaitingRoll) return false;
    final moves = _legalMoves;
    if (!_nothingToChoose(moves)) return false;
    // Linking a pair is a choice too, so the turn waits, but only when the
    // linked pair could then move on this roll. A link that leaves nothing to
    // play (an odd roll) is no choice, and waiting on it stalls the turn.
    if (_pairings.any((p) => _linkMoves(p))) return false;

    // A single move needs no caption: the chip walking says it.
    if (moves.isEmpty) {
      setState(() => _flash = 'Rolled ${_state.dice} — no legal move');
    }
    _after(moves.isEmpty ? _deadRollMillis : _autoMoveMillis, () {
      // Re-checked rather than remembered: online the server may have moved
      // the game on while the die was on show.
      if (!_myMove || _state.awaitingRoll) return;
      final now = _legalMoves;
      if (now.isEmpty) {
        final session = _session;
        session == null ? _passLocal() : session.pass();
      } else if (_nothingToChoose(now)) {
        _play(now.first);
      }
    });
    return true;
  }

  /// Whether the roll leaves the player nothing to decide.
  ///
  /// Not just "one legal move". Chips of the same player are interchangeable,
  /// so two of them standing on one square with the same square to go to are
  /// one move offered twice — pick either and the board ends up identical.
  /// The commonest case is a full yard and a six: four chips, four listed
  /// moves, one thing that can happen. Making somebody choose between four
  /// spellings of the same move is not a choice, it is a quiz.
  bool _nothingToChoose(List<Move> moves) {
    if (moves.length <= 1) return true;
    String outcome(Move m) {
      final owner = _state.tokens[m.tokenId].owner;
      return '$owner:${m.fromProgress}>${m.toProgress}';
    }

    final first = outcome(moves.first);
    return moves.every((m) => outcome(m) == first);
  }

  /// Ends a local turn and hands over.
  ///
  /// Passing is the one action that puts the next seat on turn without
  /// anything else running afterwards — a move has [_settle] to follow it, a
  /// roll continues into this method. Miss the handover here and a table with
  /// a computer in it stops dead the first time a person rolls with nothing to
  /// play.
  void _passLocal() {
    _apply(const PassTurn());
    if (!_state.isOver) _maybeTakeComputerTurn();
  }

  /// Starts a move playing. The engine is not told until the chips land.
  void _play(Move move) {
    if (_busy) return;
    final session = _session;
    if (session != null) {
      // Ask, and start walking at once rather than waiting a round trip for
      // the server. The rules here are the server's rules, so a legal move
      // is a move it will take; if it ever disagrees, its next position
      // simply replaces this one.
      session.move(move);
      _ahead = move;
    }
    final animation = MoveAnimation(
      move: move,
      before: _state,
      geometry: _geometry,
    );
    setState(() {
      _playing = animation;
      _flash = null;
    });
    _scheduleMoveSounds(animation);
    _mover
      ..duration = animation.duration
      ..forward(from: 0);
  }

  /// When this device asked the server for a roll, so the die can tumble
  /// while the answer is on its way.
  DateTime? _rollAskedAt;
  static const _rollPatience = Duration(seconds: 3);

  bool get _rollInFlight =>
      _rollAskedAt != null &&
      _state.awaitingRoll &&
      DateTime.now().difference(_rollAskedAt!) < _rollPatience;

  /// Our own move played ahead of the server, while it has not answered.
  Move? _ahead;

  GameState? _predicted(Move move) {
    if (_ahead == null) return null;
    try {
      return engine.apply(_state, PlayMove(move));
    } on IllegalActionError {
      return null;
    }
  }

  /// The move has finished playing — now let the engine have it.
  void _settle() {
    final animation = _playing;
    if (animation == null) return;

    if (_online) {
      // Online there is nothing to work out: the position the chips just
      // walked into is the one the server already sent — or, for our own
      // move when the server has not answered yet, the one it will send.
      setState(() {
        _playing = null;
        _state = _pendingState ?? _predicted(animation.move) ?? _state;
        _pendingState = null;
      });
      if (_queued.isNotEmpty) {
        final next = _queued.removeAt(0);
        _serverSaid(next);
      } else {
        _autoAdvance();
      }
      return;
    }

    setState(() {
      _playing = null;
      _state = engine.apply(_state, PlayMove(animation.move));
    });
    _autosave();
    if (_state.isOver) return;
    if (_autoAdvance()) return;
    _maybeTakeComputerTurn();
  }

  /// Deals a new game at this table, with new dice.
  void _startFreshGame() {
    _scheduled?.cancel();
    _thinking?.cancel();
    _wantsRoll = null;
    _silence();
    setState(() {
      _playing = null;
      _pendingState = null;
      _queued.clear();
      _state = GameState.newGame(_state.rules, seed: freshSeed());
      _flash = null;
      _celebrated = false;
    });
    _clockBefore = Duration.zero;
    _clock
      ..reset()
      ..start();
    _autosave();
    _maybeTakeComputerTurn();
  }

  /// Whether the move ends somewhere nobody can knock the chip off.
  ///
  /// Coming out of the yard does not count, even though a start square is a
  /// safe square and that is exactly where a chip enters. Reaching safety is
  /// something earned by crossing the board; being placed on your own doorstep
  /// is a different event, and giving the two one sound made them sound alike
  /// — which is what was wrong with both of them.
  bool _landsSomewhereSafe(Move move) {
    if (move.kind == MoveKind.enter) return false;
    final arm = _state.armOf(_state.tokens[move.tokenId].owner);
    final ring = _state.board.ringIndex(arm, move.toProgress);
    return ring != null && _state.safeRingSquares.contains(ring);
  }

  void _silence() {
    for (final t in _footsteps) {
      t.cancel();
    }
    _footsteps.clear();
  }

  /// A sound for every square the chip touches down on.
  ///
  /// A move of three squares is three taps, not one announcement once it is
  /// over. The point of hopping square by square is that the move can be
  /// counted as it happens, and a single sound at the end tells you nothing
  /// you did not already know. The last tap says what the move actually was —
  /// a chip set down, a chip knocked off, or a chip home.
  ///
  /// The knock belongs here for the same reason. A capture's animation is
  /// mostly the victim's long walk back to its base, and the collision is at
  /// the start of that, not the end.
  void _scheduleMoveSounds(MoveAnimation animation) {
    _silence();
    final move = animation.move;
    final safeEnd =
        !move.isCapture &&
        !_state.board.isFinished(move.toProgress) &&
        _landsSomewhereSafe(move);
    for (var hop = 0; hop < animation.hops; hop++) {
      final last = hop == animation.hops - 1;
      // The square before a safe one gets no step of its own, so the chime is
      // the next thing heard rather than one more step and then the chime.
      if (safeEnd && hop == animation.hops - 2) continue;
      final (name, volume) = !last
          ? (Sound.step, 0.6)
          : move.isCapture
          ? (Sound.capture, 1.0)
          : _state.board.isFinished(move.toProgress)
          ? (Sound.home, 0.9)
          : _landsSomewhereSafe(move)
          ? (Sound.safe, 1.0)
          : (Sound.step, 0.85);
      // The chime rings as the chip touches down. Started a hop early it was
      // a short ting that had faded by the time the chip sat on the square.
      _footsteps.add(
        Timer(animation.landingAt(hop), () {
          if (mounted) Sfx.instance.play(name, volume: volume);
        }),
      );
    }
  }

  /// If a computer sits at the seat on turn, play it — with a beat first, so a
  /// person can see what happened rather than watching chips teleport.
  void _maybeTakeComputerTurn() {
    if (_state.isOver || _busy || !_isComputer(_state.turn)) return;
    final level = widget.aiSeats[_state.turn]!;
    final ai = LudoAi(level: level);

    _think(600, () {
      if (_state.isOver || _busy || !_isComputer(_state.turn)) return;
      if (_state.awaitingRoll) {
        _apply(const RollDice());
        if (_state.isOver) return;
        if (_state.awaitingRoll) {
          _maybeTakeComputerTurn(); // a six bought another roll
          return;
        }
      }
      final move = ai.chooseMove(_state);
      if (move == null) {
        // Same rule as for a person: the number that ended the turn has to be
        // on show long enough to be read. Passing the instant the AI decides
        // meant the computer's die tumbled and the turn was gone before it
        // settled, which is why a computer's turn could look like nothing
        // happened at all.
        setState(() => _flash = 'Rolled ${_state.dice} — no legal move');
        _think(_deadRollMillis, () {
          _apply(const PassTurn());
          _maybeTakeComputerTurn();
        });
      } else {
        // Long enough for the die to stop; the chip walking then says the
        // rest, so it does not need the full reading pause.
        _think(dieRollMillis + 250, () => _play(move));
      }
    });
  }

  /// Waits, then acts — the human side of a turn.
  void _after(int millis, VoidCallback action) {
    _scheduled?.cancel();
    _scheduled = Timer(Duration(milliseconds: millis), () {
      if (mounted) action();
    });
  }

  /// Waits, then acts — the computer's side of a turn, on its own timer.
  void _think(int millis, VoidCallback action) {
    _thinking?.cancel();
    _thinking = Timer(Duration(milliseconds: millis), () {
      if (mounted) action();
    });
  }

  /// Picks the legal move whose chip is nearest the tap.
  void _tapBoard(Offset local, Size size) {
    if (_choice != null) {
      setState(() => _choice = null);
      return;
    }
    if (!_myMove) return;
    final moves = _legalMoves;
    if (moves.isEmpty) return;
    final side = size.shortestSide;
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2);

    // Ask where the chips are actually drawn. Working it out separately from
    // the painter is what made every chip in a yard share one hit target.
    final layout = chipLayout(_state, _geometry);

    Move? best;
    var bestDistance = double.infinity;
    for (final move in moves) {
      final at = layout[move.tokenId];
      if (at == null) continue;
      final d = (origin + Offset(at.x * side, at.y * side) - local).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = move;
      }
    }
    if (best == null || bestDistance >= side * 0.12) return;

    // A chip that could link with another on its square asks first, right
    // where it stands: one chip, or both together. Nothing to hit by
    // accident sits on the board while the player is only aiming at a chip.
    final pick = best;
    final pairing = _pairings
        .where((p) => p.tokenA == pick.tokenId || p.tokenB == pick.tokenId)
        .firstOrNull;
    if (pairing == null) {
      _play(pick);
      return;
    }
    setState(
      () => _choice = (
        state: _state,
        single: pick,
        pairing: pairing,
        both: _pairMoveAfter(_state, pairing),
      ),
    );
  }

  /// The move a pair would make if these two linked now, or null when the
  /// roll does not let a pair move (an odd roll, under the even-only rule).
  Move? _pairMoveAfter(GameState state, FormPair pairing) {
    try {
      final linked = engine.apply(state, pairing);
      return engine
          .legalMoves(linked)
          .where(
            (m) =>
                m.kind == MoveKind.advancePair &&
                m.tokenIds.contains(pairing.tokenA) &&
                m.tokenIds.contains(pairing.tokenB),
          )
          .firstOrNull;
    } on IllegalActionError {
      return null;
    }
  }

  /// The choice open over a chip that could move alone or as a pair, and
  /// the position it was asked about: a choice for an older position is
  /// stale and closes by itself.
  ({GameState state, Move single, FormPair pairing, Move? both})? _choice;

  /// Online, the pair move waiting for the server to confirm the link.
  FormPair? _moveAfterLink;

  void _chooseOne() {
    final choice = _choice;
    if (choice == null) return;
    setState(() => _choice = null);
    _play(choice.single);
  }

  void _chooseBoth() {
    final choice = _choice;
    if (choice == null) return;
    setState(() => _choice = null);
    final session = _session;
    if (session != null) {
      session.formPair(choice.pairing.tokenA, choice.pairing.tokenB);
      // Moved once the server has linked them; asking for both at once
      // would race the link.
      if (choice.both != null) _moveAfterLink = choice.pairing;
      return;
    }
    _apply(choice.pairing);
    if (choice.both != null) {
      _moveAfterLink = choice.pairing;
      _moveLinkedPair();
    } else {
      _autoAdvance();
    }
  }

  /// After the server links a pair this device asked to move, move it.
  void _moveLinkedPair() {
    final pairing = _moveAfterLink;
    if (pairing == null) return;
    final move = _legalMoves
        .where(
          (m) =>
              m.kind == MoveKind.advancePair &&
              m.tokenIds.contains(pairing.tokenA) &&
              m.tokenIds.contains(pairing.tokenB),
        )
        .firstOrNull;
    if (move == null) {
      // Not linked yet, or the turn moved on: wait for the next word, or
      // give up once it is no longer this device's move.
      if (!_myMove) _moveAfterLink = null;
      return;
    }
    _moveAfterLink = null;
    _play(move);
  }

  /// Chips in flight this frame.
  Map<int, ChipMotion> _motions() {
    final animation = _playing;
    if (animation == null) return const {};
    final t = _mover.value;
    return {
      for (final id in animation.move.tokenIds) id: animation.moverAt(t),
      for (final id in animation.move.capturedTokenIds)
        id: ?animation.capturedAt(t, id),
    };
  }

  /// The middle of a seat's house, in board coordinates.
  Pt _houseOf(int seat) {
    final slots = _geometry.yardSlots(_state.armOf(seat));
    final x = slots.map((p) => p.x).reduce((a, b) => a + b) / slots.length;
    final y = slots.map((p) => p.y).reduce((a, b) => a + b) / slots.length;
    return Pt(x, y);
  }

  /// How wide a seat's house is, as a fraction of the board.
  ///
  /// The panels are sized to it rather than to what is written in them, and
  /// that is the fix for something that looked like sloppy alignment and was:
  /// a panel wide enough to reach the edge of the screen got pinned there,
  /// while a narrower one kept its margin. So "Yellow" sat hard against the
  /// left edge and "Red", directly above it, did not — one long name and the
  /// column stopped lining up.
  ///
  /// Sized to the house, both are the width of the house they belong to, which
  /// makes the two rails and the board one grid rather than three things that
  /// happen to be near each other.
  double _houseWidth(int seat) {
    final tri = _geometry.yardShape(_state.armOf(seat));
    final xs = [tri.a.x, tri.b.x, tri.c.x];
    return xs.reduce(math.max) - xs.reduce(math.min);
  }

  /// Which seats sit above the board and which below.
  ///
  /// A seat's panel goes on the same side as its house, and in the same
  /// left-to-right order. Anything else is a small lie the player has to
  /// decode every turn — red's house top-left with red's die at the bottom of
  /// the screen reads as two different players.
  ///
  /// Split at the median rather than at the middle of the board, which is not
  /// the same thing and on a hexagon is badly not the same thing: two of its
  /// six houses sit exactly halfway down, so testing each house against the
  /// centre line put both of them below it and dealt a six-handed game two
  /// panels along the top and four crammed along the bottom. Ranking the
  /// houses and cutting the list in half gives three and three, and gives the
  /// two level houses one rail each — which also makes each rail a contiguous
  /// run round the board rather than an arbitrary set.
  (List<int>, List<int>) _seatRows() {
    final n = _state.rules.players;
    final houses = {for (var seat = 0; seat < n; seat++) seat: _houseOf(seat)};

    final ranked = [for (var seat = 0; seat < n; seat++) seat]
      ..sort((a, b) {
        final byHeight = houses[a]!.y.compareTo(houses[b]!.y);
        // Level houses go left to the top rail and right to the bottom, so the
        // one on each side of the screen stays on that side of the screen.
        return byHeight != 0 ? byHeight : houses[a]!.x.compareTo(houses[b]!.x);
      });

    final split = (n + 1) ~/ 2;
    final above = ranked.take(split).toList()
      ..sort((a, b) => houses[a]!.x.compareTo(houses[b]!.x));
    final below = ranked.skip(split).toList()
      ..sort((a, b) => houses[a]!.x.compareTo(houses[b]!.x));
    return (above, below);
  }

  String _nameOf(int seat) {
    final seats = _session?.room?.seats;
    if (seats != null && seat < seats.length) {
      if (seat == _session?.yourSeat) return 'You';
      final name = seats[seat].displayName;
      if (name != null && name.isNotEmpty) return name;
    }
    // A local computer seat is called by its colour, because that is what
    // people say out loud — "green is winning", never "the normal computer is
    // winning". The robot on its avatar is what marks it as not a person, and
    // it costs no width, which matters when six panels share a phone.
    return nameOfArm(_state.armOf(seat), _state.board.arms);
  }

  /// The names written on the houses: online only, and each player's own
  /// name — yours too, not "You".
  List<String>? _houseNames() {
    final seats = _session?.room?.seats;
    if (seats == null) return null;
    return [
      for (var s = 0; s < _state.rules.players; s++)
        s < seats.length && (seats[s].displayName ?? '').isNotEmpty
            ? seats[s].displayName!
            : s == _session?.yourSeat
            ? _session!.myName
            : '',
    ];
  }

  /// The picture over a seat. Online it is whatever that player chose; against
  /// the computer the person is this phone's player; in pass & play, where
  /// one phone has several people, each seat gets an animal of its own.
  String? _avatarOf(int seat) {
    final seats = _session?.room?.seats;
    if (seats != null) return seat < seats.length ? seats[seat].avatar : null;
    if (_isComputer(seat)) return null;
    if (widget.aiSeats.isNotEmpty) return myAvatar;
    return Avatar.animal(_passPlayAnimals[seat % _passPlayAnimals.length]);
  }

  /// Lion, fox, panda, penguin, butterfly, bee: one each, never two alike.
  static const _passPlayAnimals = [0, 4, 3, 9, 15, 16];

  /// How tall a seat rail is, including its padding.
  ///
  /// Fixed, and used to work out the board's square before either is laid
  /// out — everything between the two rails is the board, so a rail that
  /// changes height changes the board's size, and a board that resizes
  /// mid-roll flickers.
  static double _seatBandHeight(RuleConfig rules) =>
      (rules.players > 4 ? 54.0 : 64.0) +
      12 +
      rollPointerLane(rules.players > 4);

  Widget _seatRow({required bool top}) {
    final (above, below) = _seatRows();
    final seats = top ? above : below;
    final rules = _state.rules;
    if (seats.isEmpty) return SizedBox(height: _seatBandHeight(rules));

    // The extra goes on the board side, which is where the roll pointer hangs.
    final lane = rollPointerLane(rules.players > 4);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        0,
        top ? 4 : 8 + lane,
        0,
        top ? 8 + lane : 4,
      ),
      child: SizedBox(
        height: rules.players > 4 ? 54 : 64,
        child: rules.players > 4
            // Six panels, three to a rail: they share the width, because
            // three of them centred over three houses would not fit a phone.
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final seat in seats) ...[
                    if (seat != seats.first) const SizedBox(width: 7),
                    Expanded(child: _panelFor(seat, top: top)),
                  ],
                ],
              )
            // Four seats or fewer: each panel goes over its own house and
            // nowhere else. Halving the rail was the first attempt and it was
            // still wrong — a house sits a fifth of the way across the board,
            // not a quarter, so every panel came out a little to the inside.
            : Stack(
                children: [
                  for (final seat in seats)
                    Positioned.fill(
                      child: CustomSingleChildLayout(
                        delegate: _OverHouse(
                          _houseOf(seat).x,
                          _houseWidth(seat),
                          minPanelWidth(rules.players > 4),
                        ),
                        child: _panelFor(seat, top: top),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _panelFor(int seat, {required bool top}) {
    final rules = _state.rules;
    final session = _session;
    final limit = rules.turnSeconds;

    return SeatPanel(
      arm: _state.armOf(seat),
      arms: _state.board.arms,
      name: _nameOf(seat),
      isComputer:
          widget.aiSeats.containsKey(seat) ||
          (_session?.room?.seats.length ?? 0) > seat &&
              (_session?.room?.seats[seat].isComputer ?? false),
      home: _state
          .tokensOf(seat)
          .where((t) => _state.board.isFinished(t.progress))
          .length,
      total: rules.tokensPerPlayer,
      onTurn: seat == _state.turn && !_state.isOver,
      // Only the seat on turn holds the die, and only once it has been
      // rolled — an unrolled die shows an empty face, not a stale one.
      dice: seat == _state.turn ? _state.dice : null,
      turnLength: limit > 0 ? Duration(seconds: limit) : null,
      turnEndsAt: session?.turnEndsAt,
      rolling: seat == _state.turn && _rollInFlight,
      connected: session == null
          ? true
          : (session.room?.seats.length ?? 0) > seat
          ? session.room!.seats[seat].connected
          : true,
      // The die is the roll button for whoever may roll — and it stays a
      // button through the moments when the roll cannot be made yet, so that
      // an early tap is caught rather than dropped on the floor.
      onRoll:
          (seat == _state.turn &&
              !_state.isOver &&
              !_isComputer(seat) &&
              (_session == null || _session!.isMyTurn))
          ? _roll
          : null,
      // The pointer shows for whoever has to roll, whether or not this device
      // is the one that may tap.
      awaitingRoll:
          seat == _state.turn && _state.awaitingRoll && !_state.isOver,
      compact: rules.players > 4,
      // The pointer hangs into the gap between this rail and the board, which
      // is the one piece of space every screen has.
      pointerBelow: top,
      // The same letter that is written on this seat's house.
      teamLetter: rules.isTeamGame
          ? String.fromCharCode(65 + rules.teamOf(seat))
          : null,
      avatar: _avatarOf(seat),
      avatarKey: _avatarKeys.putIfAbsent(seat, GlobalKey.new),
      onAvatarTap: session != null && seat != session.yourSeat
          ? () => _throwAt(seat)
          : null,
    );
  }

  /// Each seat's picture, so a throw knows where it starts and lands.
  final Map<int, GlobalKey> _avatarKeys = {};

  /// Where the [Stack] the throws fly in sits.
  final GlobalKey _stage = GlobalKey();

  final List<(int, Thrown)> _flights = [];
  int _flightCount = 0;

  Future<void> _throwAt(int seat) async {
    final session = _session;
    if (session == null) return;
    final picked = await pickThrow(context, at: _nameOf(seat));
    if (picked != null) session.throwAt(seat, picked);
  }

  void _thrown(Thrown t) {
    if (!mounted) return;
    setState(() {
      _flights.add((_flightCount++, t));
      // A flurry is fun; a blizzard is not.
      while (_flights.length > 6) {
        _flights.removeAt(0);
      }
    });
  }

  /// The centre of [seat]'s picture in the throws' Stack, if it is on show.
  Offset? _pictureOf(int seat) {
    final stage = _stage.currentContext?.findRenderObject() as RenderBox?;
    final box =
        _avatarKeys[seat]?.currentContext?.findRenderObject() as RenderBox?;
    if (stage == null || box == null || !box.attached) return null;
    return stage.globalToLocal(box.localToGlobal(box.size.center(Offset.zero)));
  }

  /// Runs the shared ticker only while something on the board is moving.
  ///
  /// The rings and the house glow are the only things that animate on their
  /// own, and both are often absent — the computer's turn, a finished game, a
  /// player still to roll with nothing highlighted. Leaving the ticker running
  /// through all of that repainted the board sixty times a second to show a
  /// still picture.
  ///
  /// Even when they are wanted they only turn a few times and then hold
  /// still. A phone left on the table while a friend thinks was drawing
  /// frames for minutes on end, and that is where its battery went. Still
  /// rings and a lit house say "your turn" just as well once the eye has
  /// found them; each new position earns them a few more turns.
  void _setPulse({required bool needed, bool endless = false}) {
    if (!needed) {
      if (_spin.isAnimating) _spin.stop();
      _pulsedFor = null;
      return;
    }
    if (identical(_pulsedFor, _state) && (!endless || _spin.isAnimating)) {
      return;
    }
    _pulsedFor = _state;
    if (endless) {
      _spin.repeat();
    } else {
      _spin.repeat(count: pulseTurns);
    }
  }

  /// How many times the rings turn for one position before they rest.
  static const pulseTurns = 3;
  GameState? _pulsedFor;

  /// A turning ring over every chip that can move.
  List<Widget> _rings(Size size) {
    final moves = _shownMoves;
    if (moves.isEmpty) return const [];

    final side = math.min(size.width, size.height);
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2);
    final cell = _geometry.cellSize * side;
    final chipWidth = cell * chipShare(_state.board.arms);
    // Round the chip's foot, not the whole square it stands on. At twice the
    // chip's width the ring swallowed its neighbours' squares too, and on a
    // crowded square it circled the crowd rather than marking a piece.
    final diameter = chipWidth * 1.5;

    final layout = chipLayout(_state, _geometry);
    final movable = {for (final m in moves) ...m.tokenIds};

    return [
      for (final id in movable)
        if (layout[id] != null)
          Positioned(
            left: origin.dx + layout[id]!.x * side - diameter / 2,
            top: origin.dy + layout[id]!.y * side - diameter / 2,
            child: TurningRing(
              diameter: diameter,
              colour: colourOfArm(
                _state.armOf(_state.tokens[id].owner),
                _state.board.arms,
              ),
              turns: _spin,
            ),
          ),
    ];
  }

  /// Pairs this device may link right now. Only on a safe square: anywhere
  /// else chips link by themselves, and a pair comes apart by itself when it
  /// reaches safety, so there is never anything to split by hand.
  /// Whether linking [p] would give the pair a move with the current roll.
  bool _linkMoves(FormPair p) => engine
      .legalMoves(engine.apply(_state, p))
      .any((m) => m.kind == MoveKind.advancePair);

  List<FormPair> get _pairings => _myMove && !_busy
      ? engine.pairActions(_state).whereType<FormPair>().toList()
      : const <FormPair>[];

  /// Move 1 / Move pair, opened under the chip that was tapped.
  List<Widget> _pairChoice(Size size) {
    final choice = _choice;
    if (choice == null) return const [];
    final side = math.min(size.width, size.height);
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2);
    final at = chipLayout(_state, _geometry)[choice.single.tokenId];
    if (at == null) return const [];
    final cell = _geometry.cellSize * side;
    const width = 232.0, height = 64.0;
    final chip = origin + Offset(at.x * side, at.y * side);
    // Under the chip, or over it near the bottom edge; never off the board.
    final below = chip.dy + cell + height < origin.dy + side;
    final left = (chip.dx - width / 2).clamp(
      origin.dx,
      origin.dx + side - width,
    );
    final top = below ? chip.dy + cell * 0.7 : chip.dy - cell * 0.7 - height;
    final colour = colourOfArm(
      _state.armOf(_state.tokens[choice.single.tokenId].owner),
      _state.board.arms,
    );
    final scheme = Theme.of(context).colorScheme;
    return [
      Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: Material(
          color: scheme.surfaceContainerHigh,
          elevation: 6,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('pair-one'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _chooseOne,
                    child: const Text('Move 1'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('pair-both'),
                    style: FilledButton.styleFrom(
                      backgroundColor: colour,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(48),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _chooseBoth,
                    icon: const Icon(Icons.link, size: 18),
                    // A pair that cannot move on this roll can still be
                    // linked, and then waits as a pair.
                    label: Text(choice.both != null ? 'Move pair' : 'Link'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final rules = _state.rules;
    // A choice asked about an older position — the clock ran out, the
    // server moved on — no longer means anything.
    if (_choice != null && !identical(_choice!.state, _state)) _choice = null;
    // Only offer moves the player is actually allowed to make. Online that
    // matters twice over: the rings around movable chips must not light up on
    // somebody else's turn.
    final moves = _myMove ? _legalMoves : const <Move>[];
    final session = _session;
    final glowSeat = _state.awaitingRoll && !_state.isOver ? _state.turn : null;

    // A tap that arrived early, spent as soon as the board is free. Every path
    // that can free it — a move settling, a hold expiring, the server's word —
    // comes through build, so this is the one place that catches them all.
    final waiting = _wantsRoll;
    if (waiting != null) {
      if (DateTime.now().difference(waiting.at) > _wantsRollFor ||
          waiting.seat != _state.turn) {
        _wantsRoll = null;
      } else if (_myMove && _state.awaitingRoll) {
        _wantsRoll = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _roll();
        });
      }
    }

    // Once, on the frame the game ends. Every path into this screen — a local
    // move settling, the computer's turn, the server's word — arrives here, so
    // this is the one place that cannot miss it.
    if (_state.isOver && !_celebrated) {
      _celebrated = true;
      _clock.stop();
      _recordResult();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Sfx.instance.play(Sound.victory, volume: 0.9);
        // Under the fanfare, and quieter than it. The bangs are the room
        // reacting; the fanfare is the thing being said.
        Sfx.instance.play(Sound.crackers, volume: 0.62);
      });
    }
    // The rings turn and the house on turn flushes; both are boundaried
    // overlays, so the ticker costs frames for them and never for the board.
    _setPulse(
      needed: _shownMoves.isNotEmpty || glowSeat != null,
      // Chips waiting to be moved keep turning until one is: a ring that had
      // stopped looked like the game had frozen. The turn timer bounds it.
      endless: _shownMoves.isNotEmpty,
    );

    // The keyboard opens over the game rather than squeezing it: only the
    // chat bar rides up on top of it. SafeArea already keeps the bar clear
    // of the system's own bottom strip, which the keyboard covers too.
    final keyboard = math.max(
      0.0,
      MediaQuery.viewInsetsOf(context).bottom -
          MediaQuery.paddingOf(context).bottom,
    );

    final scaffold = Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: palette.felt,
      appBar: AppBar(
        backgroundColor: palette.felt,
        title: Text(
          session == null
              ? '${rules.name} · ${rules.players} seats'
              : 'Room ${session.room?.code ?? ''}',
        ),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: AppSettings.sound,
            builder: (context, on, _) => IconButton(
              key: const ValueKey('game-sound'),
              tooltip: on ? 'Mute' : 'Sound on',
              onPressed: () => AppSettings.setSound(!on),
              icon: Icon(
                on ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              ),
            ),
          ),
          IconButton(
            key: const ValueKey('game-rules'),
            tooltip: 'Rules',
            onPressed: () => showRuleBoard(context, rules),
            icon: const Icon(Icons.menu_book_rounded),
          ),
          if (session == null)
            IconButton(
              tooltip: 'New game',
              onPressed: _startFreshGame,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          key: _stage,
          children: [
            Column(
              children: [
                if (session?.disconnected ?? false)
                  const _Banner(
                    icon: Icons.wifi_off,
                    text:
                        'Lost the connection. Your seat is held for five '
                        'minutes — the table plays on meanwhile.',
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, outer) {
                      // The board and its two seat rails are laid out together and
                      // share one width. Left to itself the rail took the whole
                      // window, which on anything wider than a phone put a
                      // player's die most of a screen away from the house it
                      // belongs to.
                      final band = _seatBandHeight(rules);
                      // A chip on an outside square is wider than the square
                      // and hangs over the board's edge; on a phone, where the
                      // board is as wide as the screen, that edge is the
                      // screen's, and the chip was cut off. A small gutter
                      // either side keeps it whole.
                      const gutter = 8.0;
                      final side = math.max(
                        160.0,
                        math.min(
                          outer.maxWidth - gutter * 2,
                          outer.maxHeight - band * 2,
                        ),
                      );
                      return Center(
                        child: SizedBox(
                          width: side,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _seatRow(top: true),
                              Builder(
                                builder: (context) {
                                  final size = Size(side, side);
                                  BoardPainter layer(BoardLayer which) =>
                                      BoardPainter(
                                        state: _state,
                                        geometry: _geometry,
                                        palette: palette,
                                        legalMoves: moves,
                                        glowSeat: glowSeat,
                                        motions: _motions(),
                                        layer: which,
                                        names: _houseNames(),
                                      );

                                  // Four layers, and only two of them ever repaint. The
                                  // board and the chips sit inside RepaintBoundaries so
                                  // Flutter keeps them as finished pictures; the ring and
                                  // the moving chip are drawn over the top. Painting the
                                  // whole board every frame to turn a ring was costing a
                                  // full CPU core.
                                  // The pair choice sits beside the board's
                                  // tap handler, not inside it. Inside, a press
                                  // held a moment fired the board's tap-down
                                  // first, which closed the choice under the
                                  // finger before the button could take it.
                                  return Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      GestureDetector(
                                        onTapDown: (d) =>
                                            _tapBoard(d.localPosition, size),
                                        child: SizedBox(
                                          width: side,
                                          height: side,
                                          child: Stack(
                                            // A chip is taller than the square it
                                            // stands on — it is a piece, not a
                                            // counter — so one on the outside row
                                            // has its head over the board's edge.
                                            // Stack clips to its bounds by default,
                                            // which sliced that head flat.
                                            clipBehavior: Clip.none,
                                            children: [
                                              RepaintBoundary(
                                                child: CustomPaint(
                                                  size: size,
                                                  painter: layer(
                                                    BoardLayer.furniture,
                                                  ),
                                                ),
                                              ),
                                              RepaintBoundary(
                                                child: CustomPaint(
                                                  size: size,
                                                  painter: layer(
                                                    BoardLayer.glow,
                                                  ),
                                                ),
                                              ),
                                              if (glowSeat != null)
                                                HouseFlush(
                                                  geometry: _geometry,
                                                  arm: _state.armOf(glowSeat),
                                                  colour: colourOfArm(
                                                    _state.armOf(glowSeat),
                                                    _state.board.arms,
                                                  ),
                                                  side: side,
                                                  beat: _spin,
                                                ),
                                              ..._rings(size),
                                              RepaintBoundary(
                                                child: CustomPaint(
                                                  size: size,
                                                  painter: layer(
                                                    BoardLayer.chips,
                                                  ),
                                                ),
                                              ),
                                              AnimatedBuilder(
                                                animation: _mover,
                                                builder: (context, _) =>
                                                    CustomPaint(
                                                      size: size,
                                                      painter: layer(
                                                        BoardLayer.motions,
                                                      ),
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      ..._pairChoice(size),
                                    ],
                                  );
                                },
                              ),
                              _seatRow(top: false),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _Controls(
                  state: _state,
                  moves: moves,
                  busy: _busy,
                  // Online, "not your move" covers a computer seat, a remote
                  // player's seat, and a seat being covered for — all of them mean
                  // the same thing to these buttons: wait.
                  isComputerTurn: !_myMove && !_state.isOver,
                  onPass: () => session == null ? _passLocal() : session.pass(),
                ),
                // Room kept for the chat bar, which itself is laid over
                // the screen below so the keyboard can lift it without the
                // board shrinking.
                if (session != null && !_state.isOver)
                  const SizedBox(height: chatBarHeight),
              ],
            ),
            // Laid over the top of the board rather than above it, so a note
            // coming and going never resizes the board under the player's
            // finger.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: _TurnBar(
                  state: _state,
                  flash: _flash,
                  aiSeats: widget.aiSeats,
                  session: session,
                ),
              ),
            ),
            // Over the top of the board, like the notes, so asking does not
            // resize the board under everyone's fingers.
            if (session != null &&
                session.kickAsk != null &&
                (session.kickAskUntil?.isAfter(DateTime.now()) ?? false))
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: KickBanner(
                  key: ValueKey(session.kickAskUntil),
                  ask: session.kickAsk!,
                  until: session.kickAskUntil!,
                  onKeep: () => session.answerKick(keep: true),
                  onRemove: () => session.answerKick(keep: false),
                ),
              ),
            for (final (id, t) in _flights)
              if ((_pictureOf(t.from), _pictureOf(t.to)) case (
                final Offset from,
                final Offset to,
              ))
                Positioned.fill(
                  child: ThrowFlight(
                    key: ValueKey('flight-$id'),
                    index: t.index,
                    from: from,
                    to: to,
                    onDone: () {
                      if (mounted) {
                        setState(() => _flights.removeWhere((f) => f.$1 == id));
                      }
                    },
                  ),
                ),
            if (session != null && !_state.isOver)
              Positioned(
                left: 0,
                right: 0,
                bottom: keyboard,
                child: ChatBar(onSend: session.say),
              ),
            if (_state.isOver)
              GameOverSheet(
                state: _state,
                aiSeats: widget.aiSeats,
                nameOf: _nameOf,
                elapsed: _elapsed,
                // Online a rematch is the room's business: the host calls it,
                // and everybody else is dealt in when they do.
                onPlayAgain: session == null
                    ? _startFreshGame
                    : session.isHost
                    ? session.rematch
                    : null,
                playAgainLabel: session == null ? 'Play again' : 'Rematch',
                note: session != null && !session.isHost
                    ? 'The host can start a rematch for this table.'
                    : null,
                onLeave: () {
                  session?.leaveRoom();
                  Navigator.of(context).maybePop();
                },
              ),
          ],
        ),
      ),
    );
    // Reactions and chat lines float in the gap between the top bar and the
    // board, covering neither the room name nor the player cards.
    final stage = Stack(
      children: [
        scaffold,
        if (_bubbles.isNotEmpty)
          Positioned(
            // Just under the top bar, so the room name stays readable.
            top: MediaQuery.paddingOf(context).top + kToolbarHeight + 4,
            left: 0,
            right: 0,
            child: Material(
              type: MaterialType.transparency,
              child: IgnorePointer(
                child: Column(
                  children: [
                    for (final b in _bubbles)
                      b.text != null
                          ? ChatLine(
                              key: ValueKey(b.id),
                              who: b.who,
                              avatar: _avatarOf(b.seat),
                              text: b.text!,
                              colour: colourOfArm(
                                _state.armOf(b.seat),
                                _state.board.arms,
                              ),
                            )
                          : _ReactionBubble(
                              key: ValueKey(b.id),
                              bubble: b,
                              colour: colourOfArm(
                                _state.armOf(b.seat),
                                _state.board.arms,
                              ),
                            ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
    // Back asks first while a game is on: one slip of the thumb should not
    // walk you out of it.
    return PopScope<Object?>(
      canPop: _state.isOver,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !await _confirmLeave() || !mounted) return;
        _session?.leaveRoom();
        if (mounted) Navigator.of(this.context).pop();
      },
      child: stage,
    );
  }

  Future<bool> _confirmLeave() async {
    final online = _online;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave the game?'),
        content: Text(
          online
              ? 'The computer will play your seat while you are away. You '
                    'can rejoin from the online screen while the game is on.'
              : 'This game is saved, so you can carry on from where you '
                    'left off.',
        ),
        actions: [
          TextButton(
            key: const ValueKey('leave-stay'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            key: const ValueKey('leave-go'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return sure ?? false;
  }
}

/// Who won, or a passing note such as a turn that had no move.
class _TurnBar extends StatelessWidget {
  const _TurnBar({
    required this.state,
    required this.aiSeats,
    this.flash,
    this.session,
  });

  final GameState state;
  final Map<int, AiLevel> aiSeats;
  final String? flash;
  final OnlineSession? session;

  /// Who is at a seat. Online that is a person with a name, so use it — "Blue"
  /// is what you call a colour, not the person you are playing against.
  String _nameFor(int seat) {
    final seats = session?.room?.seats;
    if (seats != null && seat < seats.length) {
      final info = seats[seat];
      if (seat == session?.yourSeat) return 'You';
      final name = info.displayName;
      if (name != null && name.isNotEmpty) return name;
    }
    if (aiSeats.containsKey(seat)) return 'Computer (${aiSeats[seat]!.name})';
    return nameOfArm(state.armOf(seat), state.board.arms);
  }

  @override
  Widget build(BuildContext context) {
    final over = state.isOver;
    final seat = over ? state.winner! : state.turn;
    final who = _nameFor(seat);
    // Whose turn it is already shows on the board, by the seat with the die,
    // so the bar only speaks when there is something else to say.
    final label = over
        ? state.rules.isTeamGame
              ? 'Team ${state.winningTeam! + 1} wins'
              : '$who wins'
        : flash;
    if (label == null) return const SizedBox.shrink();

    final palette = BoardPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: palette.panel.withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.panelEdge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: colourOfArm(state.armOf(seat), state.board.arms),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A line across the top of the board for something the player needs to know
/// but must not be stopped by.
class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// The seat rail and the roll button.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.state,
    required this.moves,
    required this.busy,
    required this.isComputerTurn,
    required this.onPass,
  });

  final GameState state;
  final List<Move> moves;
  final bool busy;
  final bool isComputerTurn;
  final VoidCallback onPass;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      // Fixed, for the same reason as the seat rows: this bar swaps a line of
      // text for a Pass button as the turn goes on, and a button is taller
      // than a line of text.
      child: SizedBox(
        height: 40,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // The seat panels carry who is who and how many chips are home, so
            // this bar is only ever about what to do next.
            const Spacer(),
            if (state.isOver)
              const Text(
                'Game over',
                style: TextStyle(fontWeight: FontWeight.w700),
              )
            else if (busy || isComputerTurn)
              // Nothing to do while the others play; the moving die says so.
              const SizedBox.shrink()
            else if (state.awaitingRoll)
              // No button: the die in the seat's own place is what you tap.
              Text(
                'Tap the die to roll',
                style: TextStyle(fontSize: 12.5, color: palette.faint),
              )
            else if (moves.isEmpty)
              OutlinedButton(onPressed: onPass, child: const Text('Pass')),
            // With moves to make, the spinning rings already say "tap a chip".
          ],
        ),
      ),
    );
  }
}

/// Puts a seat's panel directly over its house.
///
/// A delegate rather than an Align, because Align's fractional placement is a
/// compromise between "at this fraction" and "inside the parent": it slides
/// the child inward as the child grows, so a panel is only truly centred when
/// it has no width. Here the measured size is in hand, so the middle of the
/// panel can go exactly where the middle of the house is, and be clamped only
/// when the panel would otherwise leave the rail.
class _OverHouse extends SingleChildLayoutDelegate {
  const _OverHouse(this.fraction, this.width, this.floor);

  /// Where the middle of the house is, across the board.
  final double fraction;

  /// How wide the house is, as the same fraction. The panel is given exactly
  /// this much — see [_GameScreenState._houseWidth] — so that two panels in a
  /// column line up whatever their names happen to be.
  final double width;

  /// Below which the panel's own contents will not fit. A house two fifths of
  /// a board across is plenty on a phone and not plenty on a short window,
  /// where the board is small because the height is what ran out.
  final double floor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) {
    // The floor is itself capped at half the rail, because two of these share
    // it — better a pair of panels that touch than a pair that overlap. Both
    // are widened by the same amount either way, so the two columns stay
    // level, which is the point of sizing them together at all.
    final want = math.max(c.maxWidth * width, math.min(floor, c.maxWidth / 2));
    return BoxConstraints.tightFor(width: want)
        .enforce(BoxConstraints(maxHeight: c.maxHeight));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final free = math.max(0.0, size.width - childSize.width);
    return Offset(
      (size.width * fraction - childSize.width / 2).clamp(0.0, free),
      (size.height - childSize.height) / 2,
    );
  }

  @override
  bool shouldRelayout(_OverHouse old) =>
      old.fraction != fraction || old.width != width || old.floor != floor;
}

/// One reaction on screen.
class _Bubble {
  _Bubble({
    required this.id,
    required this.who,
    required this.seat,
    this.emoji,
    this.text,
    required this.timer,
  });

  final int id;
  final String who;
  final int seat;
  final String? emoji;

  /// A line of chat, when this is one rather than a reaction.
  final String? text;
  final Timer timer;
}

class _ReactionBubble extends StatelessWidget {
  const _ReactionBubble({
    super.key,
    required this.bubble,
    required this.colour,
  });

  final _Bubble bubble;

  /// The seat's colour as this player sees it.
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(scale: t, child: child),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 4, 14, 4),
        decoration: BoxDecoration(
          color: palette.panel,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colour, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(bubble.emoji ?? '', style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 8),
            Text(
              bubble.who,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
