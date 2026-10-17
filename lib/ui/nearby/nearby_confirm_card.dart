import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../nearby/nearby_friend_request.dart';

/// The one-tap confirm for a friend application that answers one of our
/// nearby intents (plan §3.4, initiator side). Shows the card we contacted
/// and the handshake-authenticated sender key; nothing is accepted silently.
/// Returns true to accept.
Future<bool> showNearbyReplyCard(BuildContext context, NearbyReply reply) async {
  final l10n = AppLocalizations.of(context)!;
  final name = reply.intent.targetName.isEmpty
      ? l10n.nearbyUnnamed
      : reply.intent.targetName;
  final key = reply.senderPublicKey;
  final fingerprint = key.length > 20
      ? '${key.substring(0, 8)}…${key.substring(key.length - 6)}'
      : key;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.nearbyReplyTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.nearbyReplyBody(name)),
          const SizedBox(height: 12),
          Text(l10n.publicKeyLabel,
              style: Theme.of(ctx).textTheme.labelSmall),
          Tooltip(
            message: key,
            child: SelectableText(fingerprint,
                style: const TextStyle(fontFamily: 'monospace')),
          ),
          if ((reply.application.addWording ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _messageOf(reply.application.addWording!),
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.nearbyReplyLater),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.nearbyAccept),
        ),
      ],
    ),
  );
  return accepted ?? false;
}

/// The human part of a `toxee-nearby:<nonce> <message>` wording.
String _messageOf(String wording) {
  final space = wording.indexOf(' ');
  return space < 0 ? '' : wording.substring(space + 1);
}
