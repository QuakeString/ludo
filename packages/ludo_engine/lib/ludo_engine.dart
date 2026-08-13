/// Ludo rules, with no UI and no I/O.
///
/// The client runs this for offline play and the server runs the same code as
/// the authority for online play, so the two can never disagree about what is
/// legal. Everything is deterministic: a seed plus a list of actions replays a
/// game exactly.
library;

export 'src/ai.dart';
export 'src/arena.dart';
export 'src/board.dart';
export 'src/engine.dart';
export 'src/moves.dart';
export 'src/rules.dart';
export 'src/state.dart';
