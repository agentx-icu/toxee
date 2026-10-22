import 'dart:math' as math;
import 'dart:ui';

/// All coordinates use the platform plugins' logical desktop coordinate space.
/// Reject a disconnected display or a caption reduced to an inaccessible sliver.
Rect? restoreDesktopBounds(Rect? saved, List<Rect> workAreas) {
  if (saved == null || !saved.isFinite || saved.width <= 0 || saved.height <= 0) { return null; }
  final caption = Rect.fromLTWH(
    saved.left,
    saved.top,
    saved.width,
    math.min(38, saved.height),
  );
  for (final work in workAreas) {
    if (!work.isFinite || work.isEmpty) continue;
    final visible = caption.intersect(work);
    if (visible.width < math.min(160, saved.width) ||
        visible.height < math.min(28, saved.height)) { continue; }
    final width = math.min(saved.width, work.width);
    final height = math.min(saved.height, work.height);
    return Rect.fromLTWH(
      saved.left.clamp(work.left, work.right - width),
      saved.top.clamp(work.top, work.bottom - height),
      width,
      height,
    );
  }
  return null;
}
