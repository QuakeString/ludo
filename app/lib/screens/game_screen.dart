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
import '../board/seat_panel.dart';
import '../board/turning_ring.dart';
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

  /// How long a settled die is left on show before the game moves itself on.
  ///
  /// It has to clear the tumble first — the number is not readable until the
  /// cube stops — and then stay up long enough to actually be read. The old
  /// value was 900ms in total against a 780ms tumble, so the face you were
  /// meant to be looking at was up for a tenth of a second and the turn
  /// appeared to skip without ever showing a number.
  static const _readDieMillis = dieRollMillis + 850;

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
      _autoAdvance();
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

    setState(() {
      _flash = moves.isEmpty
          ? 'Rolled ${_state.dice} — no legal move'
          : 'Rolled ${_state.dice} — only one move';
    });
    _after(_readDieMillis, () {
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
      } else {
        _autoAdvance();
      }
      return;
    }

    setState(() {
      _playing = null;
      _state = engine.apply(_state, PlayMove(animation.move));
    });
    if (_state.isOver) return;
    if (_autoAdvance()) return;
    _maybeTakeComputerTurn();
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
        // Same rule as for a person: the number that ended the turn has to be
        // on show long enough to be read. Passing the instant the AI decides
        // meant the computer's die tumbled and the turn was gone before it
        // settled, which is why a computer's turn could look like nothing
        // happened at all.
        setState(() => _flash = 'Rolled ${_state.dice} — no legal move');
        _after(_readDieMillis, () {
          _apply(const PassTurn());
          _maybeTakeComputerTurn();
        });
      } else {
        // Long enough for the die to stop; the chip walking then says the
        // rest, so it does not need the full reading pause.
        _after(dieRollMillis + 250, () => _play(move));
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

  /// The middle of a seat's house, in board coordinates.
  Pt _houseOf(int seat) {
    final slots = _geometry.yardSlots(_state.armOf(seat));
    final x = slots.map((p) => p.x).reduce((a, b) => a + b) / slots.length;
    final y = slots.map((p) => p.y).reduce((a, b) => a + b) / slots.length;
    return Pt(x, y);
  }

  /// Which seats sit above the board and which below.
  ///
  /// A seat's panel goes on the same side as its house, and in the same
  /// left-to-right order. Anything else is a small lie the player has to
  /// decode every turn — red's house top-left with red's die at the bottom of
  /// the screen reads as two different players.
  (List<int>, List<int>) _seatRows() {
    final n = _state.rules.players;

    final houses = {for (var seat = 0; seat < n; seat++) seat: _houseOf(seat)};
    final above = [
      for (var seat = 0; seat < n; seat++)
        if (houses[seat]!.y < 0.5) seat,
    ]..sort((a, b) => houses[a]!.x.compareTo(houses[b]!.x));
    final below = [
      for (var seat = 0; seat < n; seat++)
        if (houses[seat]!.y >= 0.5) seat,
    ]..sort((a, b) => houses[a]!.x.compareTo(houses[b]!.x));
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
    return nameOfArm(_state.armOf(seat));
  }

  /// How tall a seat rail is, including its padding.
  ///
  /// Fixed, and used to work out the board's square before either is laid
  /// out — everything between the two rails is the board, so a rail that
  /// changes height changes the board's size, and a board that resizes
  /// mid-roll flickers.
  static double _seatBandHeight(RuleConfig rules) =>
      (rules.players > 4 ? 54.0 : 64.0) + 12;

  Widget _seatRow({required bool top}) {
    final (above, below) = _seatRows();
    final seats = top ? above : below;
    final rules = _state.rules;
    if (seats.isEmpty) return SizedBox(height: _seatBandHeight(rules));

    return Padding(
      padding: EdgeInsets.fromLTRB(0, top ? 4 : 8, 0, top ? 8 : 4),
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
                    Expanded(child: _panelFor(seat)),
                  ],
                ],
              )
            // Four seats or fewer: a house occupies half the board's width, so
            // half the rail per house puts every panel over its own corner.
            // Sharing the rail equally instead left a lone panel in the middle
            // of the screen and, on a wide window, put a player's die nowhere
            // near the house it belongs to.
            : Row(
                children: [
                  for (final half in [0, 1])
                    Expanded(
                      child: Center(
                        child: () {
                          final mine = seats.where(
                            (s) => (_houseOf(s).x < 0.5) == (half == 0),
                          );
                          return mine.isEmpty
                              ? const SizedBox.shrink()
                              : _panelFor(mine.first);
                        }(),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget _panelFor(int seat) {
    final rules = _state.rules;
    final session = _session;
    final limit = rules.turnSeconds;
    final left = session?.secondsLeft;

    return SeatPanel(
      arm: _state.armOf(seat),
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
      // The pointer shows for whoever has to roll, whether or not this device
      // is the one that may tap.
      awaitingRoll:
          seat == _state.turn && _state.awaitingRoll && !_state.isOver,
      compact: rules.players > 4,
    );
  }

  /// Runs the shared ticker only while something on the board is moving.
  ///
  /// The rings and the house glow are the only things that animate on their
  /// own, and both are often absent — the computer's turn, a finished game, a
  /// player still to roll with nothing highlighted. Leaving the ticker running
  /// through all of that repainted the board sixty times a second to show a
  /// still picture.
  void _setPulse({required bool needed}) {
    if (needed && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!needed && _spin.isAnimating) {
      _spin.stop();
    }
  }

  /// A turning ring over every chip that can move.
  List<Widget> _rings(Size size) {
    final moves = _myMove ? _legalMoves : const <Move>[];
    if (moves.isEmpty) return const [];

    final side = math.min(size.width, size.height);
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2);
    final cell = _geometry.cellSize * side;
    final chipWidth = cell * (_state.board.arms == 4 ? 0.78 : 0.66);
    final diameter = chipWidth * 2.0;

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
              colour: colourOfArm(_state.armOf(_state.tokens[id].owner)),
              turns: _spin,
            ),
          ),
    ];
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
    final glowSeat = _state.awaitingRoll && !_state.isOver ? _state.turn : null;
    // The rings turn and the house on turn flushes; both are boundaried
    // overlays, so the ticker costs frames for them and never for the board.
    _setPulse(needed: moves.isNotEmpty || glowSeat != null);

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
            Expanded(
              child: LayoutBuilder(
                builder: (context, outer) {
                  // The board and its two seat rails are laid out together and
                  // share one width. Left to itself the rail took the whole
                  // window, which on anything wider than a phone put a
                  // player's die most of a screen away from the house it
                  // belongs to.
                  final band = _seatBandHeight(rules);
                  final side = math.max(
                    160.0,
                    math.min(outer.maxWidth, outer.maxHeight - band * 2),
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
                                  );

                              // Four layers, and only two of them ever repaint. The
                              // board and the chips sit inside RepaintBoundaries so
                              // Flutter keeps them as finished pictures; the ring and
                              // the moving chip are drawn over the top. Painting the
                              // whole board every frame to turn a ring was costing a
                              // full CPU core.
                              return GestureDetector(
                                onTapDown: (d) =>
                                    _tapBoard(d.localPosition, size),
                                child: SizedBox(
                                  width: side,
                                  height: side,
                                  child: Stack(
                                    children: [
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          size: size,
                                          painter: layer(BoardLayer.furniture),
                                        ),
                                      ),
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          size: size,
                                          painter: layer(BoardLayer.glow),
                                        ),
                                      ),
                                      if (glowSeat != null)
                                        HouseFlush(
                                          geometry: _geometry,
                                          arm: _state.armOf(glowSeat),
                                          colour: colourOfArm(
                                            _state.armOf(glowSeat),
                                          ),
                                          side: side,
                                          beat: _spin,
                                        ),
                                      ..._rings(size),
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          size: size,
                                          painter: layer(BoardLayer.chips),
                                        ),
                                      ),
                                      AnimatedBuilder(
                                        animation: _mover,
                                        builder: (context, _) => CustomPaint(
                                          size: size,
                                          painter: layer(BoardLayer.motions),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
    return nameOfArm(state.armOf(seat));
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
              color: colourOfArm(state.armOf(seat)),
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
              const Text('Thinking…', style: TextStyle(fontSize: 12.5))
            else if (state.awaitingRoll)
              // No button: the die in the seat's own place is what you tap.
              Text(
                'Tap the die to roll',
                style: TextStyle(fontSize: 12.5, color: palette.faint),
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
      ),
    );
  }
}
