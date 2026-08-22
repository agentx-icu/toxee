// Seeding for the product-screenshot driver (capture_product_screenshots.dart).
//
// Everything the scenes need is materialized LOCALLY through the debug L3
// surface — friends by public key, delivered C2C bubbles in both directions,
// the group and its back-filled multi-sender history, a pending friend
// request. No peer, no P2P. What is seeded is defined in seed_data.dart; this
// file only owns the order and the idempotency checks (a re-run against a
// persisted desktop seed must not duplicate anything).
//
// Presentation seams (deliberate, all product paths rather than painted
// widgets):
//   * seeded friends are reported ONLINE (`l3_seed_friend online=true`) — a
//     key that is not on the DHT can never come online for real, and a hero
//     shot with every peer "Offline" reads as a disconnected app;
//   * seeded friends/group carry an avatar PNG so the list is not four copies
//     of the same placeholder;
//   * the hero's own group lines are INJECTED as delivered history via the
//     hero's public key instead of sent through the real (offline → pending)
//     send path, so they render a sent tick rather than a pending spinner;
//   * group lines carry spaced timestamps like the C2C thread, all anchored to
//     a deterministic base clock so the four platforms agree.

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'seed_data.dart';

/// The slice of the driver's instance connection the seed needs.
abstract interface class SeedClient {
  String get platform;

  /// The hero's full Tox ID (76 hex); the 64-hex public key prefix is what
  /// FfiChatService knows as `selfId`.
  String get toxId;

  Future<Map<String, dynamic>> l3(
    String tool,
    Map<String, Object?> args, {
    bool lenient = false,
  });

  Future<Map<String, dynamic>> dumpState({String? userId, String? convId});

  Future<void> waitMs(int ms);
}

/// Seed every scene's data. Returns the group's local id (null only when the
/// group could not be created — the driver then skips that scene loudly).
Future<String?> seedAll(SeedClient s) async {
  for (final persona in seededFriends) {
    await s.l3('l3_seed_friend', {
      'userId': persona.pubKey,
      'nickname': persona.nickname,
      'online': 'true',
      'avatarBase64': _avatarBase64(persona.avatarFile),
    });
  }
  // Deterministic clock: TODAY at 09:41 local time, so every platform's
  // capture stamps the same scripted thread with the same times (a per-capture
  // `DateTime.now()` drifted the four platforms minutes apart, which reads as
  // four different conversations on the product page). Today's date keeps the
  // relative labels honest — "Thu" for the day-old thread, a time for today's.
  final today = DateTime.now();
  final nowMs = DateTime(
    today.year,
    today.month,
    today.day,
    9,
    41,
  ).millisecondsSinceEpoch;
  // Alex is the hero shot: ends a few minutes ago, one line per minute.
  await _seedC2cThread(
    s,
    peer: personaAlex,
    lines: conversationWithAlex,
    endMs: nowMs - 4 * 60000,
    stepMs: 60000,
  );
  // Two more threads so the conversation list has texture: Sofia earlier
  // today, Kenta yesterday (the list then shows a date, not a time).
  await _seedC2cThread(
    s,
    peer: personaSofia,
    lines: conversationWithSofia,
    endMs: nowMs - 47 * 60000,
    stepMs: 90000,
  );
  await _seedC2cThread(
    s,
    peer: personaKenta,
    lines: conversationWithKenta,
    endMs: nowMs - 26 * 3600000,
    stepMs: 120000,
  );
  final groupId = await _seedGroup(s, endMs: nowMs - 60000);
  for (final applicant in seededApplicants) {
    await s.l3('l3_inject_friend_application', {
      'userId': applicant.pubKey,
      'nickname': applicant.nickname,
      'wording': applicant.wording,
    });
    await s.waitMs(80);
  }
  return groupId;
}

Future<void> _seedC2cThread(
  SeedClient s, {
  required Persona peer,
  required List<C2cLine> lines,
  required int endMs,
  required int stepMs,
}) async {
  final existing = await _messageCountWith(s, peer.pubKey);
  if (existing >= lines.length) {
    print('[seed] C2C with ${peer.nickname} already seeded ($existing)');
    return;
  }
  print('[seed] injecting C2C with ${peer.nickname}');
  var ms = endMs - (lines.length - 1) * stepMs;
  for (final line in lines) {
    await s.l3('l3_inject_c2c_text', {
      'userId': peer.pubKey,
      'text': line.text,
      'isSelf': '${line.fromHero}',
      'epochMs': '$ms',
    });
    ms += stepMs;
    await s.waitMs(60);
  }
}

Future<String?> _seedGroup(SeedClient s, {required int endMs}) async {
  final convId = await _findGroupConversationId(s);
  String groupId;
  if (convId == null) {
    print('[seed] creating group "$groupName"');
    final created = await s.l3('l3_create_group', {
      'name': groupName,
      'type': 'public',
      'avatarBase64': _avatarBase64(groupAvatarFile),
    });
    groupId = created['groupId']?.toString() ?? '';
    if (groupId.isEmpty) {
      print('[seed] l3_create_group returned no groupId: $created');
      return null;
    }
  } else {
    groupId = convId.substring('group_'.length);
    print('[seed] group "$groupName" already exists ($convId)');
  }
  final history = await _groupMessageCount(s, groupId);
  if (history < groupScript.length) {
    print('[seed] injecting group chatter');
    // Injecting a line FROM FfiChatService.selfId (the native login user id —
    // an alias, NOT the 64-hex public key; read it from the dump rather than
    // deriving it) materializes a delivered self bubble (isSelf == true)
    // instead of a real send that the offline seed environment would park as
    // pending. A wrong id here renders the hero's lines as a stranger's, with
    // the raw id as the sender name.
    final selfKey = ((await s.dumpState())['selfId'] ?? '').toString();
    if (selfKey.isEmpty) {
      print('[seed] no selfId in l3_dump_state — group self lines skipped');
      return groupId;
    }
    const stepMs = 75000;
    var ms = endMs - (groupScript.length - 1) * stepMs;
    for (final (sender, text) in groupScript) {
      await s.l3('l3_inject_group_text', {
        'groupId': groupId,
        'fromUserId': sender == 'self' ? selfKey : sender,
        'text': text,
        'epochMs': '$ms',
      });
      ms += stepMs;
      await s.waitMs(120);
    }
  }
  return groupId;
}

// ── data-layer queries ──

Future<int> _messageCountWith(SeedClient s, String peer) async {
  final st = await s.dumpState(userId: peer);
  return ((st['messages'] as List?) ?? const []).length;
}

Future<String?> _findGroupConversationId(SeedClient s) async {
  final st = await s.dumpState();
  final convs = (st['conversations'] as List?) ?? const [];
  for (final c in convs) {
    if (c is! Map) continue;
    final id = c['conversationID']?.toString() ?? '';
    if (id.startsWith('group_') && c['showName']?.toString() == groupName) {
      return id;
    }
  }
  return null;
}

Future<int> _groupMessageCount(SeedClient s, String gid) async {
  final st = await s.dumpState(convId: 'group_$gid');
  return ((st['messages'] as List?) ?? const []).length;
}

// ── assets ──

/// Base64 of a PNG under tool/screenshots/assets/, or '' when it is missing
/// (the seed then simply falls back to the app's default placeholder).
String _avatarBase64(String fileName) {
  final dir = p.join(p.dirname(Platform.script.toFilePath()), 'assets');
  final file = File(p.join(dir, fileName));
  if (!file.existsSync()) {
    print('[seed] WARN avatar asset missing: ${file.path}');
    return '';
  }
  return base64Encode(file.readAsBytesSync());
}
