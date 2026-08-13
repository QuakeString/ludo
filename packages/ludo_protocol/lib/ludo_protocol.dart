/// The wire format between the app and the game server.
///
/// Shared by both sides so the two cannot drift apart: adding a message means
/// adding it here, and both the app and the server then have to handle it.
library;

export 'src/messages.dart';
