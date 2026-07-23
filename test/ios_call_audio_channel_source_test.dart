import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final channelFile = File('$repoRoot/ios/Runner/CallAudioChannel.swift');

  test(
    'iOS call audio route choices are cleared when the session deactivates',
    () async {
      expect(
        channelFile.existsSync(),
        isTrue,
        reason: 'iOS call audio channel moved; update this regression test.',
      );
      final src = await channelFile.readAsString();
      final deactivateBody = RegExp(
        r'private func deactivateSession\(\) \{([\s\S]*?)\n  \}',
      ).firstMatch(src)?.group(1);

      expect(deactivateBody, isNotNull);
      expect(
        deactivateBody,
        contains('preferredRouteId = nil'),
        reason:
            'Route picker choices are per-call. Keeping preferredRouteId after '
            'deactivation makes the next audio/video call inherit the previous '
            'route instead of its default speaker/earpiece policy.',
      );
    },
  );

  test(
    'iOS proximity monitoring is disabled when call audio deactivates',
    () async {
      final src = await channelFile.readAsString();

      expect(src, contains('"setProximityMonitoring"'));
      expect(src, contains('UIDevice.current.isProximityMonitoringEnabled'));
      final deactivateBody = RegExp(
        r'private func deactivateSession\(\) \{([\s\S]*?)\n  \}',
      ).firstMatch(src)?.group(1);
      expect(deactivateBody, contains('setProximityMonitoring(false)'));
    },
  );

  test('iOS interruption end emits the native shouldResume option', () async {
    final src = await channelFile.readAsString();

    expect(src, contains('AVAudioSessionInterruptionOptionKey'));
    expect(src, contains('.shouldResume'));
    expect(src, contains('shouldResume'));
  });
}
