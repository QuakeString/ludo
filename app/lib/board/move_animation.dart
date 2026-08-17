import 'dart:math' as math;

import 'package:ludo_engine/ludo_engine.dart';
import 'package:ludo_geometry/ludo_geometry.dart';

import 'chip_layout.dart';

/// Where a chip is drawn mid-move, and how it is deformed.
class ChipMotion {
  const ChipMotion({
    required this.ground,
    this.lift = 0,
    this.squash = 1,
    this.scale = 1,
    this.spin = 0,
    this.fade = 1,
  });

  final Pt ground;
  final double lift;
  final double squash;
  final double scale;
  final double spin;
  final double fade;
}

/// Turns a played move into a sequence of hops.
///
/// A chip never slides. It hops once per pip, so a five is five visible steps
/// and the player can count the move as it happens — sliding hides miscounts
/// and feels weightless. A pair moving at half speed still hops once per
/// square it actually travels.
class MoveAnimation {
  MoveAnimation({
    required this.move,
    required this.before,
    required this.geometry,
  }) : _waypoints = _pathFor(move, before, geometry);

  final Move move;
  final GameState before;
  final BoardGeometry geometry;

  final List<Pt> _waypoints;

  static const hopMillis = 150;
  static const landMillis = 90;
  static const captureMillis = 700;

  int get hops => math.max(0, _waypoints.length - 1);

  /// Total run time, including the captured chip's flight home.
  Duration get duration => Duration(
    milliseconds:
        hops * (hopMillis + landMillis) + (move.isCapture ? captureMillis : 0),
  );

  /// Every square the chip passes through, start to finish.
  ///
  /// Entering from the yard is a single hop, because there is nothing between
  /// the yard and the start square to travel over.
  static List<Pt> _pathFor(Move move, GameState s, BoardGeometry g) {
    final owner = move.owner;
    final arm = s.armOf(owner);
    if (move.kind == MoveKind.enter) {
      final token = s.tokens[move.tokenId];
      // The chip leaves from the place it was actually sitting in.
      return [
        g.tokenAt(arm, -1, slot: yardSlotOf(s, token)),
        g.tokenAt(arm, 0),
      ];
    }
    return [
      for (var p = move.fromProgress; p <= move.toProgress; p++)
        g.tokenAt(arm, p),
    ];
  }

  /// The moving chip at time [t] (0..1 across [duration]).
  ChipMotion moverAt(double t) {
    if (hops == 0) {
      return ChipMotion(
        ground: _waypoints.isEmpty ? const Pt(0.5, 0.5) : _waypoints.last,
      );
    }
    final travelMillis = hops * (hopMillis + landMillis);
    final elapsed = t * duration.inMilliseconds;
    if (elapsed >= travelMillis) {
      return ChipMotion(ground: _waypoints.last);
    }

    final step = (elapsed / (hopMillis + landMillis)).floor().clamp(
      0,
      hops - 1,
    );
    final within = elapsed - step * (hopMillis + landMillis);
    final from = _waypoints[step];
    final to = _waypoints[step + 1];

    if (within <= hopMillis) {
      final p = within / hopMillis;
      return ChipMotion(
        ground: Pt(from.x + (to.x - from.x) * p, from.y + (to.y - from.y) * p),
        // A parabola, not a straight line — the chip has weight.
        lift: math.sin(math.pi * p),
      );
    }
    // Landing: squash, then recover.
    final p = (within - hopMillis) / landMillis;
    final squash = p < 0.5
        ? 1 - 0.12 * (p / 0.5)
        : 0.88 + 0.12 * ((p - 0.5) / 0.5);
    return ChipMotion(ground: to, squash: squash);
  }

  /// A captured chip's flight back to its yard: up, spinning, shrinking.
  ChipMotion? capturedAt(double t, int tokenId) {
    if (!move.isCapture || !move.capturedTokenIds.contains(tokenId)) {
      return null;
    }
    final travelMillis = hops * (hopMillis + landMillis);
    final elapsed = t * duration.inMilliseconds;
    if (elapsed < travelMillis) {
      final token = before.tokens[tokenId];
      return ChipMotion(
        ground: geometry.tokenAt(before.armOf(token.owner), token.progress),
      );
    }
    final p = ((elapsed - travelMillis) / captureMillis).clamp(0.0, 1.0);

    final token = before.tokens[tokenId];
    final from = geometry.tokenAt(before.armOf(token.owner), token.progress);
    final home = geometry.tokenAt(
      before.armOf(token.owner),
      -1,
      // Its own resting place, not id-modulo-four: token ids are global, so
      // that only lined up while every player had exactly four chips.
      slot: yardSlotOf(before, token),
    );
    return ChipMotion(
      ground: Pt(
        from.x + (home.x - from.x) * p,
        from.y + (home.y - from.y) * p,
      ),
      lift: math.sin(math.pi * p) * 2.2,
      spin: p * 2 * math.pi,
      scale: 1 - 0.35 * p,
      fade: 1 - 0.15 * p,
    );
  }
}
