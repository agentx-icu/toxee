import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../i18n/app_localizations.dart';
import '../../util/platform_utils.dart';
import '../testing/nearby_ui_keys.dart';

/// Renders a `V2TIM_ELEM_TYPE_LOCATION` message (the fork's own builder is a
/// stub). No map provider: label, coordinates, *Open in Maps* through the OS
/// and *Copy*. Shared Dart, so phones and desktops render the same bubble.
class LocationMessageBubble extends StatelessWidget {
  const LocationMessageBubble({
    super.key,
    required this.message,
    this.launcher,
  });

  final V2TimMessage message;

  /// Test seam for `launchUrl`.
  final Future<bool> Function(Uri uri)? launcher;

  double? get latitude => message.locationElem?.latitude;
  double? get longitude => message.locationElem?.longitude;

  /// The OS maps deep link for a position.
  static Uri mapsUri(double latitude, double longitude, {String? label}) {
    final lat = latitude.toStringAsFixed(6);
    final lon = longitude.toStringAsFixed(6);
    if (PlatformUtils.isAndroid) {
      return Uri.parse('geo:$lat,$lon?q=$lat,$lon');
    }
    if (PlatformUtils.isIOS || PlatformUtils.isMacOS) {
      final q = Uri.encodeComponent(label ?? '$lat,$lon');
      return Uri.parse('maps://?ll=$lat,$lon&q=$q');
    }
    return Uri.parse(
        'https://www.openstreetmap.org/?mlat=$lat&mlon=$lon#map=16/$lat/$lon');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final lat = latitude;
    final lon = longitude;
    final theme = Theme.of(context);
    if (lat == null || lon == null) {
      return Text('[${l10n.locationMessageLabel}]');
    }
    final desc = message.locationElem?.desc ?? '';
    final coords = '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_on, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  desc.isEmpty || desc == coords ? l10n.locationMessageLabel : desc,
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SelectableText(coords, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                key: NearbyUiKeys.locationBubbleOpenMaps,
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.map_outlined, size: 16),
                label: Text(l10n.openInMaps),
                onPressed: () => unawaited(_open(context, lat, lon, desc)),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.copy, size: 16),
                label: Text(l10n.copyCoordinates),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: coords));
                  if (!context.mounted) return;
                  ScaffoldMessenger.maybeOf(context)
                    ?..hideCurrentSnackBar()
                    ..showSnackBar(SnackBar(content: Text(l10n.copied)));
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, double lat, double lon, String desc) async {
    final uri = mapsUri(lat, lon, label: desc.isEmpty ? null : desc);
    final launch = launcher ?? (Uri u) => launchUrl(u, mode: LaunchMode.externalApplication);
    var ok = false;
    try {
      ok = await launch(uri);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.maybeOf(context)
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.openInMapsFailed)));
    }
  }
}
