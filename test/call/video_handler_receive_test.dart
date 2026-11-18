import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/call/video_handler.dart';

void main() {
  final luma = [76, 76, 76, 76];
  final chromaBlue = [85];
  final chromaRed = [255];

  testWidgets('an ended call cannot publish its pending video frame', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final video = VideoHandler();
      addTearDown(video.dispose);

      final pending = video.onVideoReceived(2, 2, luma, chromaBlue, chromaRed);
      await video.stop();
      await pending;

      expect(video.remoteImage.value, isNull);
    });
  });

  testWidgets('stopping the local camera preserves incoming video', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final video = VideoHandler();
      addTearDown(video.dispose);

      final pending = video.onVideoReceived(2, 2, luma, chromaBlue, chromaRed);
      await video.stopCapture();
      await pending;

      final image = video.remoteImage.value;
      expect(image?.width, 2);
      await video.stopCapture();
      expect(video.remoteImage.value, same(image));
    });
  });
}
