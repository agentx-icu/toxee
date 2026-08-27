// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

const _p2ReplyCases = {'reply_quote_real'};

bool _isP2ReplyCaseScenario(String scenario) =>
    _p2ReplyCases.contains(scenario);

Future<int> runP2ReplyCase(
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
    'reply_quote_real' => await _p2rReplyQuoteReal(a, b, toxA, toxB, nickB),
    _ => throw ArgumentError('unsupported P2 reply case: $scenario'),
  };
  print('[pair] ${ok ? 'PASS' : 'FAIL'}: $scenario');
  return ok ? 0 : 1;
}

Future<int> runP2ReplySweep(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for sweep_p2_reply: A=$toxA B=$toxB');
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
  try {
    final ok = await _p2rReplyQuoteReal(a, b, toxA, toxB, nickB);
    if (ok) {
      passed++;
    } else {
      failed++;
    }
    print('[sweep] sweep_p2_reply ${ok ? 'PASS' : 'FAIL'}: reply_quote_real');
  } on Object catch (e, st) {
    failed++;
    print('[sweep] sweep_p2_reply EXCEPTION in reply_quote_real: $e');
    print(st);
  }

  print('[sweep] sweep_p2_reply summary: passed=$passed failed=$failed');
  return failed == 0 ? 0 : 1;
}

Future<bool> _p2rReplyQuoteReal(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
  String nickB,
) async {
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] reply_quote_real: A chat did not open');
    return false;
  }
  final before = await _p2kRenderMessageIds(a, toxB);
  final nonce = DateTime.now().microsecondsSinceEpoch;
  final customData = '{"type":"reply_probe","nonce":$nonce}';

  var marked = false;
  try {
    await a.markAccountTest();
    marked = true;
    final inject = await a.l3('l3_inject_c2c_custom', {
      'fromUserId': toxB,
      'data': customData,
    });
    if (inject['ok'] != true || inject['ingested'] != true) {
      print('[pair] reply_quote_real: custom inject failed: $inject');
      return false;
    }
  } finally {
    if (marked) {
      await a.unmarkAccountTest();
    }
  }

  final customHistory = await _p2kWaitC2cMessageWhere(
    a,
    toxB,
    (m) =>
        m['isSelf'] == false &&
        m['mediaKind']?.toString() == 'custom' &&
        m['text']?.toString() == customData,
    timeoutSecs: 12,
  );
  final customId = _p2kMessageId(customHistory);
  final customRender = await _p2kWaitRenderMessageWhere(
    a,
    toxB,
    (m) => _p2kMessageId(m) == customId && m['elemType'] == 2,
    excludeIds: before,
    timeoutSecs: 12,
  );
  final customRowRendered =
      customId.isNotEmpty &&
      await a.waitKey('message_list_item:$customId', timeoutSecs: 6);
  if (!customRowRendered) {
    print('[pair] reply_quote_real: custom row did not render id=$customId');
    return false;
  }
  if (!await _openMessageMenuReal(a, customId)) {
    print('[pair] reply_quote_real: custom bubble menu did not open');
    return false;
  }
  final replyItem = await a.waitKeyCenter(
    'message_menu_item:reply',
    timeoutSecs: 4,
  );
  if (!replyItem) {
    await _dismissMessageMenu(a);
    print('[pair] reply_quote_real: Reply item absent on custom bubble');
    return false;
  }
  if (!await a.tapKeyCenter('message_menu_item:reply', timeoutSecs: 4)) {
    await _dismissMessageMenu(a);
    print('[pair] reply_quote_real: Reply item tap failed');
    return false;
  }
  final banner = await a.waitKey(
    'message_input_reply_container',
    timeoutSecs: 8,
  );
  if (!banner) {
    print('[pair] reply_quote_real: keyed quote banner did not mount');
    return false;
  }

  final replyText = 'RUIP2REPLY-$nonce';
  // clearFirst:false — the reply-quote banner is up and the composer dismisses
  // the quote on a Backspace-over-empty-field (osaClear), which would strip the
  // messageReply metadata. The field is already empty after tapping Reply.
  if (!await sendComposerMessage(a, replyText, clearFirst: false)) {
    print('[pair] reply_quote_real: A failed to send reply body');
    return false;
  }
  final bannerGone = await a.waitKeyGone(
    'message_input_reply_container',
    timeoutSecs: 8,
  );
  final sentReply = await _p2kWaitC2cMessageWhere(
    a,
    toxB,
    (m) => m['isSelf'] == true && m['text']?.toString() == replyText,
    timeoutSecs: 20,
  );
  final sentId = _p2kMessageId(sentReply);
  final cloud = sentReply?['cloudCustomData']?.toString() ?? '';
  final replyMetadataOk = _p2rReplyCloudMatches(
    cloud,
    replyToMsgId: customId,
    replyToSender: toxB,
    replyToSenderLabel: nickB,
  );
  final bReceived = await _p2kWaitC2cMessageWhere(
    b,
    toxA,
    (m) => m['isSelf'] == false && m['text']?.toString() == replyText,
    timeoutSecs: 60,
  );

  // CONVERTER COLD-RELOAD validation (codex fix-forward): the reply's
  // cloudCustomData persists in the dump messages[] (ffi.getHistory), but the
  // RENDER layer rebuilds history through getHistoryMessageList* ->
  // chatMessageToV2TimMessage. Before the converter fix that path dropped the
  // quote (it rendered live but vanished after a reload). Close + reopen the
  // chat so UIKit reloads history through the converter, then assert the
  // render-layer V2TimMessage still carries the messageReply metadata.
  var reloadCloudOk = false;
  if (sentId.isNotEmpty) {
    await returnToChatsHome(a, rounds: 3);
    if (await _ensureChatOpen(a, toxB)) {
      final reloaded = await _p2kWaitRenderMessageWhere(
        a,
        toxB,
        (m) =>
            _p2kMessageId(m) == sentId &&
            _p2rReplyCloudMatches(
              m['cloudCustomData']?.toString() ?? '',
              replyToMsgId: customId,
              replyToSender: toxB,
              replyToSenderLabel: nickB,
            ),
        timeoutSecs: 12,
      );
      reloadCloudOk = reloaded != null;
    }
  }

  print(
    '[pair] reply_quote_real: customId=$customId sentId=$sentId '
    'bannerGone=$bannerGone replyMetadataOk=$replyMetadataOk '
    'bReceived=${bReceived != null} reloadCloudOk=$reloadCloudOk '
    // The raw metadata is the only thing that separates "quote dropped before
    // send" from "quote present but keyed differently" — print it on FAIL.
    '${replyMetadataOk ? '' : 'cloud="${cloud.length > 240 ? '${cloud.substring(0, 240)}…' : cloud}"'}',
  );
  return customRender != null &&
      customRowRendered &&
      bannerGone &&
      sentReply != null &&
      replyMetadataOk &&
      bReceived != null &&
      reloadCloudOk;
}

bool _p2rReplyCloudMatches(
  String cloud, {
  required String replyToMsgId,
  required String replyToSender,
  required String replyToSenderLabel,
}) {
  if (cloud.isEmpty || replyToMsgId.isEmpty || replyToSender.isEmpty) {
    return false;
  }
  try {
    final decoded = jsonDecode(cloud);
    if (decoded is! Map) return false;
    final reply = decoded['messageReply'];
    if (reply is! Map) return false;
    // `messageSender` is the fork's DISPLAY label for the quoted sender —
    // `checkString(repliedMessage.nickName) ?? repliedMessage.sender`
    // (tencent_cloud_chat_message_data_tools.dart, same as upstream) — so it is
    // B's nickname once A has resolved it and B's bare pubkey before that. Both
    // are the correct product output; this case used to accept only the pubkey
    // and therefore FAILED whenever it ran after any sweep that had let A learn
    // B's name (live 2026-08-22: `"messageSender":"RealUiBob"` inside the
    // friendship bundle, pubkey on a fresh pair). Compare the pubkey form by
    // 64-char key (the caller may pass a 76-char Tox ID); the messageID is an
    // exact match either way.
    final sender = reply['messageSender']?.toString() ?? '';
    final senderMatches =
        _pubkey(sender) == _pubkey(replyToSender) ||
        (replyToSenderLabel.isNotEmpty && sender == replyToSenderLabel);
    return reply['messageID']?.toString() == replyToMsgId && senderMatches;
  } catch (_) {
    return false;
  }
}
