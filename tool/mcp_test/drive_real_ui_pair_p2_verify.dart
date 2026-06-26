// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

const _p2VerifyCases = {'paste_image_into_composer'};

bool _isP2VerifyCaseScenario(String scenario) =>
    _p2VerifyCases.contains(scenario);

Future<int> runP2VerifyCase(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  String scenario, {
  required bool bootRestored,
}) async {
  if (!bootRestored) {
    await ensureHome(a, nickA);
    await ensureHome(b, nickB, requireHomeMenu: false);
  }
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for $scenario: A=$toxA B=$toxB');
  }
  if (!await areFriends(a, toxB) || !await areFriends(b, toxA)) {
    final friended = await _establishFriendshipForSweep(
      a,
      b,
      toxA,
      toxB,
      nickA,
      nickB,
    );
    if (!friended) return 1;
  }

  final ok = switch (scenario) {
    'paste_image_into_composer' => await _p2vPasteImageIntoComposer(
      a,
      b,
      toxA,
      toxB,
    ),
    _ => throw ArgumentError('unsupported P2 verify case: $scenario'),
  };
  print('[pair] ${ok ? 'PASS' : 'FAIL'}: $scenario');
  return ok ? 0 : 1;
}

Future<int> runP2VerifySweep(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for sweep_p2_verify: A=$toxA B=$toxB');
  }
  final friended = await _establishFriendshipForSweep(
    a,
    b,
    toxA,
    toxB,
    nickA,
    nickB,
  );
  if (!friended) return 1;

  var passed = 0;
  var failed = 0;
  const skipped = 0;
  // Windows now stages the image through the production paste handler via the
  // l3_paste_image fork hook (the OS clipboard + Ctrl+V remain undrivable
  // headless, but the same sendImageOnDesktop path runs), so the case is no
  // longer skipped — it runs on both platforms.
  try {
    final ok = await _p2vPasteImageIntoComposer(a, b, toxA, toxB);
    if (ok) {
      passed++;
    } else {
      failed++;
    }
    print(
      '[sweep] sweep_p2_verify ${ok ? 'PASS' : 'FAIL'}: '
      'paste_image_into_composer',
    );
  } on Object catch (e, st) {
    failed++;
    print('[sweep] sweep_p2_verify EXCEPTION in paste_image_into_composer: $e');
    print(st);
  }

  print('[sweep] sweep_p2_verify summary: passed=$passed failed=$failed '
      'skipped=$skipped');
  await returnToChatsHome(a, rounds: 4);
  await returnToChatsHome(b, rounds: 4);
  return failed == 0 ? 0 : 1;
}

/// P2#6 — put a real PNG image on the macOS clipboard, focus the real desktop
/// composer, drive Cmd+V through the production RawKeyEvent paste handler, and
/// confirm the real desktop image-send popup.
Future<bool> _p2vPasteImageIntoComposer(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  if (!Platform.isMacOS && !_isWindowsRealUi) {
    print('[pair] paste_image_into_composer: macOS/Windows clipboard seeding only');
    return false;
  }
  if (!await _ensureChatOpen(a, toxB)) {
    return false;
  }
  // Re-bind currentConversation + the right-pane composer userID via the
  // production _openChat (l3_open_chat) before the paste: a row-tap open can
  // leave currentConversation null (logged "currentConversation=null"), so the
  // desktop paste handler's send fires against an unbound peer and no image
  // message is created. The asserted action stays the real Cmd+V + confirm tap.
  // The pasted image is sent as a FILE transfer — wait for B ONLINE (not just
  // friend-added) FIRST so the offer actually delivers. Then a SINGLE production
  // _openChat bind right before the paste: the fork desktop paste handler reads
  // the composer's userID, and a single settle-and-bind keeps the Cmd+V composer
  // focus/state intact (the multi-retry _ensureBoundChat used for the toxee
  // attachment path rebuilds the right pane repeatedly and disrupts the paste
  // composer — observed: "sender image not in dump").
  if (!await _waitFriendOnline(a, toxB, timeoutSecs: 60)) {
    print('[pair] paste_image_into_composer: WARN B not online before paste');
  }
  await a.openChatViaL3(userId: _pubkey(toxB));
  await Future<void>.delayed(const Duration(milliseconds: 600));

  final beforeIds = {
    for (final m in await _c2cMessages(a, toxB)) _p2kMessageId(m),
  }..removeWhere((id) => id.isEmpty);
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final png = File('${Directory.systemTemp.path}/rui_paste_$nonce.png');
  // An 8x8 8-bit RGBA PNG. The previous 1x1 8-bit GRAY+alpha PNG could not be
  // round-tripped by macOS `NSImage.tiffRepresentation` (returns nil), so
  // `Pasteboard.image` came back null and the desktop paste handler silently
  // no-op'd — the image-confirm popup never appeared. A non-degenerate RGBA PNG
  // re-encodes cleanly (verified: tiffRepresentation -> 173 png bytes), so the
  // paste path runs and stages the image. The desktop paste feature itself was
  // never broken; the fixture image was un-encodable.
  const pngB64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAICAYAAADED76LAAAAEklEQVR42mO4Y2PzHx9m'
      'GBkKAKtclMHCQrgUAAAAAElFTkSuQmCC';
  await png.writeAsBytes(base64Decode(pngB64), flush: true);

  try {
    if (_isWindowsRealUi) {
      // Headless Windows: the OS clipboard + Ctrl+V aren't drivable (the
      // driver's clipboard lives in a different window-station, invisible to the
      // app). Stage the SAME image through the production paste handler via
      // l3_paste_image, which writes it to a paste_image_<nonce>.png temp and
      // calls sendImageOnDesktop — landing on the same confirm popup as a real
      // Ctrl+V paste.
      final r = await a.l3('l3_paste_image', {
        'contentB64': base64Encode(await png.readAsBytes()),
      });
      if (r['ok'] != true) {
        print('[pair] paste_image_into_composer: l3_paste_image failed: $r');
        return false;
      }
    } else {
      if (!await _p2vSetClipboardImage(png)) {
        print(
            '[pair] paste_image_into_composer: failed to seed image clipboard');
        return false;
      }
      await a.foreground();
      if (!await a.tapKeyCenter('chat_input_text_field', timeoutSecs: 8)) {
        print('[pair] paste_image_into_composer: composer key not tappable');
        return false;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await a._osa(
        'tell application "System Events" to keystroke "v" using command down',
      );
    }

    if (!await a.waitKey(
      'desktop_send_image_confirm_button',
      timeoutSecs: 10,
    )) {
      await a.shot('/tmp/p2_verify_paste_no_confirm_${a.name}.png');
      print('[pair] paste_image_into_composer: image confirm popup missing');
      return false;
    }
    if (!await a.tapKeyCenter(
      'desktop_send_image_confirm_button',
      timeoutSecs: 6,
    )) {
      print('[pair] paste_image_into_composer: confirm button not tappable');
      return false;
    }

    // The pasted-image record carries its name as `paste_image_<appNonce>.png`.
    // Match on `fileName` OR the `filePath` basename: the SENDER-side history
    // record stores the name ONLY under `filePath` (app-temp source path) with
    // `fileName` null, while the RECEIVER record exposes it under `fileName`.
    // Mirrors the attachment-path fix (694e130) — verified live: the send always
    // worked; the prior assertion only ever checked the (null) `fileName`.
    String pastedName(Map<String, dynamic> m) {
      final nameField = m['fileName']?.toString() ?? '';
      if (nameField.startsWith('paste_image_') && nameField.endsWith('.png')) {
        return nameField;
      }
      final fp = m['filePath']?.toString() ?? '';
      final base = fp.isEmpty ? '' : fp.split('/').last;
      if (base.startsWith('paste_image_') && base.endsWith('.png')) return base;
      return '';
    }

    final sent = await _p2kWaitC2cMessageWhere(a, toxB, (m) {
      final id = _p2kMessageId(m);
      return !beforeIds.contains(id) &&
          m['isSelf'] == true &&
          m['mediaKind']?.toString() == 'image' &&
          pastedName(m).isNotEmpty;
    }, timeoutSecs: 30);
    final sentId = _p2kMessageId(sent);
    final fileName = sent == null ? '' : pastedName(sent);
    if (sent == null || sentId.isEmpty || fileName.isEmpty) {
      // DIAGNOSTIC: dump A's recent c2c messages so we can tell whether the send
      // (a) never happened (bind-null no-op) or (b) happened but the record
      // stores the image name under a different field/pattern (filePath vs
      // fileName), mirroring the attachment-path discovery in 694e130.
      final all = await _c2cMessages(a, toxB);
      final tail = all.length > 6 ? all.sublist(all.length - 6) : all;
      for (final m in tail) {
        print(
          '[pair] paste_image DIAG msg: id=${_p2kMessageId(m)} '
          'isSelf=${m['isSelf']} mediaKind=${m['mediaKind']} '
          'fileName=${m['fileName']} filePath=${m['filePath']} '
          'elemType=${m['elemType']} text=${m['text']}',
        );
      }
      print('[pair] paste_image_into_composer: sender image not in dump '
          '(count=${all.length})');
      return false;
    }
    final row = await a.waitKey('message_list_item:$sentId', timeoutSecs: 8);
    // Receiver match: same `paste_image_<nonce>.png` across either field (the
    // sender's app-chosen basename is what the file offer carries to B).
    final received = await _p2kWaitC2cMessageWhere(
      b,
      toxA,
      (m) {
        if (m['isSelf'] != false) return false;
        if (m['mediaKind']?.toString() != 'image') return false;
        final nameField = m['fileName']?.toString() ?? '';
        final fp = m['filePath']?.toString() ?? '';
        final base = fp.isEmpty ? '' : fp.split('/').last;
        return nameField == fileName || base == fileName;
      },
      timeoutSecs: 60,
    );
    print(
      '[pair] paste_image_into_composer: sentId=$sentId fileName=$fileName '
      'row=$row received=${received != null}',
    );
    return row && received != null;
  } finally {
    if (await png.exists()) {
      await png.delete();
    }
  }
}

Future<bool> _p2vSetClipboardImage(File png) async {
  final script =
      'set the clipboard to (read POSIX file "${_p2vAppleScriptLiteral(png.path)}" '
      'as «class PNGf»)';
  final result = await Process.run('osascript', ['-e', script]);
  if (result.exitCode != 0) {
    print(
      '[pair] paste_image_into_composer: osascript image clipboard failed '
      'exit=${result.exitCode} stderr=${result.stderr}',
    );
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 150));
  return true;
}

String _p2vAppleScriptLiteral(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
