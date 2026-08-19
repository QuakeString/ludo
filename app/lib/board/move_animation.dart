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
    this.trail = const [],
  });

  final Pt ground;

  /// Where the chip was a moment ago, most recent first — the streak it leaves
  /// behind it. Carried here rather than worked out by the painter, because
  /// only the animation knows where the chip has been.
  final List<Pt> trail;
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

  /// A hop's flight time, and the little squash as it lands.
  static const hopMillis = 150;
  static const landMillis = 90;

  /// Coming out of the yard is one hop, but it crosses a corner of the board
  /// rather than stepping to the next square. At the ordinary 150ms it read as
  /// the chip being flicked out rather than set down.
  static const enterHopMillis = 430;

  /// How long this move's hops take. Every hop within a move is the same
  /// length; only leaving the yard differs, and that move is a single hop.
  int get flightMillis =>
      move.kind == MoveKind.enter ? enterHopMillis : hopMillis;

  /// How far back the streak behind a moving chip reaches, and how finely it
  /// is sampled.
  static const trailMillis = 240;
  static const trailSamples = 9;

  /// How long a captured chip takes per square of its walk home.
  ///
  /// Slow enough to follow with your eyes: the whole point of walking it back
  /// rather than snapping it to its yard is that you can see how much ground
  /// was taken off you, and a blur does not show that. It has been too fast
  /// twice; this is a deliberate trudge, about eight squares a second.
  static const captureStepMillis = 105;
  static const captureMinMillis = 800;
  static const captureMaxMillis = 4200;

  /// The whole retreat, sized to how far the chip has to come back.
  int get captureMillis {
    if (!move.isCapture) return 0;
    var longest = 0;
    for (final id in move.capturedTokenIds) {
      final steps = _retreatPath(id).length;
      if (steps > longest) longest = steps;
    }
    return (longest * captureStepMillis).clamp(
      captureMinMillis,
      captureMaxMillis,
    );
  }

  int get hops => math.max(0, _waypoints.length - 1);

  /// Total run time, including the captured chip's flight home.
  Duration get duration => Duration(
    milliseconds:
        hops * (flightMillis + landMillis) +
        (move.isCapture ? captureMillis : 0),
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
        g.tokenAt(
          arm,
          -1,
          slot: yardSlotOf(s, token),
          yardCount: s.rules.tokensPerPlayer,
        ),
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
    final travelMillis = hops * (flightMillis + landMillis);
    final elapsed = t * duration.inMilliseconds;
    if (elapsed >= travelMillis) {
      return ChipMotion(ground: _waypoints.last);
    }

    final step = (elapsed / (flightMillis + landMillis)).floor().clamp(
      0,
      hops - 1,
    );
    final within = elapsed - step * (flightMillis + landMillis);
    final from = _waypoints[step];
    final to = _waypoints[step + 1];

    if (within <= flightMillis) {
      final p = within / flightMillis;
      return ChipMotion(
        ground: Pt(from.x + (to.x - from.x) * p, from.y + (to.y - from.y) * p),
        // A parabola, not a straight line — the chip has weight.
        lift: math.sin(math.pi * p),
        trail: _trailAt(elapsed),
      );
    }
    // Landing: squash, then recover.
    final p = (within - flightMillis) / landMillis;
    final squash = p < 0.5
        ? 1 - 0.12 * (p / 0.5)
        : 0.88 + 0.12 * ((p - 0.5) / 0.5);
    return ChipMotion(ground: to, squash: squash, trail: _trailAt(elapsed));
  }

  /// When the chip touches down after its [hop]th flight, counting from zero.
  ///
  /// Exposed because the sound of a chip landing is scheduled against it: a
  /// move of three squares is three taps, and only this knows when they fall.
  Duration landingAt(int hop) =>
      Duration(milliseconds: hop * (flightMillis + landMillis) + flightMillis);

  /// Where the moving chip is [elapsed] milliseconds into the move.
  Pt _groundAt(double elapsed) {
    if (hops == 0) {
      return _waypoints.isEmpty ? const Pt(0.5, 0.5) : _waypoints.last;
    }
    if (elapsed <= 0) return _waypoints.first;
    if (elapsed >= hops * (flightMillis + landMillis)) return _waypoints.last;

    final step = (elapsed / (flightMillis + landMillis)).floor().clamp(
      0,
      hops - 1,
    );
    final within = elapsed - step * (flightMillis + landMillis);
    final from = _waypoints[step];
    final to = _waypoints[step + 1];
    if (within >= flightMillis) return to;
    final p = within / flightMillis;
    return Pt(from.x + (to.x - from.x) * p, from.y + (to.y - from.y) * p);
  }

  /// The streak behind the chip: where it was, sampled backwards.
  ///
  /// Taken from the same function that says where it is, so the trail can
  /// never drift away from the chip leaving it.
  List<Pt> _trailAt(double elapsed) {
    final out = <Pt>[];
    for (var i = 1; i <= trailSamples; i++) {
      final back = elapsed - trailMillis * (i / trailSamples);
      if (back <= 0) break;
      out.add(_groundAt(back));
    }
    return out;
  }

  /// The way a captured chip goes home: back along the squares it came by.
  ///
  /// A chip that flies over the board tells you nothing. Walking it back down
  /// its own track shows the player exactly how much ground was just taken off
  /// them, which is the whole meaning of the capture.
  List<Pt> _retreatPath(int tokenId) {
    final token = before.tokens[tokenId];
    final arm = before.armOf(token.owner);
    final path = <Pt>[
      for (var p = token.progress; p >= 0; p--) geometry.tokenAt(arm, p),
      geometry.tokenAt(
        arm,
        -1,
        slot: yardSlotOf(before, token),
        yardCount: before.rules.tokensPerPlayer,
      ),
    ];
    return path;
  }

  final Map<int, List<double>> _retreatMarks = {};

  /// Distance along the retreat at each waypoint, so the walk can be paced by
  /// ground covered instead of by squares passed.
  List<double> _retreatMileposts(int tokenId) =>
      _retreatMarks.putIfAbsent(tokenId, () {
        final path = _retreatPath(tokenId);
        final marks = <double>[0];
        for (var i = 1; i < path.length; i++) {
          marks.add(marks[i - 1] + (path[i] - path[i - 1]).length);
        }
        return marks;
      });

  /// A captured chip's walk back to its yard.
  ChipMotion? capturedAt(double t, int tokenId) {
    if (!move.isCapture || !move.capturedTokenIds.contains(tokenId)) {
      return null;
    }
    final travelMillis = hops * (flightMillis + landMillis);
    final elapsed = t * duration.inMilliseconds;
    if (elapsed < travelMillis) {
      final token = before.tokens[tokenId];
      return ChipMotion(
        ground: geometry.tokenAt(before.armOf(token.owner), token.progress),
      );
    }
    final p = ((elapsed - travelMillis) / captureMillis).clamp(0.0, 1.0);
    final path = _retreatPath(tokenId);
    if (path.length < 2) return ChipMotion(ground: path.first);

    // One steady speed the whole way back, measured in ground covered rather
    // than in squares passed.
    //
    // It used to ease out, which meant it crossed most of the board in the
    // first moment and then crawled — so the part worth watching, the distance
    // being given up, went by too fast to follow, while the part nobody needs
    // to see was drawn out. Pacing by squares instead is nearly right and
    // still visibly wrong: the track turns its corners diagonally, which is
    // half again as far as a straight step, and the last stride into the yard
    // is longer than any square. The chip sped up exactly at the corners, which
    // is where the eye is following it.
    final marks = _retreatMileposts(tokenId);
    final want = marks.last * p;
    var i = 0;
    while (i < marks.length - 2 && marks[i + 1] < want) {
      i++;
    }
    final leg = marks[i + 1] - marks[i];
    final f = leg <= 0 ? 0.0 : ((want - marks[i]) / leg).clamp(0.0, 1.0);
    final a = path[i], b = path[i + 1];

    return ChipMotion(
      ground: Pt(a.x + (b.x - a.x) * f, a.y + (b.y - a.y) * f),
      // A little smaller while travelling, back to full size on arrival —
      // enough to read as "removed" without leaving the board.
      scale: 1 - 0.18 * math.sin(math.pi * p),
      fade: 1 - 0.25 * math.sin(math.pi * p),
    );
  }
}
