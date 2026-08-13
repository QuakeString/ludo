# ludo_engine

The rules of Ludo as a pure Dart package — no UI, no networking, no clock.

The Flutter app runs this for offline play and the server runs the **same code**
as the authority for online play, so the two can never disagree about what is
legal and no client can talk the server out of the rules.

```dart
final rules = RuleConfig.sixSeat;              // 6 seats, 3 chips, pairing on
var state = GameState.newGame(rules, seed: 42);
const engine = LudoEngine();

state = engine.apply(state, const RollDice());
for (final move in engine.legalMoves(state)) {
  print(move);   // Move(advance, token3, 12→17, captures 9)
}
state = engine.apply(state, PlayMove(engine.bestMove(state)!));
```

Try it without writing anything:

```
dart run example/play_a_game.dart --rules=teams --seed=42
```

## What it knows

| | |
|---|---|
| Seats | 2–6. Two to four play the classic cross (52 squares), five or six the hexagon (78). |
| Chips | 2, 3 or 4 per player, at every seat count. |
| Entry | Roll a six, or any roll — `entryRoll: 0`. |
| Safety | Star squares, start squares, both, or nothing. |
| Blockades | Two *unlinked* tokens of one seat wall the square off. |
| Home | Exact count required, or overshoot-and-stop. |
| Teams | 2v2 at four seats, 3v3 or 2v2v2 at six. Partners don't capture or block each other, and a player who is home keeps rolling for a partner. |
| Pair move | Two tokens on one square link and travel as one on an even roll, at half the pips. Locked until a safe square. Only an opposing pair can take a pair. |
| Extras | Extra roll on six, extra roll on capture, three-sixes forfeit, must-capture-to-win, turn timer. |

Every one of those is a field on [`RuleConfig`](lib/src/rules.dart) rather than a
branch in the code, which is what makes custom rules a data problem instead of a
release.

## Positions are one integer

A token's whole journey is a single `progress` value:

```
 -1                        in its yard
 0 .. trackLength-2        on the ring, at (startRing + progress) % trackLength
 trackLength-1 .. +hc-1    in its own home column
 finalProgress             home
```

Move generation is then arithmetic rather than a graph walk, states compare with
`==`, and `fingerprint()` gives a stable string for golden replay tests.

## Determinism

The dice cursor lives in the state and advances through xorshift32, not
`dart:math`'s `Random` — whose sequence is not guaranteed to match across
platforms or releases. A seed plus a list of actions therefore replays a game
byte-for-byte on a phone and on the server.

## Pairs are not blockades

Both are two tokens sharing a square, and it would be easy to conflate them. A
**blockade** is two unlinked tokens of one seat: it stops everyone. A **pair** is
a deliberate link: it moves as one, it cannot be broken until it reaches safety,
and it can only be captured by another pair. If a pair also counted as a
blockade, no pair could ever be captured, so the engine keeps them apart —
`_blockedFor` skips linked tokens and `pairCapture` decides instead.

## Tests

```
dart test          # 106 tests
dart analyze
```

Beyond the rule-by-rule tests, the suite plays **full games to completion**
across twelve rule sets and several seeds, asserting each one terminates and
produces a winner, and checks invariants after every single turn: token count
and ownership never change, progress stays in range, and every pair always has
exactly two members standing on the same square.
