// L3 seam for GROUP read receipts.
//
// `l3_mark_read` is deliberately C2C-only: it dispatches
// cleanConversationUnreadMessageCount, which routes to
// FfiChatService.markConversationRead — and that function only sends C2C
// receipts. A group read receipt is a different product path entirely
// (V2TIMMessageManager.sendMessageReadReceipts -> markMessageAsRead with a
// groupID), the one the fork's message list dispatches for group messages
// carrying needReadReceipt. Driving group receipts through the C2C tool would
// have proven nothing, so this tool mirrors the real group path instead.
//
// Lives in its own file so the pinned l3_debug_tools.dart does not keep
// growing; registered from there behind the same kDebugMode + TOXEE_L3_TEST
// gate, and MUTATING, so it also requires the test/seed account.

import 'package:mcp_toolkit/mcp_toolkit.dart';
import 'package:tencent_cloud_chat_sdk/tencent_im_sdk_plugin.dart';

import '../../sdk_fake/fake_uikit_core.dart';
import '../../util/logger.dart';

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
        'fails loudly instead of inventing traffic. Use l3_mark_read for C2C.',
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
