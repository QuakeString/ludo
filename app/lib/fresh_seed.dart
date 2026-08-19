import 'dart:math';

/// A seed for a new local game.
///
/// The engine's dice are a deterministic chain: a game's whole sequence of
/// rolls follows from its seed, which is what lets a match be replayed, lets
/// the server and every client agree without sending each roll, and lets a
/// test reproduce a position exactly. The cost of that is that the seed has to
/// come from somewhere real, and a local game was never given one — so every
/// game anybody played on this device rolled the identical sequence of dice,
/// and "New game" was the same sequence shifted by one.
int freshSeed() => Random.secure().nextInt(0x7FFFFFFF) + 1;
