import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/call_service_manager.dart';
import 'package:toxee/call/call_state_notifier.dart';

void main() {
  test('foreground call uses camera only for active local video capture', () {
    expect(
      callForegroundUsesCamera(
        mode: CallMode.audio,
        isVideoEnabled: false,
        supportsVideoCapture: true,
        isVideoCapturing: false,
      ),
      isFalse,
    );
    expect(
      callForegroundUsesCamera(
        mode: CallMode.video,
        isVideoEnabled: false,
        supportsVideoCapture: true,
        isVideoCapturing: true,
      ),
      isFalse,
    );
    expect(
      callForegroundUsesCamera(
        mode: CallMode.video,
        isVideoEnabled: true,
        supportsVideoCapture: false,
        isVideoCapturing: true,
      ),
      isFalse,
    );
    expect(
      callForegroundUsesCamera(
        mode: CallMode.video,
        isVideoEnabled: true,
        supportsVideoCapture: true,
        isVideoCapturing: false,
      ),
      isFalse,
    );
    expect(
      callForegroundUsesCamera(
        mode: CallMode.video,
        isVideoEnabled: true,
        supportsVideoCapture: true,
        isVideoCapturing: true,
      ),
      isTrue,
    );
  });
}
