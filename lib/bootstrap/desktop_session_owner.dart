import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Process ownership for a shared store. The lock file is never unlinked:
/// deleting it would let another process lock a different inode at the same path.
class DesktopSessionOwner {
  DesktopSessionOwner._(this._lock, this._server);
  final RandomAccessFile _lock;
  final ServerSocket _server;

  static Future<DesktopSessionOwner?> claim(
    String root, {
    required Future<void> Function() onActivate,
  }) async {
    final directory = Directory(root);
    await directory.create(recursive: true);
    final file = File(
      '${await directory.resolveSymbolicLinks()}/.session-owner',
    );
    final metadata = File('${file.path}.json');
    final lock = await file.open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } on FileSystemException {
      await lock.close();
      // The owner may still be binding its activation socket after taking the lock.
      for (var attempt = 0; attempt < 10; attempt++) {
        try {
          final owner = jsonDecode(await metadata.readAsString()) as Map;
          final socket = await Socket.connect(
            InternetAddress.loopbackIPv4,
            owner['port'] as int,
            timeout: const Duration(milliseconds: 200),
          );
          socket.writeln(owner['token']);
          await socket.flush();
          await socket.close();
          socket.destroy();
          return null;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }
      // A failed activation never grants write ownership.
      return null;
    }
    ServerSocket? server;
    try {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final token = List.generate(
        24,
        (_) => Random.secure().nextInt(256),
      ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
      // Windows locks deny reads of the locked byte range. Activation metadata
      // therefore lives in a separate, atomically replaced sidecar.
      final staged = File('${metadata.path}.$pid.tmp');
      await staged.writeAsString(jsonEncode({'port': server.port, 'token': token}), flush: true);
      await staged.rename(metadata.path);
      server.listen((socket) async {
        try {
          final request = await socket
              .cast<List<int>>()
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .first
              .timeout(const Duration(seconds: 1));
          if (request == token) await onActivate();
        } catch (_) {
          // Stale or invalid local activation requests cannot affect ownership.
        } finally {
          socket.destroy();
        }
      });
      return DesktopSessionOwner._(lock, server);
    } catch (_) {
      await server?.close();
      await lock.close();
      rethrow;
    }
  }

  Future<void> close() async {
    await _server.close();
    await _lock.close();
  }
}
