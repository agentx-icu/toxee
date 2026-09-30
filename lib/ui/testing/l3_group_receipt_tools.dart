// L3 seam for GROUP read receipts.
//
// TWO group read paths exist, and they prove different things:
//
//   * `l3_mark_group_read` (this file) drives
//     `V2TIMMessageManager.sendMessageReadReceipts` directly — the call the
//     fork's message list dispatches for group rows carrying
//     `needReadReceipt`. That author intent has NO carrier on the Tox wire, so
//     an inbound group row never has it set and this tool needs `force: true`
//     to do anything; the flag exists so a scenario can never quietly claim the
//     product gate was exercised when it was bypassed.
//   * `l3_mark_read` with a group target (helper below) drives
//     `cleanConversationUnreadMessageCount` → `FfiChatService.markConversationRead`,
//     the same entry point the conversation-row "mark as read" menu item
//     dispatches. That path does NOT consult `needReadReceipt` — the group
//     receipt work deliberately stopped depending on a flag that never travels
//     — so it is the only l3 way to wire group receipts through a path the
//     product really takes, with no force flag to void the claim.
//
// The header here used to say `l3_mark_read` was C2C-only "because
// markConversationRead only sends C2C receipts". That stopped being true when
// `_sendReadReceiptsOnView` learned to dispatch a known group to
// `_sendGroupReadReceiptsOnView` (third_party/tim2tox/dart/lib/service/
// ffi_chat_service.dart), and the claim survived in a comment long enough to be
// planned against. Hence the helper below rather than a second bespoke tool.
//
// Lives in its own file so the pinned l3_debug_tools.dart does not keep
// growing; registered from there behind the same kDebugMode + TOXEE_L3_TEST
// gate, and MUTATING, so it also requires the test/seed account.

import 'package:mcp_toolkit/mcp_toolkit.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

import '../../sdk_fake/fake_uikit_core.dart';
import '../../util/logger.dart';
import '../../util/prefs.dart';

/// Adds the group receipt tools to the MCP registry. [isTestAccount] is the
/// caller's account gate (l3_debug_tools' `_activeAccountIsTest`).
void registerL3GroupReceiptTools({
  required Future<bool> Function() isTestAccount,
}) {
  addMcpTool(_l3MarkGroupReadEntry(isTestAccount));
}

MCPCallEntry _l3MarkGroupReadEntry(
  Future<bool> Function() isTestAccount,
) => MCPCallEntry.tool(
  handler: (request) async {
    if (!await isTestAccount()) {
      return MCPCallResult(
        message: 'l3_mark_group_read: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) {
      return MCPCallResult(
        message: 'l3_mark_group_read: session not ready',
        parameters: {'ok': false, 'error': 'session_not_ready'},
      );
    }
    var groupId = (request['groupId'] ?? request['conversationId'] ?? '')
        .toString();
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    if (groupId.isEmpty) {
      return MCPCallResult(
        message: 'l3_mark_group_read: no target — pass groupId',
        parameters: {'ok': false, 'error': 'no_target'},
      );
    }
    if (!ffi.knownGroups.contains(groupId)) {
      return MCPCallResult(
        message: 'l3_mark_group_read: unknown group $groupId',
        parameters: {'ok': false, 'error': 'unknown_group'},
      );
    }

    // The product only receipts inbound rows the AUTHOR asked receipts for
    // (needReadReceipt), which is also the fork's gate. Receipting everything
    // by default would make a scenario green on traffic the product would
    // never receipt.
    //
    // KNOWN GAP the `force` flag exists for: the author's needReadReceipt
    // intent is a LOCAL flag on the sender's row and has no carrier on the Tox
    // wire, so an inbound group row never has it set. Correlation (the alias
    // round trip and the reader tally) is therefore only drivable with
    // force:true until that intent gets a version-safe wire representation.
    // force is test-only and must be spelled out by the caller, so a scenario
    // can never quietly claim the product gate was exercised.
    final force = request['force'] == 'true' || request['force'] == true;
    final inbound = ffi
        .getHistory(groupId)
        .where((m) => !m.isSelf && (m.msgID?.isNotEmpty ?? false))
        .toList();
    final wanted =
        force ? inbound : inbound.where((m) => m.needReadReceipt).toList();
    if (wanted.isEmpty) {
      return MCPCallResult(
        message: force
            ? 'l3_mark_group_read: no inbound group message to receipt'
            : 'l3_mark_group_read: no inbound message asks for a receipt '
                '(inbound=${inbound.length}); the author intent has no wire '
                'carrier yet — pass force=true to drive correlation',
        parameters: {
          'ok': false,
          'error': force ? 'no_inbound' : 'no_receipt_requested',
          'inboundCount': inbound.length,
        },
      );
    }

    try {
      final res = await TencentImSDKPlugin.v2TIMManager
          .getMessageManager()
          .sendMessageReadReceipts(
            messageIDList: wanted.map((m) => m.msgID!).toList(),
          );
      if (res.code != 0) {
        AppLogger.info(
          '[L3] l3_mark_group_read: SDK returned ${res.code}: ${res.desc}',
        );
        return MCPCallResult(
          message: 'l3_mark_group_read: SDK returned ${res.code}: ${res.desc}',
          parameters: {
            'ok': false,
            'error': 'sdk_error',
            'code': res.code,
            'detail': res.desc,
          },
        );
      }
      AppLogger.info(
        '[L3] l3_mark_group_read: $groupId → receipted ${wanted.length}',
      );
      return MCPCallResult(
        message: 'group read receipts sent',
        parameters: {
          'ok': true,
          'groupId': groupId,
          'forced': force,
          'receiptedCount': wanted.length,
          'messageIDs': wanted.map((m) => m.msgID!).toList(),
        },
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_mark_group_read failed', e, st);
      return MCPCallResult(
        message: 'l3_mark_group_read: failed: $e',
        parameters: {
          'ok': false,
          'error': 'mark_group_read_failed',
          'detail': '$e',
        },
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_mark_group_read',
    description:
        'L3 TEST ONLY: send GROUP read receipts through the REAL production '
        'path — V2TIMMessageManager.sendMessageReadReceipts, the same call the '
        'fork message list dispatches for group messages that carry '
        'needReadReceipt (routed into Tim2ToxSdkPlatform → '
        'FfiChatService.markMessageAsRead with a groupID, which echoes the '
        'cross-peer gmid alias so the AUTHOR can tally the reader). Only rows '
        'whose author requested a receipt are receipted; if none did, the call '
        'fails loudly instead of inventing traffic, and `force: "true"` has to be '
        'spelled out to bypass that gate. For the OTHER group read path -- '
        'the conversation-row mark-as-read, which does not consult '
        'needReadReceipt and is therefore drivable without force -- call '
        'l3_mark_read with a groupId.',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(description: 'Target group id.'),
        'conversationId': StringSchema(
          description: 'group_<id> alternative to groupId.',
        ),
        'force': StringSchema(
          description:
              'TEST-ONLY "true": receipt every inbound row, ignoring the '
              'needReadReceipt gate. Needed because the author\'s intent has '
              'no Tox wire carrier yet, so inbound rows never carry it.',
        ),
      },
    ),
  ),
);

/// `l3_mark_read`'s GROUP branch, or null when [conversationId] / [groupId]
/// name no group at all — the caller then continues down its C2C path.
///
/// Drives the SAME `cleanConversationUnreadMessageCount` the conversation-row
/// menu item dispatches, so the tool models "marked read WITHOUT opening the
/// conversation" for a group exactly as it already does for a C2C peer.
///
/// WHAT A GREEN RESULT DOES NOT PROVE. `markConversationRead` starts the group
/// receipt walk only for a group in `knownGroups`, the walk runs over the
/// history that is LOADED (it returns early for a conversation this session
/// never loaded), and the sends are not awaited. So `ok: true` is evidence that
/// the reader's local read state advanced — not that a receipt reached the
/// author. The only assertion that proves the round trip is the AUTHOR's own
/// row flipping `isRead` false → true, which is why the group branch of
/// `l3_dump_state` surfaces `isRead`.
///
/// An UNKNOWN or QUIT group is refused rather than dispatched: for a group the
/// service does not know, `markConversationRead` would advance a barrier, skip
/// the receipt walk entirely, and still return success — a green call that
/// wired nothing. A quit group additionally has no unread bucket left, so its
/// count would read 0 and look like a successful clear.
Future<MCPCallResult?> l3MarkGroupConversationRead({
  required String? groupId,
  required String conversationId,
}) async {
  final ffi = FakeUIKit.instance.im?.ffi;
  if (ffi == null) return null;
  // `groupId` wins over anything parsed out of a conversation id, and over the
  // active-peer fallback the C2C path applies: an explicit group target must
  // never be resolved into some other conversation.
  var gid = (groupId ?? '').trim();
  // A groupId KEY that is present but blank is an explicit group target with no
  // value, not an invitation to fall through to the C2C path.
  if (groupId != null && gid.isEmpty) {
    return MCPCallResult(
      message: 'l3_mark_read: no target -- groupId was empty',
      parameters: {'ok': false, 'error': 'no_target'},
    );
  }
  if (gid.isEmpty && conversationId.startsWith('group_')) {
    gid = conversationId.substring('group_'.length).trim();
  }
  if (gid.isEmpty) {
    final bare = conversationId.trim();
    final isGroupId = ffi.knownGroups.contains(bare) ||
        ffi.quitGroups.contains(bare) ||
        (bare.isNotEmpty && (await Prefs.getGroups()).contains(bare));
    if (!isGroupId) return null;
    gid = bare;
  }
  if (gid.isEmpty) {
    return MCPCallResult(
      message: 'l3_mark_read: no target — pass groupId',
      parameters: {'ok': false, 'error': 'no_target'},
    );
  }
  if (ffi.quitGroups.contains(gid)) {
    return MCPCallResult(
      message: 'l3_mark_read: $gid is a group this account has quit',
      parameters: {'ok': false, 'error': 'group_quit', 'groupId': gid},
    );
  }
  if (!ffi.knownGroups.contains(gid)) {
    return MCPCallResult(
      message: 'l3_mark_read: unknown group $gid — mark-read would clear the '
          'barrier without wiring a single receipt',
      parameters: {'ok': false, 'error': 'group_unknown', 'groupId': gid},
    );
  }
  try {
    final res = await TencentImSDKPlugin.v2TIMManager
        .getConversationManager()
        .cleanConversationUnreadMessageCount(
          conversationID: 'group_$gid',
          cleanTimestamp: 0,
          cleanSequence: 0,
        );
    if (res.code != 0) {
      AppLogger.info(
        '[L3] l3_mark_read(group): SDK returned ${res.code}: ${res.desc}',
      );
      return MCPCallResult(
        message: 'l3_mark_read: SDK returned ${res.code}: ${res.desc}',
        parameters: {
          'ok': false,
          'error': 'sdk_error',
          'code': res.code,
          'detail': res.desc,
        },
      );
    }
    // The GROUP counter, not the C2C one: groups deliberately stay on the
    // in-memory `_unreadByPeer` bucket because there is no persisted
    // read-barrier reconciliation for them, and `getUnreadOf` is the accessor
    // that routes on the authoritative knownGroups / quitGroups sets.
    final unread = ffi.getUnreadOf(gid);
    AppLogger.info('[L3] l3_mark_read(group): $gid → unread=$unread');
    return MCPCallResult(
      message: 'marked group read',
      parameters: {
        'ok': true,
        'groupId': gid,
        'conversationId': 'group_$gid',
        'unreadCount': unread,
      },
    );
  } catch (e, st) {
    AppLogger.logError('[L3] l3_mark_read(group) failed', e, st);
    return MCPCallResult(
      message: 'l3_mark_read: failed: $e',
      parameters: {'ok': false, 'error': 'mark_read_failed', 'detail': '$e'},
    );
  }
}
