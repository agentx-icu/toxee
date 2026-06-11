// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

const _p3WritableCases = {'message_burst_perf'};

bool _isP3WritableCaseScenario(String scenario) =>
    _p3WritableCases.contains(scenario);

Future<int> runP3WritableCase(
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
    'message_burst_perf' => await _p3MessageBurstPerf(a, b, toxA, toxB),
    _ => throw ArgumentError('unsupported P3 writable case: $scenario'),
  };
  print('[pair] ${ok ? 'PASS' : 'FAIL'}: $scenario');
  return ok ? 0 : 1;
}

Future<int> runP3WritableSweep(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB, requireHomeMenu: false);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for sweep_p3_writable: A=$toxA B=$toxB');
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
    final ok = await _p3MessageBurstPerf(a, b, toxA, toxB);
    if (ok) {
      passed++;
    } else {
      failed++;
    }
    print(
      '[sweep] sweep_p3_writable ${ok ? 'PASS' : 'FAIL'}: message_burst_perf',
    );
  } on Object catch (e, st) {
    failed++;
    print('[sweep] sweep_p3_writable EXCEPTION in message_burst_perf: $e');
    print(st);
  }

  print('[sweep] sweep_p3_writable summary: passed=$passed failed=$failed');
  await returnToChatsHome(a, rounds: 4);
  await returnToChatsHome(b, rounds: 4);
  return failed == 0 ? 0 : 1;
}

/// P3 — parametric real-composer burst. Delivery/count correctness remains a
/// hard gate; the timing threshold is deliberately NONBLOCKING and logs an
/// advisory signal for the run-phase owner.
Future<bool> _p3MessageBurstPerf(
  Inst a,
  Inst b,
  String toxA,
  String toxB,
) async {
  final count = _p3EnvInt(
    'RUI_BURST_PERF_COUNT',
    defaultValue: 24,
    min: 1,
    max: 2000,
  );
  final thresholdMs = _p3EnvInt(
    'RUI_BURST_PERF_NONBLOCKING_MS',
    defaultValue: 180000,
    min: 1,
    max: 3600000,
  );
  final deliveryTimeoutSecs = _p3EnvInt(
    'RUI_BURST_PERF_DELIVERY_TIMEOUT_SECS',
    defaultValue: 90,
    min: 5,
    max: 600,
  );

  if (!await _ensureChatOpen(b, toxA)) {
    print('[pair] message_burst_perf: B chat did not open');
    return false;
  }
  if (!await _ensureChatOpen(a, toxB)) {
    print('[pair] message_burst_perf: A chat did not open');
    return false;
  }

  final nonce = DateTime.now().microsecondsSinceEpoch;
  final prefix = 'RUIP3BURST-$nonce';
  final started = DateTime.now();
  var sent = 0;
  String? lastText;

  for (var i = 1; i <= count; i++) {
    final text = '$prefix-${i.toString().padLeft(4, '0')}';
    lastText = text;
    if (!await sendComposerMessage(a, text)) {
      await a.shot('/tmp/p3_message_burst_perf_send_fail_A.png');
      print('[pair] message_burst_perf: send failed at $i/$count');
      return false;
    }
    sent++;
    final checkpoint = i == 1 || i == count || i % 10 == 0;
    if (checkpoint &&
        !await _waitC2cMessageText(
          b,
          toxA,
          text,
          isSelf: false,
          timeoutSecs: deliveryTimeoutSecs,
        )) {
      await b.foreground();
      await b.shot('/tmp/p3_message_burst_perf_delivery_fail_B.png');
      print(
        '[pair] message_burst_perf: delivery checkpoint failed at $i/$count',
      );
      return false;
    }
  }

  final finalDelivered =
      lastText != null &&
      await _waitC2cMessageText(
        b,
        toxA,
        lastText,
        isSelf: false,
        timeoutSecs: deliveryTimeoutSecs,
      );
  final senderCount = await _p3CountC2cBurstMessages(
    a,
    toxB,
    prefix,
    isSelf: true,
  );
  final receiverCount = await _p3CountC2cBurstMessages(
    b,
    toxA,
    prefix,
    isSelf: false,
  );
  final elapsedMs = DateTime.now().difference(started).inMilliseconds;
  final overThreshold = elapsedMs > thresholdMs;
  print(
    '[pair] message_burst_perf: count=$count sent=$sent '
    'senderCount=$senderCount receiverCount=$receiverCount '
    'elapsedMs=$elapsedMs nonBlockingThresholdMs=$thresholdMs '
    'finalDelivered=$finalDelivered',
  );
  if (overThreshold) {
    print(
      '[pair] NONBLOCKING message_burst_perf threshold exceeded: '
      'elapsedMs=$elapsedMs thresholdMs=$thresholdMs',
    );
  }

  if (!finalDelivered || senderCount < count || receiverCount < count) {
    print(
      '[pair] FAIL: message_burst_perf incomplete '
      '(finalDelivered=$finalDelivered senderCount=$senderCount '
      'receiverCount=$receiverCount expected=$count)',
    );
    return false;
  }
  await a.shot('/tmp/p3_message_burst_perf_A.png');
  await b.foreground();
  await b.shot('/tmp/p3_message_burst_perf_B.png');
  return true;
}

int _p3EnvInt(
  String name, {
  required int defaultValue,
  required int min,
  required int max,
}) {
  final raw = Platform.environment[name]?.trim();
  if (raw == null || raw.isEmpty) {
    return defaultValue;
  }
  final parsed = int.tryParse(raw);
  if (parsed == null || parsed < min || parsed > max) {
    throw DriveError('$name must be an integer in [$min, $max], got "$raw"');
  }
  return parsed;
}

Future<int> _p3CountC2cBurstMessages(
  Inst inst,
  String tox,
  String prefix, {
  required bool isSelf,
}) async {
  final messages = await _c2cMessages(inst, tox);
  return messages.where((m) {
    return m['isSelf'] == isSelf &&
        (m['text']?.toString() ?? '').startsWith(prefix);
  }).length;
}
