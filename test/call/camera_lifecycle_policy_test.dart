// V5/B1: mobile offscreen capture stops; desktop hidden/minimized calls keep
// capturing. Both policies are explicit so a host OS cannot change the test.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_video_lifecycle_controller.dart';

void main() {
  const policies = {
    AppLifecycleState.resumed: (mobile: true, desktop: true),
    AppLifecycleState.inactive: (mobile: true, desktop: true),
    AppLifecycleState.hidden: (mobile: false, desktop: true),
    AppLifecycleState.paused: (mobile: false, desktop: false),
    AppLifecycleState.detached: (mobile: false, desktop: false),
  };
  for (final isDesktop in [false, true]) {
    for (final entry in policies.entries) {
      test(
        '${isDesktop ? 'desktop' : 'mobile'} ${entry.key.name} capture eligibility',
        () {
          expect(
            cameraMayRunIn(entry.key, isDesktop: isDesktop),
            isDesktop ? entry.value.desktop : entry.value.mobile,
          );
        },
      );
    }
  }
}
