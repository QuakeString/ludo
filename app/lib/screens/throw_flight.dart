import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ludo_protocol/ludo_protocol.dart';

/// Opens the tray of [throwables] for a player's picture. Returns the one
/// picked, by index, or null when the tray was dismissed.
Future<int?> pickThrow(BuildContext context, {required String at}) {
  return showModalBottomSheet<int>(
    context: context,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Throw at $at',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            GridView.extent(
              key: const ValueKey('throw-grid'),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              maxCrossAxisExtent: 72,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (var i = 0; i < throwables.length; i++)
                  InkResponse(
                    key: ValueKey('throw-$i'),
                    onTap: () => Navigator.of(context).pop(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          throwables[i].$1,
                          style: const TextStyle(fontSize: 30),
                        ),
                        Text(
                          throwables[i].$2,
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

/// One throw crossing the screen: the thing flies from the thrower's picture
/// to the target's, then lands with its own little show — the hammer bonks,
/// love bursts into hearts, the tomato splats.
///
/// [from] and [to] are the centres of the two pictures, in the coordinates of
/// the Stack this is laid in. Calls [onDone] when the show is over.
class ThrowFlight extends StatefulWidget {
  const ThrowFlight({
    super.key,
    required this.index,
    required this.from,
    required this.to,
    required this.onDone,
  });

  final int index;
  final Offset from;
  final Offset to;
  final VoidCallback onDone;

  static const duration = Duration(milliseconds: 2400);

  @override
  State<ThrowFlight> createState() => _ThrowFlightState();
}

class _ThrowFlightState extends State<ThrowFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(
    vsync: this,
    duration: ThrowFlight.duration,
  )..forward().whenComplete(() => widget.onDone());

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  /// The share of the time spent in the air; the rest is the landing.
  static const _air = 0.38;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _t,
        builder: (context, _) {
          final t = _t.value;
          final sprites = t < _air
              ? [_flying(Curves.easeInOut.transform(t / _air))]
              : _landing((t - _air) / (1 - _air));
          // Everything fades out together over the last few frames.
          final fade = t > 0.9 ? (1 - t) / 0.1 : 1.0;
          return Opacity(
            opacity: fade.clamp(0, 1),
            child: Stack(clipBehavior: Clip.none, children: sprites),
          );
        },
      ),
    );
  }

  String get _emoji => throwables[widget.index].$1;

  /// Things that are thrown, not handed over, tumble on the way.
  bool get _tumbles => const {5, 6, 7}.contains(widget.index);

  Widget _flying(double f) {
    final a = widget.from, b = widget.to;
    final distance = (b - a).distance;
    // A lob: up and over, higher the further it goes.
    final lift = math.sin(f * math.pi) * math.min(120.0, 30 + distance * 0.3);
    final at = Offset.lerp(a, b, f)! - Offset(0, lift);
    return _sprite(
      _emoji,
      at,
      size: 30 + 8 * math.sin(f * math.pi),
      turn: _tumbles ? f * math.pi * 3 : 0,
    );
  }

  List<Widget> _landing(double g) {
    final at = widget.to;
    switch (widget.index) {
      case 0: // hammer: two bonks on the head, then stars
        final bonk = math.sin(g * math.pi * 4).abs();
        return [
          _sprite(
            '🔨',
            at + const Offset(16, -18),
            size: 34,
            turn: -0.2 - 1.1 * (1 - bonk),
          ),
          if (g > 0.25)
            _sprite('💫', at + const Offset(0, -26), size: 22 + 6 * bonk),
        ];
      case 1: // love: a heart that swells and scatters
        return [
          _sprite('❤️', at, size: 30 + 22 * _pop(g)),
          ..._burst('❤️', at, g, count: 7, reach: 60, size: 16),
        ];
      case 2: // kiss: a big smack that floats up in little hearts
        return [
          _sprite('💋', at, size: 30 + 30 * _pop(g)),
          ..._burst('💕', at, g, count: 5, reach: 44, size: 14, rise: true),
        ];
      case 3: // handshake: a firm shake
        return [
          _sprite(
            '🤝',
            at + Offset(math.sin(g * math.pi * 8) * 6, 0),
            size: 34 + 10 * _pop(g),
          ),
        ];
      case 4: // rose: laid down gently, with a sparkle
        return [
          _sprite('🌹', at, size: 34, turn: math.sin(g * math.pi * 3) * 0.25),
          ..._burst('✨', at, g, count: 6, reach: 40, size: 14),
        ];
      case 5: // tomato: splat
        return [
          _sprite('🍅', at, size: 36, squash: _squash(g)),
          ..._burst('💦', at, g, count: 6, reach: 46, size: 14),
        ];
      case 6: // egg: cracks into a fried egg
        return [
          _sprite(g < 0.15 ? '🥚' : '🍳', at, size: 36, squash: _squash(g)),
        ];
      case 7: // bomb: boom
        return [
          _sprite(g < 0.12 ? '💣' : '💥', at, size: 34 + 30 * _pop(g)),
          if (g >= 0.12) ..._burst('🔥', at, g, count: 6, reach: 54, size: 16),
        ];
      case 8: // clap: three claps
        return [
          _sprite('👏', at, size: 32 + 12 * math.sin(g * math.pi * 6).abs()),
        ];
      default: // cheers: a clink and some bubbles
        return [
          _sprite(
            g < 0.2 ? '🍺' : '🍻',
            at,
            size: 34 + 8 * _pop(g),
            turn: math.sin(g * math.pi * 4) * 0.2,
          ),
          ..._burst('🫧', at, g, count: 5, reach: 40, size: 12, rise: true),
        ];
    }
  }

  /// Quick swell at the start of the landing that settles back.
  double _pop(double g) =>
      g < 0.3 ? Curves.easeOutBack.transform(g / 0.3) : 1 - (g - 0.3) * 0.6;

  /// Flattens on impact and stays a little flat.
  double _squash(double g) => g < 0.15 ? g / 0.15 : 1.0;

  List<Widget> _burst(
    String emoji,
    Offset at,
    double g, {
    required int count,
    required double reach,
    required double size,
    bool rise = false,
  }) {
    final out = Curves.easeOut.transform(g);
    return [
      for (var i = 0; i < count; i++)
        () {
          final angle = rise
              ? -math.pi / 2 + (i - (count - 1) / 2) * 0.45
              : i * 2 * math.pi / count + 0.3;
          final d = reach * out * (rise ? 0.6 + 0.4 * (i % 2) : 1);
          return _sprite(
            emoji,
            at + Offset(math.cos(angle) * d, math.sin(angle) * d),
            size: size * (1 - g * 0.4),
          );
        }(),
    ];
  }

  Widget _sprite(
    String emoji,
    Offset at, {
    required double size,
    double turn = 0,
    double squash = 0,
  }) {
    final box = size * 1.4;
    return Positioned(
      left: at.dx - box / 2,
      top: at.dy - box / 2,
      width: box,
      height: box,
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..rotateZ(turn)
          ..scaleByDouble(1 + squash * 0.5, 1 - squash * 0.45, 1, 1),
        child: Center(
          child: Text(emoji, style: TextStyle(fontSize: size, height: 1)),
        ),
      ),
    );
  }
}
