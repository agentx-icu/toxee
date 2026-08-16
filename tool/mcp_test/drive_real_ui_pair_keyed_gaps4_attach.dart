// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Keyed-gaps batch #4 — the ATTACHMENT / MEDIA-VIEWER half. Spine and dispatch
// live in `drive_real_ui_pair_keyed_gaps4.dart`; this file holds only case
// bodies so each part stays under the 500-LOC complexity cap. One library.

// ===========================================================================
// case — attachment_toolbar_disabled_entries_gating
// ===========================================================================
/// The DESKTOP composer toolbar's four never-driven keys —
/// `message_attachment_{image,photo,video,search}_button`. They exist in the
/// fork's icon->key switch (tencent_cloud_chat_message_input_desktop.dart) but
/// can never render in toxee: `buildToxeeMessageAttachmentConfig()` pins
/// `enableSendImage` / `enableSendVideo` / `enableSendFile` / `enableSearch` to
/// false (lib/ui/home/mobile_attachment_policy.dart), and toxee's own
/// `_buildDesktopInputOptions` (lib/ui/home_page.dart:985-1003) builds exactly
/// `Icons.attach_file` — plus `Icons.qr_code_2` in a C2C — because the desktop
/// File picker is `FileType.any` and already covers photos and videos.
///
/// WHAT IS ASSERTED — a GATING PAIR over ONE data-driven generator. Every icon
/// in `_generateBarIcons` goes through the SAME switch, so:
///   * POSITIVE leg: `message_attachment_file_button` AND
///     `message_attachment_personal_card_button` both mount. That proves the
///     toolbar rendered, that this is a C2C conversation (the personal card is
///     C2C-only), and that the icon->key switch is alive — without it the four
///     absences below would be indistinguishable from "no composer at all".
///   * NEGATIVE leg: none of the four disabled entries resolves.
/// A regression that re-enabled the media entries (or that changed the icon
/// constants the switch matches on) reds this immediately.
///
/// SKIP on the MOBILE composer — a live probe, not a platform name, because a
/// narrowed desktop window keeps the desktop builder. The mobile surface has no
/// inline toolbar at all; its own coverage is `mobile_attachment_panel_entries`.
///
/// Nothing is tapped, so no picker opens and no state changes.
Future<bool?> _kg4AttachmentToolbarGating(Inst a, String toxB) async {
  const label = 'attachment_toolbar_disabled_entries_gating';
  const disabled = <String>[
    'message_attachment_image_button',
    'message_attachment_photo_button',
    'message_attachment_video_button',
    'message_attachment_search_button',
  ];
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] $label: A could not open the C2C chat');
    return false;
  }
  switch (await _kg4ComposerKind(a)) {
    case _Kg4Composer.mobile:
      print(
        '[pair] $label: SKIP — the MOBILE composer is mounted. It renders no '
        'inline attachment toolbar (one "+" overlay opener instead), so the '
        'four desktop-only keys have no surface to be absent FROM and the '
        'gating pair is meaningless here. mobile_attachment_panel_entries '
        'covers this shell.',
      );
      return null;
    case _Kg4Composer.unknown:
      await a.shot('/tmp/ui_kg4_toolbar_nocomposer_${a.name}.png');
      print(
        '[pair] $label: neither composer anchor resolved — no composer '
        'rendered in the open chat at all',
      );
      return false;
    case _Kg4Composer.desktop:
      break;
  }

  final fileUp = await a.waitKeyCenter(
    'message_attachment_file_button',
    timeoutSecs: 6,
  );
  final cardUp = await a.waitKeyCenter(
    'message_attachment_personal_card_button',
    timeoutSecs: 6,
  );
  final present = <String>[];
  for (final key in disabled) {
    if (await a.waitKeyCenter(key, timeoutSecs: 2)) present.add(key);
  }
  await a.shot('/tmp/ui_kg4_toolbar_${a.name}.png');
  print(
    '[pair] $label: fileEntry=$fileUp personalCardEntry=$cardUp '
    'disabledEntriesPresent=${present.isEmpty ? '<none>' : present.join(',')}',
  );
  if (!fileUp || !cardUp) {
    print(
      '[pair] $label: FAIL — the POSITIVE leg is missing. Without a proven-up '
      'toolbar the four absences assert nothing, so this is a fail rather than '
      'a pass-by-absence.',
    );
    return false;
  }
  if (present.isNotEmpty) {
    print(
      '[pair] $label: FAIL — a disabled attachment entry rendered. Either '
      'buildToxeeMessageAttachmentConfig() stopped pinning the send flags to '
      'false, or _buildDesktopInputOptions started injecting an icon the '
      'fork\'s switch maps to one of these keys.',
    );
  }
  return present.isEmpty;
}

// ===========================================================================
// case — mobile_attachment_panel_entries
// ===========================================================================
/// The MOBILE composer's attachment surface: the "+" opener
/// (`message_attachment_options_button`) and the two entries toxee injects into
/// the overlay it opens (`message_attachment_file_button`,
/// `message_attachment_camera_button`).
///
/// ALL THREE KEYS ARE NEW TO THIS BATCH at the widget level. `ui_keys.dart`
/// declared and documented them — including the claim that
/// `_buildInputAreaIcon` "now takes an optional `iconKey`" and that the panel
/// "derives these keys from the option's IconData" — but the fork attached
/// NEITHER, so the whole mobile attachment surface was unreachable by key. Both
/// attachments are additive (an optional parameter that defaults to null; a
/// derived key that returns null for any unmapped icon).
///
/// WHAT IS ASSERTED. The overlay is an `OverlayEntry` that only exists between
/// `toggleAttachmentOptionsOverlay` and `_removeEntry`, so its contents
/// MOUNTING and then UNMOUNTING is a real state transition, not a static probe:
///   1. the "+" opener resolves on the mobile composer;
///   2. after the real tap, BOTH data-driven entries mount — which also proves
///      `additionalAttachmentOptionsForMobile` still returns exactly the File +
///      Camera pair (`buildToxeeMobileAttachmentOptions`);
///   3. after dismissing, both entries leave the tree again.
/// The entries themselves are deliberately NOT tapped: File opens the OS file
/// picker and Camera the OS camera sheet — the same native boundary
/// `rui-native-boundary-guards` documents — and neither has an L3
/// path-injection equivalent on a device.
///
/// SKIP on the desktop composer (live probe, see `_kg4ComposerKind`).
Future<bool?> _kg4MobileAttachmentPanel(Inst a, String toxB) async {
  const label = 'mobile_attachment_panel_entries';
  const opener = 'message_attachment_options_button';
  const fileEntry = 'message_attachment_file_button';
  const cameraEntry = 'message_attachment_camera_button';
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] $label: A could not open the C2C chat');
    return false;
  }
  switch (await _kg4ComposerKind(a)) {
    case _Kg4Composer.desktop:
      print(
        '[pair] $label: SKIP — the DESKTOP composer is mounted. Its attachment '
        'entries are an inline toolbar, not a "+"-triggered overlay; '
        'attachment_toolbar_disabled_entries_gating covers that surface.',
      );
      return null;
    case _Kg4Composer.unknown:
      await a.shot('/tmp/ui_kg4_panel_nocomposer_${a.name}.png');
      print('[pair] $label: no composer rendered in the open chat');
      return false;
    case _Kg4Composer.mobile:
      break;
  }

  // Entries must be absent BEFORE the tap, otherwise "they mounted" could be a
  // leftover overlay from an earlier case.
  final fileBefore = await a.keyCenter(fileEntry) != null;
  final cameraBefore = await a.keyCenter(cameraEntry) != null;
  if (fileBefore || cameraBefore) {
    await a.tapKeyCenter(opener, timeoutSecs: 6);
    await _kg4WaitKeyCenterGone(a, fileEntry);
  }
  if (!await a.tapKeyCenter(opener, timeoutSecs: 8)) {
    print('[pair] $label: the "+" attachment opener could not be tapped');
    return false;
  }
  final fileUp = await a.waitKeyCenter(fileEntry, timeoutSecs: 8);
  final cameraUp = await a.waitKeyCenter(cameraEntry, timeoutSecs: 6);
  await a.shot('/tmp/ui_kg4_panel_open_${a.name}.png');

  // Dismiss WITHOUT choosing an entry. The overlay's outer GestureDetector is a
  // full-screen barrier whose onTap calls `_removeEntry`, so a tap anywhere
  // outside the panel closes it; the opener's own centre is under that barrier,
  // which makes it a stable coordinate to aim at.
  await a.tapKeyCenter(opener, timeoutSecs: 6);
  final fileGone = await _kg4WaitKeyCenterGone(a, fileEntry, timeoutSecs: 10);
  final cameraGone = await _kg4WaitKeyCenterGone(
    a,
    cameraEntry,
    timeoutSecs: 10,
  );
  print(
    '[pair] $label: fileMounted=$fileUp cameraMounted=$cameraUp '
    'fileGone=$fileGone cameraGone=$cameraGone',
  );
  return fileUp && cameraUp && fileGone && cameraGone;
}

// ===========================================================================
// case — message_viewer_save_and_zoom_surface
// ===========================================================================
/// The fullscreen media viewer's two never-driven keys:
/// `message_viewer_zoom_<msgID>` (the `InteractiveViewer` wrapping the image)
/// and `message_viewer_save_button` (the "save to local" action).
///
/// WHY THE ZOOM KEY IS THE INTERESTING ONE. It is the only key in the viewer
/// that carries the MESSAGE IDENTITY — `message_viewer_root` merely says "a
/// viewer is up". Asserting `message_viewer_zoom_<id>` for the exact id the
/// case seeded proves the viewer bound the RIGHT message, which a
/// swipe/paging regression (the viewer is a Swiper over the whole media
/// history) would break while `message_viewer_root` stayed happily mounted.
///
/// WHAT IS ASSERTED:
///   1. `message_viewer_zoom_<seededId>` resolves while the viewer is up;
///   2. `message_viewer_save_button` mounts — its `if (saveableMediaSource !=
///      null)` gate resolves the image elem's local path, so a received image
///      that produced no on-disk file would fail here. That is a real product
///      assertion, not a harness detail;
///   3. closing the viewer UNMOUNTS both keys along with the root.
///
/// THE SAVE TAP IS DELIBERATELY NOT DRIVEN. `saveMedia` writes to the OS photo
/// library / Downloads directory and, on desktop, raises a native save affordance
/// — an out-of-app side effect with nothing observable left inside the app, the
/// same boundary `msgmenu_reveal_file_location_gating` stops at.
///
/// NEVER SKIPS. A viewer that will not open is a FAIL — see the failure
/// message below for why "flaky gesture" was not an acceptable diagnosis.
///
/// HOW THE BUBBLE IS TAPPED (root-caused 2026-08-16). The tap target is the
/// fork's keyed `message_image_bubble:<msgID>` GestureDetector, resolved through
/// `ui_key_center` (the ELEMENT-TREE walk) and hit with ONE `tapAt` at its
/// centre. The previous version aimed at fractions of the ROW's width taken from
/// `_p1cKeyBounds`, i.e. from flutter_skill's `interactiveStructured` — which
/// only reports widgets whose type is in its interactive allow-list (Button /
/// TextField / InkWell / GestureDetector / ListTile / ...). `message_list_item:`
/// sits on `TencentCloudChatMessageItemContainer`, a plain StatefulWidget, so
/// that lookup returned NULL on every attempt and the "6 bounded retry taps"
/// dispatched ZERO taps — a deterministic red on iPhone AND iPad that read like
/// a flaky gesture. (The fork's 300 ms `onTapUp` guard was NOT the cause:
/// flutter_skill's `_dispatchTap` is a 50 ms down->up, and its `onTapDownTime >
/// 0` clause makes even a dropped down harmless.) The row-fraction ladder is
/// kept as a FALLBACK, now fed by `_keyBox`/`ui_key_center` and corrected from
/// centre-relative to left-edge-relative, for builds without the bubble key.
Future<bool?> _kg4ViewerSaveAndZoom(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  const label = 'message_viewer_save_and_zoom_surface';
  // 1x1 PNG, the same seed `_p1cImagePreviewOpenHardened` uses.
  // A 2x2 8-bit RGBA PNG that Flutter's codec ACTUALLY decodes, pinned by
  // test/mcp/real_ui_image_seed_decodes_test.dart.
  //
  // The previous seed (a 1x1 8-bit GRAY+ALPHA PNG) was accepted by `file(1)` as
  // "PNG image data, 1 x 1" but `ui.instantiateImageCodec` rejected it outright
  // ("Codec failed to produce an image, possibly due to invalid image data").
  // The product was right to render the decode-error placeholder; the FIXTURE
  // was broken — and because that placeholder is an InkWell that wins the
  // gesture arena over the image's GestureDetector, the bubble became
  // untappable and this case read as a viewer/gesture bug for four device
  // shifts across iOS and Android. Never seed an image the hermetic test has
  // not decoded.
  const pngB64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR42mP4z8AAQv8ZYAwAQ84H'
      '+SUC+b4AAAAASUVORK5CYII=';
  final nonce = DateTime.now().microsecondsSinceEpoch % 100000;
  final fileName = 'ruikg4$nonce.png';

  final bMarked = await b.markAccountTest();
  Map<String, dynamic> sent;
  try {
    sent = await b.l3('l3_send_file', {
      'userId': toxA,
      'contentB64': pngB64,
      'fileName': fileName,
    });
  } finally {
    await _kg3Unmark(b, bMarked);
  }
  if (sent['ok'] != true) {
    print('[pair] $label: l3_send_file (B->A) failed: $sent');
    return false;
  }
  String imageMsgId = '';
  for (var i = 0; i < 60 && imageMsgId.isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    for (final m in await _c2cMessages(a, toxB)) {
      if (m['isSelf'] == false &&
          m['mediaKind']?.toString() == 'image' &&
          (m['fileName']?.toString() ?? '').contains(fileName)) {
        imageMsgId = m['msgID']?.toString() ?? '';
      }
    }
  }
  if (imageMsgId.isEmpty) {
    await a.shot('/tmp/ui_kg4_viewer_noimg_${a.name}.png');
    print('[pair] $label: the seeded image never reached A (name=$fileName)');
    return false;
  }
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] $label: A could not open the C2C chat');
    return false;
  }
  final rowKey = 'message_list_item:$imageMsgId';
  if (!await a.waitKey(rowKey, timeoutSecs: 12)) {
    await a.shot('/tmp/ui_kg4_viewer_norow_${a.name}.png');
    print('[pair] $label: the image bubble row never rendered');
    return false;
  }
  // The tappable GestureDetector mounts only once the image decode resolves.
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  // DIAGNOSIS, printed once: which resolver can even SEE the row. `structured`
  // is flutter_skill's interactiveStructured (null for a non-interactive keyed
  // widget — that was the whole bug); `keyBox` is the element-tree walk;
  // `bubble` is the fork's keyed tap target, whose presence also means the image
  // decoded. Keep this line — it is what turns a future red into an answer.
  final bubbleKey = 'message_image_bubble:$imageMsgId';
  print(
    '[pair] $label: row/bubble resolution '
    'structured=${await _p1cKeyBounds(a, rowKey)} '
    'keyBox=${await _keyBox(a, rowKey)} '
    'bubble=${await _keyBox(a, bubbleKey)} '
    'render=${await _kg4ImageRenderState(a, imageMsgId)}',
  );
  var viewerUp = false;
  // Attempt 0 is the exact tap target; the rest are the legacy row-fraction
  // ladder, now computed from the row's LEFT edge (`_keyBox` reports a CENTRE,
  // unlike interactiveStructured's top-left) for builds without the bubble key.
  const fractions = <double>[0.18, 0.28, 0.40, 0.50, 0.22, 0.33];
  for (var attempt = 0; attempt <= fractions.length && !viewerUp; attempt++) {
    if (attempt == 0) {
      if (!await a.tapKeyAt(bubbleKey)) continue;
    } else {
      final box = await _keyBox(a, rowKey);
      if (box == null || box.w <= 0) {
        await _ensureChatOpen(a, toxB);
        await a.waitKey(rowKey, timeoutSecs: 4);
        continue;
      }
      await a.tapAt(
        box.x - box.w / 2 + box.w * fractions[attempt - 1],
        box.y,
      );
    }
    viewerUp = await a.waitKey('message_viewer_root', timeoutSecs: 3);
    if (!viewerUp) {
      await Future<void>.delayed(Duration(milliseconds: 500 + attempt * 300));
    }
  }
  if (!viewerUp) {
    await a.shot('/tmp/ui_kg4_viewer_noopen_${a.name}.png');
    // The bubble's tap target only mounts once the image DECODES, so a bubble
    // stuck on the error placeholder is untappable no matter how the gesture is
    // aimed — and that is a PRODUCT state, not a gesture problem. Re-read the
    // message's `filePath` (the received-side local path, set once the transfer
    // completes) so the log says which of the two it is: an absent/unreadable
    // path is the decode failure, a good path means the gesture really missed.
    // Live on Android 2026-08-16 the screenshot showed the red error badge.
    var filePath = '<not-found>';
    for (final m in await _c2cMessages(a, toxB)) {
      if (m['msgID']?.toString() == imageMsgId) {
        filePath = m['filePath']?.toString() ?? '<null>';
      }
    }
    final render = await _kg4ImageRenderState(a, imageMsgId);
    // Is the widget even decoding the file the harness verified? The fork keys
    // the render wrapper with the PATH it hands to `Image.file`, so this one
    // probe separates "the file is undecodable" from "the widget is holding a
    // STALE path" (the receive-side temp file, deleted after the transfer moved
    // it) — two bugs in two different layers.
    final rendersFinalPath =
        await a.keyCenter('message_image_render_path:$filePath') != null;
    // iOS/macOS run the app on THIS host, so the driver can read the very file
    // the widget is trying to decode. That closes the last ambiguity: a valid
    // file plus an `error` render state is a PRODUCT decode bug, full stop.
    var onDisk = '<host-unreadable>';
    if (filePath.startsWith('/')) {
      final f = File(filePath);
      onDisk = f.existsSync() ? '${f.lengthSync()}B' : 'MISSING';
    }
    await returnToChatsHome(a, rounds: 4);
    print(
      '[pair] $label: seeded image filePath="$filePath" onDisk=$onDisk '
      'render=$render rendersFinalPath=$rendersFinalPath',
    );
    print(
      '[pair] $label: FAIL — the image bubble could not be opened by a tap at '
      'the keyed `$bubbleKey` target nor after ${fractions.length} bounded '
      'retry taps across the row\'s width. READ `render=` ABOVE FIRST: '
      '`error` means the bubble is showing the DECODE-FAILURE placeholder, '
      'whose InkWell wins the gesture arena over the image GestureDetector — '
      'the bubble is then untappable BY CONSTRUCTION and no tap timing or '
      'position can help; that is a product decode bug (see the fork\'s '
      'bounded evict-and-retry in tencent_cloud_chat_message_image.dart), '
      'especially when onDisk shows a real byte count. `loading` means the '
      'decode never resolved. `image` means the tap target really was mounted '
      'and the gesture or the viewer route is at fault. This case never SKIPs: '
      'a skip would be indistinguishable from the viewer being genuinely '
      'unopenable, which is exactly the regression it exists to catch. The '
      'SEEDING half passing only proves the inbound image path, not this one.',
    );
    return false;
  }

  final zoomKey = 'message_viewer_zoom_$imageMsgId';
  final zoomUp = await a.waitKeyCenter(zoomKey, timeoutSecs: 8);
  final saveUp = await a.waitKeyCenter(
    'message_viewer_save_button',
    timeoutSecs: 8,
  );
  await a.shot('/tmp/ui_kg4_viewer_${a.name}.png');
  print(
    '[pair] $label: save tap NOT driven by design — `saveMedia` writes to the '
    'OS photo library / Downloads and leaves no in-app observable. Asserting '
    'the render + identity gates only.',
  );

  var closed = false;
  if (await a.tapKeyCenter('message_viewer_root', timeoutSecs: 4)) {
    closed = await a.waitKeyGone('message_viewer_root', timeoutSecs: 6);
  }
  if (!closed) {
    try {
      await a.osaEscape();
    } on DriveError {
      // best-effort; the assertions below read the real state either way.
    }
    closed = await a.waitKeyGone('message_viewer_root', timeoutSecs: 6);
  }
  final zoomGone = await _kg4WaitKeyCenterGone(a, zoomKey, timeoutSecs: 10);
  final saveGone = await _kg4WaitKeyCenterGone(
    a,
    'message_viewer_save_button',
    timeoutSecs: 10,
  );
  await returnToChatsHome(a, rounds: 4);

  print(
    '[pair] $label: msgId=$imageMsgId zoomBound=$zoomUp saveMounted=$saveUp '
    'viewerClosed=$closed zoomGone=$zoomGone saveGone=$saveGone',
  );
  if (!saveUp) {
    print(
      '[pair] $label: the save action did not render, which means '
      '`_currentSaveableMediaSource()` found no existing local path and no '
      'remote URL for a RECEIVED image — a product gap in how the tox file '
      'transfer lands the image elem, not a harness limitation.',
    );
  }
  return zoomUp && saveUp && closed && zoomGone && saveGone;
}

/// Which of the image bubble's three states is on screen for [msgId]:
/// `image` (the tappable GestureDetector), `error` (the decode-failure
/// placeholder — an InkWell that WINS the arena over that GestureDetector, so
/// the bubble is untappable), `loading`, or `absent`.
///
/// The two placeholders share the image's geometry, so a bounds probe cannot
/// tell them apart; these fork-side keys can. Without them a red here could
/// only say "the viewer did not open".
Future<String> _kg4ImageRenderState(Inst inst, String msgId) async {
  if (await inst.keyCenter('message_image_error:$msgId') != null) return 'error';
  if (await inst.keyCenter('message_image_loading:$msgId') != null) {
    return 'loading';
  }
  if (await inst.keyCenter('message_image_bubble:$msgId') != null) {
    return 'image';
  }
  return 'absent';
}
