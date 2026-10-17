import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/app_localizations.dart';
import 'location_source.dart';

/// The user-facing permission flow for location (checklist P1/P1b: explain
/// a blocked permission and offer the way to Settings; never a silent dead
/// end). Deliberately separate from the call helper, which skips runtime
/// requests on macOS/Linux — location prompts there too.
class LocationPermissionHelper {
  LocationPermissionHelper(this._source);

  final LocationSource _source;

  /// Single-flight: a second request while the OS prompt is up would be
  /// rejected by the platform (and on Android cancels the first).
  Future<LocationPermissionState>? _inflight;

  /// Ensures the permission; shows the explain → Settings dialog when the OS
  /// did not (or will not) ask. Returns true when the position may be read.
  Future<bool> ensure(BuildContext context) async {
    final state = await request();
    if (state == LocationPermissionState.granted) return true;
    if (!context.mounted) return false;
    await showDeniedDialog(context, state);
    return false;
  }

  Future<LocationPermissionState> request() {
    final pending = _inflight;
    if (pending != null) return pending;
    final run = _source.requestPermission().whenComplete(() => _inflight = null);
    _inflight = run;
    return run;
  }

  Future<void> showDeniedDialog(
      BuildContext context, LocationPermissionState state) async {
    final l10n = AppLocalizations.of(context)!;
    final body = switch (state) {
      LocationPermissionState.serviceDisabled => l10n.locationServiceDisabled,
      LocationPermissionState.unavailable => l10n.locationUnavailable,
      _ => l10n.locationPermissionDenied,
    };
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.locationServices),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          if (state != LocationPermissionState.unavailable)
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                unawaited(_source.openSettings());
              },
              child: Text(l10n.openSettings),
            ),
        ],
      ),
    );
  }
}
