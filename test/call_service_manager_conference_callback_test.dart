import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/av_conference_session_bridge.dart';
import 'package:toxee/call/conference_audio_callback_registry.dart';

void main() {
  test(
    'keeps overlapping conference group callbacks isolated during teardown',
    () {
      AvConferenceAudioFrameCallback? nativeCallback;
      var nativeCallbackInstallations = 0;
      final groupAFrames = <int>[];
      final groupBFrames = <int>[];
      final ownerA = AvConferenceSessionOwner();
      final ownerB = AvConferenceSessionOwner();
      final registry = ConferenceAudioCallbackRegistry(
        installNativeCallback: (callback) {
          nativeCallback = callback;
          nativeCallbackInstallations += 1;
        },
      );

      registry.register('group-a', ownerA, (
        _,
        __,
        ___,
        ____,
        sampleCount,
        _____,
        ______,
      ) {
        groupAFrames.add(sampleCount);
      });
      registry.register('group-b', ownerB, (
        _,
        __,
        ___,
        ____,
        sampleCount,
        _____,
        ______,
      ) {
        groupBFrames.add(sampleCount);
      });

      void emit(String groupId, int sampleCount) {
        nativeCallback?.call(
          groupId,
          1,
          2,
          const <int>[1, 2],
          sampleCount,
          1,
          48000,
        );
      }

      expect(nativeCallbackInstallations, 1);
      emit('group-a', 10);
      emit('group-b', 20);
      expect(groupAFrames, <int>[10]);
      expect(groupBFrames, <int>[20]);

      registry.unregister('group-a', ownerA);
      expect(nativeCallback, isNotNull);
      emit('group-a', 30);
      emit('group-b', 40);

      expect(groupAFrames, <int>[10]);
      expect(groupBFrames, <int>[20, 40]);

      registry.unregister('group-b', ownerB);
      expect(nativeCallback, isNull);
      expect(nativeCallbackInstallations, 2);
    },
  );

  test('duplicate same-group registration does not replace its owner', () {
    AvConferenceAudioFrameCallback? nativeCallback;
    var ownerFrames = 0;
    var duplicateFrames = 0;
    final owner = AvConferenceSessionOwner();
    final duplicate = AvConferenceSessionOwner();
    final registry = ConferenceAudioCallbackRegistry(
      installNativeCallback: (callback) {
        nativeCallback = callback;
      },
    );

    expect(
      registry.register('shared-group', owner, (
        _,
        __,
        ___,
        ____,
        _____,
        ______,
        _______,
      ) {
        ownerFrames += 1;
      }),
      isTrue,
    );
    expect(
      registry.register('shared-group', duplicate, (
        _,
        __,
        ___,
        ____,
        _____,
        ______,
        _______,
      ) {
        duplicateFrames += 1;
      }),
      isFalse,
    );

    expect(registry.unregister('shared-group', duplicate), isFalse);

    nativeCallback?.call('shared-group', 1, 2, const <int>[1, 2], 2, 1, 48000);

    expect(ownerFrames, 1);
    expect(duplicateFrames, 0);
    expect(registry.unregister('shared-group', owner), isTrue);
    expect(nativeCallback, isNull);
  });
}
