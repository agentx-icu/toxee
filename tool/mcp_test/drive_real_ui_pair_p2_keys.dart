// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

const _p2kCases = {
  'sticker_face_cell_send',
  'new_messages_chip_tap',
  'presence_dot_relaunch',
};

bool _isP2KeysCaseScenario(String scenario) => _p2kCases.contains(scenario);

Future<int> runP2KeysCase(
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
    'sticker_face_cell_send' => await _p2kStickerFaceCellSend(a, b, toxA, toxB),
    'new_messages_chip_tap' => await _p2kNewMessagesChipTap(a, b, toxA, toxB),
    'presence_dot_relaunch' => await _p2kPresenceDotRelaunch(a, b, toxB, nickB),
    _ => throw ArgumentError('unsupported P2 keys case: $scenario'),
  };
  print('[pair] ${ok ? 'PASS' : 'FAIL'}: $scenario');
  return ok ? 0 : 1;
}

Future<int> runP2KeysSweep(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for sweep_p2_keys: A=$toxA B=$toxB');
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
  Future<void> hard(String id, Future<bool> Function() run) async {
    try {
      final ok = await run();
      if (ok) {
        passed++;
      } else {
        failed++;
      }
      print('[sweep] sweep_p2_keys ${ok ? 'PASS' : 'FAIL'}: $id');
    } on Object catch (e, st) {
      failed++;
      print('[sweep] sweep_p2_keys EXCEPTION in $id: $e');
      print(st);
    }
  }

  await hard(
    'sticker_face_cell_send',
    () => _p2kStickerFaceCellSend(a, b, toxA, toxB),
  );
  await hard(
    'new_messages_chip_tap',
    () => _p2kNewMessagesChipTap(a, b, toxA, toxB),
  );
  await hard(
    'presence_dot_relaunch',
    () => _p2kPresenceDotRelaunch(a, b, toxB, nickB),
  );

  print('[sweep] sweep_p2_keys summary: passed=$passed failed=$failed');
  return failed == 0 ? 0 : 1;
}

Future<bool> _p2kStickerFaceCellSend(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] sticker_face_cell_send: A chat did not open');
    return false;
  }
  final before = await _p2kRenderMessageIds(a, toxB);

  await a.foreground();
  if (!await _p2kTapKey(a, 'sticker_panel_button')) {
    print('[pair] sticker_face_cell_send: sticker panel button absent');
    return false;
  }
  // The desktop sticker PANEL container carries no ValueKey in the fork, so the
  // panel-open proof is the first keyed FACE TAB mounting (a `sticker_face_tab:*`
  // only exists inside the open panel — `tencent_cloud_chat_sticker_widget.dart`).
  // (An earlier draft gated on a phantom `desktop_sticker_panel` key that was
  // never added to the fork — codex-review catch.) `_p2kTapFirstAvailableFaceTab`
  // both proves the panel opened AND selects a real face pack.
  final facePack = await _p2kTapFirstAvailableFaceTab(a);
  if (facePack == null) {
    print('[pair] sticker_face_cell_send: panel did not open / '
        'no keyed face sticker tab mounted');
    return false;
  }
  final faceCellKey = 'sticker_face_cell:$facePack:0';
  if (!await a.waitKey(faceCellKey, timeoutSecs: 6)) {
    print('[pair] sticker_face_cell_send: face cell $faceCellKey absent');
    return false;
  }
  if (!await _p2kTapKey(a, faceCellKey)) {
    print('[pair] sticker_face_cell_send: tap $faceCellKey failed');
    return false;
  }

  final faceRender = await _p2kWaitRenderMessageWhere(
    a,
    toxB,
    (m) => m['isSelf'] == true && m['elemType'] == 8,
    excludeIds: before,
    timeoutSecs: 20,
  );
  final faceId = _p2kMessageId(faceRender);
  final aRowRendered =
      faceId.isNotEmpty &&
      await a.waitKey('message_list_item:$faceId', timeoutSecs: 8);
  final bWire = await _p2kWaitC2cMessageWhere(
    b,
    toxA,
    (m) =>
        m['isSelf'] == false &&
        (m['text']?.toString().startsWith('__face__:') ?? false),
    timeoutSecs: 45,
  );
  print(
    '[pair] sticker_face_cell_send: facePack=$facePack faceId=$faceId '
    'aRowRendered=$aRowRendered bWire=${bWire != null}',
  );
  return faceRender != null && aRowRendered && bWire != null;
}

Future<bool> _p2kNewMessagesChipTap(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  final seeded = await _seedChatHistory(a, b, toxA, toxB);
  final earliestId = seeded?.earliestId ?? '';
  if (earliestId.isEmpty) {
    print('[pair] new_messages_chip_tap: earliest history id unresolved');
    return false;
  }

  await returnToChatsHome(a, rounds: 4);
  await _ensureChatOpen(a, toxB);
  final earliestRowKey = 'message_list_item:$earliestId';
  var scrolledUp = await a.waitKey(earliestRowKey, timeoutSecs: 1);
  for (var i = 0; i < 24 && !scrolledUp; i++) {
    try {
      await a.scrollAtCoords(640, 330, dy: -600);
    } on DriveError {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    scrolledUp = await a.waitKey(earliestRowKey, timeoutSecs: 1);
  }
  if (!scrolledUp) {
    print('[pair] new_messages_chip_tap: could not hold an older row onscreen');
    return false;
  }

  final nonce = DateTime.now().microsecondsSinceEpoch;
  final inbound = 'RUIP2CHIP-$nonce';
  await b.foreground();
  await openChat(b, toxA);
  if (!await sendComposerMessage(b, inbound)) {
    print('[pair] new_messages_chip_tap: B failed to send inbound');
    return false;
  }

  final inboundMessage = await _p2kWaitC2cMessageWhere(
    a,
    toxB,
    (m) => m['isSelf'] == false && m['text']?.toString() == inbound,
    timeoutSecs: 60,
  );
  final inboundId = _p2kMessageId(inboundMessage);
  await a.foreground();
  final chipShown = await a.waitKey('new_messages_chip', timeoutSecs: 12);
  final chipTapped = chipShown && await _p2kTapKey(a, 'new_messages_chip');
  final inboundRowRendered =
      inboundId.isNotEmpty &&
      await a.waitKey('message_list_item:$inboundId', timeoutSecs: 10);
  final activeAfter = await _currentConversationId(a);
  final stayedInChat = activeAfter == _c2cConvId(toxB);
  print(
    '[pair] new_messages_chip_tap: scrolledUp=$scrolledUp '
    'inboundId=$inboundId chipShown=$chipShown chipTapped=$chipTapped '
    'inboundRowRendered=$inboundRowRendered stayedInChat=$stayedInChat',
  );
  return inboundMessage != null &&
      chipShown &&
      chipTapped &&
      inboundRowRendered &&
      stayedInChat;
}

Future<bool> _p2kPresenceDotRelaunch(
  Inst a,
  Inst b,
  String toxB,
  String nickB,
) async {
  final convId = _c2cConvId(toxB);
  if (!await _seedConvRow(a, toxB)) {
    print('[pair] presence_dot_relaunch: could not seed A conversation row');
    return false;
  }
  await returnToChatsHome(a, rounds: 4);
  final onlineBeforeData = await _p2kWaitFriendOnline(a, toxB, true);
  final onlineBeforeKey = await a.waitKey(
    'conversation_item_online_dot:$convId:online',
    timeoutSecs: 8,
  );

  var stopped = false;
  var relaunched = false;
  try {
    await _p1rStopInstanceOnly(b);
    stopped = true;
    final offlineData = await _p2kWaitFriendOnline(a, toxB, false);
    await returnToChatsHome(a, rounds: 2);
    final offlineKey = await a.waitKey(
      'conversation_item_online_dot:$convId:offline',
      timeoutSecs: 20,
    );

    await _p1rLaunchStoppedInstance(b, expectedToxId: toxB, nick: nickB);
    relaunched = true;
    final onlineAfterData = await _p2kWaitFriendOnline(a, toxB, true);
    await returnToChatsHome(a, rounds: 2);
    final onlineAfterKey = await a.waitKey(
      'conversation_item_online_dot:$convId:online',
      timeoutSecs: 20,
    );
    print(
      '[pair] presence_dot_relaunch: beforeData=$onlineBeforeData '
      'beforeKey=$onlineBeforeKey offlineData=$offlineData '
      'offlineKey=$offlineKey onlineAfterData=$onlineAfterData '
      'onlineAfterKey=$onlineAfterKey',
    );
    return onlineBeforeData &&
        onlineBeforeKey &&
        offlineData &&
        offlineKey &&
        onlineAfterData &&
        onlineAfterKey;
  } finally {
    if (stopped && !relaunched) {
      try {
        await _p1rLaunchStoppedInstance(b, expectedToxId: toxB, nick: nickB);
      } on Object catch (e) {
        print('[pair] presence_dot_relaunch recovery relaunch failed: $e');
      }
    }
  }
}

Future<bool> _p2kTapKey(Inst inst, String key, {int timeoutSecs = 6}) async {
  if (!await inst.waitKey(key, timeoutSecs: timeoutSecs)) return false;
  if (await inst.tapKeyAt(key)) return true;
  try {
    await inst.tapKeyCenter(key, timeoutSecs: timeoutSecs);
    return true;
  } on DriveError {
    return false;
  }
}

Future<int?> _p2kTapFirstAvailableFaceTab(Inst inst) async {
  // The fork keys each face tab `sticker_face_tab:${e.index}` where `e.index` is
  // the sticker pack's own index property (`tencent_cloud_chat_sticker_widget.dart`),
  // which is NOT guaranteed to fall in any fixed small set — probe a generous
  // 0..9 range (was a too-narrow [3,2,1] that could miss a 0-based pack). The
  // cell key reuses the SAME pack index (`sticker_face_cell:<pack>:0`), so the
  // returned value stays consistent with the caller's cell lookup.
  for (var pack = 0; pack <= 9; pack++) {
    final key = 'sticker_face_tab:$pack';
    if (await inst.waitKey(key, timeoutSecs: 1) &&
        await _p2kTapKey(inst, key)) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      return pack;
    }
  }
  return null;
}

Future<Set<String>> _p2kRenderMessageIds(Inst inst, String tox) async {
  final s = await inst.dumpState(conversationId: _c2cConvId(tox));
  final raw = (s['renderMessages'] as List?) ?? const [];
  return {
    for (final m in raw)
      if (m is Map) _p2kMessageId(m.cast<String, dynamic>()),
  }..removeWhere((id) => id.isEmpty);
}

Future<Map<String, dynamic>?> _p2kWaitRenderMessageWhere(
  Inst inst,
  String tox,
  bool Function(Map<String, dynamic> message) test, {
  Set<String> excludeIds = const {},
  int timeoutSecs = 30,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final s = await inst.dumpState(conversationId: _c2cConvId(tox));
    final raw = (s['renderMessages'] as List?) ?? const [];
    for (final item in raw.reversed) {
      if (item is! Map) continue;
      final m = item.cast<String, dynamic>();
      final id = _p2kMessageId(m);
      if (excludeIds.contains(id)) continue;
      if (test(m)) return m;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return null;
}

Future<Map<String, dynamic>?> _p2kWaitC2cMessageWhere(
  Inst inst,
  String tox,
  bool Function(Map<String, dynamic> message) test, {
  int timeoutSecs = 60,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final msgs = await _c2cMessages(inst, tox);
    for (final m in msgs.reversed) {
      if (test(m)) return m;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return null;
}

String _p2kMessageId(Map<String, dynamic>? message) {
  if (message == null) return '';
  final msgId = message['msgID']?.toString() ?? '';
  if (msgId.isNotEmpty) return msgId;
  return message['id']?.toString() ?? '';
}

Future<bool> _p2kWaitFriendOnline(
  Inst inst,
  String tox,
  bool want, {
  int timeoutSecs = 30,
}) async {
  final wantId = _pubkey(tox).toLowerCase();
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final s = await inst.dumpState();
    final friends = (s['friends'] as List?) ?? const [];
    for (final f in friends) {
      if (f is! Map) continue;
      final userId = f['userId']?.toString().toLowerCase() ?? '';
      if (userId != wantId) continue;
      if (f['online'] == want) return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}
