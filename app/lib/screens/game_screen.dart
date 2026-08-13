import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

import '../board/board_painter.dart';
import '../board/move_animation.dart';
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
  });

  final RuleConfig rules;
  final int seed;

  /// Seats played by the computer, and how hard each one plays.
  final Map<int, AiLevel> aiSeats;

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

  @override
  void initState() {
    super.initState();
    _state = GameState.newGame(widget.rules, seed: widget.seed);
    _geometry = BoardGeometry.forSpec(_state.board);
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _mover = AnimationController(vsync: this, duration: Duration.zero)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _settle();
      });
    _maybeTakeComputerTurn();
  }

  @override
  void dispose() {
    _scheduled?.cancel();
    _pulse.dispose();
    _mover.dispose();
    super.dispose();
  }

  List<Move> get _legalMoves =>
      _playing != null ? const [] : engine.legalMoves(_state);

  bool get _busy => _playing != null;
  bool _isComputer(int seat) => widget.aiSeats.containsKey(seat);

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

  void _roll() {
    if (_busy) return;
    _apply(const RollDice());
    if (_state.isOver) return;

    if (!_state.awaitingRoll && engine.legalMoves(_state).isEmpty) {
      // A roll with nothing to play is not a puzzle for the player to work
      // out — say so, then move the game on.
      setState(() => _flash = 'Rolled ${_state.dice} — no legal move');
      _after(900, () => _apply(const PassTurn()));
      return;
    }
    _maybeTakeComputerTurn();
  }

  /// Starts a move playing. The engine is not told until the chips land.
  void _play(Move move) {
    if (_busy) return;
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
    if (_busy) return;
    final moves = _legalMoves;
    if (moves.isEmpty || _isComputer(_state.turn)) return;
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

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final rules = _state.rules;
    final moves = _legalMoves;

    return Scaffold(
      backgroundColor: palette.felt,
      appBar: AppBar(
        backgroundColor: palette.felt,
        title: Text('${rules.name} · ${rules.players} seats'),
        actions: [
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
            _TurnBar(state: _state, flash: _flash, aiSeats: widget.aiSeats),
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
            _Controls(
              state: _state,
              moves: moves,
              busy: _busy,
              isComputerTurn: _isComputer(_state.turn),
              onRoll: _roll,
              onPass: () => _apply(const PassTurn()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whose turn it is, plus the turn clock when the rules use one.
class _TurnBar extends StatelessWidget {
  const _TurnBar({required this.state, required this.aiSeats, this.flash});

  final GameState state;
  final Map<int, AiLevel> aiSeats;
  final String? flash;

  @override
  Widget build(BuildContext context) {
    final over = state.isOver;
    final seat = over ? state.winner! : state.turn;
    final who = aiSeats.containsKey(seat)
        ? 'Computer (${aiSeats[seat]!.name})'
        : seatNames[seat];
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
          if (state.rules.turnTimerDots > 0 && !over)
            for (var i = 0; i < state.rules.turnTimerDots; i++)
              Container(
                margin: const EdgeInsets.only(left: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: seatColors[1],
                  shape: BoxShape.circle,
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
    final rules = state.rules;
    final home = [
      for (var p = 0; p < rules.players; p++)
        state
            .tokensOf(p)
            .where((t) => state.board.isFinished(t.progress))
            .length,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Wrap(
              spacing: 14,
              runSpacing: 2,
              children: [
                for (var p = 0; p < rules.players; p++)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: seatColors[p],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '${home[p]}/${rules.tokensPerPlayer}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: p == state.turn
                              ? FontWeight.w700
                              : FontWeight.w400,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
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
