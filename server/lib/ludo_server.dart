/// The authority for online matches.
///
/// The server runs the very same `ludo_engine` the app runs, so the two cannot
/// disagree about what is legal. Clients send intents, never states.
library;

export 'src/room.dart';
export 'src/serve.dart';
export 'src/server.dart';
