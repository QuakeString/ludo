import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';
import 'package:ludo_protocol/ludo_protocol.dart';

import '../board/board_painter.dart';
import '../board/move_animation.dart';
import '../board/seat_panel.dart';
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
  });

  final RuleConfig rules;
  final int seed;

  /// Seats played by the computer, and how hard each one plays.
  final Map<int, AiLevel> aiSeats;

  /// Set for an online match. When it is, this screen stops being a player of
  /// the game and becomes a view of one: taps turn into intents sent to the
  /// server, and the position only ever changes because the server said so.
  final OnlineSession? session;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  static const engine = LudoEngine();

  late GameState _state;
  late BoardGeometry _geometry;
  late final AnimationController _pulse;
  late final AnimationController _mover;

  /// The move currently playing out. While it runs, [_state] is still the
  /// position *before* the move, and the travelling chips are drawn on top —
  /// so the board and the animation can never disagree.
  MoveAnimation? _playing;
  Timer? _scheduled;
  String? _flash;

  /// Online only: the position to settle into once the current animation has
  /// finished, and any updates that arrived while it was still running.
  GameState? _pendingState;
  final List<MatchUpdate> _queued = [];
  StreamSubscription<MatchUpdate>? _matchSub;

  OnlineSession? get _session => widget.session;
  bool get _online => _session != null;

  @override
  void initState() {
    super.initState();
    final session = _session;
    _state =
        session?.state ?? GameState.newGame(widget.rules, seed: widget.seed);
    _geometry = BoardGeometry.forSpec(_state.board);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _mover = AnimationController(vsync: this, duration: Duration.zero)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _settle();
      });

    if (session != null) {
      _matchSub = session.matches.listen(_serverSaid);
      session.addListener(_sessionChanged);
    } else {
      _maybeTakeComputerTurn();
    }
  }

  @override
  void dispose() {
    _scheduled?.cancel();
    _matchSub?.cancel();
    _session?.removeListener(_sessionChanged);
    _pulse.dispose();
    _mover.dispose();
    super.dispose();
  }

  List<Move> get _legalMoves =>
      _playing != null ? const [] : engine.legalMoves(_state);

  bool get _busy => _playing != null;
  bool _isComputer(int seat) => widget.aiSeats.containsKey(seat);

  /// Whether this device may act right now. Offline that means any seat a
  /// person is sitting at; online it means your seat and no other.
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
    } on IllegalActionError catch (e) {
      setState(() => _flash = e.message);
    }
  }

  // --- online: the server talks, the board listens -------------------------

  void _sessionChanged() {
    if (mounted) setState(() {});
  }

  /// A new position from the server.
  ///
  /// It is never applied straight away when it came from a move: the chips are
  /// walked from where they were to where the server says they are now, so a
  /// remote player's move reads the same as your own instead of teleporting.
  void _serverSaid(MatchUpdate update) {
    if (!mounted) return;
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
      setState(() {
        _state = update.state;
        _flash = update.autoPlayed
            ? 'Time ran out — played automatically'
            : null;
      });
      return;
    }

    _pendingState = update.state;
    final animation = MoveAnimation(
      move: move,
      before: _state,
      geometry: _geometry,
    );
    setState(() {
      _playing = animation;
      _flash = update.autoPlayed ? 'Time ran out — played automatically' : null;
    });
    _mover
      ..duration = animation.duration
      ..forward(from: 0);
  }

  void _roll() {
    if (_busy) return;
    final session = _session;
    if (session != null) {
      // Online the dice are the server's. Asking is all this device does.
      if (session.isMyTurn) session.roll();
      return;
    }
    _apply(const RollDice());
    if (_state.isOver) return;

    if (!_state.awaitingRoll && engine.legalMoves(_state).isEmpty) {
      // A roll with nothing to play is not a puzzle for the player to work
      // out — say so, then move the game on.
      setState(() => _flash = 'Rolled ${_state.dice} — no legal move');
      _after(900, _passLocal);
      return;
    }
    _maybeTakeComputerTurn();
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
      // Ask, then wait. Nothing moves on this board until the server has
      // agreed it may — a move drawn optimistically and then taken back is a
      // worse experience than one that starts a moment later.
      session.move(move);
      return;
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
    _mover
      ..duration = animation.duration
      ..forward(from: 0);
  }

  /// The move has finished playing — now let the engine have it.
  void _settle() {
    final animation = _playing;
    if (animation == null) return;

    if (_online) {
      // Online there is nothing to work out: the position the chips just
      // walked into is the one the server already sent.
      setState(() {
        _playing = null;
        _state = _pendingState ?? _state;
        _pendingState = null;
      });
      if (_queued.isNotEmpty) {
        final next = _queued.removeAt(0);
        _serverSaid(next);
      }
      return;
    }

    setState(() {
      _playing = null;
      _state = engine.apply(_state, PlayMove(animation.move));
    });
    if (!_state.isOver) _maybeTakeComputerTurn();
  }

  /// If a computer sits at the seat on turn, play it — with a beat first, so a
  /// person can see what happened rather than watching chips teleport.
  void _maybeTakeComputerTurn() {
    if (_state.isOver || _busy || !_isComputer(_state.turn)) return;
    final level = widget.aiSeats[_state.turn]!;
    final ai = LudoAi(level: level);

    _after(600, () {
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
        _apply(const PassTurn());
        _maybeTakeComputerTurn();
      } else {
        _after(350, () => _play(move));
      }
    });
  }

  void _after(int millis, VoidCallback action) {
    _scheduled?.cancel();
    _scheduled = Timer(Duration(milliseconds: millis), () {
      if (mounted) action();
    });
  }

  /// Picks the legal move whose chip is nearest the tap.
  void _tapBoard(Offset local, Size size) {
    if (!_myMove) return;
    final moves = _legalMoves;
    if (moves.isEmpty) return;
    final side = size.shortestSide;
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2);

    Move? best;
    var bestDistance = double.infinity;
    for (final move in moves) {
      final token = _state.tokens[move.tokenId];
      final at = _geometry.tokenAt(_state.armOf(token.owner), token.progress);
      final d = (origin + Offset(at.x * side, at.y * side) - local).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = move;
      }
    }
    if (best != null && bestDistance < side * 0.12) _play(best);
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

  /// Which seats sit above the board and which below.
  ///
  /// You are always on the bottom row, because the die is a thing you reach
  /// for — it belongs under your thumb, not across the table. Everyone else is
  /// dealt out from the seat after yours so the order round the screen matches
  /// the order of play.
  (List<int>, List<int>) _seatRows() {
    final n = _state.rules.players;
    final me = _session?.yourSeat ?? 0;
    final order = [for (var i = 0; i < n; i++) (me + i) % n];

    // Two players face each other; otherwise split the table in half, with the
    // seats that play soonest after you nearest to you.
    final belowCount = switch (n) {
      2 => 1,
      3 => 1,
      4 => 2,
      5 => 2,
      _ => 3,
    };
    final below = order.take(belowCount).toList();
    final above = order.skip(belowCount).toList().reversed.toList();
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
    return seatNames[seat];
  }

  Widget _seatRow({required bool top}) {
    final (above, below) = _seatRows();
    final seats = top ? above : below;
    if (seats.isEmpty) return const SizedBox.shrink();

    final rules = _state.rules;
    final session = _session;
    final limit = rules.turnSeconds;
    final left = session?.secondsLeft;

    // A row, not a wrap: panels share the width so they always fit on one
    // line. Wrapping cost the board a chunk of height at four seats and more
    // at six, which is the wrong thing to spend space on.
    Widget fit(Widget panel) =>
        seats.length == 1 ? panel : Expanded(child: panel);

    return Padding(
      padding: EdgeInsets.fromLTRB(10, top ? 4 : 8, 10, top ? 8 : 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final seat in seats) ...[
            if (seat != seats.first) const SizedBox(width: 7),
            fit(
              SeatPanel(
                seat: seat,
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
                timerDots: rules.turnTimerDots,
                dotsLit: (left == null || limit <= 0)
                    ? rules.turnTimerDots
                    : (left * rules.turnTimerDots / limit).ceil().clamp(
                        0,
                        rules.turnTimerDots,
                      ),
                connected: session == null
                    ? true
                    : (session.room?.seats.length ?? 0) > seat
                    ? session.room!.seats[seat].connected
                    : true,
                // The die is the roll button for whoever may roll.
                onRoll: (seat == _state.turn && _myMove && _state.awaitingRoll)
                    ? _roll
                    : null,
                compact: rules.players > 4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final rules = _state.rules;
    // Only offer moves the player is actually allowed to make. Online that
    // matters twice over: the rings around movable chips must not light up on
    // somebody else's turn.
    final moves = _myMove ? _legalMoves : const <Move>[];
    final session = _session;

    return Scaffold(
      backgroundColor: palette.felt,
      appBar: AppBar(
        backgroundColor: palette.felt,
        title: Text(
          session == null
              ? '${rules.name} · ${rules.players} seats'
              : 'Room ${session.room?.code ?? ''}',
        ),
        actions: [
          if (session == null)
            IconButton(
              tooltip: 'New game',
              onPressed: () => setState(() {
                _scheduled?.cancel();
                _playing = null;
                _state = GameState.newGame(rules, seed: widget.seed + 1);
                _flash = null;
                _maybeTakeComputerTurn();
              }),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _TurnBar(
              state: _state,
              flash: _flash,
              aiSeats: widget.aiSeats,
              session: session,
            ),
            if (session?.disconnected ?? false)
              const _Banner(
                icon: Icons.wifi_off,
                text:
                    'Lost the connection. Your seat is held for five '
                    'minutes — the table plays on meanwhile.',
              ),
            _seatRow(top: true),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      return GestureDetector(
                        onTapDown: (d) => _tapBoard(d.localPosition, size),
                        child: AnimatedBuilder(
                          animation: Listenable.merge([_pulse, _mover]),
                          builder: (context, _) => CustomPaint(
                            size: size,
                            painter: BoardPainter(
                              state: _state,
                              geometry: _geometry,
                              palette: palette,
                              legalMoves: moves,
                              pulse: _pulse.value,
                              motions: _motions(),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            _seatRow(top: false),
            _Controls(
              state: _state,
              moves: moves,
              busy: _busy,
              // Online, "not your move" covers a computer seat, a remote
              // player's seat, and a seat being covered for — all of them mean
              // the same thing to these buttons: wait.
              isComputerTurn: !_myMove && !_state.isOver,
              onRoll: _roll,
              onPass: () => session == null ? _passLocal() : session.pass(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whose turn it is, plus the turn clock when the rules use one.
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
    return seatNames[seat];
  }

  @override
  Widget build(BuildContext context) {
    final over = state.isOver;
    final seat = over ? state.winner! : state.turn;
    final who = _nameFor(seat);
    final label = over
        ? state.rules.isTeamGame
              ? 'Team ${state.winningTeam! + 1} wins'
              : '$who wins'
        : flash ??
              (state.awaitingRoll
                  ? '$who — roll the dice'
                  : '$who — move a chip');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Row(
        children: [
          Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              color: seatColors[seat],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
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
    required this.onRoll,
    required this.onPass,
  });

  final GameState state;
  final List<Move> moves;
  final bool busy;
  final bool isComputerTurn;
  final VoidCallback onRoll;
  final VoidCallback onPass;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
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
            const Text('Thinking…', style: TextStyle(fontSize: 12.5))
          else if (state.awaitingRoll)
            FilledButton.icon(
              onPressed: onRoll,
              icon: const Icon(Icons.casino_outlined),
              label: const Text('Roll'),
              style: FilledButton.styleFrom(
                backgroundColor: seatColors[state.turn],
                foregroundColor: Colors.white,
              ),
            )
          else if (moves.isEmpty)
            OutlinedButton(onPressed: onPass, child: const Text('Pass'))
          else
            Text(
              '${moves.length} move${moves.length == 1 ? '' : 's'} — tap a chip',
              style: const TextStyle(fontSize: 12.5),
            ),
        ],
      ),
    );
  }
}
