import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../util/prefs.dart';
import 'conversation_list_builder.dart';

/// The self conversation ("note to self"): `c2c_<own public key>`, the user's
/// local notebook. Tim2Tox keeps everything sent to it on this device
/// (`FfiChatService.isSelfPeer`) and refuses to delete it; toxee lists it in
/// the conversation list and offers no Delete on it.
///
/// The row's input, or null while no identity is loaded (no own key yet).
/// The title is the own nickname (falling back to the start of the key), the
/// avatar is the own avatar.
Future<SelfConversationInput?> resolveSelfConversation(
  FfiChatService ffi,
) async {
  final key = ffi.selfPublicKey;
  if (key == null) return null;
  final profile = await Future.wait<String?>([
    Prefs.getNickname(),
    Prefs.getAvatarPath(),
  ]);
  final nickname = profile[0]?.trim() ?? '';
  return (
    key: key,
    title: nickname.isNotEmpty ? nickname : key.substring(0, 8),
    faceUrl: profile[1],
    activity: ffi.lastMessages[key]?.timestamp,
  );
}

/// Whether [conversationID] is the self conversation of [ffi]'s account.
bool isSelfConversationId(FfiChatService? ffi, String conversationID) =>
    ffi != null &&
    conversationID.startsWith('c2c_') &&
    ffi.isSelfPeer(conversationID);
