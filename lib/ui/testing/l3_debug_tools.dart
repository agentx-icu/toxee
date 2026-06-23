// L3 debug MCP tool surface — deterministic control + introspection hooks for
// the AI-driven Layer-3 UI automation (see
// `doc/research/L3_MCP_IMPROVEMENT_PLAN.en.md`, codex-vetted 2026-05-29).
//
// WHY: synthetic MCP gestures cannot drive two core flows — message SEND
// (the desktop composer is Enter-to-send via the legacy `RawKeyEvent.onKey`
// path, which `fmt_press_key` does not reach) and the message context menu
// (no semantic long-press). The earlier workaround (a real OS `osascript`
// Return) is fragile.
//
// `l3_send_text` calls the toxee-level service send
// (`FakeChatMessageProvider.sendText` → `FakeConversationManager.sendText` →
// `FfiChatService.sendText` → DHT). This reaches the SAME underlying send +
// offline-queue + final-msgID machinery the composer ultimately hits, so it is
// adequate for the deterministic plain-text send / echo / offline-queue
// scenarios (S12/S25/S62). It is NOT the exact composer path: it deliberately
// skips the UIKit optimistic layer (the initial SENDING bubble,
// `onSendMessageProgress`, reply-pill clearing). Reply / forward (S17/S18)
// build structured `cloudCustomData` and route through
// `Tim2ToxSdkPlatform.sendMessage`; those get their OWN tools (`l3_reply_text`
// / `l3_forward_message`) — do NOT add a raw cloudCustomData escape hatch here.
// (codex-confirmed 2026-05-29.)
//
// SAFETY: registered ONLY behind `kDebugMode && bool.fromEnvironment(
// 'TOXEE_L3_TEST')`. The flag is injected by `run_toxee.sh` whenever an
// `MCP_BINDING` is set (the canonical L3 launch). `kDebugMode` tree-shakes
// this file out of profile/release. Mutating tools additionally refuse to run
// unless the active account looks like a test/seed account.
//
// Tools (callable via arenukvern `fmt_client_tool`, name `l3_*`, or directly
// as `ext.mcp.toolkit.l3_*`):
//   - l3_register_account {nickname, statusMessage?, password?} deterministic register
//   - l3_boot_existing_account {toxId, nickname, statusMessage?, password?} deterministic boot
//   - l3_add_friend_request {userId, message?}         deterministic add-friend
//   - l3_start_call {userId, video?}                   deterministic outgoing call
//   - l3_call_action {action}                          accept/reject/hangup/mute/video
//   - l3_send_text   {userId?|conversationId?, text}   deterministic C2C send
//   - l3_dump_state  {}                                JSON snapshot for asserts
//   - l3_set_export_save_path {path?}                  override export saveFile
//   - l3_set_account_import_pick_path {path?}          override restore/import pickFiles
//   - l3_set_attachment_pick_path {path?}              override message attachment pickFiles
//   - l3_accept_friend_request {userId}                deterministic accept

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Locale, Size, ThemeMode;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:mcp_toolkit/mcp_toolkit.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/data/contact/tencent_cloud_chat_contact_data.dart';
import 'package:tim2tox_dart/service/tuicallkit_adapter.dart';
import 'package:window_manager/window_manager.dart';

import '../../navigation/app_navigation.dart';
import '../../notifications/notification_service.dart';
import '../profile/profile_avatar_picker.dart';
import '../../sdk_fake/fake_uikit_core.dart';
import '../../sdk_fake/uikit_data_facade.dart';
import '../../util/account_service.dart';
import '../../util/app_bootstrap_coordinator.dart';
import '../../util/appearance_sync.dart';
import '../../util/logger.dart';
import '../../util/prefs.dart';
import '../../util/tox_utils.dart';

/// True only on the canonical L3 launch (`run_toxee.sh` with an `MCP_BINDING`
/// injects `--dart-define=TOXEE_L3_TEST=true`). Combined with [kDebugMode] this
/// keeps the whole surface out of profile/release builds.
const bool kL3TestSurfaceEnabled =
    kDebugMode && bool.fromEnvironment('TOXEE_L3_TEST');

const String _l3SharedPrefsPrefixEnv = 'TOXEE_SHARED_PREFS_PREFIX';
const String _l3AppSupportDirEnv = 'TOXEE_APP_SUPPORT_DIR';
const String _l3TccfGlobalSubdirEnv = 'TOXEE_TCCF_GLOBAL_SUBDIR';

typedef L3ExportSaveFileInvoker =
    Future<String?> Function(String dialogTitle, String fileName);

bool? _l3TestSurfaceEnabledOverrideForTests;
String? _exportSaveFilePathOverride;
String? _accountImportPickFilePathOverride;
String? _attachmentPickFilePathOverride;

/// S46/S47: the live auto-accept setter hook. `l3_set_setting` only writes
/// Prefs, but the inbound friend-application / group-invite listeners read a
/// CACHED HomePage flag (`_autoAcceptFriends` etc.) that a Prefs write does not
/// refresh — so the setting never takes effect mid-session. HomePage registers
/// this applier (gated) in `_initAfterSessionReady` and clears it on dispose;
/// it drives the SAME `_setAutoAcceptFriends`/`_setAutoAcceptGroupInvites` the
/// settings toggle uses (cached flag + Prefs + accept-pending side effect). When
/// present, `l3_set_setting` routes through it; otherwise it falls back to a
/// Prefs-only write (e.g. unit tests with no live HomePage).
typedef L3AutoAcceptApplier = Future<void> Function(String key, bool value);
L3AutoAcceptApplier? _l3AutoAcceptApplier;
typedef L3HomeShellApplier = Future<void> Function(String tab);
L3HomeShellApplier? _l3HomeShellApplier;
typedef L3OpenAddFriendDialogInvoker = Future<bool> Function();
L3OpenAddFriendDialogInvoker? _l3OpenAddFriendDialogInvoker;
typedef L3OpenAddGroupDialogInvoker = Future<bool> Function();
L3OpenAddGroupDialogInvoker? _l3OpenAddGroupDialogInvoker;
typedef L3OpenChatInvoker =
    Future<bool> Function({String? userId, String? groupId});
L3OpenChatInvoker? _l3OpenChatInvoker;
typedef L3OpenSelfProfileInvoker = Future<bool> Function();
L3OpenSelfProfileInvoker? _l3OpenSelfProfileInvoker;
typedef L3PopToRootInvoker = Future<bool> Function();
L3PopToRootInvoker? _l3PopToRootInvoker;
typedef L3OpenGlobalSearchInvoker = Future<bool> Function();
L3OpenGlobalSearchInvoker? _l3OpenGlobalSearchInvoker;
typedef L3OpenGroupAddMemberInvoker = Future<bool> Function(String groupId);
L3OpenGroupAddMemberInvoker? _l3OpenGroupAddMemberInvoker;
typedef L3OpenGroupMemberListInvoker = Future<bool> Function(String groupId);
L3OpenGroupMemberListInvoker? _l3OpenGroupMemberListInvoker;
typedef L3OpenGroupProfileInvoker = Future<bool> Function(String groupId);
L3OpenGroupProfileInvoker? _l3OpenGroupProfileInvoker;
typedef L3OpenConversationMenuInvoker =
    Future<bool> Function(String conversationId, {String? action});
L3OpenConversationMenuInvoker? _l3OpenConversationMenuInvoker;
typedef L3HomeShellSnapshotReader = Map<String, dynamic> Function();
L3HomeShellSnapshotReader? _l3HomeShellSnapshotReader;

/// Project the message provider's in-flight RECEIVE file-progress map
/// (`FakeMessageProvider.fileProgress`, msgID → byte counts) into the
/// `l3_dump_state.fileTransfers` shape: msgID → {received, total, percent, path}.
/// `percent` is `floor(received/total*100)` (0 when total<=0). Extracted as a
/// pure function so the percent math + projection shape are L1-testable (S94)
/// without the live recv-event timing or the MCP harness. NOTE: this projects
/// whatever is in the map — the "entry vanishes at 100%" behaviour is the LIVE
/// `file_done` clear (fake_msg_provider_routing.dart), not this function.
@visibleForTesting
Map<String, Map<String, Object?>> projectFileTransfers(
  Map<String, ({int received, int total, String? path})> fileProgress,
) {
  return {
    for (final e in fileProgress.entries)
      e.key: {
        'received': e.value.received,
        'total': e.value.total,
        'percent': e.value.total > 0
            ? (e.value.received * 100 / e.value.total).floor()
            : 0,
        'path': e.value.path,
      },
  };
}

/// Register (or clear, with null) the live auto-accept applier. No-op unless the
/// L3 test surface is enabled.
void registerL3AutoAcceptApplier(L3AutoAcceptApplier? fn) {
  if (kL3TestSurfaceEnabled) _l3AutoAcceptApplier = fn;
}

void registerL3HomeShellApplier(L3HomeShellApplier? fn) {
  if (kL3TestSurfaceEnabled) _l3HomeShellApplier = fn;
}

void registerL3OpenAddFriendDialogInvoker(L3OpenAddFriendDialogInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenAddFriendDialogInvoker = fn;
}

void registerL3OpenAddGroupDialogInvoker(L3OpenAddGroupDialogInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenAddGroupDialogInvoker = fn;
}

void registerL3OpenChatInvoker(L3OpenChatInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenChatInvoker = fn;
}

void registerL3OpenSelfProfileInvoker(L3OpenSelfProfileInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenSelfProfileInvoker = fn;
}

void registerL3PopToRootInvoker(L3PopToRootInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3PopToRootInvoker = fn;
}

void registerL3OpenGlobalSearchInvoker(L3OpenGlobalSearchInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenGlobalSearchInvoker = fn;
}

void registerL3OpenGroupAddMemberInvoker(L3OpenGroupAddMemberInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenGroupAddMemberInvoker = fn;
}

void registerL3OpenGroupMemberListInvoker(L3OpenGroupMemberListInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenGroupMemberListInvoker = fn;
}

void registerL3OpenGroupProfileInvoker(L3OpenGroupProfileInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenGroupProfileInvoker = fn;
}

void registerL3OpenConversationMenuInvoker(L3OpenConversationMenuInvoker? fn) {
  if (kL3TestSurfaceEnabled) _l3OpenConversationMenuInvoker = fn;
}

void registerL3HomeShellSnapshotReader(L3HomeShellSnapshotReader? fn) {
  if (kL3TestSurfaceEnabled) _l3HomeShellSnapshotReader = fn;
}

/// The currently-registered home-shell snapshot reader, exposed so a HomePage's
/// dispose can identity-guard its unregister: a switch-back
/// (`pushAndRemoveUntil(HomePage)`) mounts the NEW HomePage (which re-registers)
/// BEFORE the old one disposes, so an unconditional `register…(null)` on dispose
/// would clobber the new instance's reader and leave the dump's `homeShellTab`
/// null after every switch (breaking `_settingsTabActive`/settings nav).
L3HomeShellSnapshotReader? get currentL3HomeShellSnapshotReader =>
    _l3HomeShellSnapshotReader;

/// S79: avatar-pick override path (mirrors the export-save override). When set,
/// the avatar image picker is bypassed and this fixed path is returned, so the
/// native NSOpenPanel never blocks a headless L3 run.
String? _avatarPickPathOverride;

String? get debugCurrentAvatarPickOverridePath =>
    _isL3TestSurfaceActive ? _avatarPickPathOverride : null;

String? get debugCurrentAccountImportPickOverridePath =>
    _isL3TestSurfaceActive ? _accountImportPickFilePathOverride : null;

String? get debugCurrentAttachmentPickOverridePath =>
    _isL3TestSurfaceActive ? _attachmentPickFilePathOverride : null;

/// Mirrors [runL3AwareExportSaveFilePicker] for the avatar image picker: returns
/// the override path when set, else delegates to the real [pickFiles].
Future<String?> runL3AwareAvatarPicker({
  required Future<String?> Function() pickFiles,
}) async {
  final overridePath = debugCurrentAvatarPickOverridePath;
  if (overridePath != null) {
    AppLogger.info('[L3] avatar pick override hit -> $overridePath');
    return overridePath;
  }
  return pickFiles();
}

/// Restore/import account pickers open native dialogs on desktop; the L3 harness
/// can set a fixed path so a real UI tap still continues through the controller.
Future<String?> runL3AwareAccountImportPicker({
  required Future<String?> Function() pickFile,
}) async {
  final overridePath = debugCurrentAccountImportPickOverridePath;
  if (overridePath != null) {
    AppLogger.info('[L3] account import picker override hit -> $overridePath');
    return overridePath;
  }
  return pickFile();
}

/// Message attachment image/video/file pickers need the same fixed-path seam as
/// account import: drive the real toolbar first, bypass only the native dialog.
Future<String?> runL3AwareAttachmentPicker({
  required Future<String?> Function() pickFile,
}) async {
  final overridePath = debugCurrentAttachmentPickOverridePath;
  if (overridePath != null) {
    AppLogger.info('[L3] attachment picker override hit -> $overridePath');
    return overridePath;
  }
  return pickFile();
}

bool get _isL3TestSurfaceActive =>
    _l3TestSurfaceEnabledOverrideForTests ?? kL3TestSurfaceEnabled;

String? _normalizeExportSaveOverridePath(String? path) {
  final trimmed = path?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

Map<String, String?> _l3HarnessEnvironmentSnapshot(Map<String, String> env) {
  String? clean(String key) {
    final value = env[key]?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  return {
    'sharedPrefsPrefix': clean(_l3SharedPrefsPrefixEnv),
    'appSupportDirOverride': clean(_l3AppSupportDirEnv),
    'tccfGlobalSubdir': clean(_l3TccfGlobalSubdirEnv),
  };
}

@visibleForTesting
Map<String, String?> debugL3HarnessEnvironmentSnapshotForTests(
  Map<String, String> env,
) => _l3HarnessEnvironmentSnapshot(env);

@visibleForTesting
void debugSetL3TestSurfaceEnabledForTests(bool? value) {
  _l3TestSurfaceEnabledOverrideForTests = value;
}

@visibleForTesting
void debugSetExportSaveFileOverridePathForTests(String? path) {
  _exportSaveFilePathOverride = _normalizeExportSaveOverridePath(path);
}

@visibleForTesting
void debugSetAccountImportPickFileOverridePathForTests(String? path) {
  _accountImportPickFilePathOverride = _normalizeExportSaveOverridePath(path);
}

@visibleForTesting
void debugSetAttachmentPickFileOverridePathForTests(String? path) {
  _attachmentPickFilePathOverride = _normalizeExportSaveOverridePath(path);
}

@visibleForTesting
void debugResetL3FilePickerOverridesForTests() {
  _exportSaveFilePathOverride = null;
  _avatarPickPathOverride = null;
  _accountImportPickFilePathOverride = null;
  _attachmentPickFilePathOverride = null;
}

@visibleForTesting
String? get debugCurrentExportSaveFileOverridePath =>
    _isL3TestSurfaceActive ? _exportSaveFilePathOverride : null;

Future<String?> runL3AwareExportSaveFilePicker({
  required String dialogTitle,
  required String fileName,
  required L3ExportSaveFileInvoker saveFile,
}) async {
  final overridePath = debugCurrentExportSaveFileOverridePath;
  if (overridePath != null) {
    AppLogger.info(
      '[L3] export save picker override hit: '
      '$fileName -> $overridePath',
    );
    return overridePath;
  }
  return saveFile(dialogTitle, fileName);
}

/// Register the L3 debug MCP tools, if enabled. No-op otherwise. Call after
/// `MCPToolkitBinding.instance.initialize()` in `main()`.
void registerL3DebugToolsIfEnabled() {
  if (!kL3TestSurfaceEnabled) return;
  AppLogger.info(
    '[L3] Registering debug MCP tools (l3_send_text, l3_dump_state, '
    'l3_register_account, '
    'l3_boot_existing_account, '
    'l3_add_friend_request, '
    'l3_start_call, l3_call_action, '
    'l3_clear_history, l3_clear_active_conversation, '
    'l3_force_home_root, '
    'l3_open_add_friend_dialog, l3_open_chat, l3_open_global_search, '
    'l3_invoke_message_action, l3_mark_read, '
    'l3_accept_friend_request, l3_refuse_friend_request, l3_delete_friend, '
    'l3_set_friend_remark, l3_set_blocked, '
    'l3_set_export_save_path, l3_set_account_import_pick_path, '
    'l3_set_attachment_pick_path, '
    'l3_reply_text, l3_forward_message, l3_inject_c2c_custom, '
    'l3_inject_c2c_text, l3_seed_friend, l3_inject_friend_application, '
    'l3_open_self_profile, l3_pop_to_root, '
    'l3_set_setting, l3_set_pinned, l3_set_self_profile, '
    'l3_simulate_notification_tap, l3_set_c2c_recv_opt, l3_send_file, '
    'l3_create_group, l3_join_group, l3_leave_group, l3_send_group_text, '
    'l3_set_avatar_pick_path, l3_pick_avatar, l3_set_typing, '
    'l3_window_state, l3_invite_to_group, l3_kick_group_member, '
    'l3_group_member_list, l3_dht_info, l3_add_bootstrap_node, '
    'l3_contact_search). '
    'TOXEE_L3_TEST is set — this MUST NOT happen in release.',
  );
  addMcpTool(_l3RegisterAccountEntry());
  addMcpTool(_l3BootExistingAccountEntry());
  addMcpTool(_l3AddFriendRequestEntry());
  addMcpTool(_l3StartCallEntry());
  addMcpTool(_l3CallActionEntry());
  addMcpTool(_l3SendTextEntry());
  addMcpTool(_l3ReplyTextEntry());
  addMcpTool(_l3ForwardMessageEntry());
  addMcpTool(_l3InjectC2cCustomEntry());
  addMcpTool(_l3InjectC2cTextEntry());
  addMcpTool(_l3SeedFriendEntry());
  addMcpTool(_l3InjectFriendApplicationEntry());
  addMcpTool(_l3OpenSelfProfileEntry());
  addMcpTool(_l3PopToRootEntry());
  addMcpTool(_l3DumpStateEntry());
  addMcpTool(_l3ClearHistoryEntry());
  addMcpTool(_l3ClearActiveConversationEntry());
  addMcpTool(_l3ForceHomeRootEntry());
  addMcpTool(_l3OpenAddFriendDialogEntry());
  addMcpTool(_l3OpenAddGroupDialogEntry());
  addMcpTool(_l3OpenChatEntry());
  addMcpTool(_l3OpenGlobalSearchEntry());
  addMcpTool(_l3OpenGroupAddMemberEntry());
  addMcpTool(_l3OpenGroupMemberListEntry());
  addMcpTool(_l3OpenGroupProfileEntry());
  addMcpTool(_l3OpenConversationMenuEntry());
  addMcpTool(_l3InvokeMessageActionEntry());
  addMcpTool(_l3MarkReadEntry());
  addMcpTool(_l3AcceptFriendRequestEntry());
  addMcpTool(_l3RefuseFriendRequestEntry());
  addMcpTool(_l3DeleteFriendEntry());
  addMcpTool(_l3SetFriendRemarkEntry());
  addMcpTool(_l3SetBlockedEntry());
  addMcpTool(_l3SetExportSavePathEntry());
  addMcpTool(_l3SetAccountImportPickPathEntry());
  addMcpTool(_l3SetAttachmentPickPathEntry());
  addMcpTool(_l3SetSettingEntry());
  addMcpTool(_l3SetPinnedEntry());
  addMcpTool(_l3SetSelfProfileEntry());
  addMcpTool(_l3SimulateNotificationTapEntry());
  addMcpTool(_l3SetC2CRecvOptEntry());
  addMcpTool(_l3SendFileEntry());
  addMcpTool(_l3CreateGroupEntry());
  addMcpTool(_l3JoinGroupEntry());
  addMcpTool(_l3LeaveGroupEntry());
  addMcpTool(_l3SendGroupTextEntry());
  addMcpTool(_l3InjectGroupTextEntry());
  addMcpTool(_l3SetAvatarPickPathEntry());
  addMcpTool(_l3PickAvatarEntry());
  addMcpTool(_l3SetTypingEntry());
  addMcpTool(_l3WindowStateEntry());
  addMcpTool(_l3InviteToGroupEntry());
  addMcpTool(_l3KickGroupMemberEntry());
  addMcpTool(_l3GroupMemberListEntry());
  addMcpTool(_l3DhtInfoEntry());
  addMcpTool(_l3AddBootstrapNodeEntry());
  addMcpTool(_l3ContactSearchEntry());
  // UNGATED group-campaign plumbing hooks (work on fresh/non-test accounts).
  // These mirror the test-gated set_setting(autoAcceptGroupInvites) /
  // group_member_list / leave_group operations the real-UI two-process
  // group_message campaign needs on freshly-registered accounts, where the
  // gated variants refuse. They are pure harness ops (no user-visible flow),
  // like l3_open_add_group_dialog / dump_state.
  addMcpTool(_l3SetAutoAcceptGroupInvitesEntry());
  addMcpTool(_l3GroupMemberCountEntry());
  addMcpTool(_l3LeaveGroupUncheckedEntry());
  addMcpTool(_l3ClearGroupHistoryEntry());
  addMcpTool(_l3SetActiveConversationEntry());
  addMcpTool(_l3MarkCurrentAccountTestEntry());
  addMcpTool(_l3UnmarkCurrentAccountTestEntry());
}

/// Exact fixture identities the mutating/destructive tools are allowed to
/// touch. Belt-and-suspenders on top of the build-time [kL3TestSurfaceEnabled]
/// gate. codex P1: a substring nickname match ("contains test") is too loose
/// for a destructive surface (delete) — a real account named e.g. "tester"
/// would pass. Use EXACT nickname match + the known echo-fixture Tox ID
/// prefix. Extend these sets when adding new test accounts.
const Set<String> _kTestNicknames = {
  'echo_seeded_test',
  'echo_live_test',
  'echobotserver',
};
const Set<String> _kTestToxIdPrefixes = {
  '8895A8D64C34334F', // the canonical echo_seeded fixture account
};

/// Stable 64-hex public-key prefix of a Tox ID (the identity part; the
/// trailing nospam+checksum can in principle change without changing who the
/// account is). Used for seed-marker membership checks.
String _toxIdPublicKey(String toxId) {
  final normalized = toxId.trim().toUpperCase();
  return normalized.length >= 64 ? normalized.substring(0, 64) : normalized;
}

/// True when [toxId] was registered through the debug-only L3 path
/// (`l3_register_account` records every new account in
/// [Prefs.getL3SeedToxIds]). Matching is by public-key prefix.
Future<bool> _isL3SeedToxId(String toxId) async {
  if (toxId.isEmpty) return false;
  final pk = _toxIdPublicKey(toxId);
  final seedIds = await Prefs.getL3SeedToxIds();
  return seedIds.any((s) => _toxIdPublicKey(s) == pk);
}

/// Guard: mutating tools only act on a known test/seed fixture account so an
/// accidentally enabled surface can't touch a real user's data.
///
/// An account qualifies through ANY of:
///   1. exact fixture nickname ([_kTestNicknames]) — legacy echo fixtures;
///   2. known fixture Tox ID prefix ([_kTestToxIdPrefixes]);
///   3. the persistent SEED-ACCOUNT MARKER ([Prefs.getL3SeedToxIds]): the
///      account was CREATED via `l3_register_account`, which only exists on
///      the debug L3 surface. Identity-by-construction beats identity-by-
///      nickname — seed personas (product screenshots) carry realistic
///      display names and may rename via `l3_set_self_profile` without
///      locking themselves out of the mutating tools.
Future<bool> _activeAccountIsTest() async {
  final nick = ((await Prefs.getNickname()) ?? '').toLowerCase().trim();
  if (_kTestNicknames.contains(nick)) return true;
  final toxId = ((await Prefs.getCurrentAccountToxId()) ?? '').toUpperCase();
  if (_kTestToxIdPrefixes.any(toxId.startsWith)) return true;
  return _isL3SeedToxId(toxId);
}

/// codex Item B: each C2C-only tool rejects an explicit `group_` id, but that
/// guard runs BEFORE the `ffi.activePeerId` fallback — and the active id is
/// already normalized (its `group_` prefix stripped), so a group conversation
/// could slip into a C2C-only tool via the fallback. Re-check the RESOLVED bare
/// id against ALL group sources (all normalized/prefix-less):
///   - [liveGroups] = `ffi.knownGroups` — AUTHORITATIVE in-memory joined set
///     (one receive path adds without persisting immediately, so
///     `Prefs.getGroups` alone misses freshly-joined groups);
///   - [quitGroups] = `ffi.quitGroups` — a JUST-QUIT group is removed from
///     knownGroups but `activePeerId` is NOT cleared on quit, so a quit-but-
///     still-active group id could otherwise slip through as fake C2C
///     (codex re-review caught this);
///   - `Prefs.getGroups()` — persisted backstop.
/// Returns a rejection result if [bareUserId] is any kind of group, else null.
Future<MCPCallResult?> _rejectIfGroupTarget(
  String tool,
  String bareUserId,
  Set<String> liveGroups,
  Set<String> quitGroups,
) async {
  if (liveGroups.contains(bareUserId) || quitGroups.contains(bareUserId)) {
    return MCPCallResult(
      message: '$tool: resolved target is a group — C2C only',
      parameters: {'ok': false, 'error': 'group_unsupported'},
    );
  }
  final persisted = await Prefs.getGroups();
  if (persisted.contains(bareUserId)) {
    return MCPCallResult(
      message: '$tool: resolved target is a group — C2C only',
      parameters: {'ok': false, 'error': 'group_unsupported'},
    );
  }
  return null;
}

/// S18: send a REPLY (quoted message). Builds the V2TIM `messageReply`
/// cloudCustomData the UIKit composer builds (the replied message's id +
/// abstract + sender), then sends via `FfiChatService.sendText` so it persists
/// on the sender-side ChatMessage (survives reload). The replied message is
/// resolved from this conversation's history by `replyToMsgId` or — for runner
/// gates that don't know the run-specific native id — by a UNIQUE `replyToText`.
/// Read back via `l3_dump_state.messages[].cloudCustomData`. MUTATING —
/// test/seed account, C2C only. NOTE: the quote is NOT delivered to the peer
/// (Tox carries plain text); this exercises the SENDER-side persistence (the
/// S18 data half).
MCPCallEntry _l3ReplyTextEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final text = request['text'] ?? '';
    if (text.isEmpty) {
      return MCPCallResult(
        message: 'l3_reply_text: missing required "text"',
        parameters: {'ok': false, 'error': 'missing_text'},
      );
    }
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_reply_text: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_reply_text: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var userId = request['userId'] ?? request['conversationId'] ?? '';
    if (userId.startsWith('group_') || request['groupId'] != null) {
      return MCPCallResult(
        message: 'l3_reply_text: C2C only — group replies are not supported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    if (userId.startsWith('c2c_')) userId = userId.substring(4);
    if (userId.isEmpty) userId = ffi.activePeerId ?? '';
    if (userId.isEmpty) {
      return MCPCallResult(
        message:
            'l3_reply_text: no target — pass "userId" or open a chat first',
        parameters: {'ok': false, 'error': 'no_target'},
      );
    }
    final groupReject = await _rejectIfGroupTarget(
      'l3_reply_text',
      userId,
      ffi.knownGroups,
      ffi.quitGroups,
    );
    if (groupReject != null) return groupReject;
    final replyToMsgId = (request['replyToMsgId'] ?? '').toString();
    final replyToText = (request['replyToText'] ?? '').toString();
    if (replyToMsgId.isEmpty && replyToText.isEmpty) {
      return MCPCallResult(
        message: 'l3_reply_text: need "replyToMsgId" or "replyToText"',
        parameters: {'ok': false, 'error': 'missing_reply_target'},
      );
    }
    // Resolve the replied message from this conversation's persisted history
    // (type inferred from getHistory's List<ChatMessage>).
    final history = ffi.getHistory(userId);
    var matches = replyToMsgId.isNotEmpty
        ? history
              .where(
                (m) =>
                    m.msgID == replyToMsgId ||
                    m.altMsgIds.contains(replyToMsgId),
              )
              .toList()
        : history.where((m) => m.text == replyToText).toList();
    // Optional isSelf disambiguator: a running echo peer mirrors a self text
    // back inbound, so the same `replyToText` can match twice — filter to the
    // requested direction so a gate can reply to the SELF copy deterministically.
    final replyToIsSelf = request['replyToIsSelf'];
    if (replyToIsSelf != null && replyToMsgId.isEmpty) {
      final wantSelf = replyToIsSelf.toString().toLowerCase() == 'true';
      matches = matches.where((m) => m.isSelf == wantSelf).toList();
    }
    if (replyToText.isNotEmpty && matches.length > 1) {
      return MCPCallResult(
        message:
            'l3_reply_text: replyToText "$replyToText" is ambiguous '
            '(${matches.length} matches) — use a unique text or replyToMsgId',
        parameters: {'ok': false, 'error': 'ambiguous_reply_target'},
      );
    }
    if (matches.isEmpty) {
      return MCPCallResult(
        message: 'l3_reply_text: replied message not found in history',
        parameters: {'ok': false, 'error': 'reply_target_not_found'},
      );
    }
    final replied = matches.first;
    // Build the cloudCustomData EXACTLY as the UIKit composer does
    // (tencent_cloud_chat_message_data_tools.dart): top-level "messageReply".
    final cloud = jsonEncode({
      'messageReply': {
        'messageID': replied.msgID,
        'messageTimestamp': replied.timestamp.millisecondsSinceEpoch ~/ 1000,
        'messageSeq': null,
        'messageAbstract': replied.text,
        'messageSender': replied.fromUserId,
        'messageType': 1, // V2TIM_ELEM_TYPE_TEXT
        'version': 1,
      },
    });
    try {
      await ffi.sendText(userId, text, cloudCustomData: cloud);
      AppLogger.info(
        '[L3] l3_reply_text: replied to ${replied.msgID} in $userId',
      );
      return MCPCallResult(
        message: 'reply sent',
        parameters: {
          'ok': true,
          'userId': userId,
          'text': text,
          'replyToMsgId': replied.msgID,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_reply_text failed', e, st);
      return MCPCallResult(
        message: 'l3_reply_text: failed: $e',
        parameters: {'ok': false, 'error': 'reply_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_reply_text',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING, C2C only): send a REPLY — '
        'builds the V2TIM messageReply cloudCustomData (replied msg id + '
        'abstract + sender) and sends via FfiChatService.sendText so it persists '
        'sender-side (survives reload). Resolve the replied message by '
        '"replyToMsgId" or a UNIQUE "replyToText". The quote is NOT sent to the '
        'peer (Tox carries plain text). Read back via '
        'l3_dump_state.messages[].cloudCustomData.',
    inputSchema: ObjectSchema(
      properties: {
        'text': StringSchema(description: 'The reply body text.'),
        'replyToMsgId': StringSchema(
          description: 'msgID of the replied message (or use replyToText).',
        ),
        'replyToText': StringSchema(
          description:
              'UNIQUE text of the replied message (resolver for gates).',
        ),
        'replyToIsSelf': StringSchema(
          description:
              'true|false: disambiguate replyToText to the self/inbound copy '
              '(a running echo peer mirrors a self text back).',
        ),
        'userId': StringSchema(
          description:
              'C2C target (bare or c2c_); defaults to the active chat.',
        ),
      },
    ),
  ),
);

/// S17: FORWARD a message — resolve a source message (by UNIQUE `sourceText`)
/// in one conversation and re-send its text to a target conversation. Mirrors
/// toxee's individual-forward (clone + re-send; a text forward carries NO extra
/// metadata, matching the product — this is NOT faked with a forward marker).
/// MUTATING — test/seed account, C2C only. `fromUserId` defaults to the active
/// chat; `toUserId` defaults to `fromUserId` (forward within the same chat).
MCPCallEntry _l3ForwardMessageEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_forward_message: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_forward_message: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    final sourceText = (request['sourceText'] ?? '').toString();
    if (sourceText.isEmpty) {
      return MCPCallResult(
        message:
            'l3_forward_message: need "sourceText" (the message to forward)',
        parameters: {'ok': false, 'error': 'missing_source_text'},
      );
    }
    String norm(String id) {
      var v = id.trim();
      if (v.startsWith('c2c_')) v = v.substring(4);
      return v;
    }

    var fromUserId = norm((request['fromUserId'] ?? '').toString());
    if (fromUserId.isEmpty) fromUserId = ffi.activePeerId ?? '';
    var toUserId = norm((request['toUserId'] ?? '').toString());
    if (toUserId.isEmpty) toUserId = fromUserId;
    if ((request['fromUserId']?.toString().startsWith('group_') ?? false) ||
        (request['toUserId']?.toString().startsWith('group_') ?? false)) {
      return MCPCallResult(
        message: 'l3_forward_message: C2C only',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    if (fromUserId.isEmpty || toUserId.isEmpty) {
      return MCPCallResult(
        message:
            'l3_forward_message: no source/target — pass fromUserId/toUserId',
        parameters: {'ok': false, 'error': 'no_target'},
      );
    }
    for (final g in [fromUserId, toUserId]) {
      final reject = await _rejectIfGroupTarget(
        'l3_forward_message',
        g,
        ffi.knownGroups,
        ffi.quitGroups,
      );
      if (reject != null) return reject;
    }
    // Resolve the source message (prove it exists + is unambiguous) before
    // re-sending its text — that resolution is the "forward". An echo peer
    // mirrors a self text back inbound, so allow an isSelf disambiguator.
    var matches = ffi
        .getHistory(fromUserId)
        .where((m) => m.text == sourceText)
        .toList();
    final sourceIsSelf = request['sourceIsSelf'];
    if (sourceIsSelf != null) {
      final wantSelf = sourceIsSelf.toString().toLowerCase() == 'true';
      matches = matches.where((m) => m.isSelf == wantSelf).toList();
    }
    if (matches.isEmpty) {
      return MCPCallResult(
        message: 'l3_forward_message: source "$sourceText" not found',
        parameters: {'ok': false, 'error': 'source_not_found'},
      );
    }
    if (matches.length > 1) {
      return MCPCallResult(
        message:
            'l3_forward_message: source "$sourceText" is ambiguous '
            '(${matches.length}) — use a unique text',
        parameters: {'ok': false, 'error': 'ambiguous_source'},
      );
    }
    try {
      await ffi.sendText(toUserId, matches.first.text);
      AppLogger.info(
        '[L3] l3_forward_message: forwarded "$sourceText" '
        '${fromUserId.substring(0, fromUserId.length.clamp(0, 8))}.. -> '
        '${toUserId.substring(0, toUserId.length.clamp(0, 8))}..',
      );
      return MCPCallResult(
        message: 'forwarded',
        parameters: {
          'ok': true,
          'fromUserId': fromUserId,
          'toUserId': toUserId,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_forward_message failed', e, st);
      return MCPCallResult(
        message: 'l3_forward_message: failed: $e',
        parameters: {'ok': false, 'error': 'forward_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_forward_message',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING, C2C only): FORWARD a message '
        '— resolve a source by UNIQUE "sourceText" in "fromUserId" (default '
        'active) and re-send its text to "toUserId" (default = fromUserId). '
        'Faithful to toxee individual-forward (clone + re-send, no extra '
        'metadata). Assert via l3_dump_state.messages[] on the target.',
    inputSchema: ObjectSchema(
      properties: {
        'sourceText': StringSchema(
          description: 'UNIQUE text of the message to forward.',
        ),
        'sourceIsSelf': StringSchema(
          description:
              'true|false: disambiguate sourceText to the self/inbound copy.',
        ),
        'fromUserId': StringSchema(
          description: 'Source C2C conv (bare/c2c_); defaults to active.',
        ),
        'toUserId': StringSchema(
          description: 'Target C2C conv (bare/c2c_); defaults to fromUserId.',
        ),
      },
    ),
  ),
);

/// Inject one INBOUND C2C custom message via the FfiChatService ingestion seam.
/// The resulting V2TIM message is a real custom elem, which keeps the UIKit
/// message-menu Reply option available for real-UI automation.
MCPCallEntry _l3InjectC2cCustomEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_inject_c2c_custom: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_inject_c2c_custom: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }

    String norm(Object? value) {
      var id = value?.toString().trim() ?? '';
      if (id.startsWith('c2c_')) id = id.substring(4);
      return id;
    }

    var fromUserId = norm(
      request['fromUserId'] ?? request['userId'] ?? request['conversationId'],
    );
    if (fromUserId.isEmpty) fromUserId = ffi.activePeerId ?? '';
    final data = (request['data'] ?? request['customData'] ?? '').toString();
    if (fromUserId.isEmpty || data.isEmpty) {
      return MCPCallResult(
        message: 'l3_inject_c2c_custom: need "fromUserId" and "data"',
        parameters: {'ok': false, 'error': 'bad_args'},
      );
    }
    final groupReject = await _rejectIfGroupTarget(
      'l3_inject_c2c_custom',
      fromUserId,
      ffi.knownGroups,
      ffi.quitGroups,
    );
    if (groupReject != null) return groupReject;

    try {
      final ingested = ffi.ingestInboundC2cCustom(from: fromUserId, data: data);
      AppLogger.info(
        '[L3] l3_inject_c2c_custom: from=$fromUserId '
        'ingested=$ingested',
      );
      return MCPCallResult(
        message: ingested ? 'c2c custom ingested' : 'skipped (blocked)',
        parameters: {
          'ok': true,
          'ingested': ingested,
          'fromUserId': fromUserId,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_inject_c2c_custom failed', e, st);
      return MCPCallResult(
        message: 'l3_inject_c2c_custom: failed: $e',
        parameters: {'ok': false, 'error': 'inject_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_inject_c2c_custom',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING, C2C only): materialize one '
        'INBOUND custom message via the real FfiChatService C2C ingestion '
        'pipeline. data becomes customElem.data, so UIKit sees a real custom '
        'bubble suitable for Reply-menu automation.',
    inputSchema: ObjectSchema(
      properties: {
        'fromUserId': StringSchema(
          description:
              'Sender C2C user id (bare or c2c_). Defaults to active chat.',
        ),
        'data': StringSchema(description: 'customElem.data payload.'),
        'customData': StringSchema(description: 'Alias for data.'),
      },
    ),
  ),
);

/// SEED HARNESS: materialize one DELIVERED plain-text C2C bubble (inbound or
/// sender-side) without a peer — for the product-screenshot pipeline. Plain
/// text (not custom), so the chat renders a normal bubble.
MCPCallEntry _l3InjectC2cTextEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_inject_c2c_text: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_inject_c2c_text: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    String norm(Object? v) {
      var id = v?.toString().trim() ?? '';
      if (id.startsWith('c2c_')) id = id.substring(4);
      return id;
    }

    var userId = norm(request['userId'] ?? request['conversationId']);
    if (userId.isEmpty) userId = ffi.activePeerId ?? '';
    final text = (request['text'] ?? '').toString();
    if (userId.isEmpty || text.isEmpty) {
      return MCPCallResult(
        message: 'l3_inject_c2c_text: need "userId" and "text"',
        parameters: {'ok': false, 'error': 'bad_args'},
      );
    }
    final groupReject = await _rejectIfGroupTarget(
      'l3_inject_c2c_text',
      userId,
      ffi.knownGroups,
      ffi.quitGroups,
    );
    if (groupReject != null) return groupReject;
    final isSelf =
        (request['isSelf'] ?? 'false').toString().toLowerCase() == 'true';
    final epochMs = int.tryParse((request['epochMs'] ?? '').toString());
    try {
      final ingested = ffi.ingestC2cText(
        peer: userId,
        text: text,
        isSelf: isSelf,
        epochMs: epochMs,
      );
      return MCPCallResult(
        message: ingested ? 'c2c text ingested' : 'skipped (blocked)',
        parameters: {
          'ok': true,
          'ingested': ingested,
          'userId': userId,
          'isSelf': isSelf,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_inject_c2c_text failed', e, st);
      return MCPCallResult(
        message: 'l3_inject_c2c_text: failed: $e',
        parameters: {'ok': false, 'error': 'inject_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_inject_c2c_text',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING, C2C only): materialize one '
        'DELIVERED plain-text C2C bubble via the FfiChatService ingestion '
        'pipeline WITHOUT a peer. isSelf=false (default) → inbound from userId '
        '(bumps unread when the chat is inactive); isSelf=true → sender-side '
        'delivered bubble (no unread, no offline "sending" state). Pass epochMs '
        'to order a scripted back-and-forth.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(
          description:
              'Conversation peer (bare or c2c_). Defaults to active chat.',
        ),
        'text': StringSchema(description: 'Bubble text.'),
        'isSelf': StringSchema(
          description: 'true = sender-side delivered; false (default) = inbound.',
        ),
        'epochMs': StringSchema(
          description: 'Optional epoch millis to control ordering.',
        ),
      },
    ),
  ),
);

/// SEED HARNESS: add a confirmed local friend by public key (tox norequest add)
/// with a cached display name — so a seeded C2C / group conversation renders a
/// real name instead of the raw key, with no real handshake. Idempotent.
MCPCallEntry _l3SeedFriendEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_seed_friend: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_seed_friend: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    final userId = (request['userId'] ?? '').toString().trim();
    final nickname = (request['nickname'] ?? '').toString().trim();
    if (userId.isEmpty) {
      return MCPCallResult(
        message: 'l3_seed_friend: need "userId"',
        parameters: {'ok': false, 'error': 'missing_user_id'},
      );
    }
    if (userId.startsWith('group_')) {
      return MCPCallResult(
        message: 'l3_seed_friend: groups unsupported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    try {
      // Idempotent: only norequest-add when this pubkey isn't already a friend
      // (a re-add returns TOX_ERR_FRIEND_ADD_ALREADY_SENT → acceptFriend throws).
      final pk = _toxIdPublicKey(userId);
      final friends = await ffi.getFriendList();
      final exists = friends.any((f) => _toxIdPublicKey(f.userId) == pk);
      if (!exists) {
        // acceptFriendRequest() → tox_friend_add_norequest(public_key): adds a
        // friend by key with no incoming request required
        // (AcceptFriendApplication never consults a queue), so this works for a
        // fully synthetic peer.
        await ffi.acceptFriendRequest(userId);
      }
      if (nickname.isNotEmpty) {
        await ffi.seedLocalFriendNickname(userId, nickname);
      }
      await FakeUIKit.instance.im?.refreshContacts();
      await FakeUIKit.instance.im?.refreshConversations();
      AppLogger.info(
        '[L3] l3_seed_friend: ${exists ? 'updated' : 'added'} '
        '${pk.substring(0, pk.length.clamp(0, 16))} as "$nickname"',
      );
      return MCPCallResult(
        message: 'friend seeded',
        parameters: {
          'ok': true,
          'userId': userId,
          'nickname': nickname,
          'alreadyFriend': exists,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_seed_friend failed', e, st);
      return MCPCallResult(
        message: 'l3_seed_friend: failed: $e',
        parameters: {'ok': false, 'error': 'seed_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_seed_friend',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): add a confirmed local '
        'friend by public key via tox_friend_add_norequest (no handshake) and '
        'cache its display name, so a seeded conversation renders a real name. '
        'Idempotent — re-runs only refresh the cached nickname.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(description: 'Friend Tox ID / public key.'),
        'nickname': StringSchema(description: 'Display name to cache.'),
      },
      required: ['userId'],
    ),
  ),
);

/// SEED HARNESS: materialize a pending INBOUND friend application (New-Friends
/// page) without a peer, optionally with the applicant's display name.
MCPCallEntry _l3InjectFriendApplicationEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_inject_friend_application: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_inject_friend_application: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    final userId = (request['userId'] ?? '').toString().trim();
    final nickname = (request['nickname'] ?? '').toString().trim();
    final wording = (request['wording'] ?? '').toString();
    if (userId.isEmpty) {
      return MCPCallResult(
        message: 'l3_inject_friend_application: need "userId"',
        parameters: {'ok': false, 'error': 'missing_user_id'},
      );
    }
    if (userId.startsWith('group_')) {
      return MCPCallResult(
        message: 'l3_inject_friend_application: groups unsupported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    try {
      ffi.seedFriendApplication(
        userId: userId,
        wording: wording.isEmpty ? 'Hi! Add me on Tox?' : wording,
        nickName: nickname.isEmpty ? null : nickname,
      );
      // The New-Contacts list queries getFriendApplicationList on open; the
      // contacts badge picks it up on the next 5s steady poll. Nudge contacts
      // so the badge updates promptly too.
      await FakeUIKit.instance.im?.refreshContacts();
      AppLogger.info(
        '[L3] l3_inject_friend_application: seeded '
        '${userId.substring(0, userId.length.clamp(0, 16))} ("$nickname")',
      );
      return MCPCallResult(
        message: 'friend application seeded',
        parameters: {'ok': true, 'userId': userId, 'nickname': nickname},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_inject_friend_application failed', e, st);
      return MCPCallResult(
        message: 'l3_inject_friend_application: failed: $e',
        parameters: {'ok': false, 'error': 'inject_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_inject_friend_application',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): materialize one pending '
        'INBOUND friend application (the New-Friends page) without a peer. '
        'Optional "nickname" sets the applicant display name (Tox requests '
        'carry none); "wording" is the request message.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(description: 'Applicant Tox ID / public key.'),
        'nickname': StringSchema(description: 'Applicant display name.'),
        'wording': StringSchema(description: 'Request message.'),
      },
      required: ['userId'],
    ),
  ),
);

/// Navigation-stability hook: open the self-profile page (Tox ID + QR) through
/// the SAME layout-aware showSelfProfile() the user-avatar tap uses (right pane
/// on desktop/tablet, fullscreen route on phones). UNGATED like l3_open_chat.
MCPCallEntry _l3OpenSelfProfileEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_open_self_profile: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    final invoker = _l3OpenSelfProfileInvoker;
    if (invoker == null) {
      return MCPCallResult(
        message: 'l3_open_self_profile: invoker not registered',
        parameters: {'ok': false, 'error': 'invoker_not_registered'},
      );
    }
    final opened = await invoker();
    AppLogger.info(
      '[L3] l3_open_self_profile: ${opened ? 'opened' : 'FAILED to open'}',
    );
    return MCPCallResult(
      message: opened ? 'self profile opened' : 'l3_open_self_profile failed',
      parameters: {'ok': opened},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_open_self_profile',
    description:
        'Navigation-stability hook: open the self-profile page (Tox ID + QR) '
        'via the layout-aware showSelfProfile() the avatar tap uses. Works on '
        'desktop/tablet (right pane) and phones (fullscreen route).',
    inputSchema: ObjectSchema(properties: {}),
  ),
);

/// Navigation-stability hook: pop every pushed route / dialog back to the
/// HomePage root (the mobile message route, the profile route/modal, desktop
/// dialogs). Layout-agnostic — lets the screenshot pipeline re-navigate from a
/// known state between scenes on phones (where l3_force_home_root only swaps
/// the tab and does not pop the UIKit-pushed route).
MCPCallEntry _l3PopToRootEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final invoker = _l3PopToRootInvoker;
    if (invoker == null) {
      return MCPCallResult(
        message: 'l3_pop_to_root: invoker not registered',
        parameters: {'ok': false, 'error': 'invoker_not_registered'},
      );
    }
    final ok = await invoker();
    return MCPCallResult(
      message: ok ? 'popped to root' : 'l3_pop_to_root failed',
      parameters: {'ok': ok},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_pop_to_root',
    description:
        'Navigation-stability hook: pop all pushed routes / dialogs back to the '
        'HomePage root (mobile message/profile routes, desktop modals). '
        'Layout-agnostic; use between screenshot scenes on phones.',
    inputSchema: ObjectSchema(properties: {}),
  ),
);

MCPCallEntry _l3SendTextEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final text = request['text'] ?? '';
    if (text.isEmpty) {
      return MCPCallResult(
        message: 'l3_send_text: missing required "text"',
        parameters: {'ok': false, 'error': 'missing_text'},
      );
    }
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message:
            'l3_send_text: refused — active account is not a '
            'test/seed account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    final provider = FakeUIKit.instance.messageProvider;
    if (ffi == null || provider == null) {
      return MCPCallResult(
        message: 'l3_send_text: session not ready (no ffi/provider)',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    // Resolve the target: explicit userId/conversationId param, else the
    // active conversation peer. This tool is C2C-only — reject group ids.
    var userId = request['userId'] ?? request['conversationId'] ?? '';
    if (userId.startsWith('group_') || request['groupId'] != null) {
      return MCPCallResult(
        message: 'l3_send_text: C2C only — group sends are not supported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    if (userId.startsWith('c2c_')) userId = userId.substring(4);
    if (userId.isEmpty) userId = ffi.activePeerId ?? '';
    if (userId.isEmpty) {
      return MCPCallResult(
        message:
            'l3_send_text: no target — pass "userId" or open a '
            'conversation first',
        parameters: {'ok': false, 'error': 'no_target'},
      );
    }
    final groupReject = await _rejectIfGroupTarget(
      'l3_send_text',
      userId,
      ffi.knownGroups,
      ffi.quitGroups,
    );
    if (groupReject != null) return groupReject;
    try {
      await provider.sendText(userID: userId, text: text);
      AppLogger.info(
        '[L3] l3_send_text: sent "$text" to $userId (service send path)',
      );
      return MCPCallResult(
        message: 'sent',
        parameters: {'ok': true, 'userId': userId, 'text': text},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_send_text failed', e, st);
      return MCPCallResult(
        message: 'l3_send_text: send failed: $e',
        parameters: {'ok': false, 'error': 'send_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_send_text',
    description:
        'L3 TEST ONLY: deterministically send a C2C text message '
        'through the real app send path (bypasses the un-driveable '
        'Enter-to-send composer gesture). Targets the given userId/Tox ID, '
        'or the currently open conversation if omitted.',
    inputSchema: ObjectSchema(
      properties: {
        'text': StringSchema(description: 'Message text to send'),
        'userId': StringSchema(
          description:
              'Target Tox ID (64 or 76 hex). Optional — '
              'defaults to the active conversation peer.',
        ),
        'conversationId': StringSchema(
          description:
              'Alternative to userId: a c2c_<toxId> '
              'conversation id. group_* is rejected (C2C only).',
        ),
      },
      required: ['text'],
    ),
  ),
);

MCPCallEntry _l3RegisterAccountEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final nickname = request['nickname']?.toString().trim() ?? '';
    final statusMessage = request['statusMessage']?.toString().trim() ?? '';
    final password = request['password']?.toString() ?? '';
    if (nickname.isEmpty) {
      return MCPCallResult(
        message: 'l3_register_account: need "nickname"',
        parameters: {'ok': false, 'error': 'missing_nickname'},
      );
    }
    // Any nickname is allowed here: the account is a disposable seed account
    // BY CONSTRUCTION (this register path only exists on the debug L3
    // surface), and the persistent SEED-ACCOUNT MARKER written below — not
    // the nickname — is what grants subsequent mutating-tool access. This
    // lets screenshot/demo personas use realistic display names.
    try {
      final currentService = FakeUIKit.instance.im?.ffi;
      if (currentService != null) {
        final existing = await Prefs.getCurrentAccountToxId();
        return MCPCallResult(
          message: 'l3_register_account: session already ready',
          parameters: {
            'ok': true,
            'nickname': nickname,
            'toxId': existing,
            'alreadyReady': true,
          },
        );
      }
      final result = await AccountService.registerNewAccount(
        nickname: nickname,
        statusMessage: statusMessage,
        password: password,
      );
      // SEED-ACCOUNT MARKER: persist before boot so the account passes
      // _activeAccountIsTest() from its very first mutating call.
      await Prefs.addL3SeedToxId(result.toxId);
      await AppBootstrapCoordinator.boot(result.service);
      await navigateToHomeIfPossible(result.service);
      AppLogger.info(
        '[L3] l3_register_account: registered $nickname '
        'toxId=${result.toxId} (seed-marker recorded)',
      );
      return MCPCallResult(
        message: 'account registered',
        parameters: {
          'ok': true,
          'nickname': nickname,
          'toxId': result.toxId,
          'profileDirectory': result.profileDirectory,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_register_account failed', e, st);
      return MCPCallResult(
        message: 'l3_register_account: failed: $e',
        parameters: {'ok': false, 'error': 'register_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_register_account',
    description:
        'L3 TEST ONLY: register and boot a new test account without driving '
        'RegisterPage UI. Any nickname is allowed — the new toxId is recorded '
        'in the persistent seed-account marker (Prefs.l3SeedToxIds), which is '
        'what authorizes later mutating l3 tools on this account.',
    inputSchema: ObjectSchema(
      properties: {
        'nickname': StringSchema(description: 'Test nickname to register.'),
        'statusMessage': StringSchema(description: 'Optional status message.'),
        'password': StringSchema(description: 'Optional account password.'),
      },
      required: ['nickname'],
    ),
  ),
);

MCPCallEntry _l3BootExistingAccountEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final toxId = request['toxId']?.toString().trim() ?? '';
    final nickname = request['nickname']?.toString().trim() ?? '';
    final statusMessage = request['statusMessage']?.toString().trim() ?? '';
    final password = request['password']?.toString();
    if (toxId.isEmpty || nickname.isEmpty) {
      return MCPCallResult(
        message: 'l3_boot_existing_account: need "toxId" and "nickname"',
        parameters: {'ok': false, 'error': 'missing_args'},
      );
    }
    // Boot is allowed for an account carrying the persistent seed-account
    // marker (the authoritative identity — created via l3_register_account;
    // this is the path the screenshot pipeline uses, checked against the
    // REQUESTED toxId since no account is active yet) OR via a reserved
    // fixture nickname. The nickname path is a PRE-EXISTING, load-bearing
    // affordance: ~20 fixture-C drivers restore `echo_live_test` from a
    // manifest whose random toxId has no known prefix and (after a defaults
    // wipe) no marker. It is safe only because the WHOLE surface is
    // kDebugMode + TOXEE_L3_TEST gated and the nicknames are exact reserved
    // sentinels. (codex: dropped the redundant toxId-prefix OR I had added —
    // booting echo_seeded already goes through its `echo_seeded_test`
    // nickname, so the prefix branch added reach without adding safety.)
    final isReservedFixtureNick = _kTestNicknames.contains(
      nickname.toLowerCase().trim(),
    );
    if (!isReservedFixtureNick && !await _isL3SeedToxId(toxId)) {
      return MCPCallResult(
        message:
            'l3_boot_existing_account: toxId is not an L3-registered seed '
            'account and nickname is not a reserved fixture',
        parameters: {'ok': false, 'error': 'not_seed_account'},
      );
    }
    try {
      final currentService = FakeUIKit.instance.im?.ffi;
      if (currentService != null) {
        final existing = await Prefs.getCurrentAccountToxId();
        return MCPCallResult(
          message: 'l3_boot_existing_account: session already ready',
          parameters: {
            'ok': true,
            'toxId': existing,
            'nickname': nickname,
            'alreadyReady': true,
          },
        );
      }
      final service = await AccountService.initializeServiceForAccount(
        toxId: toxId,
        nickname: nickname,
        statusMessage: statusMessage,
        password: password,
        startPolling: false,
      );
      await AppBootstrapCoordinator.boot(service);
      await navigateToHomeIfPossible(service);
      await Prefs.addAccount(
        toxId: toxId,
        nickname: nickname,
        statusMessage: statusMessage,
      );
      AppLogger.info(
        '[L3] l3_boot_existing_account: booted $nickname toxId=$toxId',
      );
      return MCPCallResult(
        message: 'existing account booted',
        parameters: {'ok': true, 'toxId': toxId, 'nickname': nickname},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_boot_existing_account failed', e, st);
      return MCPCallResult(
        message: 'l3_boot_existing_account: failed: $e',
        parameters: {'ok': false, 'error': 'boot_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_boot_existing_account',
    description:
        'L3 TEST ONLY: boot an existing test account from a known toxId/profile '
        'without driving LoginPage UI. The toxId must be a legacy fixture '
        'account or carry the seed-account marker (registered via '
        'l3_register_account).',
    inputSchema: ObjectSchema(
      properties: {
        'toxId': StringSchema(description: 'Existing account toxId.'),
        'nickname': StringSchema(description: 'Display nickname to persist.'),
        'statusMessage': StringSchema(description: 'Optional status message.'),
        'password': StringSchema(description: 'Optional account password.'),
      },
      required: ['toxId', 'nickname'],
    ),
  ),
);

MCPCallEntry _l3AddFriendRequestEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final userId = request['userId']?.toString().trim() ?? '';
    final message = request['message']?.toString().trim();
    if (userId.isEmpty) {
      return MCPCallResult(
        message: 'l3_add_friend_request: need "userId"',
        parameters: {'ok': false, 'error': 'missing_user_id'},
      );
    }
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_add_friend_request: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_add_friend_request: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    if (userId.startsWith('group_')) {
      return MCPCallResult(
        message: 'l3_add_friend_request: groups unsupported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    try {
      final result = await ffi.addFriend(
        userId,
        requestMessage: (message != null && message.isNotEmpty)
            ? message
            : null,
      );
      if (!result.isSuccess) {
        return MCPCallResult(
          message:
              'l3_add_friend_request: addFriend failed: '
              '${result.resultInfo.isNotEmpty ? result.resultInfo : result.resultCode}',
          parameters: {
            'ok': false,
            'error': 'add_friend_failed',
            'resultCode': result.resultCode,
            'resultInfo': result.resultInfo,
          },
        );
      }
      FakeUIKit.instance.im?.registerPendingFriendAdd(userId);
      await FakeUIKit.instance.im?.refreshContacts();
      AppLogger.info('[L3] l3_add_friend_request: sent request to $userId');
      return MCPCallResult(
        message: 'friend request sent',
        parameters: {'ok': true, 'userId': userId},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_add_friend_request failed', e, st);
      return MCPCallResult(
        message: 'l3_add_friend_request: failed: $e',
        parameters: {'ok': false, 'error': 'request_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_add_friend_request',
    description:
        'L3 TEST ONLY: send a friend request to the given userId through the '
        'real FFI/service path, then refresh local contacts. Useful for '
        'Fixture C / friend-handshake scenarios without driving AddFriendDialog UI.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(
          description: 'Target peer Tox ID (64 or 76 hex).',
        ),
        'message': StringSchema(
          description: 'Optional custom friend request message.',
        ),
      },
      required: ['userId'],
    ),
  ),
);

MCPCallEntry _l3StartCallEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final userId = request['userId']?.toString().trim() ?? '';
    final video = request['video']?.toString().toLowerCase().trim() == 'true';
    if (userId.isEmpty) {
      return MCPCallResult(
        message: 'l3_start_call: need "userId"',
        parameters: {'ok': false, 'error': 'missing_user_id'},
      );
    }
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_start_call: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final adapter = getTUICallKitAdapter();
    if (adapter == null) {
      return MCPCallResult(
        message: 'l3_start_call: call adapter not ready',
        parameters: {'ok': false, 'error': 'call_adapter_not_ready'},
      );
    }
    try {
      final ok = await adapter.handleCall(
        type: video ? TYPE_VIDEO : TYPE_AUDIO,
        userids: <String>[userId],
      );
      if (!ok) {
        return MCPCallResult(
          message: 'l3_start_call: adapter returned false',
          parameters: {'ok': false, 'error': 'call_failed'},
        );
      }
      AppLogger.info(
        '[L3] l3_start_call: started ${video ? "video" : "audio"} call to $userId',
      );
      return MCPCallResult(
        message: 'call started',
        parameters: {'ok': true, 'userId': userId, 'video': video},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_start_call failed', e, st);
      return MCPCallResult(
        message: 'l3_start_call: failed: $e',
        parameters: {'ok': false, 'error': 'call_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_start_call',
    description:
        'L3 TEST ONLY: initiate an outgoing C2C audio/video call via the real '
        'TUICallKitAdapter + signaling + ToxAV path.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(
          description: 'Target peer Tox ID (64 or 76 hex).',
        ),
        'video': StringSchema(description: 'true for video, else audio'),
      },
      required: ['userId'],
    ),
  ),
);

MCPCallEntry _l3CallActionEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_call_action: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final action = request['action']?.toString().trim().toLowerCase() ?? '';
    final manager = FakeUIKit.instance.callServiceManager;
    if (manager == null) {
      return MCPCallResult(
        message: 'l3_call_action: call manager not ready',
        parameters: {'ok': false, 'error': 'call_manager_not_ready'},
      );
    }
    try {
      switch (action) {
        case 'accept':
          await manager.acceptCall();
          break;
        case 'reject':
          await manager.rejectCall();
          break;
        case 'hangup':
          await manager.hangUp();
          break;
        case 'mute':
          await manager.toggleMute();
          break;
        case 'video':
          await manager.toggleVideo();
          break;
        case 'network_drop':
          // S69: there is no ToxAV peer-offline callback, so killing the peer
          // does not auto-end an established call. Drive the reconnect path
          // directly: markReconnecting() sets isReconnecting=true and starts
          // the 8s grace timer, after which the call ends (endReason
          // network_error). The driver asserts isReconnecting then state=ended.
          manager.markReconnecting();
          break;
        default:
          return MCPCallResult(
            message: 'l3_call_action: unsupported action "$action"',
            parameters: {'ok': false, 'error': 'unsupported_action'},
          );
      }
      AppLogger.info('[L3] l3_call_action: $action');
      return MCPCallResult(
        message: 'call action $action applied',
        parameters: {'ok': true, 'action': action},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_call_action failed', e, st);
      return MCPCallResult(
        message: 'l3_call_action: failed: $e',
        parameters: {
          'ok': false,
          'error': 'call_action_failed',
          'detail': '$e',
        },
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_call_action',
    description:
        'L3 TEST ONLY: perform a call action on the active call: accept, '
        'reject, hangup, mute, or video.',
    inputSchema: ObjectSchema(
      properties: {
        'action': StringSchema(
          description: 'accept | reject | hangup | mute | video | network_drop',
        ),
      },
      required: ['action'],
    ),
  ),
);

/// Message-action hook (plan item 3, codex's preferred `invokeAction` form):
/// invoke a message context-menu action by msgID WITHOUT the un-driveable
/// long-press → menu gesture. Covers the deterministic side-effect actions
/// `delete` (→ provider.deleteMessages) and `copy` (→ OS clipboard, verifiable
/// via `pbpaste`). `reply`/`forward` are structured flows that get their own
/// tools (`l3_reply_text`/`l3_forward_message`) — NOT folded in here. Verifying
/// the menu *surface* itself (S15) still needs the real menu UI and is out of
/// scope for this tool.
MCPCallEntry _l3InvokeMessageActionEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_invoke_message_action: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final msgId = request['msgId'] ?? request['msgID'] ?? '';
    final action = (request['action'] ?? '').toLowerCase();
    if (msgId.isEmpty || action.isEmpty) {
      return MCPCallResult(
        message: 'l3_invoke_message_action: need "msgId" and "action"',
        parameters: {'ok': false, 'error': 'missing_args'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    final provider = FakeUIKit.instance.messageProvider;
    if (ffi == null || provider == null) {
      return MCPCallResult(
        message: 'l3_invoke_message_action: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var userId = request['userId'] ?? request['conversationId'] ?? '';
    if (userId.startsWith('group_') || request['groupId'] != null) {
      return MCPCallResult(
        message: 'l3_invoke_message_action: C2C only — group unsupported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    if (userId.startsWith('c2c_')) userId = userId.substring(4);
    if (userId.isEmpty) userId = ffi.activePeerId ?? '';
    if (userId.isEmpty) {
      return MCPCallResult(
        message: 'l3_invoke_message_action: no target conversation',
        parameters: {'ok': false, 'error': 'no_target'},
      );
    }
    final groupReject = await _rejectIfGroupTarget(
      'l3_invoke_message_action',
      userId,
      ffi.knownGroups,
      ffi.quitGroups,
    );
    if (groupReject != null) return groupReject;
    try {
      switch (action) {
        case 'delete':
          // codex P2: pre-validate existence (covers unknown msgId AND
          // wrong-conversation), else a no-op delete falsely reports ok.
          // Mirrors copy's existence check. Then delete + verify gone.
          final present = ffi
              .getHistory(userId)
              .any((m) => m.msgID == msgId || m.altMsgIds.contains(msgId));
          if (!present) {
            return MCPCallResult(
              message:
                  'l3_invoke_message_action: delete no-op — msgId not '
                  'found in conversation $userId',
              parameters: {'ok': false, 'error': 'msg_not_found'},
            );
          }
          await provider.deleteMessages(userID: userId, msgIDs: [msgId]);
          final stillThere = ffi
              .getHistory(userId)
              .any((m) => m.msgID == msgId || m.altMsgIds.contains(msgId));
          if (stillThere) {
            return MCPCallResult(
              message:
                  'l3_invoke_message_action: delete did not remove '
                  'the message',
              parameters: {'ok': false, 'error': 'delete_failed'},
            );
          }
          break;
        case 'copy':
          final msg = ffi
              .getHistory(userId)
              .where((m) => m.msgID == msgId || m.altMsgIds.contains(msgId))
              .toList();
          if (msg.isEmpty) {
            return MCPCallResult(
              message: 'l3_invoke_message_action: msgId not found',
              parameters: {'ok': false, 'error': 'msg_not_found'},
            );
          }
          // codex P2: text-only. A media message has no menu "Copy text".
          if ((msg.first.mediaKind ?? '').isNotEmpty) {
            return MCPCallResult(
              message:
                  'l3_invoke_message_action: copy is text-only '
                  '(mediaKind=${msg.first.mediaKind})',
              parameters: {'ok': false, 'error': 'not_text'},
            );
          }
          await Clipboard.setData(ClipboardData(text: msg.first.text));
          break;
        default:
          return MCPCallResult(
            message:
                'l3_invoke_message_action: unsupported action '
                '"$action" (supported: delete, copy)',
            parameters: {'ok': false, 'error': 'unsupported_action'},
          );
      }
      AppLogger.info(
        '[L3] l3_invoke_message_action: $action on $msgId ($userId)',
      );
      return MCPCallResult(
        message: 'invoked $action',
        parameters: {'ok': true, 'action': action, 'msgId': msgId},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_invoke_message_action failed', e, st);
      return MCPCallResult(
        message: 'l3_invoke_message_action: failed: $e',
        parameters: {'ok': false, 'error': 'action_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_invoke_message_action',
    description:
        'L3 TEST ONLY: invoke a message context-menu action by '
        'msgId without the long-press gesture. Supported actions: '
        'delete, copy. Targets userId/conversationId or the active conv.',
    inputSchema: ObjectSchema(
      properties: {
        'msgId': StringSchema(description: 'Target message msgID'),
        'action': StringSchema(description: 'delete | copy'),
        'userId': StringSchema(
          description: 'Conversation Tox ID. Optional — active conv.',
        ),
        'conversationId': StringSchema(
          description: 'c2c_<toxId> alternative to userId.',
        ),
      },
      required: ['msgId', 'action'],
    ),
  ),
);

/// Per-scenario reset (plan item 6): clear one C2C conversation's history so a
/// runner can isolate scenarios without a full seed restore + relaunch. Keeps
/// the friend + conversation, but also clears the ACTIVE conversation when the
/// cleared peer is currently active so the next scenario does not inherit a
/// "chat already open/read" state that can suppress unread assertions. Test/
/// seed account only.
MCPCallEntry _l3ClearHistoryEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_clear_history: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_clear_history: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var userId = request['userId'] ?? request['conversationId'] ?? '';
    if (userId.startsWith('group_') || request['groupId'] != null) {
      return MCPCallResult(
        message: 'l3_clear_history: C2C only — group ids unsupported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    if (userId.startsWith('c2c_')) userId = userId.substring(4);
    if (userId.isEmpty) userId = ffi.activePeerId ?? '';
    if (userId.isEmpty) {
      return MCPCallResult(
        message: 'l3_clear_history: no target — pass userId',
        parameters: {'ok': false, 'error': 'no_target'},
      );
    }
    final groupReject = await _rejectIfGroupTarget(
      'l3_clear_history',
      userId,
      ffi.knownGroups,
      ffi.quitGroups,
    );
    if (groupReject != null) return groupReject;
    try {
      await ffi.clearC2CHistory(userId);
      if (ffi.activePeerId == userId) {
        ffi.setActivePeer(null);
      }
      AppLogger.info('[L3] l3_clear_history: cleared $userId');
      return MCPCallResult(
        message: 'cleared',
        parameters: {'ok': true, 'userId': userId},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_clear_history failed', e, st);
      return MCPCallResult(
        message: 'l3_clear_history: failed: $e',
        parameters: {'ok': false, 'error': 'clear_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_clear_history',
    description:
        'L3 TEST ONLY: clear one C2C conversation\'s message '
        'history (per-scenario reset). Friend/conversation preserved. '
        'Targets userId/conversationId, or the active conversation.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(description: 'Target Tox ID (64/76 hex).'),
        'conversationId': StringSchema(
          description: 'c2c_<toxId> alternative to userId.',
        ),
      },
    ),
  ),
);

MCPCallEntry _l3ClearActiveConversationEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_clear_active_conversation: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_clear_active_conversation: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    final previousConversationId =
        UikitDataFacade.currentConversation?.conversationID;
    final previousActivePeerId = ffi.activePeerId;
    ffi.setActivePeer(null);
    UikitDataFacade.currentConversation = null;
    AppLogger.info(
      '[L3] l3_clear_active_conversation: cleared '
      '${previousConversationId ?? previousActivePeerId ?? 'none'}',
    );
    return MCPCallResult(
      message: 'cleared active conversation',
      parameters: {
        'ok': true,
        'previousConversationId': previousConversationId,
        'previousActivePeerId': previousActivePeerId,
      },
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_clear_active_conversation',
    description:
        'L3 TEST ONLY: clear the currently selected conversation from the '
        'desktop shell without mutating history or friendship state.',
    inputSchema: ObjectSchema(properties: {}),
  ),
);

MCPCallEntry _l3ForceHomeRootEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_force_home_root: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final currentService = FakeUIKit.instance.im?.ffi;
    if (currentService == null) {
      return MCPCallResult(
        message: 'l3_force_home_root: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    final previousConversationId =
        UikitDataFacade.currentConversation?.conversationID;
    final previousActivePeerId = currentService.activePeerId;
    final targetTab =
        request['tab']?.toString().trim().toLowerCase() ?? 'chats';
    currentService.setActivePeer(null);
    UikitDataFacade.currentConversation = null;
    final shellApplier = _l3HomeShellApplier;
    if (shellApplier != null) {
      await shellApplier(targetTab);
    } else {
      final navigated = await navigateToHomeIfPossible(currentService);
      if (!navigated) {
        return MCPCallResult(
          message: 'l3_force_home_root: navigator not ready',
          parameters: {'ok': false, 'error': 'navigator_not_ready'},
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await FakeUIKit.instance.im?.refreshConversations();
    await FakeUIKit.instance.im?.refreshContacts();
    AppLogger.info(
      '[L3] l3_force_home_root: restored HomePage '
      'tab=$targetTab '
      '(previousConversation=${previousConversationId ?? 'none'}, '
      'previousActivePeer=${previousActivePeerId ?? 'none'})',
    );
    return MCPCallResult(
      message: 'forced HomePage root',
      parameters: {
        'ok': true,
        'tab': targetTab,
        'previousConversationId': previousConversationId,
        'previousActivePeerId': previousActivePeerId,
      },
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_force_home_root',
    description:
        'L3 TEST ONLY: rebuild the current session back onto the desktop '
        'HomePage root, clearing any active conversation selection first. '
        'Optional tab: chats | contacts | applications | settings.',
    inputSchema: ObjectSchema(
      properties: {
        'tab': StringSchema(
          description:
              'Optional target tab after recovery: chats | contacts | '
              'applications | settings. Default: chats.',
        ),
      },
    ),
  ),
);

MCPCallEntry _l3OpenAddFriendDialogEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_open_add_friend_dialog: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    final invoker = _l3OpenAddFriendDialogInvoker;
    if (invoker == null) {
      return MCPCallResult(
        message: 'l3_open_add_friend_dialog: invoker not registered',
        parameters: {'ok': false, 'error': 'invoker_not_registered'},
      );
    }
    final opened = await invoker();
    return MCPCallResult(
      message: opened
          ? 'add friend dialog opened'
          : 'add friend dialog unavailable',
      parameters: {'ok': opened},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_open_add_friend_dialog',
    description:
        'Open the real AddFriendDialog from the current HomePage session '
        'without relying on the Contacts app-bar entry point. Intended only '
        'as a navigation-stability harness hook; the dialog itself is still '
        'filled and submitted through real UI.',
    inputSchema: ObjectSchema(properties: {}),
  ),
);

/// Open a C2C (`userId`) or group (`groupId`) chat by driving the SAME
/// production `_openChat` path the conversation row / contact-profile
/// "Send Message" tile uses (switches to the Chats tab and binds the desktop
/// master-detail right pane; the production `_selectConversation` synthesizes a
/// conversation when none is listed yet, so this opens the FIRST chat with no
/// row). UNGATED — a navigation-stability hook (like l3_open_add_friend_dialog /
/// l3_open_add_group_dialog), NOT the asserted action: the message send / menu /
/// recall the case verifies is still a real widget gesture. Exists because the
/// multi-tap contacts→profile→Send-Message dance is unreliable under 2-process
/// foreground contention, which gated the first-chat-open of every chat sweep.
MCPCallEntry _l3OpenChatEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_open_chat: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    final rawUser = request['userId']?.toString().trim() ?? '';
    final rawGroup = request['groupId']?.toString().trim() ?? '';
    final hasUser = rawUser.isNotEmpty;
    final hasGroup = rawGroup.isNotEmpty;
    if (hasUser == hasGroup) {
      return MCPCallResult(
        message: 'l3_open_chat: exactly one of userId / groupId is required',
        parameters: {'ok': false, 'error': 'bad_args'},
      );
    }
    final invoker = _l3OpenChatInvoker;
    if (invoker == null) {
      return MCPCallResult(
        message: 'l3_open_chat: invoker not registered',
        parameters: {'ok': false, 'error': 'invoker_not_registered'},
      );
    }
    final opened = await invoker(
      userId: hasUser ? rawUser : null,
      groupId: hasGroup ? rawGroup : null,
    );
    final conversationId = hasGroup ? 'group_$rawGroup' : 'c2c_$rawUser';
    AppLogger.info(
      '[L3] l3_open_chat: ${opened ? 'opened' : 'FAILED to open'} '
      '$conversationId',
    );
    return MCPCallResult(
      message: opened ? 'opened chat $conversationId' : 'l3_open_chat failed',
      parameters: {'ok': opened, 'conversationId': conversationId},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_open_chat',
    description:
        'Navigation-stability hook: open the C2C (userId = friend pubkey) or '
        'group (groupId) chat through the production _openChat path the '
        'conversation row / profile Send-Message tile uses (flips to the Chats '
        'tab + binds the desktop master-detail right pane). Works for a FIRST '
        'chat with no conversation row yet. NOT the asserted action — the send '
        '/ menu / recall stays a real widget gesture. Exactly one of userId / '
        'groupId is required.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(
          description:
              'C2C peer public key / userID (the c2c_<userId> conversation). '
              'Mutually exclusive with groupId.',
        ),
        'groupId': StringSchema(
          description:
              'Group ID (the group_<groupId> conversation). Mutually '
              'exclusive with userId.',
        ),
      },
    ),
  ),
);

/// Push toxee's global search overlay (the SAME `CustomSearch` route the
/// Cmd/Ctrl+F shortcut opens, in global all-conversations mode). UNGATED —
/// a navigation-stability hook like l3_open_chat / l3_open_add_friend_dialog,
/// NOT the asserted action: the result tap + chat open the case verifies stay
/// real widget gestures. Exists because the macOS Cmd/Ctrl+F keystroke
/// (osascript) is occasionally dropped when the window isn't fully foregrounded
/// under 2-process contention, which flaked the global-search-open setup.
MCPCallEntry _l3OpenGlobalSearchEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final invoker = _l3OpenGlobalSearchInvoker;
    if (invoker == null) {
      return MCPCallResult(
        message: 'l3_open_global_search: invoker not registered',
        parameters: {'ok': false, 'error': 'invoker_not_registered'},
      );
    }
    final opened = await invoker();
    AppLogger.info(
      '[L3] l3_open_global_search: ${opened ? 'opened' : 'FAILED to open'}',
    );
    return MCPCallResult(
      message: opened ? 'opened global search' : 'l3_open_global_search failed',
      parameters: {'ok': opened},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_open_global_search',
    description:
        'Navigation-stability hook: push the global search overlay '
        '(CustomSearch in all-conversations mode) through the same route the '
        'Cmd/Ctrl+F shortcut uses, deterministically (no synthetic keystroke). '
        'NOT the asserted action — the result tap + chat open stay real '
        'gestures. Desktop master-detail layout only.',
    inputSchema: ObjectSchema(properties: {}),
  ),
);

/// Open the real AddGroupDialog (NOT test-account gated — like
/// l3_open_add_friend_dialog, this is a navigation-stability hook only; the
/// dialog itself is filled + submitted through real UI). Lets a fresh non-test
/// account (the handshake→group_message campaigns) create a group through the
/// REAL create UI instead of the gated l3_create_group.
MCPCallEntry _l3OpenAddGroupDialogEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_open_add_group_dialog: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    final invoker = _l3OpenAddGroupDialogInvoker;
    if (invoker == null) {
      return MCPCallResult(
        message: 'l3_open_add_group_dialog: invoker not registered',
        parameters: {'ok': false, 'error': 'invoker_not_registered'},
      );
    }
    final opened = await invoker();
    return MCPCallResult(
      message: opened
          ? 'add group dialog opened'
          : 'add group dialog unavailable',
      parameters: {'ok': opened},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_open_add_group_dialog',
    description:
        'Open the real AddGroupDialog from the current HomePage session. '
        'Navigation-stability harness hook only; the dialog is filled + '
        'submitted (name + type + Create) through real UI.',
    inputSchema: ObjectSchema(properties: {}),
  ),
);

/// Deep-link to the REAL group add-member screen for [groupId], skipping the
/// brittle chat→header-avatar→group-profile→add-member navigation hops. The
/// invite itself is still performed through the real UI: the harness selects a
/// contact (`add_member_contact_item:<userId>`) and taps the real confirm
/// button (`group_member_invite_confirm_button` → `inviteUserToGroup`).
///
/// UNGATED on purpose — the campaign drives this on freshly-registered,
/// non-test accounts (the same rationale as `l3_open_add_group_dialog`).
MCPCallEntry _l3OpenGroupAddMemberEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_open_group_add_member: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var groupId = (request['groupId'] as Object?)?.toString().trim() ?? '';
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    if (groupId.isEmpty) {
      return MCPCallResult(
        message: 'l3_open_group_add_member: need "groupId"',
        parameters: {'ok': false, 'error': 'missing_group_id'},
      );
    }
    if (!ffi.knownGroups.contains(groupId)) {
      return MCPCallResult(
        message: 'l3_open_group_add_member: not a joined group: $groupId',
        parameters: {'ok': false, 'error': 'not_joined', 'groupId': groupId},
      );
    }
    final invoker = _l3OpenGroupAddMemberInvoker;
    if (invoker == null) {
      return MCPCallResult(
        message: 'l3_open_group_add_member: invoker not registered',
        parameters: {'ok': false, 'error': 'invoker_not_registered'},
      );
    }
    final opened = await invoker(groupId);
    return MCPCallResult(
      message: opened
          ? 'group add-member screen opened'
          : 'group add-member screen unavailable',
      parameters: {'ok': opened, 'groupId': groupId},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_open_group_add_member',
    description:
        'Open the real group add-member screen for a joined group. '
        'Navigation-stability harness hook only; the member is selected + '
        'invited (inviteUserToGroup) through the real add-member UI.',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(
          description:
              'Local group id (tox_N), with or without the '
              '"group_" conversation prefix.',
        ),
      },
    ),
  ),
);

/// Deep-link to OPEN the REAL group member-list page for [groupId], skipping the
/// brittle chat→header-avatar→group-profile→"Group Members" navigation hops
/// (the members entry is a KeyedSubtree that also wraps the "+ Add Members"
/// affordance, so a coordinate tap is ambiguous). The member-list page is then
/// driven through REAL widgets: the keyed per-member rows
/// (`group_member_list_item:<userId>`), the desktop kick menu
/// (`group_member_desktop_kick_item` via a real secondary-tap), and member-list
/// scrolling. Mirrors `l3_open_group_add_member` — navigation-stability harness
/// hook only, UNGATED on purpose (driven on freshly-registered non-test
/// accounts).
MCPCallEntry _l3OpenGroupMemberListEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_open_group_member_list: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var groupId = (request['groupId'] as Object?)?.toString().trim() ?? '';
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    if (groupId.isEmpty) {
      return MCPCallResult(
        message: 'l3_open_group_member_list: need "groupId"',
        parameters: {'ok': false, 'error': 'missing_group_id'},
      );
    }
    if (!ffi.knownGroups.contains(groupId)) {
      return MCPCallResult(
        message: 'l3_open_group_member_list: not a joined group: $groupId',
        parameters: {'ok': false, 'error': 'not_joined', 'groupId': groupId},
      );
    }
    final invoker = _l3OpenGroupMemberListInvoker;
    if (invoker == null) {
      return MCPCallResult(
        message: 'l3_open_group_member_list: invoker not registered',
        parameters: {'ok': false, 'error': 'invoker_not_registered'},
      );
    }
    final opened = await invoker(groupId);
    return MCPCallResult(
      message: opened
          ? 'group member-list page opened'
          : 'group member-list page unavailable',
      parameters: {'ok': opened, 'groupId': groupId},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_open_group_member_list',
    description:
        'Open the real group member-list page for a joined group. '
        'Navigation-stability harness hook only; the member rows / desktop kick '
        'menu / scrolling are driven through the real member-list UI.',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(
          description:
              'Local group id (tox_N), with or without the '
              '"group_" conversation prefix.',
        ),
      },
    ),
  ),
);

/// Deep-link to OPEN the real group PROFILE page for a joined group, popping any
/// stale pushed routes first so the profile is the clean, on-top, full-width
/// route (the avatar-tap path leaves stale nested profile/member-list routes
/// across cases, which made `_openGroupProfile`'s key resolution land on a
/// covered, half-width profile — clear/leave below the fold at the wrong x, the
/// mute switch un-tappable). Mirrors `l3_open_group_member_list`: navigation-
/// stability harness hook only; the rename / mute / clear / leave widgets are
/// still driven through the real profile UI. UNGATED on purpose.
MCPCallEntry _l3OpenGroupProfileEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_open_group_profile: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var groupId = (request['groupId'] as Object?)?.toString().trim() ?? '';
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    if (groupId.isEmpty) {
      return MCPCallResult(
        message: 'l3_open_group_profile: need "groupId"',
        parameters: {'ok': false, 'error': 'missing_group_id'},
      );
    }
    if (!ffi.knownGroups.contains(groupId)) {
      return MCPCallResult(
        message: 'l3_open_group_profile: not a joined group: $groupId',
        parameters: {'ok': false, 'error': 'not_joined', 'groupId': groupId},
      );
    }
    final invoker = _l3OpenGroupProfileInvoker;
    if (invoker == null) {
      return MCPCallResult(
        message: 'l3_open_group_profile: invoker not registered',
        parameters: {'ok': false, 'error': 'invoker_not_registered'},
      );
    }
    final opened = await invoker(groupId);
    return MCPCallResult(
      message: opened
          ? 'group profile page opened'
          : 'group profile page unavailable',
      parameters: {'ok': opened, 'groupId': groupId},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_open_group_profile',
    description:
        'Open the real group profile page for a joined group (popping stale '
        'pushed routes first so it is the clean on-top route). Navigation-'
        'stability harness hook only; rename / mute / clear / leave are driven '
        'through the real profile UI.',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(
          description:
              'Local group id (tox_N), with or without the '
              '"group_" conversation prefix.',
        ),
      },
    ),
  ),
);

/// Deep-link to OPEN the conversation-row context menu for [conversationId]
/// (`group_<gid>` or `c2c_<id>`), skipping the un-driveable right-click /
/// long-press gesture that flutter_skill (tap/tapAt/waitForElement only) cannot
/// perform. Mirrors `l3_open_add_group_dialog` / `l3_open_group_add_member`:
/// navigation-stability harness hook only — the menu ITEMS
/// (`conversation_context_menu_{pin,unpin,mark_read,delete}_item`) and the
/// delete-confirm dialog (`delete_conversation_confirm_button`) are still tapped
/// through the real UI. The invoker resolves the conversation from the live
/// `UikitDataFacade.conversationList` and calls the SAME
/// `_showConversationContextMenu(conv, position)` the secondary-tap/long-press
/// handlers call (so pin/mark-read/delete go through the real
/// pinConversation / cleanConversationUnreadMessageCount / deleteConversation
/// paths). UNGATED on purpose — driven on freshly-registered, non-test accounts.
MCPCallEntry _l3OpenConversationMenuEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_open_conversation_menu: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    final conversationId =
        (request['conversationId'] as Object?)?.toString().trim() ?? '';
    if (conversationId.isEmpty) {
      return MCPCallResult(
        message: 'l3_open_conversation_menu: need "conversationId"',
        parameters: {'ok': false, 'error': 'missing_conversation_id'},
      );
    }
    final invoker = _l3OpenConversationMenuInvoker;
    if (invoker == null) {
      return MCPCallResult(
        message: 'l3_open_conversation_menu: invoker not registered',
        parameters: {'ok': false, 'error': 'invoker_not_registered'},
      );
    }
    final action = (request['action'] as Object?)?.toString().trim();
    if (action != null &&
        action.isNotEmpty &&
        !const {'pin', 'mark_read', 'delete'}.contains(action)) {
      return MCPCallResult(
        message: 'l3_open_conversation_menu: unknown action "$action"',
        parameters: {'ok': false, 'error': 'unknown_action'},
      );
    }
    final resolvedAction = (action == null || action.isEmpty) ? null : action;
    final ok = await invoker(conversationId, action: resolvedAction);
    return MCPCallResult(
      message: ok
          ? (resolvedAction == null
                ? 'conversation context menu opened'
                : 'conversation menu action "$resolvedAction" dispatched')
          : 'conversation not found in list',
      parameters: {
        'ok': ok,
        'conversationId': conversationId,
        if (resolvedAction != null) 'action': resolvedAction,
      },
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_open_conversation_menu',
    description:
        'Open the conversation-row context menu (Pin/Unpin, Mark as read, '
        'Delete) for a conversation by id (group_<gid> or c2c_<id>), without the '
        'un-driveable right-click / long-press gesture. Harness hook only. With '
        'no "action", the visual menu is shown for real-UI item taps. With '
        '"action" = pin|mark_read|delete, the SAME production handler the menu '
        'dispatches runs directly (deterministic; avoids the flutter_skill '
        'double-fire on PopupMenuItem) — delete still raises the real '
        'confirm dialog (tap delete_conversation_confirm_button).',
    inputSchema: ObjectSchema(
      properties: {
        'conversationId': StringSchema(
          description:
              'group_<gid> or c2c_<toxId> (exact conversationID from '
              'l3_dump_state.conversations[]).',
        ),
        'action': StringSchema(
          description:
              'Optional: pin | mark_read | delete. Dispatches the real '
              'handler directly instead of showing the visual menu.',
        ),
      },
    ),
  ),
);

/// Mark a C2C conversation read: advances the per-conversation lastView
/// barrier so `getC2CUnreadCount` (surfaced as `unreadCount` in l3_dump_state)
/// drops to 0. Lets a scenario assert unread>0 → mark-read → unread==0 (S19).
/// Test/seed account only; C2C only.
MCPCallEntry _l3MarkReadEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_mark_read: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_mark_read: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var userId = request['userId'] ?? request['conversationId'] ?? '';
    if (userId.startsWith('group_') || request['groupId'] != null) {
      return MCPCallResult(
        message: 'l3_mark_read: C2C only — group ids unsupported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    if (userId.startsWith('c2c_')) userId = userId.substring(4);
    if (userId.isEmpty) userId = ffi.activePeerId ?? '';
    if (userId.isEmpty) {
      return MCPCallResult(
        message: 'l3_mark_read: no target — pass userId',
        parameters: {'ok': false, 'error': 'no_target'},
      );
    }
    final groupReject = await _rejectIfGroupTarget(
      'l3_mark_read',
      userId,
      ffi.knownGroups,
      ffi.quitGroups,
    );
    if (groupReject != null) return groupReject;
    try {
      // Marking a conversation read in the real app == opening it (making
      // it the active conversation): `setActivePeer` zeroes the in-memory
      // unread counter synchronously AND fire-and-forget advances the
      // persisted lastView barrier. Mirror that exact path rather than
      // inventing a new API. The in-memory zero is synchronous, so the
      // unread read below reflects the result immediately (a kill+reload
      // assertion could still race the unawaited barrier save).
      ffi.setActivePeer(userId);
      final unread = ffi.getC2CUnreadCount(userId);
      AppLogger.info('[L3] l3_mark_read: $userId → unread=$unread');
      return MCPCallResult(
        message: 'marked read',
        parameters: {'ok': true, 'userId': userId, 'unreadCount': unread},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_mark_read failed', e, st);
      return MCPCallResult(
        message: 'l3_mark_read: failed: $e',
        parameters: {'ok': false, 'error': 'mark_read_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_mark_read',
    description:
        'L3 TEST ONLY: mark a C2C conversation read by OPENING it '
        '(sets it as the active conversation — same path the real app uses '
        'when you open a chat; side effects: changes activePeerId + '
        'suppresses its notifications). Zeroes the in-memory unreadCount '
        'synchronously; the persisted lastView barrier write is best-effort '
        '(unawaited), so unreadCount is authoritative for an immediate '
        'in-memory assertion but a kill+reload assertion may race. Targets '
        'userId/conversationId, or the active conversation.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(description: 'Target Tox ID (64/76 hex).'),
        'conversationId': StringSchema(
          description: 'c2c_<toxId> alternative to userId.',
        ),
      },
    ),
  ),
);

/// S27: DECLINE a pending friend application from [userId] via the real
/// FFI/service path (`FfiChatService.refuseFriendApplication`), then refresh
/// contacts. The application leaves `l3_dump_state.friendApplications[]` and the
/// peer does NOT enter `friends[]`. MUTATING — test/seed account only.
MCPCallEntry _l3RefuseFriendRequestEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_refuse_friend_request: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final rawUserId = request['userId']?.toString().trim() ?? '';
    if (rawUserId.isEmpty) {
      return MCPCallResult(
        message: 'l3_refuse_friend_request: need "userId"',
        parameters: {'ok': false, 'error': 'missing_user_id'},
      );
    }
    final userId = normalizeToxId(rawUserId);
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_refuse_friend_request: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    if (userId.startsWith('group_')) {
      return MCPCallResult(
        message: 'l3_refuse_friend_request: groups unsupported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    try {
      await ffi.refuseFriendApplication(userId);
      await FakeUIKit.instance.im?.refreshContacts();
      AppLogger.info('[L3] l3_refuse_friend_request: declined $userId');
      return MCPCallResult(
        message: 'friend application declined',
        parameters: {'ok': true, 'userId': userId},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_refuse_friend_request failed', e, st);
      return MCPCallResult(
        message: 'l3_refuse_friend_request: failed: $e',
        parameters: {'ok': false, 'error': 'refuse_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_refuse_friend_request',
    description:
        'L3 TEST ONLY: DECLINE a pending friend application from the given '
        'userId via the real FFI/service path (refuseFriendApplication), then '
        'refresh contacts. The application leaves friendApplications[] and the '
        'peer does NOT become a friend. For Fixture C friend-decline (S27).',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(
          description: 'Peer Tox ID (64/76 hex) whose application to decline.',
        ),
      },
      required: ['userId'],
    ),
  ),
);

MCPCallEntry _l3DeleteFriendEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final rawUserId = request['userId']?.toString().trim() ?? '';
    if (rawUserId.isEmpty) {
      return MCPCallResult(
        message: 'l3_delete_friend: need "userId"',
        parameters: {'ok': false, 'error': 'missing_user_id'},
      );
    }
    final userId = normalizeToxId(rawUserId);
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_delete_friend: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    if (userId.startsWith('group_')) {
      return MCPCallResult(
        message: 'l3_delete_friend: groups unsupported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    try {
      await ffi.deleteFriend(userId);
      await FakeUIKit.instance.im?.refreshContacts();
      AppLogger.info('[L3] l3_delete_friend: deleted $userId');
      return MCPCallResult(
        message: 'friend deleted',
        parameters: {'ok': true, 'userId': userId},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_delete_friend failed', e, st);
      return MCPCallResult(
        message: 'l3_delete_friend: failed: $e',
        parameters: {'ok': false, 'error': 'delete_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_delete_friend',
    description:
        'L3 TEST ONLY: delete the given friend via the real FFI/service path, '
        'then refresh contacts. Intended as a cleanup fallback when the real '
        'profile delete affordance is unavailable during harness recovery.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(
          description:
              'Peer Tox ID (64/76 hex) to remove from the friend list.',
        ),
      },
      required: ['userId'],
    ),
  ),
);

/// S29 block/unblock: add or remove a C2C peer from the local blacklist via the
/// REAL SDK path (`getFriendshipManager().addToBlackList` / `deleteFromBlackList`),
/// which routes through the installed Tim2ToxSdkPlatform → persists via the
/// ExtendedPreferencesService AND refreshes `FfiChatService`'s in-memory block
/// cache (so the inbound filter takes effect immediately). MUTATING — test/seed
/// account, C2C only. Read back via `l3_dump_state.blockedUsers`; the inbound
/// suppression is observable via `messages[]` (a blocked echo peer's mirror is
/// dropped).
MCPCallEntry _l3SetBlockedEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_set_blocked: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    var userId = (request['userId'] ?? request['conversationId'] ?? '')
        .toString()
        .trim();
    if (userId.startsWith('group_') || request['groupId'] != null) {
      return MCPCallResult(
        message: 'l3_set_blocked: C2C only — groups unsupported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    if (userId.startsWith('c2c_')) userId = userId.substring(4);
    final ffi = FakeUIKit.instance.im?.ffi;
    if (userId.isEmpty) userId = ffi?.activePeerId ?? '';
    if (userId.isEmpty) {
      return MCPCallResult(
        message: 'l3_set_blocked: no target — pass "userId"',
        parameters: {'ok': false, 'error': 'no_target'},
      );
    }
    userId = normalizeToxId(userId);
    final groupReject = await _rejectIfGroupTarget(
      'l3_set_blocked',
      userId,
      ffi?.knownGroups ?? const <String>{},
      ffi?.quitGroups ?? const <String>{},
    );
    if (groupReject != null) return groupReject;
    final rawBlocked = (request['blocked'] ?? 'true')
        .toString()
        .toLowerCase()
        .trim();
    if (rawBlocked != 'true' && rawBlocked != 'false') {
      return MCPCallResult(
        message:
            'l3_set_blocked: "blocked" must be true|false (got "$rawBlocked")',
        parameters: {'ok': false, 'error': 'bad_value'},
      );
    }
    final blocked = rawBlocked == 'true';
    try {
      final res = blocked
          ? await TencentImSDKPlugin.v2TIMManager
                .getFriendshipManager()
                .addToBlackList(userIDList: [userId])
          : await TencentImSDKPlugin.v2TIMManager
                .getFriendshipManager()
                .deleteFromBlackList(userIDList: [userId]);
      if (res.code != 0) {
        return MCPCallResult(
          message: 'l3_set_blocked: SDK returned ${res.code}: ${res.desc}',
          parameters: {'ok': false, 'error': 'sdk_error', 'detail': res.desc},
        );
      }
      await FakeUIKit.instance.im?.refreshContacts();
      AppLogger.info('[L3] l3_set_blocked MUTATED $userId blocked=$blocked');
      return MCPCallResult(
        message: 'block updated: $userId blocked=$blocked',
        parameters: {
          'ok': true,
          'userId': userId,
          'blocked': blocked,
          'blockedUsers': ffi?.blockedUsers.toList() ?? const <String>[],
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_set_blocked failed', e, st);
      return MCPCallResult(
        message: 'l3_set_blocked: failed: $e',
        parameters: {
          'ok': false,
          'error': 'set_blocked_failed',
          'detail': '$e',
        },
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_set_blocked',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING, C2C only): block or unblock '
        'a peer via the real SDK friendship path (addToBlackList / '
        'deleteFromBlackList) — persists + refreshes the FfiChatService '
        "inbound-filter cache so a blocked sender's inbound messages are "
        'dropped. userId accepts bare or c2c_, or defaults to the active '
        'conversation. blocked is true|false. Read back via '
        'l3_dump_state.blockedUsers.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(description: 'Peer Tox ID (bare or c2c_).'),
        'blocked': StringSchema(description: 'true | false'),
      },
    ),
  ),
);

/// S30/H5: set or CLEAR a friend's user-edited remark/alias via
/// `Prefs.setFriendRemark` (account-scoped — the SAME store the profile/settings
/// edit path writes; distinct from the Tox nickName). An empty remark clears it.
/// Read back via `l3_dump_state.friends[].remark`. MUTATING — test/seed account
/// only, C2C only.
MCPCallEntry _l3SetFriendRemarkEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_set_friend_remark: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    var userId = (request['userId'] ?? request['conversationId'] ?? '')
        .toString()
        .trim();
    if (userId.startsWith('group_') || request['groupId'] != null) {
      return MCPCallResult(
        message: 'l3_set_friend_remark: C2C only — groups unsupported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    if (userId.startsWith('c2c_')) userId = userId.substring(4);
    final ffi = FakeUIKit.instance.im?.ffi;
    if (userId.isEmpty) userId = ffi?.activePeerId ?? '';
    if (userId.isEmpty) {
      return MCPCallResult(
        message: 'l3_set_friend_remark: no target — pass "userId"',
        parameters: {'ok': false, 'error': 'no_target'},
      );
    }
    userId = normalizeToxId(userId);
    // Guard the resolved bare id against a group slipping through the active
    // fallback (mirrors the C2C-only message tools).
    final groupReject = await _rejectIfGroupTarget(
      'l3_set_friend_remark',
      userId,
      ffi?.knownGroups ?? const <String>{},
      ffi?.quitGroups ?? const <String>{},
    );
    if (groupReject != null) return groupReject;
    // The remark is intentionally allowed to be empty (that CLEARS it).
    final remark = (request['remark'] ?? '').toString();
    try {
      await Prefs.setFriendRemark(userId, remark);
      await FakeUIKit.instance.im?.refreshContacts();
      AppLogger.info(
        '[L3] l3_set_friend_remark MUTATED $userId remark='
        '${remark.isEmpty ? "(cleared)" : remark}',
      );
      return MCPCallResult(
        message: 'remark updated: $userId',
        parameters: {'ok': true, 'userId': userId, 'remark': remark},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_set_friend_remark failed', e, st);
      return MCPCallResult(
        message: 'l3_set_friend_remark: failed: $e',
        parameters: {'ok': false, 'error': 'set_remark_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_set_friend_remark',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING, C2C only): set or CLEAR a '
        "friend's user-edited remark/alias via Prefs.setFriendRemark "
        '(account-scoped). An empty remark clears it. userId accepts a bare or '
        'c2c_ id, or defaults to the active conversation. Read back via '
        'l3_dump_state.friends[].remark.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(description: 'Friend Tox ID (bare or c2c_).'),
        'remark': StringSchema(
          description: 'New remark; empty string clears it.',
        ),
      },
    ),
  ),
);

MCPCallEntry _l3AcceptFriendRequestEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_accept_friend_request: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final rawUserId = request['userId']?.toString().trim() ?? '';
    if (rawUserId.isEmpty) {
      return MCPCallResult(
        message: 'l3_accept_friend_request: need "userId"',
        parameters: {'ok': false, 'error': 'missing_user_id'},
      );
    }
    final userId = normalizeToxId(rawUserId);
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_accept_friend_request: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    if (userId.startsWith('group_')) {
      return MCPCallResult(
        message: 'l3_accept_friend_request: groups unsupported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    try {
      await ffi.acceptFriendRequest(userId);
      FakeUIKit.instance.im?.registerPendingFriendAdd(userId);
      await FakeUIKit.instance.im?.refreshContacts();
      AppLogger.info('[L3] l3_accept_friend_request: accepted $userId');
      return MCPCallResult(
        message: 'friend accepted',
        parameters: {'ok': true, 'userId': userId},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_accept_friend_request failed', e, st);
      return MCPCallResult(
        message: 'l3_accept_friend_request: failed: $e',
        parameters: {'ok': false, 'error': 'accept_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_accept_friend_request',
    description:
        'L3 TEST ONLY: accept a friend request from the given userId via the '
        'real FFI/service path, then refresh contacts. Useful for Fixture C / '
        'friend-handshake scenarios without driving the pending-requests UI.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(
          description: 'Peer Tox ID (64 or 76 hex) to accept as a friend.',
        ),
      },
      required: ['userId'],
    ),
  ),
);

MCPCallEntry _l3SetExportSavePathEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_set_export_save_path: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final path = _normalizeExportSaveOverridePath(request['path']?.toString());
    _exportSaveFilePathOverride = path;
    AppLogger.info(
      '[L3] l3_set_export_save_path: '
      '${path == null ? "CLEARED" : "SET -> $path"}',
    );
    return MCPCallResult(
      message: path == null
          ? 'export save override cleared'
          : 'export save override set',
      parameters: {'ok': true, 'path': path, 'cleared': path == null},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_set_export_save_path',
    description:
        'L3 TEST ONLY (test/seed account): set or clear the debug-only '
        'saveFile override used by Settings export flows. When set, '
        'export save dialogs are bypassed and the fixed path is returned. '
        'Pass an empty path to clear it.',
    inputSchema: ObjectSchema(
      properties: {
        'path': StringSchema(
          description:
              'Absolute path to return from export saveFile. Empty clears.',
        ),
      },
    ),
  ),
);

MCPCallEntry _l3SetAccountImportPickPathEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_set_account_import_pick_path: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final path = _normalizeExportSaveOverridePath(request['path']?.toString());
    _accountImportPickFilePathOverride = path;
    AppLogger.info(
      '[L3] l3_set_account_import_pick_path: '
      '${path == null ? "CLEARED" : "SET -> $path"}',
    );
    return MCPCallResult(
      message: path == null
          ? 'account import pick override cleared'
          : 'account import pick override set',
      parameters: {'ok': true, 'path': path, 'cleared': path == null},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_set_account_import_pick_path',
    description:
        'L3 TEST ONLY (test/seed account): set or clear the debug-only '
        'open-file override used by login restore/import flows. When set, the '
        'native file picker is bypassed and this fixed path is returned. Pass '
        'an empty path to clear.',
    inputSchema: ObjectSchema(
      properties: {
        'path': StringSchema(
          description:
              'Absolute .tox/.zip path to return from account import pickFiles. '
              'Empty clears.',
        ),
      },
    ),
  ),
);

MCPCallEntry _l3SetAttachmentPickPathEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_set_attachment_pick_path: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    // PREFER contentB64: a sandboxed macOS app can only READ files it wrote under
    // its OWN container, so an external `/tmp` path the driver wrote is unreadable
    // and the real attachment send fails at the FFI with -6 ("Cannot read file").
    // When content is supplied, the APP materializes it under Directory.systemTemp
    // (inside the container) and points the override at THAT app-readable path,
    // mirroring l3_send_file. (`path` stays for already-app-accessible files.)
    final contentB64 = request['contentB64']?.toString();
    if (contentB64 != null && contentB64.isNotEmpty) {
      final name = (request['fileName']?.toString().trim().isNotEmpty ?? false)
          ? request['fileName']!.toString().trim()
          : 'l3_attach.bin';
      final List<int> bytes;
      try {
        bytes = base64Decode(contentB64);
      } on FormatException catch (e) {
        return MCPCallResult(
          message: 'l3_set_attachment_pick_path: contentB64 not valid base64: $e',
          parameters: {'ok': false, 'error': 'bad_base64'},
        );
      }
      final dir = await Directory.systemTemp.createTemp('l3attach');
      final f = File('${dir.path}/$name');
      await f.writeAsBytes(bytes);
      _attachmentPickFilePathOverride = f.path;
      AppLogger.info(
        '[L3] l3_set_attachment_pick_path: materialized $name -> ${f.path}',
      );
      return MCPCallResult(
        message: 'attachment pick override materialized',
        parameters: {'ok': true, 'path': f.path},
      );
    }
    final path = _normalizeExportSaveOverridePath(request['path']?.toString());
    _attachmentPickFilePathOverride = path;
    AppLogger.info(
      '[L3] l3_set_attachment_pick_path: '
      '${path == null ? "CLEARED" : "SET -> $path"}',
    );
    return MCPCallResult(
      message: path == null
          ? 'attachment pick override cleared'
          : 'attachment pick override set',
      parameters: {'ok': true, 'path': path, 'cleared': path == null},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_set_attachment_pick_path',
    description:
        'L3 TEST ONLY (test/seed account): set or clear the debug-only '
        'message attachment picker override. Drive the real toolbar/menu first; '
        'the native file picker then returns this fixed path. PREFER "contentB64" '
        '+ "fileName" (the app writes a sandbox-readable file); a host "path" '
        'under /tmp is NOT readable by the sandboxed app. Pass an empty path to clear.',
    inputSchema: ObjectSchema(
      properties: {
        'path': StringSchema(
          description:
              'Absolute media/file path to return from attachment pickFiles. '
              'Empty clears. Use only for already-app-accessible files.',
        ),
        'contentB64': StringSchema(
          description:
              'Base64 file bytes; the app writes them to a sandbox-readable temp '
              'file and returns THAT path. Preferred over "path".',
        ),
        'fileName': StringSchema(
          description: 'File name for the materialized contentB64 file.',
        ),
      },
    ),
  ),
);

/// S79: set/clear the avatar image-picker override (mirrors the export-save
/// override). When set, [runL3AwareAvatarPicker] returns this path instead of
/// showing the native NSOpenPanel, so the avatar-set flow is L3-drivable.
MCPCallEntry _l3SetAvatarPickPathEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_set_avatar_pick_path: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final path = _normalizeExportSaveOverridePath(request['path']?.toString());
    _avatarPickPathOverride = path;
    AppLogger.info(
      '[L3] l3_set_avatar_pick_path: '
      '${path == null ? "CLEARED" : "SET -> $path"}',
    );
    return MCPCallResult(
      message: path == null
          ? 'avatar pick override cleared'
          : 'avatar pick override set',
      parameters: {'ok': true, 'path': path, 'cleared': path == null},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_set_avatar_pick_path',
    description:
        'L3 TEST ONLY (test/seed account): set or clear the avatar image-picker '
        'override. When set, the native image picker is bypassed and this fixed '
        'path is returned by the avatar-set flow. Pass an empty path to clear.',
    inputSchema: ObjectSchema(
      properties: {
        'path': StringSchema(
          description:
              'Absolute image path to use as the picked avatar. Empty clears.',
        ),
      },
    ),
  ),
);

/// #5 (codex-vetted 2026-05-30): drive a FIXTURE-SAFE account setting so a
/// scenario can exercise a toggle→assert flow against the [_l3DumpStateEntry]
/// read-model (S46/S47 write-half). MUTATING — test/seed account only, and the
/// allowed-key set is intentionally narrow: only the two auto-accept flags.
/// `autoLogin` is rejected (setting it false would break the seeded account's
/// auto-login, which the L3 harness depends on). `themeMode` / `languageCode`
/// ARE drivable: they route through the shared appliers in
/// `lib/util/appearance_sync.dart` (the same functions the Settings rows
/// call), so the app chrome AND the UIKit-rendered surfaces switch together —
/// the old "needs the live ThemeController" rejection predated the static
/// AppTheme/AppLocale notifiers + shared-applier extraction.
MCPCallEntry _l3SetSettingEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_set_setting: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final key = request['key']?.trim() ?? '';
    final raw = request['value'];
    if (key.isEmpty || raw == null) {
      return MCPCallResult(
        message: 'l3_set_setting: need "key" and "value"',
        parameters: {'ok': false, 'error': 'bad_args'},
      );
    }
    // MCP args arrive as strings. `vs` keeps original case (for the int/enum
    // keys); bool keys lowercase it below.
    final vs = raw.toString().trim();
    // ---- Typed, fixture-safe settings (coverage-widening) -----------------
    // autoDownloadSizeLimit: int MB (L8). bootstrapNodeMode: enum auto|manual|
    // lan (C1). Both are GLOBAL Prefs the runner asserts via the matching
    // l3_dump_state read field; a scenario restores the documented default at
    // the end so the fixture self-cleans.
    if (key == 'autoDownloadSizeLimit') {
      final mb = int.tryParse(vs);
      if (mb == null || mb < 0) {
        return MCPCallResult(
          message:
              'l3_set_setting: autoDownloadSizeLimit needs int>=0 (got "$raw")',
          parameters: {'ok': false, 'error': 'bad_value'},
        );
      }
      // codex P2: write inside try/catch so a storage failure returns
      // {ok:false} like the bool branches, instead of throwing out of the ext.
      try {
        await Prefs.setAutoDownloadSizeLimit(mb);
        AppLogger.info('[L3] l3_set_setting MUTATED autoDownloadSizeLimit=$mb');
        return MCPCallResult(
          message: 'setting updated: autoDownloadSizeLimit=$mb',
          parameters: {'ok': true, 'key': key, 'value': mb},
        );
      } catch (e, st) {
        AppLogger.logError(
          '[L3] l3_set_setting autoDownloadSizeLimit failed',
          e,
          st,
        );
        return MCPCallResult(
          message: 'l3_set_setting: failed: $e',
          parameters: {
            'ok': false,
            'error': 'set_setting_failed',
            'detail': '$e',
          },
        );
      }
    }
    // themeMode: light|dark|system through the shared applier so the app
    // chrome and the UIKit surfaces flip together (mixed-theme screenshots
    // were the failure mode the old rejection was guarding against — the
    // applier IS the live-controller path now).
    if (key == 'themeMode') {
      const modes = {
        'light': ThemeMode.light,
        'dark': ThemeMode.dark,
        'system': ThemeMode.system,
      };
      final mode = modes[vs.toLowerCase()];
      if (mode == null) {
        return MCPCallResult(
          message:
              'l3_set_setting: themeMode must be light|dark|system '
              '(got "$raw")',
          parameters: {'ok': false, 'error': 'bad_value'},
        );
      }
      try {
        await applyThemeModeEverywhere(mode);
        AppLogger.info('[L3] l3_set_setting MUTATED themeMode=$vs');
        return MCPCallResult(
          message: 'setting updated: themeMode=$vs',
          parameters: {'ok': true, 'key': key, 'value': vs, 'applied': 'live'},
        );
      } catch (e, st) {
        AppLogger.logError('[L3] l3_set_setting themeMode failed', e, st);
        return MCPCallResult(
          message: 'l3_set_setting: failed: $e',
          parameters: {
            'ok': false,
            'error': 'set_setting_failed',
            'detail': '$e',
          },
        );
      }
    }
    // languageCode: en|zh|zh-Hant|ja|ko|ar through the shared applier (app
    // localizations + UIKit intl together). 'zh' maps to Hans like the
    // Settings row default.
    if (key == 'languageCode') {
      final locale = switch (vs.toLowerCase()) {
        'en' => const Locale('en'),
        'zh' || 'zh-hans' => const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
        ),
        'zh-hant' => const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hant',
        ),
        'ja' => const Locale('ja'),
        'ko' => const Locale('ko'),
        'ar' => const Locale('ar'),
        _ => null,
      };
      if (locale == null) {
        return MCPCallResult(
          message:
              'l3_set_setting: languageCode must be '
              'en|zh|zh-Hans|zh-Hant|ja|ko|ar (got "$raw")',
          parameters: {'ok': false, 'error': 'bad_value'},
        );
      }
      try {
        await applyLocaleEverywhere(locale);
        AppLogger.info('[L3] l3_set_setting MUTATED languageCode=$vs');
        return MCPCallResult(
          message: 'setting updated: languageCode=$vs',
          parameters: {'ok': true, 'key': key, 'value': vs, 'applied': 'live'},
        );
      } catch (e, st) {
        AppLogger.logError('[L3] l3_set_setting languageCode failed', e, st);
        return MCPCallResult(
          message: 'l3_set_setting: failed: $e',
          parameters: {
            'ok': false,
            'error': 'set_setting_failed',
            'detail': '$e',
          },
        );
      }
    }
    if (key == 'bootstrapNodeMode') {
      const modes = {'auto', 'manual', 'lan'};
      if (!modes.contains(vs)) {
        return MCPCallResult(
          message:
              'l3_set_setting: bootstrapNodeMode must be auto|manual|lan '
              '(got "$raw")',
          parameters: {'ok': false, 'error': 'bad_value'},
        );
      }
      // codex P2: same try/catch error contract as above.
      try {
        await Prefs.setBootstrapNodeMode(vs);
        AppLogger.info('[L3] l3_set_setting MUTATED bootstrapNodeMode=$vs');
        return MCPCallResult(
          message: 'setting updated: bootstrapNodeMode=$vs',
          parameters: {'ok': true, 'key': key, 'value': vs},
        );
      } catch (e, st) {
        AppLogger.logError(
          '[L3] l3_set_setting bootstrapNodeMode failed',
          e,
          st,
        );
        return MCPCallResult(
          message: 'l3_set_setting: failed: $e',
          parameters: {
            'ok': false,
            'error': 'set_setting_failed',
            'detail': '$e',
          },
        );
      }
    }
    // ---- Boolean, fixture-safe settings -----------------------------------
    final lvs = vs.toLowerCase();
    if (lvs != 'true' && lvs != 'false') {
      return MCPCallResult(
        message: 'l3_set_setting: "value" must be true|false (got "$raw")',
        parameters: {'ok': false, 'error': 'bad_value'},
      );
    }
    final value = lvs == 'true';
    const allowed = {
      'autoAcceptFriends',
      'autoAcceptGroupInvites',
      'notificationSound',
    };
    if (!allowed.contains(key)) {
      return MCPCallResult(
        message:
            'l3_set_setting: key "$key" not allowed — drivable keys: '
            'autoAcceptFriends / autoAcceptGroupInvites / notificationSound '
            '(bool), autoDownloadSizeLimit (int MB), bootstrapNodeMode '
            '(auto|manual|lan), themeMode (light|dark|system), languageCode '
            '(en|zh|zh-Hans|zh-Hant|ja|ko|ar). autoLogin rejected '
            '(harness-safety: the seeded auto-login must survive).',
        parameters: {'ok': false, 'error': 'key_not_allowed'},
      );
    }
    // notificationSound (L7) is a plain account-scoped Prefs bool — the
    // settings "notification sound" toggle. It is NOT an auto-accept flag, so
    // it writes Prefs directly and does NOT go through the inbound-listener
    // applier below.
    if (key == 'notificationSound') {
      try {
        await Prefs.setNotificationSoundEnabled(value);
        AppLogger.info('[L3] l3_set_setting MUTATED notificationSound=$value');
        return MCPCallResult(
          message: 'setting updated: notificationSound=$value',
          parameters: {'ok': true, 'key': key, 'value': value},
        );
      } catch (e, st) {
        AppLogger.logError(
          '[L3] l3_set_setting notificationSound failed',
          e,
          st,
        );
        return MCPCallResult(
          message: 'l3_set_setting: failed: $e',
          parameters: {
            'ok': false,
            'error': 'set_setting_failed',
            'detail': '$e',
          },
        );
      }
    }
    // Prefer the LIVE applier (drives the real HomePage setter: cached flag +
    // Prefs + accept-pending side effect) so the setting actually takes effect
    // for the inbound auto-accept listeners (S46/S47). Falls back to a Prefs-
    // only write when no live HomePage is registered (e.g. unit tests).
    final applier = _l3AutoAcceptApplier;
    if (applier != null) {
      try {
        await applier(key, value);
        AppLogger.info(
          '[L3] l3_set_setting MUTATED (live applier) $key=$value',
        );
        return MCPCallResult(
          message: 'setting updated (live): $key=$value',
          parameters: {
            'ok': true,
            'key': key,
            'value': value,
            'applied': 'live',
          },
        );
      } catch (e, st) {
        AppLogger.logError(
          '[L3] l3_set_setting live applier failed; falling back to Prefs',
          e,
          st,
        );
      }
    }
    try {
      final toxId = (await Prefs.getCurrentAccountToxId()) ?? '';
      final scoped = toxId.isEmpty ? null : toxId;
      var nativeSyncSkipped = false;
      if (key == 'autoAcceptFriends') {
        // Mirror home_page._setAutoAcceptFriends' PERSISTENCE only. The UI
        // setState + (value && pending apps) auto-accept side-effect are
        // intentionally NOT replicated: this runs outside the widget tree,
        // and auto-accepting real pending friend requests mid-test would be
        // a destructive surprise. dump_state reads this persisted flag.
        await Prefs.setAutoAcceptFriends(value, scoped);
      } else {
        // autoAcceptGroupInvites: the Prefs write is the asserted contract;
        // attempt the native FFI sync for fidelity but (codex) DON'T fail
        // the read-model test on an orthogonal runtime detail — if the
        // service bridge is absent, report partial success + a flag.
        await Prefs.setAutoAcceptGroupInvites(value, scoped);
        final ffi = FakeUIKit.instance.im?.ffi;
        if (ffi != null) {
          ffi.setAutoAcceptGroupInvites(value);
        } else {
          nativeSyncSkipped = true;
        }
      }
      // Auditability (codex): a mutating test action must be obvious in both
      // the log AND the response.
      AppLogger.info(
        '[L3] l3_set_setting MUTATED $key=$value'
        '${nativeSyncSkipped ? " (native group sync SKIPPED — no service)" : ""}',
      );
      return MCPCallResult(
        message: 'setting updated: $key=$value',
        parameters: {
          'ok': true,
          'key': key,
          'value': value,
          if (nativeSyncSkipped) 'nativeSyncSkipped': true,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_set_setting failed', e, st);
      return MCPCallResult(
        message: 'l3_set_setting: failed: $e',
        parameters: {
          'ok': false,
          'error': 'set_setting_failed',
          'detail': '$e',
        },
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_set_setting',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): set a '
        'fixture-safe account setting so a scenario can drive a '
        'toggle→assert flow against l3_dump_state. Allowed keys: '
        'autoAcceptFriends (Prefs only), autoAcceptGroupInvites (Prefs + a '
        'best-effort native FFI sync; reports nativeSyncSkipped:true if the '
        'service is absent), notificationSound (account-scoped Prefs bool, L7) '
        '— value is true|false; autoDownloadSizeLimit (L8) — value is an int '
        'MB string; bootstrapNodeMode (C1) — value is auto|manual|lan; '
        'themeMode — light|dark|system via the shared applier (app + UIKit '
        'switch together); languageCode — en|zh|zh-Hans|zh-Hant|ja|ko|ar via '
        'the shared applier. autoLogin is REJECTED (harness-safety). Restore '
        'the seeded default at the end of a scenario so the fixture '
        'self-cleans.',
    inputSchema: ObjectSchema(
      properties: {
        'key': StringSchema(
          description:
              'autoAcceptFriends | autoAcceptGroupInvites | notificationSound '
              '| autoDownloadSizeLimit | bootstrapNodeMode | themeMode | '
              'languageCode',
        ),
        'value': StringSchema(
          description:
              'true|false (bool keys) | int MB | auto|manual|lan | '
              'light|dark|system | en|zh|zh-Hans|zh-Hant|ja|ko|ar',
        ),
      },
    ),
  ),
);

/// S52 (codex-vetted approach 2026-06-01): change the CURRENT account's own
/// nickname / status / avatar so a paired friend (a second running instance)
/// observes the change ride a live Tox `friend_name` callback (nickname) or a
/// `TOX_FILE_KIND_AVATAR` transfer (avatar). Mirrors the sidebar profile-edit
/// path: `FfiChatService.updateSelfProfile` (Tox-level `tox_self_set_name`)
/// + `Prefs.setNickname`/`setStatusMessage` for local fidelity, and
/// `updateAvatar` (hash-gated; needs a genuinely NEW image). MUTATING — guarded
/// to a test/seed account. NOTE: accounts registered via `l3_register_account`
/// carry the persistent seed-account marker, so renaming them does NOT lock
/// out later mutating tools. Only LEGACY fixture accounts (recognized purely
/// by their `_kTestNicknames` nickname) lose mutating access after a rename —
/// for those, run S52 on a disposable FRESH account (no later A mutation).
MCPCallEntry _l3SetSelfProfileEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_set_self_profile: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_set_self_profile: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    // request values are dynamic; cast through Object? so the chain is a clean
    // String? (a raw `dynamic?.toString()` chain stays dynamic, which makes the
    // `!` below read as unnecessary to the analyzer).
    final String? nick = (request['nickname'] as Object?)?.toString().trim();
    final String? status = (request['statusMessage'] as Object?)?.toString();
    final String? avatarPath = (request['avatarPath'] as Object?)
        ?.toString()
        .trim();
    // avatarContent: inline bytes the app writes to its OWN temp file before
    // updateAvatar — sidesteps the cross-sandbox source-readability problem
    // (the driver can't place a file the sandboxed app can read). The bytes
    // need not be a valid image: updateAvatar just hashes + sends them as a
    // kind-1 file, and the receiver stores them + sets the friend avatar path
    // (what S52 asserts). Use a UNIQUE value per run so the hash-gate doesn't
    // skip the send.
    final String? avatarContent = (request['avatarContent'] as Object?)
        ?.toString();
    final hasNick = nick != null && nick.isNotEmpty;
    final hasStatus = status != null;
    final hasAvatar =
        (avatarPath != null && avatarPath.isNotEmpty) ||
        (avatarContent != null && avatarContent.isNotEmpty);
    if (!hasNick && !hasStatus && !hasAvatar) {
      return MCPCallResult(
        message:
            'l3_set_self_profile: need at least one of '
            'nickname / statusMessage / avatarPath / avatarContent',
        parameters: {'ok': false, 'error': 'no_fields'},
      );
    }
    try {
      final changed = <String>[];
      if (hasNick || hasStatus) {
        // updateSelfProfile requires BOTH fields; preserve the unchanged one
        // (read the current persisted value) so neither gets clobbered.
        final newNick = hasNick ? nick : ((await Prefs.getNickname()) ?? '');
        final newStatus = hasStatus
            ? status
            : ((await Prefs.getStatusMessage()) ?? '');
        await ffi.updateSelfProfile(
          nickname: newNick,
          statusMessage: newStatus,
        );
        // Mirror sidebar.dart: persist locally so the app's own view matches.
        if (hasNick) {
          await Prefs.setNickname(newNick);
          changed.add('nickname');
        }
        if (hasStatus) {
          await Prefs.setStatusMessage(newStatus);
          changed.add('statusMessage');
        }
      }
      if (hasAvatar) {
        var pathToSend = avatarPath ?? '';
        if (avatarContent != null && avatarContent.isNotEmpty) {
          final dir = await Directory.systemTemp.createTemp('l3avatar');
          final f = File(
            '${dir.path}/avatar_${DateTime.now().microsecondsSinceEpoch}.png',
          );
          await f.writeAsString(avatarContent);
          pathToSend = f.path;
        }
        await ffi.updateAvatar(pathToSend);
        changed.add('avatar');
      }
      AppLogger.info('[L3] l3_set_self_profile MUTATED ${changed.join(",")}');
      return MCPCallResult(
        message: 'self profile updated',
        parameters: {'ok': true, 'changed': changed},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_set_self_profile failed', e, st);
      return MCPCallResult(
        message: 'l3_set_self_profile: failed: $e',
        parameters: {
          'ok': false,
          'error': 'set_profile_failed',
          'detail': '$e',
        },
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_set_self_profile',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): change the current '
        "account's own nickname / statusMessage / avatar via the real "
        'FfiChatService.updateSelfProfile + updateAvatar path so a paired '
        'friend observes the change over the live DHT. Pass any subset of '
        'nickname, statusMessage, avatarPath. avatar is hash-gated (use a NEW '
        'image). Renaming is safe for l3-registered (seed-marker) accounts; '
        'only legacy nickname-recognized fixture accounts lose mutating-tool '
        'access after a rename — run those on a disposable fresh account.',
    inputSchema: ObjectSchema(
      properties: {
        'nickname': StringSchema(description: 'New self nickname.'),
        'statusMessage': StringSchema(description: 'New self status message.'),
        'avatarPath': StringSchema(
          description: 'Absolute path to a NEW avatar image (hash-gated send).',
        ),
        'avatarContent': StringSchema(
          description:
              'Inline avatar bytes; the app writes a sandbox-safe temp source '
              'and sends it (use a unique value per run to beat the hash-gate).',
        ),
      },
    ),
  ),
);

/// S79: invoke the avatar pick+persist flow with the picker bypassed. Writes a
/// sandbox-safe temp source image from [content] (or uses [path]), temporarily
/// sets the avatar-pick override, runs the REAL `pickAndPersistAvatar` (copy
/// into the avatars dir + persist), then restores the override. Returns the
/// persisted destPath. test/seed account only.
MCPCallEntry _l3PickAvatarEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_pick_avatar: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final content = (request['content'] as Object?)?.toString();
    final path = (request['path'] as Object?)?.toString().trim();
    String? src = (path != null && path.isNotEmpty) ? path : null;
    if (src == null && content != null) {
      final dir = await Directory.systemTemp.createTemp('l3pickavatar');
      final f = File(
        '${dir.path}/picked_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await f.writeAsString(content);
      src = f.path;
    }
    if (src == null) {
      return MCPCallResult(
        message: 'l3_pick_avatar: need "content" or "path"',
        parameters: {'ok': false, 'error': 'missing_source'},
      );
    }
    final prev = _avatarPickPathOverride;
    _avatarPickPathOverride = src;
    try {
      final toxId = (await Prefs.getCurrentAccountToxId()) ?? '';
      final picked = await pickAndPersistAvatar(
        isEditable: true,
        userId: toxId,
      );
      if (picked == null) {
        return MCPCallResult(
          message: 'l3_pick_avatar: pickAndPersistAvatar returned null',
          parameters: {'ok': false, 'error': 'pick_failed'},
        );
      }
      AppLogger.info('[L3] l3_pick_avatar: persisted ${picked.destPath}');
      return MCPCallResult(
        message: 'avatar picked',
        parameters: {'ok': true, 'destPath': picked.destPath},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_pick_avatar failed', e, st);
      return MCPCallResult(
        message: 'l3_pick_avatar: failed: $e',
        parameters: {'ok': false, 'error': 'pick_failed', 'detail': '$e'},
      );
    } finally {
      _avatarPickPathOverride = prev;
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_pick_avatar',
    description:
        'L3 TEST ONLY (test/seed account): run the avatar pick+persist flow with '
        'the native picker bypassed — provide inline "content" (app writes a temp '
        'source image) or an existing "path". Returns the persisted destPath. '
        'Verify via l3_dump_state (self avatar) / Prefs.',
    inputSchema: ObjectSchema(
      properties: {
        'content': StringSchema(
          description: 'Inline image bytes; app writes a temp source.',
        ),
        'path': StringSchema(description: 'Existing source image path.'),
      },
    ),
  ),
);

/// S53 (codex-vetted approach 2026-06-01): exercise the in-app notification-tap
/// ROUTING half without an OS banner / OS tap. Pushes a `c2c_<pubkey>` payload
/// onto the SAME `NotificationService.onSelectStream` the OS handler writes to,
/// which production routes via `NotificationMessageListener.onConversationTapped`
/// → `_routeToNotificationPayload` → `_openChat` → sets
/// `UikitDataFacade.currentConversation` (and the Chats tab). Assert the open
/// conversation via `l3_dump_state.currentConversation`. The OS banner posting
/// + OS-level tap remain OS-gated and out of scope for this tool.
MCPCallEntry _l3SimulateNotificationTapEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_simulate_notification_tap: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    var payload = (request['conversationId'] ?? request['payload'] ?? '')
        .toString()
        .trim();
    if (payload.isEmpty) {
      return MCPCallResult(
        message:
            'l3_simulate_notification_tap: need "conversationId" '
            '(e.g. c2c_<pubkey>, group_<gid>, missed_call:<id>)',
        parameters: {'ok': false, 'error': 'missing_conversation_id'},
      );
    }
    // Convenience: a bare Tox id becomes a C2C tap payload (the real form).
    const known = ['c2c_', 'group_', 'missed_call:', 'friend_req:'];
    if (!known.any(payload.startsWith)) {
      payload = 'c2c_$payload';
    }
    NotificationService.instance.debugInjectNotificationTap(payload);
    AppLogger.info(
      '[L3] l3_simulate_notification_tap: injected payload "$payload"',
    );
    return MCPCallResult(
      message: 'notification tap injected',
      parameters: {'ok': true, 'payload': payload},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_simulate_notification_tap',
    description:
        'L3 TEST ONLY (test/seed account): inject a notification-tap payload '
        'onto NotificationService.onSelectStream to drive the real in-app '
        'routing (opens the conversation; sets UikitDataFacade.currentConversation '
        'and flips to the Chats tab) WITHOUT a real OS banner/tap. Pass a '
        'c2c_<pubkey> / group_<gid> / missed_call:<id> payload, or a bare Tox '
        'id (treated as c2c_). Assert the result via l3_dump_state.currentConversation.',
    inputSchema: ObjectSchema(
      properties: {
        'conversationId': StringSchema(
          description:
              'Tap payload: c2c_<pubkey>, group_<gid>, or bare Tox id.',
        ),
      },
    ),
  ),
);

/// S83 (codex-vetted approach 2026-06-01): mute/unmute a C2C conversation by
/// setting its per-peer receive option (0=receive, 1=no-notify, 2=block). The
/// notification listener's `_shouldSuppress` reads `recvOpt` from the UIKit
/// conversation CACHE (`UikitDataFacade.conversationList[i].recvOpt`,
/// notification_message_listener.dart:224) — which is hydrated from Prefs only
/// at conversation-refresh time. So this writes `Prefs.setC2CReceiveMessageOpt`
/// (persistence + what the converter reads) AND mutates the cached
/// conversation's `recvOpt` in place (the exact value the converter would
/// produce) + notifies, so the suppression input is live immediately.
/// `recvOpt` is surfaced in `l3_dump_state.conversations[]`. MUTATING, C2C-only,
/// test/seed account.
MCPCallEntry _l3SetC2CRecvOptEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_set_c2c_recv_opt: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_set_c2c_recv_opt: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var userId = request['userId'] ?? request['conversationId'] ?? '';
    if (userId.startsWith('group_') || request['groupId'] != null) {
      return MCPCallResult(
        message: 'l3_set_c2c_recv_opt: C2C only — group ids unsupported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    if (userId.startsWith('c2c_')) userId = userId.substring(4);
    if (userId.isEmpty) userId = ffi.activePeerId ?? '';
    if (userId.isEmpty) {
      return MCPCallResult(
        message: 'l3_set_c2c_recv_opt: no target — pass userId',
        parameters: {'ok': false, 'error': 'no_target'},
      );
    }
    final groupReject = await _rejectIfGroupTarget(
      'l3_set_c2c_recv_opt',
      userId,
      ffi.knownGroups,
      ffi.quitGroups,
    );
    if (groupReject != null) return groupReject;
    final raw = request['opt']?.toString().trim() ?? '';
    final opt = int.tryParse(raw);
    if (opt == null || opt < 0 || opt > 2) {
      return MCPCallResult(
        message: 'l3_set_c2c_recv_opt: "opt" must be 0|1|2 (got "$raw")',
        parameters: {'ok': false, 'error': 'bad_opt'},
      );
    }
    try {
      final toxId = (await Prefs.getCurrentAccountToxId()) ?? '';
      await Prefs.setC2CReceiveMessageOpt(
        userId,
        opt,
        toxId.isEmpty ? null : toxId,
      );
      // _shouldSuppress reads recvOpt from the UIKit conversation cache, not
      // Prefs — mutate the cached entry in place so suppression is live now.
      final wantPk = toToxPublicKey(userId);
      var cacheMatched = 0;
      for (final c in UikitDataFacade.conversationList) {
        final cid = c.conversationID;
        final bare = cid.startsWith('c2c_') ? cid.substring(4) : cid;
        if (c.type == 1 && toToxPublicKey(bare) == wantPk) {
          c.recvOpt = opt;
          cacheMatched++;
        }
      }
      UikitDataFacade.notifyCurrentConversation();
      AppLogger.info(
        '[L3] l3_set_c2c_recv_opt MUTATED $userId opt=$opt '
        '(cacheMatched=$cacheMatched)',
      );
      return MCPCallResult(
        message: 'recv opt set: $userId=$opt',
        parameters: {
          'ok': true,
          'userId': userId,
          'opt': opt,
          'cacheMatched': cacheMatched,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_set_c2c_recv_opt failed', e, st);
      return MCPCallResult(
        message: 'l3_set_c2c_recv_opt: failed: $e',
        parameters: {
          'ok': false,
          'error': 'set_recv_opt_failed',
          'detail': '$e',
        },
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_set_c2c_recv_opt',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING, C2C-only): set a C2C '
        "conversation's receive option (0=receive, 1=no-notify, 2=block/mute) "
        'so the notification listener suppresses inbound banners. Writes Prefs '
        'AND updates the UIKit conversation cache that _shouldSuppress reads. '
        'recvOpt is exposed in l3_dump_state.conversations[]. Targets '
        'userId/conversationId, or the active conversation.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(description: 'Target Tox ID (64/76 hex).'),
        'conversationId': StringSchema(
          description: 'c2c_<toxId> alternative to userId.',
        ),
        'opt': StringSchema(description: '0 | 1 | 2'),
      },
      required: ['opt'],
    ),
  ),
);

/// S21 send_file_attachment / S24 accept_incoming_file: send a C2C file via the
/// real `FakeChatMessageProvider.sendFile` → `FfiChatService.sendFile` →
/// `tox_file_send` path. The receiving instance AUTO-accepts files under its
/// size limit (default 30 MiB), so a small file covers both the send (S21) and
/// the receive/accept (S24) legs. Prefer the `content` arg: the app writes the
/// source file itself (into its own sandbox-writable temp dir) so there is no
/// cross-sandbox source-readability problem; `filePath` sends an existing path
/// directly. MUTATING, C2C-only, test/seed account. Assert via
/// `l3_dump_state.messages[].{mediaKind,fileName,filePath}`.
MCPCallEntry _l3SendFileEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_send_file: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    final provider = FakeUIKit.instance.messageProvider;
    if (ffi == null || provider == null) {
      return MCPCallResult(
        message: 'l3_send_file: session not ready (no ffi/provider)',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var userId = request['userId'] ?? request['conversationId'] ?? '';
    if (userId.startsWith('group_') || request['groupId'] != null) {
      return MCPCallResult(
        message: 'l3_send_file: C2C only — group sends are not supported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    if (userId.startsWith('c2c_')) userId = userId.substring(4);
    if (userId.isEmpty) userId = ffi.activePeerId ?? '';
    if (userId.isEmpty) {
      return MCPCallResult(
        message:
            'l3_send_file: no target — pass "userId" or open a conversation',
        parameters: {'ok': false, 'error': 'no_target'},
      );
    }
    final groupReject = await _rejectIfGroupTarget(
      'l3_send_file',
      userId,
      ffi.knownGroups,
      ffi.quitGroups,
    );
    if (groupReject != null) return groupReject;
    final fileName = (request['fileName'] as Object?)?.toString().trim();
    final content = (request['content'] as Object?)?.toString();
    // contentB64: BINARY-safe inline source (base64). `content` goes through
    // writeAsString and corrupts non-text bytes (PNG/PDF), and `filePath`
    // can't reach host-side files from inside the macOS app sandbox — the
    // screenshot seed pipeline sends its generated media this way.
    final contentB64 = (request['contentB64'] as Object?)?.toString();
    var filePath = (request['filePath'] as Object?)?.toString().trim();
    try {
      if (contentB64 != null && contentB64.isNotEmpty) {
        final name = (fileName == null || fileName.isEmpty)
            ? 'l3_file.bin'
            : fileName;
        final List<int> bytes;
        try {
          bytes = base64Decode(contentB64);
        } on FormatException catch (e) {
          return MCPCallResult(
            message: 'l3_send_file: contentB64 is not valid base64: $e',
            parameters: {'ok': false, 'error': 'bad_base64'},
          );
        }
        final dir = await Directory.systemTemp.createTemp('l3send');
        final f = File('${dir.path}/$name');
        await f.writeAsBytes(bytes);
        filePath = f.path;
      } else if (content != null) {
        // App writes its OWN source file (sandbox-safe: it writes + reads it).
        final name = (fileName == null || fileName.isEmpty)
            ? 'l3_file.txt'
            : fileName;
        final dir = await Directory.systemTemp.createTemp('l3send');
        final f = File('${dir.path}/$name');
        await f.writeAsString(content);
        filePath = f.path;
      }
      if (filePath == null || filePath.isEmpty) {
        return MCPCallResult(
          message: 'l3_send_file: need "content", "contentB64" or "filePath"',
          parameters: {'ok': false, 'error': 'missing_source'},
        );
      }
      await provider.sendFile(
        userID: userId,
        filePath: filePath,
        fileName: fileName,
      );
      AppLogger.info(
        '[L3] l3_send_file: sent "$filePath" (name=$fileName) to $userId',
      );
      return MCPCallResult(
        message: 'file sent',
        parameters: {
          'ok': true,
          'userId': userId,
          'filePath': filePath,
          'fileName': fileName,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_send_file failed', e, st);
      return MCPCallResult(
        message: 'l3_send_file: send failed: $e',
        parameters: {'ok': false, 'error': 'send_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_send_file',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING, C2C-only): send a file '
        'attachment to a C2C peer via the real sendFile path. Pass "content" '
        '(the app writes a sandbox-safe temp source file) or an existing '
        '"filePath", plus optional "fileName". The receiver auto-accepts files '
        'under its size limit. Assert via l3_dump_state.messages[].mediaKind / '
        'fileName / filePath.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(
          description: 'Target Tox ID (64/76 hex). Optional — active conv.',
        ),
        'conversationId': StringSchema(
          description: 'c2c_<toxId> alternative to userId.',
        ),
        'content': StringSchema(
          description:
              'Inline TEXT file content; the app writes a temp source file.',
        ),
        'contentB64': StringSchema(
          description:
              'Inline BINARY file content as base64 (PNG/PDF-safe); the app '
              'decodes + writes a temp source file inside its sandbox.',
        ),
        'filePath': StringSchema(
          description:
              'Existing app-readable source path (alternative to content).',
        ),
        'fileName': StringSchema(description: 'Optional display file name.'),
      },
    ),
  ),
);

/// S34 group_message_two_process: create / join / send in an NGC group so two
/// live instances exchange a group message. `createGroup(type:'group')` makes a
/// PUBLIC group and returns a 64-char chat-id; the peer joins by that chat-id
/// (no invite — proven in tim2tox auto_tests `scenario_group_test.dart`).
/// History is keyed by the bare group id (NOT `group_`-prefixed); a sent message
/// is isSelf=true, an inbound one (event type==10) is isSelf=false. Assert via
/// `l3_dump_state {conversationId: group_<gid>}` (the group-history readout).
/// MUTATING, test/seed account.
MCPCallEntry _l3CreateGroupEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_create_group: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_create_group: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    final name = (request['name'] as Object?)?.toString().trim();
    // type: 'public' (default) → PUBLIC NGC (joinable by chat-id via the DHT);
    // 'private' → PRIVATE NGC (invite-only; peers connect over the existing
    // friend link, NOT the public DHT — far more reliable for a same-host pair).
    // Maps to the C++ groupType string the privacy switch reads ("Private" →
    // TOX_GROUP_PRIVACY_STATE_PRIVATE; anything else → PUBLIC).
    final type = (request['type'] as Object?)?.toString().trim().toLowerCase();
    final groupType = type == 'private' ? 'Private' : 'group';
    try {
      final effectiveName = (name == null || name.isEmpty)
          ? 'l3_test_group'
          : name;
      final gid = await ffi.createGroup(effectiveName, groupType: groupType);
      if (gid == null || gid.isEmpty) {
        return MCPCallResult(
          message: 'l3_create_group: createGroup returned null',
          parameters: {'ok': false, 'error': 'create_failed'},
        );
      }
      // toxee's createGroup returns a LOCAL group id (e.g. "tox_1"); the
      // joinable 64-char NGC chat-id is a separate value (tox_group_get_chat_id).
      // Fetch it (with a short retry — it can lag the create by a tick) so a
      // peer can l3_join_group it.
      String? chatId;
      for (var i = 0; i < 12; i++) {
        chatId = ffi.getGroupChatId(gid);
        if (chatId != null && chatId.length == 64) break;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      // Store the display name like the UI create path does — the
      // conversation list resolves group titles from Prefs.getGroupName
      // (fake_provider._refreshGroups), so without this the tile (and the
      // chat header) shows the bare local id ("tox_1"). Persist the EFFECTIVE
      // name (incl. the default) so the no-name path doesn't regress to the
      // bare id either (codex).
      await Prefs.setGroupName(gid, effectiveName);
      AppLogger.info('[L3] l3_create_group: created $gid chatId=$chatId');
      return MCPCallResult(
        message: 'group created',
        parameters: {'ok': true, 'groupId': gid, 'chatId': chatId},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_create_group failed', e, st);
      return MCPCallResult(
        message: 'l3_create_group: failed: $e',
        parameters: {'ok': false, 'error': 'create_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_create_group',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): create an NGC group and '
        'return its local id + 64-char chat-id. type=public (default) is '
        'DHT-joinable by l3_join_group; type=private is invite-only (peers '
        'connect over the friend link — use l3_invite_to_group). Optional "name".',
    inputSchema: ObjectSchema(
      properties: {
        'name': StringSchema(description: 'Optional group name.'),
        'type': StringSchema(
          description:
              'public (default, chat-id-joinable) | private (invite-only).',
        ),
      },
    ),
  ),
);

/// Inject one INBOUND group text through the REAL ingestion seam
/// (`FfiChatService.ingestInboundGroupText` — the same dedup → history →
/// unread → stream pipeline the native type==10 event drives), so a
/// deterministic multi-sender group view can be seeded without relying on
/// same-host NGC peer links (NAT-hairpin announces make those a per-pair
/// coin flip; see the screenshots plan). The rendered bubble is
/// indistinguishable from real delivery because it IS the delivery path
/// minus the radio. MUTATING — test/seed account only.
MCPCallEntry _l3InjectGroupTextEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_inject_group_text: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_inject_group_text: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var groupId = (request['groupId'] as Object?)?.toString().trim() ?? '';
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    final fromUserId =
        (request['fromUserId'] as Object?)?.toString().trim() ?? '';
    final text = (request['text'] as Object?)?.toString() ?? '';
    if (groupId.isEmpty || fromUserId.isEmpty || text.isEmpty) {
      return MCPCallResult(
        message: 'l3_inject_group_text: need "groupId", "fromUserId", "text"',
        parameters: {'ok': false, 'error': 'bad_args'},
      );
    }
    if (!ffi.knownGroups.contains(groupId)) {
      return MCPCallResult(
        message: 'l3_inject_group_text: not a joined group: $groupId',
        parameters: {'ok': false, 'error': 'unknown_group'},
      );
    }
    try {
      final ingested = ffi.ingestInboundGroupText(
        gid: groupId,
        from: fromUserId,
        text: text,
      );
      AppLogger.info(
        '[L3] l3_inject_group_text: gid=$groupId from=$fromUserId '
        'ingested=$ingested',
      );
      return MCPCallResult(
        message: ingested ? 'group text ingested' : 'skipped (dup/quit)',
        parameters: {'ok': true, 'ingested': ingested},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_inject_group_text failed', e, st);
      return MCPCallResult(
        message: 'l3_inject_group_text: failed: $e',
        parameters: {'ok': false, 'error': 'inject_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_inject_group_text',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): materialize one INBOUND '
        'group text via the real FfiChatService ingestion seam (dedup, '
        'history persistence, unread, message stream) — deterministic '
        'multi-sender group seeding without same-host NGC peer-link '
        'flakiness. fromUserId should be the sender\'s main Tox pubkey so '
        'the UI resolves its display name from the friend list.',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(description: 'Local group id (tox_N).'),
        'fromUserId': StringSchema(description: 'Sender Tox pubkey (64 hex).'),
        'text': StringSchema(description: 'Message text.'),
      },
      required: ['groupId', 'fromUserId', 'text'],
    ),
  ),
);

MCPCallEntry _l3JoinGroupEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_join_group: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_join_group: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var groupId = (request['groupId'] as Object?)?.toString().trim() ?? '';
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    if (groupId.isEmpty) {
      return MCPCallResult(
        message: 'l3_join_group: need "groupId" (64-char chat-id)',
        parameters: {'ok': false, 'error': 'missing_group_id'},
      );
    }
    try {
      await ffi.joinGroup(groupId);
      AppLogger.info('[L3] l3_join_group: joined $groupId');
      return MCPCallResult(
        message: 'group joined',
        parameters: {'ok': true, 'groupId': groupId},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_join_group failed', e, st);
      return MCPCallResult(
        message: 'l3_join_group: failed: $e',
        parameters: {'ok': false, 'error': 'join_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_join_group',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): join a PUBLIC NGC group by '
        'its 64-char chat-id (no invite needed). Accepts a bare id or group_<id>.',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(description: '64-char group chat-id.'),
      },
      required: ['groupId'],
    ),
  ),
);

/// S35: leave/quit a group the local (test) account belongs to. Calls
/// `FfiChatService.quitGroup` (ffi_chat_service.dart:5075), which drives the
/// native quit (tox_group_leave / tox_conference_delete via DartQuitGroup →
/// V2TIMGroupManagerImpl::QuitGroup) and synchronously removes the gid from
/// `ffi.knownGroups` + adds it to `ffi.quitGroups`. Single-instance clean: the
/// CREATOR leaving its OWN group resolves group_number from its local maps, so
/// the leave + knownGroups removal succeed without a second peer. Accepts a
/// bare LOCAL group id (e.g. "tox_1", as returned by l3_create_group's
/// `groupId`) or a `group_<id>` conversation id. MUTATING — test/seed account.
MCPCallEntry _l3LeaveGroupEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_leave_group: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_leave_group: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var groupId = (request['groupId'] as Object?)?.toString().trim() ?? '';
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    if (groupId.isEmpty) {
      return MCPCallResult(
        message: 'l3_leave_group: need "groupId" (local id or group_<id>)',
        parameters: {'ok': false, 'error': 'missing_group_id'},
      );
    }
    try {
      await ffi.quitGroup(groupId);
      AppLogger.info('[L3] l3_leave_group: left $groupId');
      return MCPCallResult(
        message: 'group left',
        parameters: {
          'ok': true,
          'groupId': groupId,
          'knownGroups': ffi.knownGroups.toList(),
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_leave_group failed', e, st);
      return MCPCallResult(
        message: 'l3_leave_group: failed: $e',
        parameters: {'ok': false, 'error': 'leave_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_leave_group',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): leave/quit a group the '
        'local account belongs to (drives the native tox_group_leave path and '
        'removes the gid from knownGroups). Accepts a bare LOCAL group id (the '
        '`groupId` from l3_create_group) or group_<id>.',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(
          description: 'Local group id (e.g. "tox_1") or group_<id>.',
        ),
      },
      required: ['groupId'],
    ),
  ),
);

MCPCallEntry _l3SendGroupTextEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final text = (request['text'] as Object?)?.toString() ?? '';
    if (text.isEmpty) {
      return MCPCallResult(
        message: 'l3_send_group_text: missing required "text"',
        parameters: {'ok': false, 'error': 'missing_text'},
      );
    }
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_send_group_text: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_send_group_text: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var groupId = (request['groupId'] as Object?)?.toString().trim() ?? '';
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    if (groupId.isEmpty) {
      return MCPCallResult(
        message: 'l3_send_group_text: need "groupId"',
        parameters: {'ok': false, 'error': 'missing_group_id'},
      );
    }
    try {
      await ffi.sendGroupText(groupId, text);
      AppLogger.info('[L3] l3_send_group_text: sent "$text" to group $groupId');
      return MCPCallResult(
        message: 'group text sent',
        parameters: {'ok': true, 'groupId': groupId, 'text': text},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_send_group_text failed', e, st);
      return MCPCallResult(
        message: 'l3_send_group_text: failed: $e',
        parameters: {'ok': false, 'error': 'send_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_send_group_text',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): send a text message to an '
        'NGC group via the real FfiChatService.sendGroupText path. Accepts a '
        'bare group id or group_<id>.',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(description: 'Target group id (64-char).'),
        'text': StringSchema(description: 'Message text.'),
      },
      required: ['groupId', 'text'],
    ),
  ),
);

/// S47/S81: invite a friend to an NGC group via the SDK group manager
/// (`getGroupManager().inviteUserToGroup` → native_im adapter →
/// `DartInviteUserToGroup` → C++ `tox_group_invite_friend`), the SAME path the
/// UIKit add-member flow uses. With the invitee's `autoAcceptGroupInvites=true`
/// (l3_set_setting), the C++ pipeline auto-joins via `tox_group_invite_accept`.
/// MUTATING, test/seed account.
MCPCallEntry _l3InviteToGroupEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_invite_to_group: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    var groupId = (request['groupId'] as Object?)?.toString().trim() ?? '';
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    final userId = (request['userId'] as Object?)?.toString().trim() ?? '';
    if (groupId.isEmpty || userId.isEmpty) {
      return MCPCallResult(
        message: 'l3_invite_to_group: need "groupId" and "userId"',
        parameters: {'ok': false, 'error': 'missing_args'},
      );
    }
    try {
      final res = await TencentImSDKPlugin.v2TIMManager
          .getGroupManager()
          .inviteUserToGroup(groupID: groupId, userList: [userId]);
      final ok = res.code == 0;
      AppLogger.info(
        '[L3] l3_invite_to_group: group=$groupId user=$userId '
        'code=${res.code} desc=${res.desc}',
      );
      return MCPCallResult(
        message: ok ? 'invite sent' : 'invite failed (code=${res.code})',
        parameters: {
          'ok': ok,
          'code': res.code,
          'desc': res.desc,
          'groupId': groupId,
          'userId': userId,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_invite_to_group failed', e, st);
      return MCPCallResult(
        message: 'l3_invite_to_group: failed: $e',
        parameters: {'ok': false, 'error': 'invite_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_invite_to_group',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): invite a friend to an NGC '
        'group via the SDK group manager (reaches C++ tox_group_invite_friend). '
        'With the invitee autoAcceptGroupInvites=true, they auto-join.',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(
          description: 'Group id (local tox_N or chat-id).',
        ),
        'userId': StringSchema(description: 'Friend Tox ID to invite.'),
      },
      required: ['groupId', 'userId'],
    ),
  ),
);

/// S49 (B-block): run the in-page contact-search filter deterministically —
/// the SAME case-insensitive remark/nick/userID match the (now-rendered) contact
/// AZ-list uses — and return the filtered count. Lets a scenario assert the
/// contact search field's filter without flaky UI snapshot-counting; the field
/// itself renders with ValueKey('contact_search_field'). Read-only.
MCPCallEntry _l3ContactSearchEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final query = (request['query'] as Object?)?.toString() ?? '';
    try {
      final count = TencentCloudChatContactData.filteredContactCountForQuery(
        query,
      );
      AppLogger.info(
        '[L3] l3_contact_search: query="$query" filteredCount=$count',
      );
      return MCPCallResult(
        message: 'contact search',
        parameters: {'ok': true, 'query': query, 'filteredCount': count},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_contact_search failed', e, st);
      return MCPCallResult(
        message: 'l3_contact_search: failed: $e',
        parameters: {
          'ok': false,
          'error': 'contact_search_failed',
          'detail': '$e',
        },
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_contact_search',
    description:
        'L3 TEST ONLY: run the in-page contact-search filter (case-insensitive '
        'remark/nick/userID contains) and return filteredCount. Empty query → '
        'full contact count. Read-only.',
    inputSchema: ObjectSchema(
      properties: {
        'query': StringSchema(description: 'Search query (empty = full list).'),
      },
    ),
  ),
);

/// S37: kick a member from a group via the SDK group manager
/// (`getGroupManager().kickGroupMember` → native_im → C++ `DartKickGroupMember`
/// → `tox_group_kick_peer`), the real binary-replacement path (NOT the no-op
/// Platform wrapper). MUTATING, test/seed account. (Role-change is a separate
/// path; this covers kick.)
MCPCallEntry _l3KickGroupMemberEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_kick_group_member: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    var groupId = (request['groupId'] as Object?)?.toString().trim() ?? '';
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    final rawUserId = (request['userId'] as Object?)?.toString().trim() ?? '';
    if (groupId.isEmpty || rawUserId.isEmpty) {
      return MCPCallResult(
        message: 'l3_kick_group_member: need "groupId" and "userId"',
        parameters: {'ok': false, 'error': 'missing_args'},
      );
    }
    // KickGroupMember resolves the member by its 64-char PUBLIC KEY; a 76-char
    // Tox address (pubkey+nospam+checksum) fails to convert. Normalize first.
    final userId = toToxPublicKey(rawUserId);
    try {
      final res = await TencentImSDKPlugin.v2TIMManager
          .getGroupManager()
          .kickGroupMember(groupID: groupId, memberList: [userId]);
      final ok = res.code == 0;
      AppLogger.info(
        '[L3] l3_kick_group_member: group=$groupId user=$userId '
        'code=${res.code} desc=${res.desc}',
      );
      return MCPCallResult(
        message: ok ? 'member kicked' : 'kick failed (code=${res.code})',
        parameters: {
          'ok': ok,
          'code': res.code,
          'desc': res.desc,
          'groupId': groupId,
          'userId': userId,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_kick_group_member failed', e, st);
      return MCPCallResult(
        message: 'l3_kick_group_member: failed: $e',
        parameters: {'ok': false, 'error': 'kick_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_kick_group_member',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): kick a member from a group '
        'via the SDK group manager (reaches C++ tox_group_kick_peer — NOT the '
        'no-op Platform wrapper).',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(
          description: 'Group id (local tox_N or chat-id).',
        ),
        'userId': StringSchema(description: 'Member Tox ID to kick.'),
      },
      required: ['groupId', 'userId'],
    ),
  ),
);

/// S37: list an NGC group's members via the SDK group manager
/// (`getGroupManager().getGroupMemberList` → C++ `GetGroupMemberList`). The
/// crux of the kick flow: each REMOTE member's `userID` is that member's
/// NGC GROUP-SPECIFIC public key (from `tox_group_peer_get_public_key`), NOT
/// their friend/Tox pubkey — the SAME identity `KickGroupMember` resolves via
/// the callback-populated `group_peer_id_cache_`. So "list members → kick by a
/// member's userID" resolves where "kick by friend userID" never could. The
/// self entry is added with the caller's GLOBAL Tox pubkey, so `isSelf` is
/// computed by matching the current account's pubkey; a driver kicks the
/// non-self member. A remote member appearing here also PROVES the founder's
/// peer cache holds it — the exact precondition for the kick to resolve.
/// Read-only; test/seed account only.
MCPCallEntry _l3GroupMemberListEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_group_member_list: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    var groupId = (request['groupId'] as Object?)?.toString().trim() ?? '';
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    if (groupId.isEmpty) {
      return MCPCallResult(
        message: 'l3_group_member_list: need "groupId"',
        parameters: {'ok': false, 'error': 'missing_group_id'},
      );
    }
    try {
      // The self entry's userID is the caller's GLOBAL Tox pubkey (C++ adds it
      // via tox_self_get_public_key), so match against the current account to
      // flag self. Remote members carry their per-group pubkey instead.
      final selfPk = toToxPublicKey(
        (await Prefs.getCurrentAccountToxId()) ?? '',
      );
      // Without a self pubkey, isSelf would be false for EVERY member — a
      // driver would then mistake the self entry for "the other member" and try
      // to kick itself. Fail loudly instead of returning mislabeled members.
      if (selfPk.isEmpty) {
        return MCPCallResult(
          message:
              'l3_group_member_list: no current account tox id — cannot '
              'distinguish self',
          parameters: {'ok': false, 'error': 'no_self_id', 'groupId': groupId},
        );
      }
      final res = await TencentImSDKPlugin.v2TIMManager
          .getGroupManager()
          .getGroupMemberList(
            groupID: groupId,
            filter: GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ALL,
            nextSeq: '0',
            count: 100,
          );
      if (res.code != 0) {
        return MCPCallResult(
          message: 'l3_group_member_list: failed (code=${res.code})',
          parameters: {
            'ok': false,
            'error': 'member_list_failed',
            'code': res.code,
            'desc': res.desc,
            'groupId': groupId,
          },
        );
      }
      final raw = res.data?.memberInfoList;
      // De-duplicate by Tox public key. The NGC peer enumeration underneath
      // getGroupMemberList is keyed by ephemeral per-session peer ids, so a peer
      // that churns (disconnect/reconnect — frequent when many instances run on
      // one host) can surface multiple times for the SAME public key (observed:
      // member count grows 2->3->4 across rapid create/leave cycles, with the
      // peer's row userID repeated verbatim). The real UI member-list page
      // collapses these in its render, so this seam must report the same
      // canonical view — otherwise a consumer (e.g. the 2-process member-row
      // resolver) can't tell which entry maps to the rendered row. Keep the
      // highest-role entry per pubkey so a ghost Member copy can't shadow the
      // Owner/Admin. The deeper source-level fix belongs in tim2tox
      // getGroupMemberList; deferred per the submodule-pin freeze.
      final byPk = <String, V2TimGroupMemberFullInfo>{};
      final pkOrder = <String>[];
      if (raw != null) {
        for (final m in raw) {
          final pk = toToxPublicKey(m.userID);
          final existing = byPk[pk];
          if (existing == null) {
            byPk[pk] = m;
            pkOrder.add(pk);
          } else if ((m.role ?? 0) > (existing.role ?? 0)) {
            byPk[pk] = m;
          }
        }
      }
      final members = <Map<String, Object?>>[];
      for (final pk in pkOrder) {
        final m = byPk[pk]!;
        final uid = m.userID;
        members.add({
          'userID': uid,
          'nickName': m.nickName,
          'role': m.role,
          'isSelf': selfPk.isNotEmpty && pk == selfPk,
        });
      }
      AppLogger.info(
        '[L3] l3_group_member_list: group=$groupId count=${members.length}',
      );
      return MCPCallResult(
        message: 'group members',
        parameters: {
          'ok': true,
          'groupId': groupId,
          'memberCount': members.length,
          'members': members,
          'nextSeq': res.data?.nextSeq,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_group_member_list failed', e, st);
      return MCPCallResult(
        message: 'l3_group_member_list: failed: $e',
        parameters: {
          'ok': false,
          'error': 'member_list_failed',
          'detail': '$e',
        },
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_group_member_list',
    description:
        'L3 TEST ONLY (test/seed account): list an NGC group\'s members. Each '
        'member exposes userID (the NGC GROUP-SPECIFIC public key — the identity '
        'l3_kick_group_member resolves, NOT the friend Tox pubkey), nickName, '
        'role, and isSelf. A remote member appearing here proves the founder\'s '
        'peer cache holds it (the kick precondition). Read-only.',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(
          description: 'Group id (local tox_N or chat-id).',
        ),
      },
      required: ['groupId'],
    ),
  ),
);

/// UNGATED campaign hook: enable/disable native auto-accept of group invites on
/// the CURRENT account, so a fresh/non-test B auto-joins a PRIVATE group invite
/// over the friend link (`tox_group_invite_accept`). Mirrors the
/// autoAcceptGroupInvites branch of the test-gated `l3_set_setting` (Prefs write
/// + native ffi sync); dump_state reads the same persisted flag back. Needed
/// because `l3_set_setting` refuses non-test accounts, which would block the
/// "B auto-joins" group_message campaign before it starts.
MCPCallEntry _l3SetAutoAcceptGroupInvitesEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final raw = (request['value'] as Object?)?.toString().trim().toLowerCase();
    if (raw == null || (raw != 'true' && raw != 'false')) {
      return MCPCallResult(
        message: 'l3_set_auto_accept_group_invites: need "value" true|false',
        parameters: {'ok': false, 'error': 'missing_value'},
      );
    }
    final value = raw == 'true';
    try {
      final toxId = (await Prefs.getCurrentAccountToxId()) ?? '';
      final scoped = toxId.isEmpty ? null : toxId;
      await Prefs.setAutoAcceptGroupInvites(value, scoped);
      final ffi = FakeUIKit.instance.im?.ffi;
      var nativeSyncSkipped = false;
      if (ffi != null) {
        ffi.setAutoAcceptGroupInvites(value);
      } else {
        nativeSyncSkipped = true;
      }
      AppLogger.info(
        '[L3] l3_set_auto_accept_group_invites MUTATED autoAcceptGroupInvites='
        '$value${nativeSyncSkipped ? " (native sync SKIPPED — no service)" : ""}',
      );
      return MCPCallResult(
        message: 'autoAcceptGroupInvites=$value',
        parameters: {
          'ok': true,
          'value': value,
          if (nativeSyncSkipped) 'nativeSyncSkipped': true,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_set_auto_accept_group_invites failed', e, st);
      return MCPCallResult(
        message: 'l3_set_auto_accept_group_invites: failed: $e',
        parameters: {'ok': false, 'error': 'set_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_set_auto_accept_group_invites',
    description:
        'UNGATED harness hook: set native auto-accept of group invites on the '
        'current account (Prefs + ffi). Lets a fresh/non-test B auto-join a '
        'PRIVATE group invite. value=true|false.',
    inputSchema: ObjectSchema(
      properties: {'value': StringSchema(description: 'true|false')},
      required: ['value'],
    ),
  ),
);

/// UNGATED campaign hook: return the member COUNT of a joined NGC group via the
/// SDK group manager (same `getGroupMemberList` the test-gated
/// `l3_group_member_list` uses, count only — no per-member identity, so no
/// self-pubkey requirement). The real-UI group_message peer-readiness gate
/// (`_waitGroupPeersConnected`) needs this on fresh/non-test accounts, where the
/// full member-list tool refuses. Read-only.
MCPCallEntry _l3GroupMemberCountEntry() => MCPCallEntry.tool(
  handler: (request) async {
    var groupId = (request['groupId'] as Object?)?.toString().trim() ?? '';
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    if (groupId.isEmpty) {
      return MCPCallResult(
        message: 'l3_group_member_count: need "groupId"',
        parameters: {'ok': false, 'error': 'missing_group_id'},
      );
    }
    try {
      final res = await TencentImSDKPlugin.v2TIMManager
          .getGroupManager()
          .getGroupMemberList(
            groupID: groupId,
            filter: GroupMemberFilterTypeEnum.V2TIM_GROUP_MEMBER_FILTER_ALL,
            nextSeq: '0',
            count: 100,
          );
      if (res.code != 0) {
        return MCPCallResult(
          message: 'l3_group_member_count: failed (code=${res.code})',
          parameters: {
            'ok': false,
            'error': 'member_list_failed',
            'code': res.code,
            'groupId': groupId,
          },
        );
      }
      final count = res.data?.memberInfoList?.length ?? 0;
      return MCPCallResult(
        message: 'group member count',
        parameters: {'ok': true, 'groupId': groupId, 'count': count},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_group_member_count failed', e, st);
      return MCPCallResult(
        message: 'l3_group_member_count: failed: $e',
        parameters: {
          'ok': false,
          'error': 'member_list_failed',
          'detail': '$e',
        },
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_group_member_count',
    description:
        'UNGATED harness hook: number of members in a joined NGC group '
        '(getGroupMemberList count). For the group_message peer-readiness gate '
        'on fresh/non-test accounts. Read-only.',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(
          description:
              'Group id (local tox_N or chat-id), with or without the '
              '"group_" prefix.',
        ),
      },
      required: ['groupId'],
    ),
  ),
);

/// UNGATED campaign hook: leave/quit a group (`ffi.quitGroup`), mirroring the
/// test-gated `l3_leave_group` without the test-account gate. The real-UI
/// group_message retry cleanup (`_leaveAllGroups`) uses this on fresh/non-test
/// accounts so a failed attempt's group doesn't leak into the next retry.
MCPCallEntry _l3LeaveGroupUncheckedEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_leave_group_unchecked: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var groupId = (request['groupId'] as Object?)?.toString().trim() ?? '';
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    if (groupId.isEmpty) {
      return MCPCallResult(
        message: 'l3_leave_group_unchecked: need "groupId"',
        parameters: {'ok': false, 'error': 'missing_group_id'},
      );
    }
    try {
      await ffi.quitGroup(groupId);
      AppLogger.info('[L3] l3_leave_group_unchecked: left $groupId');
      return MCPCallResult(
        message: 'left group',
        parameters: {
          'ok': true,
          'groupId': groupId,
          'knownGroups': ffi.knownGroups.toList(),
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_leave_group_unchecked failed', e, st);
      return MCPCallResult(
        message: 'l3_leave_group_unchecked: failed: $e',
        parameters: {'ok': false, 'error': 'leave_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_leave_group_unchecked',
    description:
        'UNGATED harness hook: quit a group (ffi.quitGroup), for group_message '
        'retry cleanup on fresh/non-test accounts.',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(
          description: 'Group id (local tox_N or group_<id>).',
        ),
      },
      required: ['groupId'],
    ),
  ),
);

/// UNGATED campaign hook: clear a JOINED group's message history
/// (`ffi.clearGroupHistory`) — the executable counterpart to the C2C-only
/// `l3_clear_history` (which rejects group ids with `group_unsupported`).
/// `clearGroupHistory` clears the history persistence + the in-memory
/// `_lastByPeer`/`_unreadByPeer` entries but NEVER touches the pinned set, so a
/// gate can assert "clear preserves the row + pin" (S122/S154). Ungated so the
/// two-process group gates run on fresh/non-test accounts.
MCPCallEntry _l3ClearGroupHistoryEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_clear_group_history: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var groupId = (request['groupId'] as Object?)?.toString().trim() ?? '';
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    if (groupId.isEmpty) {
      return MCPCallResult(
        message: 'l3_clear_group_history: need "groupId"',
        parameters: {'ok': false, 'error': 'missing_group_id'},
      );
    }
    // Groupness guard (codex): `ffi.clearGroupHistory` is key-based history
    // deletion with NO groupness check, so a mistyped id or a bare C2C pubkey
    // would otherwise wipe the wrong conversation's history. Only clear ids this
    // instance actually knows as a group (joined OR previously-quit).
    if (!ffi.knownGroups.contains(groupId) &&
        !ffi.quitGroups.contains(groupId)) {
      return MCPCallResult(
        message: 'l3_clear_group_history: not a joined group: $groupId',
        parameters: {'ok': false, 'error': 'not_joined', 'groupId': groupId},
      );
    }
    try {
      await ffi.clearGroupHistory(groupId);
      final remaining = ffi.getHistory(groupId).length;
      AppLogger.info(
        '[L3] l3_clear_group_history: cleared $groupId (remaining=$remaining)',
      );
      return MCPCallResult(
        message: 'cleared group history',
        parameters: {'ok': true, 'groupId': groupId, 'remaining': remaining},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_clear_group_history failed', e, st);
      return MCPCallResult(
        message: 'l3_clear_group_history: failed: $e',
        parameters: {'ok': false, 'error': 'clear_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_clear_group_history',
    description:
        'UNGATED harness hook: clear a joined group\'s message history '
        '(ffi.clearGroupHistory) — the group counterpart to the C2C-only '
        'l3_clear_history. Preserves the conversation row + pin state. For the '
        'S122/S154 clear-history gates on fresh/non-test accounts.',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(
          description: 'Group id (local tox_N or group_<id>).',
        ),
      },
      required: ['groupId'],
    ),
  ),
);

/// UNGATED harness hook: set (or clear, when omitted/empty) this instance's
/// ACTIVE conversation (`ffi.setActivePeer`). A group's inbound path only
/// accrues unread while the group is NOT the active conversation
/// (`ffi_chat_service`: `_activePeerId != gid` → `_unreadByPeer[gid]++`), so the
/// S118/S133 mark-read gate clears the active conversation, lets the peer send,
/// asserts unread>0, then marks read. Ungated for fresh/non-test two-process
/// accounts.
MCPCallEntry _l3SetActiveConversationEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_set_active_conversation: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var target =
        (request['conversationId'] as Object?)?.toString().trim().isNotEmpty ==
            true
        ? (request['conversationId'] as Object).toString().trim()
        : ((request['userId'] as Object?)?.toString().trim() ?? '');
    if (target.startsWith('group_')) target = target.substring(6);
    if (target.startsWith('c2c_')) target = target.substring(4);
    ffi.setActivePeer(target.isEmpty ? null : target);
    AppLogger.info(
      '[L3] l3_set_active_conversation: active='
      '${target.isEmpty ? '(none)' : target}',
    );
    return MCPCallResult(
      message: 'active conversation set',
      parameters: {'ok': true, 'activePeerId': ffi.activePeerId},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_set_active_conversation',
    description:
        'UNGATED harness hook: set/clear the active conversation '
        '(ffi.setActivePeer). Pass conversationId/userId to focus it, or omit '
        'for none. Group unread only accrues while the group is NOT active, so '
        'the S118/S133 mark-read gate clears active before seeding unread.',
    inputSchema: ObjectSchema(
      properties: {
        'conversationId': StringSchema(
          description: 'group_<gid>/c2c_<id>/bare id to focus; omit for none.',
        ),
        'userId': StringSchema(description: 'Alias for conversationId.'),
      },
    ),
  ),
);

/// UNGATED harness hook: grant the CURRENT account the L3 seed-account marker
/// ([Prefs.addL3SeedToxId]) so the test-account-gated tools act on this account.
///
/// SCOPE (honest — codex P1): the marker is the SAME `[_activeAccountIsTest]`
/// grant `l3_register_account` writes, so it authorizes the WHOLE
/// test-account-gated surface (l3_send_file / l3_clear_history / l3_send_text /
/// l3_set_blocked / l3_create_group / l3_set_pinned / …), NOT a "seeding-only"
/// subset — there is no per-tool scope today. The campaign uses it only to SEED
/// (the asserted action in every case stays the real widget/gesture), but the
/// privilege it confers is broad, so a sweep MUST revoke it
/// (`l3_unmark_current_account_test`) before it ends so the launch does not
/// leave a privileged account behind for a reused launch (the result-state
/// poison codex P1 flagged).
///
/// WHY THIS IS SAFE + IN-CONTRACT (Batch-6 gating answer): the whole L3 surface
/// only registers when the app is BUILT with `kDebugMode && TOXEE_L3_TEST`
/// (kL3TestSurfaceEnabled) — a debug harness build, never release. An account
/// REGISTERED through the real UI (every fresh real-UI sweep launch) carries NO
/// seed marker, so the gated tools refuse it with `non_test_account` — which
/// blocks the SEEDING the campaign contract explicitly allows. This tool lets a
/// sweep mark its OWN throwaway account, exactly as `l3_register_account` does,
/// and the marker is also revoked when the account is deleted
/// (Prefs.removeL3SeedToxId in removeAccount), so the grant can't outlive the
/// account. Pure harness plumbing, like `l3_open_add_friend_dialog`.
MCPCallEntry _l3MarkCurrentAccountTestEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final toxId = (await Prefs.getCurrentAccountToxId() ?? '').trim();
    if (toxId.isEmpty) {
      return MCPCallResult(
        message: 'l3_mark_current_account_test: no active account',
        parameters: {'ok': false, 'error': 'no_active_account'},
      );
    }
    await Prefs.addL3SeedToxId(toxId);
    final isTest = await _activeAccountIsTest();
    AppLogger.info(
      '[L3] l3_mark_current_account_test: seed-marker recorded for '
      '$toxId (isTest=$isTest)',
    );
    return MCPCallResult(
      message: 'current account marked as L3 seed account',
      parameters: {'ok': true, 'toxId': toxId, 'isTestAccount': isTest},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_mark_current_account_test',
    description:
        'UNGATED harness hook: record the CURRENT account in the persistent '
        'L3 seed-account marker (Prefs.l3SeedToxIds) so the test-account-gated '
        'tools act on it. NOTE: this grants the WHOLE gated surface (not just '
        'seeding) — pair it with l3_unmark_current_account_test to revoke before '
        'the launch ends. The whole L3 surface is already kDebugMode + '
        'TOXEE_L3_TEST gated; the marker is also revoked when the account is '
        'deleted.',
    inputSchema: ObjectSchema(properties: {}),
  ),
);

/// UNGATED harness hook: REVOKE the CURRENT account's L3 seed-account marker
/// ([Prefs.removeL3SeedToxId]) — the inverse of `l3_mark_current_account_test`.
/// A sweep that marked its throwaway account calls this in its end-guard so the
/// launch ends with the SAME (non-test) privilege state it started, leaving no
/// hidden grant behind for a reused launch (codex P1). No-op if the current
/// account was never marked or is a permanent fixture (nickname/prefix-based,
/// which the marker can't revoke — those aren't marker-granted).
MCPCallEntry _l3UnmarkCurrentAccountTestEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final toxId = (await Prefs.getCurrentAccountToxId() ?? '').trim();
    if (toxId.isEmpty) {
      return MCPCallResult(
        message: 'l3_unmark_current_account_test: no active account',
        parameters: {'ok': false, 'error': 'no_active_account'},
      );
    }
    await Prefs.removeL3SeedToxId(toxId);
    final isTest = await _activeAccountIsTest();
    AppLogger.info(
      '[L3] l3_unmark_current_account_test: seed-marker revoked for '
      '$toxId (isTest=$isTest)',
    );
    return MCPCallResult(
      message: 'current account seed-marker revoked',
      parameters: {'ok': true, 'toxId': toxId, 'isTestAccount': isTest},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_unmark_current_account_test',
    description:
        'UNGATED harness hook: revoke the CURRENT account\'s L3 seed-account '
        'marker (the inverse of l3_mark_current_account_test) so a sweep that '
        'temporarily marked its throwaway account ends with the same non-test '
        'privilege state it started. No-op for permanent fixtures.',
    inputSchema: ObjectSchema(properties: {}),
  ),
);

/// Fixture-C two-process NGC connectivity: expose this instance's LOCAL DHT
/// endpoint (UDP port + DHT public key) so a two-process driver can wire a
/// FULL-MESH local bootstrap between the paired instances. Same-host instances
/// otherwise only bootstrap to the PUBLIC DHT (never to each other), so
/// PUBLIC-group peer discovery is slow/flaky and the founder's peer-join never
/// fires — the exact failure the tim2tox auto_tests' `configureLocalBootstrap`
/// full-mesh was built to fix. Read-only.
MCPCallEntry _l3DhtInfoEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_dht_info: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    try {
      final port = ffi.getUdpPort();
      final dhtId = ffi.getDhtId();
      AppLogger.info('[L3] l3_dht_info: udpPort=$port dhtId=$dhtId');
      return MCPCallResult(
        message: 'dht info',
        parameters: {'ok': true, 'udpPort': port, 'dhtId': dhtId},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_dht_info failed', e, st);
      return MCPCallResult(
        message: 'l3_dht_info: failed: $e',
        parameters: {'ok': false, 'error': 'dht_info_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_dht_info',
    description:
        "L3 TEST ONLY: return this instance's local DHT endpoint "
        '{udpPort, dhtId} so a two-process driver can wire a full-mesh local '
        'bootstrap (reliable same-host NGC peer discovery). Read-only.',
    inputSchema: ObjectSchema(properties: {}),
  ),
);

/// Add a Tox DHT bootstrap node at runtime — the seam a Fixture-C driver uses to
/// bootstrap the paired instances to EACH OTHER (127.0.0.1 + the peer's
/// l3_dht_info), so PUBLIC-group NGC peer discovery works same-host. The
/// founder MUST also bootstrap to the joiner (full mesh) or its peer-join never
/// fires (auto_tests note). MUTATING (Tox-network state), test/seed account only.
MCPCallEntry _l3AddBootstrapNodeEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_add_bootstrap_node: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_add_bootstrap_node: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    final host = (request['host'] as Object?)?.toString().trim() ?? '';
    final portRaw = (request['port'] as Object?)?.toString().trim() ?? '';
    final pubkey = (request['pubkey'] as Object?)?.toString().trim() ?? '';
    final port = int.tryParse(portRaw);
    if (host.isEmpty || port == null || port <= 0 || pubkey.isEmpty) {
      return MCPCallResult(
        message: 'l3_add_bootstrap_node: need host, port (int>0), pubkey',
        parameters: {'ok': false, 'error': 'bad_args'},
      );
    }
    try {
      final success = await ffi.addBootstrapNode(host, port, pubkey);
      AppLogger.info(
        '[L3] l3_add_bootstrap_node: $host:$port -> success=$success',
      );
      return MCPCallResult(
        message: success
            ? 'bootstrap node added'
            : 'bootstrap add returned false',
        parameters: {'ok': success, 'host': host, 'port': port},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_add_bootstrap_node failed', e, st);
      return MCPCallResult(
        message: 'l3_add_bootstrap_node: failed: $e',
        parameters: {
          'ok': false,
          'error': 'add_bootstrap_failed',
          'detail': '$e',
        },
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_add_bootstrap_node',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): add a Tox DHT bootstrap '
        'node at runtime {host, port, pubkey}. Used to bootstrap the paired '
        'Fixture-C instances to EACH OTHER (127.0.0.1 + peer l3_dht_info) so '
        'same-host PUBLIC-group NGC peer discovery works (mirrors auto_tests '
        'configureLocalBootstrap full-mesh).',
    inputSchema: ObjectSchema(
      properties: {
        'host': StringSchema(description: 'Bootstrap host (e.g. 127.0.0.1).'),
        'port': StringSchema(description: 'UDP port (int).'),
        'pubkey': StringSchema(description: 'DHT public key hex (64 chars).'),
      },
      required: ['host', 'port', 'pubkey'],
    ),
  ),
);

/// S63 (typing leg): send a C2C typing indicator via the real
/// `FfiChatService.sendTyping` → `tox_self_set_typing` path. The peer observes
/// it as `l3_dump_state.friends[].isTyping` (true while the received typing:1 is
/// unexpired, ~3s). The read-receipt half of S63 is a documented no-op
/// (`_sendReceipt` early-returns). MUTATING, C2C-only, test/seed account.
MCPCallEntry _l3SetTypingEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_set_typing: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_set_typing: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var userId = request['userId'] ?? request['conversationId'] ?? '';
    if (userId.startsWith('group_') || request['groupId'] != null) {
      return MCPCallResult(
        message: 'l3_set_typing: C2C only — groups unsupported',
        parameters: {'ok': false, 'error': 'group_unsupported'},
      );
    }
    if (userId.startsWith('c2c_')) userId = userId.substring(4);
    if (userId.isEmpty) userId = ffi.activePeerId ?? '';
    if (userId.isEmpty) {
      return MCPCallResult(
        message: 'l3_set_typing: no target — pass userId',
        parameters: {'ok': false, 'error': 'no_target'},
      );
    }
    final groupReject = await _rejectIfGroupTarget(
      'l3_set_typing',
      userId,
      ffi.knownGroups,
      ffi.quitGroups,
    );
    if (groupReject != null) return groupReject;
    final on =
        (request['on'] ?? 'true').toString().toLowerCase().trim() != 'false';
    try {
      await ffi.sendTyping(userId, on);
      AppLogger.info('[L3] l3_set_typing: $userId on=$on');
      return MCPCallResult(
        message: 'typing set',
        parameters: {'ok': true, 'userId': userId, 'on': on},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_set_typing failed', e, st);
      return MCPCallResult(
        message: 'l3_set_typing: failed: $e',
        parameters: {'ok': false, 'error': 'typing_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_set_typing',
    description:
        'L3 TEST ONLY (test/seed account, C2C-only): send a typing indicator to '
        'a peer (tox_self_set_typing). The peer sees it in '
        'l3_dump_state.friends[].isTyping (~3s expiry — re-send to keep it on). '
        'on=true|false.',
    inputSchema: ObjectSchema(
      properties: {
        'userId': StringSchema(
          description: 'Target Tox ID. Optional — active conv.',
        ),
        'conversationId': StringSchema(description: 'c2c_<toxId> alternative.'),
        'on': StringSchema(description: 'true | false (default true)'),
      },
    ),
  ),
);

/// S58: drive the desktop window lifecycle (minimize/restore/hide/show/focus)
/// via window_manager, so a scenario can verify the app keeps receiving over
/// the DHT while backgrounded. test/seed account only; macOS/desktop.
MCPCallEntry _l3WindowStateEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_window_state: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final state =
        (request['state'] as Object?)?.toString().trim().toLowerCase() ?? '';
    try {
      switch (state) {
        case 'minimize':
          await windowManager.minimize();
          break;
        case 'restore':
          await windowManager.restore();
          break;
        case 'hide':
          await windowManager.hide();
          break;
        case 'show':
          await windowManager.show();
          break;
        case 'focus':
          await windowManager.focus();
          break;
        case 'bounds':
          // Deterministic window geometry for the screenshot pipeline: a
          // reused profile restores whatever bounds were last persisted
          // (possibly hand-dragged between runs), so each capture run forces
          // a known logical size before shooting.
          final width = double.tryParse(
            (request['width'] as Object?)?.toString() ?? '',
          );
          final height = double.tryParse(
            (request['height'] as Object?)?.toString() ?? '',
          );
          if (width == null || height == null || width <= 0 || height <= 0) {
            return MCPCallResult(
              message:
                  'l3_window_state: bounds needs positive "width" and '
                  '"height"',
              parameters: {'ok': false, 'error': 'bad_bounds'},
            );
          }
          await windowManager.setSize(Size(width, height));
          await windowManager.center();
          break;
        default:
          return MCPCallResult(
            message:
                'l3_window_state: unsupported state "$state" '
                '(minimize|restore|hide|show|focus|bounds)',
            parameters: {'ok': false, 'error': 'unsupported_state'},
          );
      }
      AppLogger.info('[L3] l3_window_state: $state');
      return MCPCallResult(
        message: 'window state $state applied',
        parameters: {'ok': true, 'state': state},
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_window_state failed', e, st);
      return MCPCallResult(
        message: 'l3_window_state: failed: $e',
        parameters: {
          'ok': false,
          'error': 'window_state_failed',
          'detail': '$e',
        },
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_window_state',
    description:
        'L3 TEST ONLY (test/seed account, desktop): drive the window lifecycle — '
        'minimize | restore | hide | show | focus — to exercise background/'
        'foreground behavior (S58); or state=bounds with width+height (logical '
        'px) to force a deterministic centered window size (screenshot '
        'pipeline).',
    inputSchema: ObjectSchema(
      properties: {
        'state': StringSchema(
          description: 'minimize | restore | hide | show | focus | bounds',
        ),
        'width': StringSchema(description: 'Logical width for state=bounds.'),
        'height': StringSchema(description: 'Logical height for state=bounds.'),
      },
      required: ['state'],
    ),
  ),
);

/// F2 conversation pin/unpin (coverage-widening). Drives the SAME path the
/// UIKit conversation long-press "pin" action uses:
/// `FakeConversationManager.setPinned(conversationID, pin)` → `Prefs.setPinned`
/// + a pinned-first conversation-list re-emit. Read back via
/// `l3_dump_state.pinnedConversations` (Prefs-backed, race-free) and the
/// per-item `conversations[].isPinned`. MUTATING — test/seed account only.
/// Accepts a C2C bare/`c2c_` id OR a `group_<gid>` id (pinning is valid for
/// both, unlike the C2C-only message tools); a bare id is treated as C2C.
MCPCallEntry _l3SetPinnedEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_set_pinned: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final convMgr = FakeUIKit.instance.conversationManager;
    if (convMgr == null) {
      return MCPCallResult(
        message: 'l3_set_pinned: session not ready (no conversationManager)',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var conv = (request['conversationId'] ?? request['userId'] ?? '')
        .toString()
        .trim();
    if (conv.isEmpty) {
      // Fall back to the active conversation. activePeerId is the BARE id for
      // BOTH C2C and groups, so prefix by KIND — else an open GROUP would be
      // pinned under a phantom c2c_ key (codex P2).
      final ffi = FakeUIKit.instance.im?.ffi;
      final active = ffi?.activePeerId ?? '';
      if (active.isNotEmpty) {
        final isGroup =
            ffi != null &&
            (ffi.knownGroups.contains(active) ||
                ffi.quitGroups.contains(active) ||
                (await Prefs.getGroups()).contains(active));
        conv = isGroup ? 'group_$active' : 'c2c_$active';
      }
    }
    if (conv.isEmpty) {
      return MCPCallResult(
        message:
            'l3_set_pinned: no target — pass "conversationId" '
            '(c2c_<id> | group_<gid> | bare C2C id) or open a conversation '
            'first',
        parameters: {'ok': false, 'error': 'no_target'},
      );
    }
    // FakeConversationManager.setPinned expects the prefixed conversationID; a
    // bare id is a C2C peer → add the c2c_ prefix.
    if (!conv.startsWith('c2c_') && !conv.startsWith('group_')) {
      conv = 'c2c_$conv';
    }
    final rawPin = (request['pinned'] ?? request['pin'] ?? 'true')
        .toString()
        .toLowerCase()
        .trim();
    if (rawPin != 'true' && rawPin != 'false') {
      return MCPCallResult(
        message: 'l3_set_pinned: "pinned" must be true|false (got "$rawPin")',
        parameters: {'ok': false, 'error': 'bad_value'},
      );
    }
    final pin = rawPin == 'true';
    try {
      await convMgr.setPinned(conv, pin);
      final pinnedNow = (await Prefs.getPinned()).toList();
      AppLogger.info('[L3] l3_set_pinned MUTATED $conv pinned=$pin');
      return MCPCallResult(
        message: 'pin updated: $conv pinned=$pin',
        parameters: {
          'ok': true,
          'conversationId': conv,
          'pinned': pin,
          'pinnedConversations': pinnedNow,
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_set_pinned failed', e, st);
      return MCPCallResult(
        message: 'l3_set_pinned: failed: $e',
        parameters: {'ok': false, 'error': 'set_pinned_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_set_pinned',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): pin or unpin a '
        'conversation via FakeConversationManager.setPinned — the UIKit '
        'long-press "pin" path (Prefs.setPinned + pinned-first re-sort). '
        'conversationId accepts c2c_<id> | group_<gid> | a bare C2C id '
        '(bare → c2c_). pinned is true|false. Read back via '
        'l3_dump_state.pinnedConversations / conversations[].isPinned.',
    inputSchema: ObjectSchema(
      properties: {
        'conversationId': StringSchema(
          description: 'c2c_<id> | group_<gid> | bare C2C id',
        ),
        'pinned': StringSchema(description: 'true | false'),
      },
    ),
  ),
);

/// Whether the current account (Prefs.getCurrentAccountToxId) has a stored
/// password verifier. Returns false when there is no current account or on any
/// read error (the dump must never throw). Used by l3_dump_state's
/// `currentAccountHasPassword` field.
Future<bool> _currentAccountHasPassword() async {
  try {
    final toxId = await Prefs.getCurrentAccountToxId();
    if (toxId == null || toxId.isEmpty) return false;
    return await Prefs.hasAccountPassword(toxId);
  } catch (_) {
    return false;
  }
}

/// The persisted saved-account list (Prefs `account_list` toxIds) for
/// l3_dump_state's `savedAccountToxIds` field. Ground truth for the account
/// register/switch/delete real-UI gates. No-throw: returns [] on any read
/// error (the dump must never throw); works logged-out (Prefs is global).
Future<List<String>> _savedAccountToxIds() async {
  try {
    final list = await Prefs.getAccountList();
    return [
      for (final account in list)
        if ((account['toxId'] ?? '').isNotEmpty) account['toxId']!,
    ];
  } catch (_) {
    return <String>[];
  }
}

MCPCallEntry _l3DumpStateEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final ffi = FakeUIKit.instance.im?.ffi;
    final params = <String, dynamic>{
      'sessionReady': ffi != null,
      'selfId': ffi?.selfId,
      'activePeerId': ffi?.activePeerId,
      'isConnected': ffi?.isConnected,
      'nickname': await Prefs.getNickname(),
      // S8/B10: the account's own status message (self-profile). Account Prefs
      // (Prefs.getStatusMessage), coerced null→'' so the unset state is a stable
      // '' (not null) — lets a gate assert an empty-status START invariant via
      // state_equals and round-trip via state{contains|notContains}.
      'statusMessage': (await Prefs.getStatusMessage()) ?? '',
      'currentAccountToxId': await Prefs.getCurrentAccountToxId(),
      // DIAGNOSTIC: the UIKit basic.currentUser.userID (drives the member-list
      // isSelf() / myRole computation that gates the desktop kick item).
      'uikitCurrentUserId':
          TencentCloudChat.instance.dataInstance.basic.currentUser?.userID,
      // Account-level settings for the CURRENT account. #4 (codex-vetted
      // 2026-05-30): the prior "no stable getters" note was OUTDATED — these
      // are the SAME getters the settings page + PreferencesService use, and
      // the no-arg form resolves to the current account, so they report the
      // EFFECTIVE value the user sees (not the raw global key). These are
      // account/session state, NOT a property of a resolved C2C target, so
      // they live in the base payload (NOT behind the C2C-only group guard).
      'languageCode': await Prefs.getLanguageCode(),
      'themeMode': await Prefs.getThemeMode(),
      'autoLogin': await Prefs.getAutoLogin(),
      'autoAcceptFriends': await Prefs.getAutoAcceptFriends(),
      'autoAcceptGroupInvites': await Prefs.getAutoAcceptGroupInvites(),
      // Coverage-widening read fields. Each is TOP-LEVEL so the runner's
      // `state{field,equals|contains}` predicate can assert it directly, and
      // each mirrors a settings/network getter the UI uses (resolved for the
      // CURRENT account where the getter is account-scoped):
      //   notificationSound     → L7 per-account notification-sound toggle
      //   bootstrapNodeMode     → C1 node mode (auto|manual|lan), global
      //   downloadsDirectory    → L8 download dir (null = platform default)
      //   autoDownloadSizeLimit → L8 auto-download cap in MB
      // The matching write half goes through l3_set_setting (typed keys).
      'notificationSound': await Prefs.getNotificationSoundEnabled(),
      'bootstrapNodeMode': await Prefs.getBootstrapNodeMode(),
      'downloadsDirectory': await Prefs.getDownloadsDirectory(),
      'autoDownloadSizeLimit': await Prefs.getAutoDownloadSizeLimit(),
      // F2 pin: the authoritative pinned-conversation set, read from
      // Prefs.getPinned() (what FakeConversationManager.setPinned writes BEFORE
      // it returns) — race-free vs the async conversation-list re-emit. In the
      // BASE payload (not ffi-gated) so the hermetic pin gate isn't coupled to
      // session/FFI boot timing (codex P2). Entries are normalized store keys
      // (bare normalized id for C2C, 'group_<gid>' for groups), so a scenario
      // asserts via state{field:pinnedConversations, contains:<peer-id-prefix>}.
      'pinnedConversations': (await Prefs.getPinned()).toList(),
      'exportSaveFileOverridePath': debugCurrentExportSaveFileOverridePath,
      // Whether the CURRENT account is password-protected (Prefs-backed verifier
      // exists). Lets the Batch-3 login sweep PROVE the no-password end-state
      // invariant (set/clear-password cases) directly instead of inferring it
      // from a snackbar. Coerced to false when there is no current account.
      'currentAccountHasPassword': await _currentAccountHasPassword(),
      // The persisted saved-account list (Prefs `account_list` toxIds) —
      // ground truth for the account register/switch/delete real-UI gates: a
      // login card's visual absence alone could false-pass on an unloaded
      // list, and an end-clean guard needs to PROVE a throwaway account is
      // really gone. Read-only; works logged-out too (Prefs is global).
      'savedAccountToxIds': await _savedAccountToxIds(),
      ..._l3HarnessEnvironmentSnapshot(Platform.environment),
    };
    final homeShell = _l3HomeShellSnapshotReader?.call();
    if (homeShell != null) {
      params['homeShell'] = homeShell;
      params['homeShellTab'] = homeShell['tab'];
      params['homeShellIndex'] = homeShell['index'];
      params['homeShellCurrentConversationId'] =
          homeShell['currentConversationId'];
      params['homeShellInContactProfileContext'] =
          homeShell['inContactProfileContext'];
    }
    if (ffi != null) {
      try {
        final friends = await ffi.getFriendList();
        final friendList = <Map<String, dynamic>>[];
        for (final friend in friends) {
          // S52: a friend's received avatar path (set on the receiver when an
          // inbound kind-1 avatar transfer completes) lives in Prefs, not in
          // getFriendList's tuple — surface it so the propagation is assertable.
          final avatarPath = await Prefs.getFriendAvatarPath(friend.userId);
          // S30/H5: the user-edited friend remark/alias (distinct from the
          // Tox nickName). Lives in account-scoped Prefs, NOT in getFriendList's
          // tuple — surface it so l3_set_friend_remark round-trips are assertable
          // via state{field:friends, contains|notContains:<remark>}. '' when unset.
          final remark = await Prefs.getFriendRemark(friend.userId) ?? '';
          friendList.add({
            'userId': friend.userId,
            'nickName': friend.nickName,
            'status': friend.status,
            'online': friend.online,
            'avatarPath': avatarPath,
            'remark': remark,
            // S63: live typing indicator for this friend (true while a received
            // typing:1 is unexpired). Expires ~3s after the last typing event.
            'isTyping': ffi.isTyping(friend.userId),
          });
        }
        params['friends'] = friendList;
        params['friendCount'] = friends.length;
        // S29: the live in-memory blocked-user set (FfiChatService.blockedUsers,
        // normalized ids) — the SAME set the inbound filter checks. Top-level
        // so a gate asserts via state{field:blockedUsers, contains|notContains}.
        params['blockedUsers'] = ffi.blockedUsers.toList();
      } catch (e) {
        params['friendsError'] = e.toString();
      }
      try {
        final apps = await ffi.getFriendApplications();
        params['friendApplications'] = [
          for (final app in apps)
            {'userId': app.userId, 'wording': app.wording},
        ];
        params['friendApplicationCount'] = apps.length;
      } catch (e) {
        params['friendApplicationsError'] = e.toString();
      }
    }
    final callState = FakeUIKit.instance.callStateNotifier;
    if (callState != null) {
      params['call'] = {
        'state': callState.state.name,
        'mode': callState.mode.name,
        'direction': callState.direction.name,
        'inviteID': callState.inviteID,
        'remoteUserID': callState.remoteUserID,
        'remoteNickname': callState.remoteNickname,
        'isMuted': callState.isMuted,
        'isVideoEnabled': callState.isVideoEnabled,
        'isSpeakerOn': callState.isSpeakerOn,
        'callDurationSeconds': callState.callDuration.inSeconds,
        'isReconnecting': callState.isReconnecting,
        'callQuality': callState.callQuality.name,
      };
    }
    // #4: the conversation list the sidebar renders (C2C + group) for
    // presence / unread / ordering assertions (S20 delete-conversation, S72
    // multi-account isolation). The array order IS the sidebar order.
    // NOTE (codex): this list is UI-live and hydrates shortly AFTER login,
    // so a scenario must POLL (wait_for state_contains) before asserting
    // presence rather than reading it immediately. Only populated once the
    // session is up. faceUrl/customData omitted (sensitive/noisy); orderKey
    // omitted (volatile — the array order already conveys ordering).
    if (ffi != null) {
      params['conversations'] = [
        for (final c in UikitDataFacade.conversationList)
          {
            'conversationID': c.conversationID,
            'type': c.type, // 1 = C2C, 2 = group
            'showName': c.showName,
            'unreadCount': c.unreadCount,
            'lastMessageText': c.lastMessage?.textElem?.text,
            'isPinned': c.isPinned,
            // recvOpt (0=receive, 1=no-notify, 2=block/mute) — the exact field
            // _shouldSuppress reads (notification_message_listener.dart:224).
            // S83 sets it via l3_set_c2c_recv_opt and asserts it here.
            'recvOpt': c.recvOpt,
          },
      ];
      // Exact-membership companion to `conversations` (a list of maps, which the
      // runner's containsItem/notContainsItem can't address): the sidebar
      // conversationIDs as a flat string list. Lets a group/conversation gate
      // assert EXACT presence/absence of 'group_<gid>' (or 'c2c_<id>') without
      // the prefix-substring trap ('group_tox_1' ⊂ 'group_tox_10').
      params['conversationIds'] = [
        for (final c in UikitDataFacade.conversationList) c.conversationID,
      ];
      // K2 app badge: the aggregate unread the sidebar/dock badge renders
      // (UikitDataFacade.totalUnreadCount → the UIKit conversation store's
      // totalUnreadCount). Top-level so the runner can assert the badge total
      // directly via state{field:totalUnreadCount}.
      params['totalUnreadCount'] = UikitDataFacade.totalUnreadCount;
      // S34: the in-memory joined-group set (ffi.knownGroups). A creator keys
      // history by its LOCAL group id (e.g. "tox_1"); a joiner keys by what it
      // passed to joinGroup (the chat-id). Expose both sides' actual ids so a
      // two-process driver can read group history by the right key instead of
      // guessing.
      params['knownGroups'] = ffi.knownGroups.toList();
      // S94/G2: in-flight RECEIVE file-transfer progress, keyed by msgID, as a
      // 0-100 percent + raw byte counts. Read from the message provider's
      // public `fileProgress` snapshot (fed by the progressUpdates recv stream,
      // throttled to one update / 200ms per transfer). Entries appear WHILE a
      // transfer is mid-flight and are REMOVED on completion — so a gate must
      // POLL this DURING a LARGE transfer to catch an intermediate 0<p<100
      // sample; a terminal/post-completion dump sees it empty (expected). Only
      // the RECEIVER observes this (send-side progress is not tracked). percent
      // uses floor() so it never exposes 100 (completion = key disappears).
      final progressProvider = FakeUIKit.instance.messageProvider;
      params['fileTransfers'] = progressProvider == null
          ? <String, dynamic>{}
          : projectFileTransfers(progressProvider.fileProgress);
      // The open/active conversation set by the conversation-tap routing
      // (UikitDataFacade.currentConversation). S53 injects a notification tap
      // via l3_simulate_notification_tap and asserts this flips to the tapped
      // conversation. null when no chat is open. NOTE: this is distinct from
      // ffi.activePeerId — notification routing sets currentConversation, not
      // activePeerId, so S53 must assert on THIS field.
      final cur = UikitDataFacade.currentConversation;
      params['currentConversation'] = cur == null
          ? null
          : {
              'conversationID': cur.conversationID,
              'type': cur.type,
              'showName': cur.showName,
              'userID': cur.userID,
              'groupID': cur.groupID,
            };
      final currentUserId = cur?.userID;
      params['activeChatPeerOnline'] =
          currentUserId == null || currentUserId.isEmpty
          ? null
          : TencentCloudChat.instance.dataInstance.contact
                .getOnlineStatusByUserId(userID: currentUserId);
    }
    // Optional: include the PERSISTED message list for a conversation so
    // tests can assert on history (count, text, isSelf, msgID) instead of
    // log-grep. Defaults to the active peer. Reads the same persistence the
    // cold-start render uses, so it reflects the deduped ground truth.
    if (ffi != null) {
      // Resolve the conversation target, then CANONICALIZE to a bare id
      // ONCE before any group check (codex 2026-05-30, re-review ×3). This
      // tool is C2C-only; the unread/render block below must never run for a
      // group. Earlier attempts checked the `group_` prefix at a fixed point
      // (before the activePeerId fallback) and relied on `_rejectIfGroupTarget`
      // recognizing only BARE ids — which left a residual: a `group_`-prefixed
      // value arriving via the fallback (or a malformed `c2c_group_<gid>`)
      // could slip into the C2C block (unread normalizes the prefix away, and
      // the render lookup can match a `group_<gid>` key directly). Canonicalizing
      // AFTER all resolution removes that ordering/invariant dependency.
      var conv = request['conversationId'] ?? request['userId'] ?? '';
      if (conv.startsWith('c2c_')) conv = conv.substring(4);
      if (conv.isEmpty) conv = ffi.activePeerId ?? '';
      // A `group_` prefix surviving here — from explicit input OR a
      // non-normalized activePeerId — unambiguously means group. Strip it so
      // the bare-id `_rejectIfGroupTarget` membership check is reliable, and
      // remember we saw it.
      final hadGroupPrefix = conv.startsWith('group_');
      if (hadGroupPrefix) conv = conv.substring(6);
      // isGroup if: an explicit `groupId` param, a stripped `group_` marker
      // from any source, or the resolved bare id is a known/quit/persisted
      // group. Skip the conversation block (but keep the base snapshot) when
      // any holds.
      final isGroup =
          hadGroupPrefix ||
          request['groupId'] != null ||
          (conv.isNotEmpty &&
              await _rejectIfGroupTarget(
                    'l3_dump_state',
                    conv,
                    ffi.knownGroups,
                    ffi.quitGroups,
                  ) !=
                  null);
      if (isGroup && conv.isNotEmpty) {
        // S34 group-history readout. The C2C-only unread/render-dedup blocks
        // don't apply, but getHistory is keyed by the BARE group id and a
        // group message carries the same {msgID,text,isSelf,fromUserId,
        // timestamp} shape, so emit those for two-process group assertions.
        final history = ffi.getHistory(conv);
        params['conversation'] = conv;
        params['conversationKind'] = 'group';
        params['messageCount'] = history.length;
        params['messages'] = history
            .map(
              (m) => {
                'msgID': m.msgID,
                'text': m.text,
                'isSelf': m.isSelf,
                'fromUserId': m.fromUserId,
                'timestamp': m.timestamp.toIso8601String(),
                // isPending=true ONLY on the offline-queue append
                // (_queueOfflineGroupText); the CONNECTED direct-send path
                // leaves it false. Surfaced so a group-send gate can assert
                // messages[].isPending==false and thus prove the message took
                // the connected path, not a disconnected local-queue write that
                // would otherwise persist an identical row (codex P1).
                'isPending': m.isPending,
              },
            )
            .toList();
      } else if (isGroup) {
        params['conversationSkipped'] = 'group_unsupported';
      } else if (conv.isNotEmpty) {
        final history = ffi.getHistory(conv);
        params['conversation'] = conv;
        params['messageCount'] = history.length;
        // Unread via the PATH-INDEPENDENT C2C count (persistence + lastView
        // barrier), NOT the in-memory counter — so it reflects an inbound
        // echo regardless of which hybrid path persisted it first (the
        // in-memory counter under-counts when the binary-replacement hook
        // wins; see getC2CUnreadCount). `l3_mark_read` advances the barrier,
        // so a scenario can assert unread>0 → mark-read → unread==0 (S19).
        // Only inbound (isSelf:false) messages count, so this needs the echo.
        params['unreadCount'] = ffi.getC2CUnreadCount(conv);
        params['messages'] = history
            .map(
              (m) => {
                'msgID': m.msgID,
                'text': m.text,
                'isSelf': m.isSelf,
                'fromUserId': m.fromUserId,
                'timestamp': m.timestamp.toIso8601String(),
                // isPending=true while a self-message sits in the offline queue
                // (disconnected send), false once delivered / on the connected
                // path. Parity with the group block (codex P1).
                'isPending': m.isPending,
                // Media/file fields (S21 send / S24 accept): mediaKind is
                // 'image'|'video'|'audio'|'file', filePath is set on the
                // received side once the transfer completes.
                'mediaKind': m.mediaKind,
                'fileName': m.fileName,
                'filePath': m.filePath,
                'fileSize': m.fileSize,
                // S63 receipts: isReceived flips on a peer 'received' (delivery)
                // receipt; isRead on a 'read' receipt (recipient marked read).
                'isReceived': m.isReceived,
                'isRead': m.isRead,
                // S17/S18: structured reply/forward metadata (JSON string), the
                // V2TIM cloudCustomData persisted sender-side by l3_reply_text
                // (`{"messageReply":{messageID,messageAbstract,...}}`). null for
                // a plain message.
                'cloudCustomData': m.cloudCustomData,
              },
            )
            .toList();
        // #29 (codex-redesigned 2026-05-30): render-layer (UIKit message
        // list) snapshot to verify Bug C — a dual-path inbound DUPLICATE
        // that only manifests in the UIKit render list, not persistence, so
        // persistence messageCount alone cannot prove the fix. The render
        // map (messageListMap) is EXACT-STRING keyed and toxee writers
        // populate it under several id forms (64-char pubkey, 76-char full
        // Tox id, with/without `c2c_` prefix, mixed case). A fixed
        // case-variant probe both false-negatives on 64-vs-76 drift AND can
        // UNDERCOUNT a split (same message under two key forms, each 1,
        // total 2 — the exact bug). So resolve by LOGICAL Tox identity:
        // enumerate every render key, strip any `c2c_` prefix, match by
        // toToxPublicKey (lower-cases, collapses 76 -> 64); aggregate rows
        // across ALL matching keys so a split is COUNTED not hidden, and
        // record each matched key's count for ambiguity diagnosis.
        // renderResolved=false (zero matches) makes a test fail LOUDLY
        // instead of reading an empty list as "no duplicate". C2C-only: a
        // group's key won't share a c2c peer's pubkey. (codex review.)
        try {
          final wantPk = toToxPublicKey(conv);
          final matchedKeys = <String, int>{};
          final renderRows = <Map<String, Object?>>[];
          for (final key in UikitDataFacade.messageListKeys()) {
            final bare = key.startsWith('c2c_') ? key.substring(4) : key;
            if (toToxPublicKey(bare) != wantPk) continue;
            final list = UikitDataFacade.getMessageList(key: key);
            matchedKeys[key] = list.length;
            for (final m in list) {
              renderRows.add({
                'msgID': m.msgID,
                'id': m.id,
                'userID': m.userID,
                'sender': m.sender,
                'text': m.textElem?.text,
                'isSelf': m.isSelf,
                'elemType': m.elemType,
                'timestamp': m.timestamp,
                'renderKey': key,
                // Reply/forward metadata as the RENDER-layer V2TimMessage carries
                // it. After a chat reopen this reflects the cold-reload path
                // (getHistoryMessageList* -> converter), so a test can assert the
                // reply quote survives reload, not just the persisted messages[].
                'cloudCustomData': m.cloudCustomData,
              });
            }
          }
          params['renderResolved'] = matchedKeys.isNotEmpty;
          params['renderMatchedKeys'] = matchedKeys;
          params['renderMessageCount'] = renderRows.length;
          params['renderMessages'] = renderRows;
        } catch (e) {
          params['renderResolved'] = false;
          params['renderError'] = e.toString();
        }
      }
    }
    return MCPCallResult(message: 'l3 state snapshot', parameters: params);
  },
  definition: MCPToolDefinition(
    name: 'l3_dump_state',
    description:
        'L3 TEST ONLY: JSON snapshot of session state '
        '(selfId, activePeerId, isConnected, nickname), current-account '
        'settings (languageCode, themeMode, autoLogin, autoAcceptFriends, '
        'autoAcceptGroupInvites) and the sidebar conversation list '
        '(conversations: conversationID/type/showName/unreadCount/'
        'lastMessageText/isPinned — UI-live, poll before asserting; '
        'conversationIds is the flat id list for exact membership checks) PLUS, '
        'for the given '
        'conversationId/userId (or the active conversation), the persisted '
        'message list (msgID, text, isSelf, fromUserId, timestamp) AND the '
        'UIKit render-layer list resolved by logical Tox identity '
        '(renderResolved, renderMatchedKeys, renderMessageCount, '
        'renderMessages with msgID/id/userID/sender/text/isSelf/elemType) '
        'so dual-path render duplicates (Bug C) can be asserted directly '
        'and a key-resolution miss fails loudly, for structured assertions '
        'without UI scraping or log-grep.',
    inputSchema: ObjectSchema(
      properties: {
        'conversationId': StringSchema(
          description:
              'c2c_<toxId> or bare Tox ID to dump messages for. '
              'Optional — defaults to the active conversation.',
        ),
        'userId': StringSchema(
          description: 'Alias for conversationId (bare Tox ID).',
        ),
      },
    ),
  ),
);
