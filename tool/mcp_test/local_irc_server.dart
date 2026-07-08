import 'dart:async';
import 'dart:convert';
import 'dart:io';

class LocalIrcServer {
  LocalIrcServer._(this._server);

  /// Start a throwaway loopback IRC server for the real-UI IRC scenarios.
  ///
  /// [host] is the bind address (default `127.0.0.1`); [port] is the bind port
  /// (default `0` = an OS-assigned ephemeral port). A FIXED [port] matters only
  /// for the remote/mobile real-UI platforms where the app under test is NOT on
  /// the same host as this driver:
  ///   - Android: the app runs on a device/emulator, so the host loopback is
  ///     reached via `adb reverse tcp:<port> tcp:<port>`, which must be set up
  ///     for a KNOWN port BEFORE this server picks one — hence the fixed port.
  ///   - macOS / iOS Simulator / Windows: the app shares the host loopback, so
  ///     the ephemeral default is used unchanged (no reverse-forward needed).
  /// The driver reads `TOXEE_IRC_LOOPBACK_PORT` / `TOXEE_IRC_LOOPBACK_BIND_HOST`
  /// and passes them here, so platforms that don't set them keep the previous
  /// byte-for-byte behaviour.
  static Future<LocalIrcServer> start({
    String host = '127.0.0.1',
    int port = 0,
  }) async {
    final server = await ServerSocket.bind(host, port);
    final ircServer = LocalIrcServer._(server);
    ircServer._subscription = server.listen(ircServer._handleClient);
    return ircServer;
  }

  /// Build a server from the driver's IRC-loopback environment overrides, so
  /// every real-UI IRC scenario resolves the bind host/port the same way. With
  /// no env set this is identical to `start()` (ephemeral loopback).
  static Future<LocalIrcServer> startFromEnv(Map<String, String> env) {
    final host = (env['TOXEE_IRC_LOOPBACK_BIND_HOST'] ?? '127.0.0.1').trim();
    final port = int.tryParse((env['TOXEE_IRC_LOOPBACK_PORT'] ?? '').trim()) ?? 0;
    return start(host: host.isEmpty ? '127.0.0.1' : host, port: port);
  }

  final ServerSocket _server;
  final List<String> _seenCommands = <String>[];
  final StreamController<String> _commands =
      StreamController<String>.broadcast();
  StreamSubscription<Socket>? _subscription;

  String get host => _server.address.address;
  int get port => _server.port;
  List<String> get seenCommands => List.unmodifiable(_seenCommands);

  Future<String> waitForCommandContaining(
    String needle, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    for (final command in _seenCommands) {
      if (command.contains(needle)) return command;
    }
    return _commands.stream
        .firstWhere((command) => command.contains(needle))
        .timeout(timeout);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _commands.close();
    await _server.close();
  }

  void _handleClient(Socket socket) {
    var nick = 'ruiNick';
    unawaited(
      socket
          .map<List<int>>((chunk) => chunk)
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              final command = line.trimRight();
              if (command.isEmpty) return;
              _record(command);
              final parts = command.split(RegExp(r'\s+'));
              final verb = parts.first.toUpperCase();
              if (verb == 'NICK' && parts.length > 1) {
                nick = parts[1];
                return;
              }
              if (verb == 'USER') {
                _write(
                  socket,
                  ':toxee.local 001 $nick :Welcome to toxee local IRC',
                );
                return;
              }
              if (verb == 'JOIN' && parts.length > 1) {
                final channel = parts[1];
                _write(socket, ':$nick!local@toxee.local JOIN :$channel');
                _write(
                  socket,
                  ':toxee.local 353 $nick = $channel :$nick localPeer',
                );
                _write(
                  socket,
                  ':toxee.local 366 $nick $channel :End of /NAMES list.',
                );
                return;
              }
              if (verb == 'PING') {
                final token = command.substring('PING'.length).trim();
                _write(socket, ':toxee.local PONG toxee.local $token');
              }
            },
            onDone: socket.destroy,
            onError: (_) => socket.destroy(),
          )
          .asFuture<void>(),
    );
  }

  void _record(String command) {
    _seenCommands.add(command);
    _commands.add(command);
  }

  void _write(Socket socket, String line) {
    socket.write('$line\r\n');
  }
}
