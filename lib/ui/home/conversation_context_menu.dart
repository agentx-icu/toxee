import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../util/app_spacing.dart';
import '../testing/ui_keys.dart';

/// The conversation-row context menu (right-click on desktop, long-press on
/// mobile) and its delete confirmation. [isSelf] marks the self conversation
/// ("note to self"), which offers no Delete: it is the user's local notebook
/// and is never deleted (Tim2ToxSdkPlatform refuses it as well).
List<PopupMenuEntry<String>> buildConversationContextMenuItems({
  required AppLocalizations l10n,
  required ColorScheme scheme,
  required bool isPinned,
  required bool hasUnread,
  bool isSelf = false,
}) {
  return <PopupMenuEntry<String>>[
    PopupMenuItem<String>(
      key: isPinned
          ? UiKeys.conversationContextMenuUnpinItem
          : UiKeys.conversationContextMenuPinItem,
      value: 'pin',
      child: Row(
        children: [
          Icon(
            isPinned ? Icons.push_pin_outlined : Icons.push_pin,
            size: 18,
            color: scheme.onSurface,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(isPinned ? l10n.unpinConversation : l10n.pinConversation),
        ],
      ),
    ),
    PopupMenuItem<String>(
      key: UiKeys.conversationContextMenuMarkReadItem,
      value: 'mark_read',
      enabled: hasUnread,
      child: Row(
        children: [
          Icon(
            Icons.mark_email_read_outlined,
            size: 18,
            color: hasUnread ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(l10n.markConversationAsRead),
        ],
      ),
    ),
    // The self conversation (the user's notebook) is never deleted.
    if (!isSelf) const PopupMenuDivider(),
    if (!isSelf)
    PopupMenuItem<String>(
      key: UiKeys.conversationContextMenuDeleteItem,
      value: 'delete',
      child: Row(
        children: [
          Icon(Icons.delete_outline, size: 18, color: scheme.error),
          const SizedBox(width: AppSpacing.sm),
          Text(l10n.delete, style: TextStyle(color: scheme.error)),
        ],
      ),
    ),
  ];
}

AlertDialog buildDeleteConversationDialog({
  required BuildContext dialogCtx,
  required AppLocalizations l10n,
  required ColorScheme scheme,
  required String conversationLabel,
}) {
  // Pop ONLY while this dialog is still the topmost route. Without this guard a
  // double-invocation of the button — a fast real double-click, or a test
  // harness that both dispatches a synthetic pointer AND directly calls
  // `onPressed` — fires `pop` twice: the first closes the dialog, the second
  // unwinds the root HomePage route, emptying the Navigator and blanking the
  // whole window. `ModalRoute.isCurrent` flips to false synchronously inside
  // the first `pop`, so the second call is a no-op. This dialog is shown
  // directly over HomePage (the only route), which is exactly the case where
  // the extra pop has nothing left to land on.
  void dismiss(bool result) {
    final route = ModalRoute.of(dialogCtx);
    if (route != null && route.isCurrent) {
      Navigator.of(dialogCtx).pop(result);
    }
  }

  return AlertDialog(
    title: Text(l10n.deleteConversationTitle),
    content: Text(l10n.deleteConversationBody(conversationLabel)),
    actions: [
      TextButton(
        key: UiKeys.deleteConversationCancelButton,
        onPressed: () => dismiss(false),
        child: Text(l10n.cancel),
      ),
      TextButton(
        key: UiKeys.deleteConversationConfirmButton,
        onPressed: () => dismiss(true),
        style: TextButton.styleFrom(foregroundColor: scheme.error),
        child: Text(l10n.delete),
      ),
    ],
  );
}
