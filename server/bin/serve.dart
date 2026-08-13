import 'dart:io';

import 'package:ludo_server/ludo_server.dart';

/// The game server.
///
///   dart run bin/serve.dart              # listens on 8080
///   PORT=9000 dart run bin/serve.dart
///   dart run bin/serve.dart --health     # asks a running server if it is up
///
/// One process holds every live room in memory. A match only matters while it
/// is being played — one that outlived a restart would be one everybody had
/// already left — so persistence belongs to accounts and match history rather
/// than to rooms.
Future<void> main(List<String> args) async {
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;

  // The container image has no shell, so the health check runs this same
  // binary with a flag and reports through the exit code.
  if (args.contains('--health')) {
    exit(await _isHealthy(port) ? 0 : 1);
  }

  final server = await startServer(port: port);
  stdout.writeln('Ludo server listening on port ${server.port}');

  // Shut down cleanly so in-flight sockets are closed rather than dropped.
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    signal.watch().listen((_) async {
      stdout.writeln('shutting down');
      await server.close();
      exit(0);
    });
  }
}

/// Asks the already-running server whether it is up.
Future<bool> _isHealthy(int port) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
  try {
    final request = await client.get('127.0.0.1', port, '/health');
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}
