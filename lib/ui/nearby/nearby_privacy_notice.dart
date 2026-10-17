import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';

/// Shown once when "Visible to people nearby" is first turned on: what is
/// shared, with whom, and what is not (plan §4.5). Returns true when the user
/// accepts.
Future<bool> showNearbyPrivacyNotice(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.nearbyPrivacyTitle),
      content: SingleChildScrollView(child: Text(l10n.nearbyPrivacyBody)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.nearbyPrivacyAccept),
        ),
      ],
    ),
  );
  return accepted ?? false;
}

/// Consent before an intent discloses the user's Tox ID to one chosen peer.
Future<bool> showNearbyConsent(BuildContext context, String peerName) async {
  final l10n = AppLocalizations.of(context)!;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.nearbyConsentTitle),
      content: Text(l10n.nearbyConsentBody(peerName)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.nearbySendRequest),
        ),
      ],
    ),
  );
  return accepted ?? false;
}
