import 'package:flutter/material.dart';
import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

import '../board/board_painter.dart';
import '../theme/seat_colors.dart';

/// Pass and play: one device, two to six seats, every rule the engine knows.
///
/// The screen holds no rules of its own. It asks the engine what is legal,
/// draws that, and sends back the move the player picked — so an illegal move
/// is not something the UI has to guard against, it is something the engine
/// will not offer.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.rules, this.seed = 1});

  final RuleConfig rules;
  final int seed;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  static const engine = LudoEngine();

  late GameState _state;
  late BoardGeometry _geometry;
  late final AnimationController _pulse;
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
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  List<Move> get _legalMoves => engine.legalMoves(_state);

  void _act(GameAction action) {
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
    _act(const RollDice());
    // A roll with nothing to play is not a dead end the player has to work
    // out — say so, and move the game on.
    if (!_state.awaitingRoll && _legalMoves.isEmpty && !_state.isOver) {
      final rolled = _state.dice;
      setState(() => _flash = 'Rolled $rolled — no legal move');
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted && !_state.awaitingRoll && _legalMoves.isEmpty) {
          _act(const PassTurn());
        }
      });
    }
  }

  /// Picks the move whose destination is nearest the tap.
  void _tapBoard(Offset local, Size size) {
    final moves = _legalMoves;
    if (moves.isEmpty) return;
    final side = size.shortestSide;
    final origin = Offset((size.width - side) / 2, (size.height - side) / 2);

    Move? best;
    var bestDistance = double.infinity;
    for (final move in moves) {
      final token = _state.tokens[move.tokenId];
      final arm = _state.armOf(token.owner);
      // Aim at where the chip is now — you tap the chip you want to move.
      final at = _geometry.tokenAt(arm, token.progress);
      final px = origin + Offset(at.x * side, at.y * side);
      final d = (px - local).distance;
      if (d < bestDistance) {
        bestDistance = d;
        best = move;
      }
    }
    if (best != null && bestDistance < side * 0.12) _act(PlayMove(best));
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
              _state = GameState.newGame(rules, seed: widget.seed + 1);
              _flash = null;
            }),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _TurnBar(state: _state, flash: _flash),
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
                          animation: _pulse,
                          builder: (context, _) => CustomPaint(
                            size: size,
                            painter: BoardPainter(
                              state: _state,
                              geometry: _geometry,
                              palette: palette,
                              legalMoves: moves,
                              pulse: _pulse.value,
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
              onRoll: _roll,
              onPass: () => _act(const PassTurn()),
              onMove: (m) => _act(PlayMove(m)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whose turn it is, plus the six-dot turn clock when the rules use one.
class _TurnBar extends StatelessWidget {
  const _TurnBar({required this.state, this.flash});

  final GameState state;
  final String? flash;

  @override
  Widget build(BuildContext context) {
    final over = state.isOver;
    final seat = over ? state.winner! : state.turn;
    final label = over
        ? state.rules.isTeamGame
              ? 'Team ${state.winningTeam! + 1} wins'
              : '${seatNames[seat]} wins'
        : flash ??
              (state.awaitingRoll
                  ? '${seatNames[seat]} — roll the dice'
                  : '${seatNames[seat]} — move a chip');

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
            Row(
              children: [
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
    required this.onRoll,
    required this.onPass,
    required this.onMove,
  });

  final GameState state;
  final List<Move> moves;
  final VoidCallback onRoll;
  final VoidCallback onPass;
  final void Function(Move) onMove;

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
