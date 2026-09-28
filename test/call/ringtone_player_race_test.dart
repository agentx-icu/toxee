// A9 follow-up: the call can end while the ringtone is still starting
// (callers do not await start()). A stop() that lands meanwhile must win —
// otherwise the ring loops after the call is over.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/ringtone_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The AudioPlayer is still constructed (and asks its plugin to create it).
  const players = MethodChannel('xyz.luan/audioplayers');
  const global = MethodChannel('xyz.luan/audioplayers.global');
  late Directory tmp;
  late List<String> events;
  late Completer<void> playing;

  setUp(() {
    events = [];
    playing = Completer<void>();
    tmp = Directory.systemTemp.createTempSync('ringtone-race-');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(players, (_) async => null);
    messenger.setMockMethodCallHandler(global, (_) async => null);
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(players, null);
    messenger.setMockMethodCallHandler(global, null);
    tmp.deleteSync(recursive: true);
  });

  RingtonePlayer ringtone() => RingtonePlayer(
    isIOS: false,
    isAndroid: false,
    playLoop: (_, volume) async {
      await playing.future; // the platform is slow to start playing
      events.add('play');
    },
    setLoopVolume: (v) async => events.add('volume $v'),
    stopLoop: () async => events.add('stop'),
    createWav: () async => '${tmp.path}/ring.wav',
  );

  test('a stop during start leaves nothing ringing', () async {
    final player = ringtone();
    final starting = player.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final stopping = player.stop(); // the call ended meanwhile
    playing.complete();
    await Future.wait([starting, stopping]);
    expect(events, ['play', 'stop'], reason: 'the late play is stopped');
  });

  test('start after stop rings again; a double start rings once', () async {
    playing.complete();
    final player = ringtone();
    await player.start();
    await player.start();
    await player.stop();
    await player.start();
    expect(events, ['play', 'stop', 'play']);
    await player.stop();
  });

  test('iOS on screen: native ringer plus a muted loop; leaving the screen '
      'stops the native one and unmutes the loop', () async {
    playing.complete();
    const callAudio = MethodChannel('toxee/call_audio');
    final native = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(callAudio, (call) async {
      native.add(call.method);
      return call.method == 'playIncomingRingtone' ? true : null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(callAudio, null),
    );
    final loop = <String>[];
    final player = RingtonePlayer(
      isIOS: true,
      isAndroid: false,
      playLoop: (_, volume) async => loop.add('play $volume'),
      setLoopVolume: (v) async => loop.add('volume $v'),
      stopLoop: () async => loop.add('stop'),
      createWav: () async => '${tmp.path}/ring.wav',
    );
    await player.start();
    expect(native, ['playIncomingRingtone']);
    expect(loop, ['play 0.0']);

    final binding = TestWidgetsFlutterBinding.instance;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await Future<void>.delayed(Duration.zero);
    expect(native, ['playIncomingRingtone', 'stopIncomingRingtone']);
    expect(loop, ['play 0.0', 'volume 1.0']);

    await player.stop();
    expect(loop.last, 'stop');
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  test('stop + restart while the first start is pending: one ring', () async {
    final player = ringtone();
    final a = player.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final stopping = player.stop();
    final b = player.start();
    playing.complete();
    await Future.wait([a, stopping, b]);
    // A finished, was stopped, then B rang: exactly one loop is playing.
    expect(events, ['play', 'stop', 'play']);
    await player.stop();
  });

  group('iOS on screen', () {
    const callAudio = MethodChannel('toxee/call_audio');
    late List<String> native;

    setUp(() {
      native = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(callAudio, (call) async {
        native.add(call.method);
        return call.method == 'playIncomingRingtone' ? true : null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(callAudio, null);
      TestWidgetsFlutterBinding.instance.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
    });

    RingtonePlayer ios({required List<String> loop, Completer<void>? gate, bool loopFails = false}) =>
        RingtonePlayer(
          isIOS: true,
          isAndroid: false,
          playLoop: (_, volume) async {
            await gate?.future;
            if (loopFails) throw StateError('no audio');
            loop.add('play $volume');
          },
          setLoopVolume: (v) async => loop.add('volume $v'),
          stopLoop: () async => loop.add('stop'),
          createWav: () async => '${tmp.path}/ring.wav',
        );

    void hide() {
      final binding = TestWidgetsFlutterBinding.instance;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }

    test('a hide while the muted loop is still starting still unmutes it', () async {
      final loop = <String>[];
      final gate = Completer<void>();
      final player = ios(loop: loop, gate: gate);
      final starting = player.start();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      hide(); // before the muted loop has started
      gate.complete();
      await starting;
      await player.stop(); // queued after the hand-over
      expect(native, ['playIncomingRingtone', 'stopIncomingRingtone']);
      expect(loop, ['play 0.0', 'volume 1.0', 'stop']);
    });

    test('a failing companion loop keeps the native ring', () async {
      final loop = <String>[];
      final player = ios(loop: loop, loopFails: true);
      await player.start();
      expect(native, ['playIncomingRingtone'], reason: 'still ringing');
      await player.stop();
      expect(native.last, 'stopIncomingRingtone');
    });
  });
}
