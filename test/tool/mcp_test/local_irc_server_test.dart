import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/mcp_test/local_irc_server.dart';

Future<String> _readLine(StreamIterator<String> iterator) async {
  if (!await iterator.moveNext()) {
    throw StateError('socket closed before a line was available');
  }
  return iterator.current.trimRight();
}

void main() {
  test(
    'LocalIrcServer completes welcome and channel join transcript',
    () async {
      final server = await LocalIrcServer.start();
      final socket = await Socket.connect(server.host, server.port);
      final lines = StreamIterator<String>(
        socket
            .map<List<int>>((chunk) => chunk)
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );
      addTearDown(() async {
        await lines.cancel();
        socket.destroy();
        await server.dispose();
      });

      socket.write('NICK ruiNick\r\n');
      socket.write('USER ruiNick 0 * :Real UI\r\n');

      expect(await _readLine(lines), contains(' 001 ruiNick '));

      socket.write('JOIN #rui-live rui-secret\r\n');

      expect(await _readLine(lines), contains(' JOIN :#rui-live'));
      expect(await _readLine(lines), contains(' 353 ruiNick = #rui-live '));
      expect(await _readLine(lines), contains(' 366 ruiNick #rui-live '));
      expect(
        await server.waitForCommandContaining('JOIN #rui-live'),
        contains('JOIN #rui-live rui-secret'),
      );
    },
  );

  test('LocalIrcServer answers ping and records quit', () async {
    final server = await LocalIrcServer.start();
    final socket = await Socket.connect(server.host, server.port);
    final lines = StreamIterator<String>(
      socket
          .map<List<int>>((chunk) => chunk)
          .transform(utf8.decoder)
          .transform(const LineSplitter()),
    );
    addTearDown(() async {
      await lines.cancel();
      socket.destroy();
      await server.dispose();
    });

    socket.write('NICK pingNick\r\n');
    socket.write('USER pingNick 0 * :Ping User\r\n');
    await _readLine(lines);

    socket.write('PING :rui-probe\r\n');
    expect(
      await _readLine(lines),
      equals(':toxee.local PONG toxee.local :rui-probe'),
    );

    socket.write('QUIT :done\r\n');
    expect(
      await server.waitForCommandContaining('QUIT :done'),
      equals('QUIT :done'),
    );
  });

  group('startFromEnv (Android adb-reverse fixed-port support)', () {
    test('no env binds an ephemeral loopback port (macOS/iOS/Windows path)',
        () async {
      final server = await LocalIrcServer.startFromEnv(const {});
      addTearDown(server.dispose);
      // Identical observable behaviour to the legacy start(): loopback host,
      // an OS-assigned port. This is what macOS/iOS/Windows use unchanged. (The
      // full JOIN/PING transcript is already exercised by the start() tests
      // above; startFromEnv with no env calls start() with the same args.)
      expect(server.host, '127.0.0.1');
      expect(server.port, greaterThan(0));
      // It is actually accepting on the loopback: a clean connect + close
      // (no writes, so there are no un-drained server responses to reset).
      final socket = await Socket.connect(server.host, server.port);
      await socket.close();
      socket.destroy();
    });

    test('TOXEE_IRC_LOOPBACK_PORT binds that exact port', () async {
      // Grab + release an ephemeral port to use as a known-free fixed port.
      final probe = await ServerSocket.bind('127.0.0.1', 0);
      final fixedPort = probe.port;
      await probe.close();

      // The just-closed port can briefly linger before the OS frees it, so the
      // fixed re-bind is retried a few times (a test-harness race, not a
      // LocalIrcServer concern). The behaviour under test is "the env port is
      // honored", which the equality assertion below proves.
      LocalIrcServer? server;
      for (var attempt = 0; attempt < 8 && server == null; attempt++) {
        try {
          server = await LocalIrcServer.startFromEnv({
            'TOXEE_IRC_LOOPBACK_PORT': '$fixedPort',
            'TOXEE_IRC_LOOPBACK_BIND_HOST': '127.0.0.1',
          });
        } on SocketException {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      expect(server, isNotNull,
          reason: 'fixed-port bind never succeeded within the retry window');
      addTearDown(server!.dispose);
      expect(server.port, fixedPort,
          reason: 'the fixed env port must be honored so the Android launcher '
              'can adb-reverse a known port');
      expect(server.host, '127.0.0.1');
    });

    test('blank/garbage env values fall back to ephemeral loopback', () async {
      final server = await LocalIrcServer.startFromEnv({
        'TOXEE_IRC_LOOPBACK_PORT': 'not-a-number',
        'TOXEE_IRC_LOOPBACK_BIND_HOST': '',
      });
      addTearDown(server.dispose);
      expect(server.host, '127.0.0.1');
      expect(server.port, greaterThan(0));
    });
  });
}
