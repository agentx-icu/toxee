// P0-C regression guard: while an AV call is live, toxav_iterate must run on
// the fast cadence regardless of how idle the text/file side is. Before this
// policy existed, the adaptive poll interval could relax to 1000ms mid-call,
// starving RTP receive and causing audible stutter.
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

void main() {
  Duration interval({
    bool av = false,
    bool fileTransfer = false,
    bool knownInstances = false,
    bool shared = false,
    Duration sinceActivity = const Duration(seconds: 10),
  }) {
    return FfiChatService.computePollInterval(
      avSessionActive: av,
      hasActiveFileTransfer: fileTransfer,
      hasKnownInstances: knownInstances,
      isSharedInstance: shared,
      timeSinceActivity: sinceActivity,
    );
  }

  group('computePollInterval', () {
    test('AV session forces 20ms even when everything else says idle', () {
      expect(
        interval(av: true, sinceActivity: const Duration(minutes: 5)),
        const Duration(milliseconds: 20),
      );
    });

    test('AV session outranks the file-transfer and instance fast paths', () {
      expect(
        interval(av: true, fileTransfer: true, knownInstances: true),
        const Duration(milliseconds: 20),
      );
    });

    test('file transfer polls at 50ms when no call is active', () {
      expect(interval(fileTransfer: true), const Duration(milliseconds: 50));
    });

    test('test/multi-instance and shared-instance poll at 50ms', () {
      expect(interval(knownInstances: true), const Duration(milliseconds: 50));
      expect(interval(shared: true), const Duration(milliseconds: 50));
    });

    test('recent activity polls at 200ms, idle at 1000ms', () {
      expect(
        interval(sinceActivity: const Duration(seconds: 1)),
        const Duration(milliseconds: 200),
      );
      expect(
        interval(sinceActivity: const Duration(seconds: 3)),
        const Duration(milliseconds: 1000),
      );
    });
  });
}
