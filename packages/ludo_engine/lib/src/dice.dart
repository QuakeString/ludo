/// The dice.
///
/// xoshiro128\*\*: four words of thirty-two bits, a period of 2^128−1, and it
/// passes the test batteries that xorshift32 — what this replaces — fails.
///
/// The word size is the constraint that picks it, not the quality. Dart's `int`
/// is a real 64-bit integer when compiled ahead of time and a double when
/// compiled to JavaScript, where the bitwise operators work on 32 bits. A
/// 64-bit generator therefore produces different numbers in a browser than on
/// a phone — and the entire reason the dice are carried inside the game state
/// is that every device must agree on them. Four 32-bit words sidestep that,
/// and every arithmetic step below is kept under 2^53 so that a double holds
/// it exactly.
///
/// The state is deliberately *not* part of what the server sends to players.
/// See [GameState.toJson].
class DiceRng {
  const DiceRng(this.a, this.b, this.c, this.d);

  /// Spreads one seed across the whole state.
  ///
  /// Straight through SplitMix32 four times rather than dropping the seed into
  /// one word: a generator started from a state that is mostly zeros takes a
  /// while to stop looking like it, and a low seed would do exactly that.
  factory DiceRng.fromSeed(int seed) {
    var x = (seed == 0 ? 1 : seed) & 0xFFFFFFFF;
    int mix() {
      x = (x + 0x9E3779B9) & 0xFFFFFFFF;
      var z = x;
      z = _mul32(z ^ (z ~/ 0x10000), 0x85EBCA6B);
      z = _mul32(z ^ (z ~/ 0x2000), 0xC2B2AE35);
      return z ^ (z ~/ 0x10000);
    }

    final w = [mix(), mix(), mix(), mix()];
    // All-zero is the one state xoshiro cannot leave.
    return w.every((v) => v == 0)
        ? const DiceRng(1, 2, 3, 4)
        : DiceRng(w[0], w[1], w[2], w[3]);
  }

  final int a, b, c, d;

  /// A number this state can be identified by, for anything that wants to vary
  /// with the dice without consuming them.
  int get mark => a;

  /// The next 32-bit word, and the state that follows it.
  (DiceRng, int) _next() {
    final result = _mul32(_rotl(_mul32(b, 5), 7), 9);
    final t = _mul32(b, 512); // b << 9

    var (na, nb, nc, nd) = (a, b, c, d);
    nc ^= na;
    nd ^= nb;
    nb ^= nc;
    na ^= nd;
    nc ^= t;
    nd = _rotl(nd, 11);
    return (DiceRng(na, nb, nc, nd), result);
  }

  /// One die of [sides] faces, and the state that follows it.
  ///
  /// Rejection, not remainder. 2^32 is not a multiple of six, so `% 6` would
  /// hand four of the faces one extra chance in 715 million; throwing away the
  /// last partial block instead costs nothing measurable and is simply right.
  (DiceRng, int) roll(int sides) {
    final block = 0x100000000 ~/ sides;
    final limit = block * sides;
    var state = this;
    for (var guard = 0; guard < 64; guard++) {
      final (next, word) = state._next();
      state = next;
      if (word < limit) return (state, word ~/ block + 1);
    }
    // Sixty-four rejections in a row cannot happen — the chance is under one
    // in 10^100 — but a loop with no way out is not something to ship.
    final (next, word) = state._next();
    return (next, word % sides + 1);
  }

  /// The face this state would give, without spending it.
  int peek(int sides) => roll(sides).$2;

  List<int> toJson() => [a, b, c, d];

  static DiceRng fromJson(Object? v) {
    if (v is List && v.length == 4) {
      final w = [for (final x in v) (x as num).toInt() & 0xFFFFFFFF];
      if (!w.every((n) => n == 0)) return DiceRng(w[0], w[1], w[2], w[3]);
    }
    // A state that arrived without dice in it — a client's copy, which is not
    // allowed to know them. Anything it rolled locally would be ignored by the
    // server anyway.
    return const DiceRng(1, 2, 3, 4);
  }

  @override
  bool operator ==(Object other) =>
      other is DiceRng &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d;

  @override
  int get hashCode => Object.hash(a, b, c, d);

  @override
  String toString() => 'DiceRng($a,$b,$c,$d)';
}

/// Thirty-two bit multiply, done in halves so the intermediate never leaves
/// the range a double holds exactly. `x * y` directly would reach 2^64 and
/// quietly lose its low bits in a browser.
int _mul32(int x, int y) {
  final xl = x & 0xFFFF, xh = (x ~/ 0x10000) & 0xFFFF;
  final yl = y & 0xFFFF, yh = (y ~/ 0x10000) & 0xFFFF;
  final lo = xl * yl;
  final mid = (xh * yl + xl * yh) & 0xFFFF;
  return (lo + mid * 0x10000) & 0xFFFFFFFF;
}

int _rotl(int x, int k) =>
    ((x * (1 << k)) & 0xFFFFFFFF) | (x ~/ (1 << (32 - k)));
