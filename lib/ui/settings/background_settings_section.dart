import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../i18n/app_localizations.dart';
import '../../notifications/notification_privacy.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/logger.dart';
import '../testing/ui_keys_settings.dart';
import '../widgets/section_header.dart';

/// Settings > Background & notifications.
///
/// - Hide message content in notifications (every platform).
/// - Android only: whether battery optimization may stop the background
///   session, with a button for the system exemption dialog. Tox has no push
///   server, so a stopped session means no messages or calls arrive; many
///   OEM builds stop apps that are not exempt.
class BackgroundSettingsSection extends StatefulWidget {
  const BackgroundSettingsSection({
    super.key,
    @visibleForTesting this.isAndroidOverride,
    @visibleForTesting this.channel = _channel,
  });

  final bool? isAndroidOverride;
  final MethodChannel channel;

  static const MethodChannel _channel = MethodChannel(
    'toxee/notification_access',
  );

  @override
  State<BackgroundSettingsSection> createState() =>
      _BackgroundSettingsSectionState();
}

class _BackgroundSettingsSectionState extends State<BackgroundSettingsSection> {
  bool _hideContent = false;
  bool _touched = false; // a tap wins over the initial read
  int _taps = 0;

  /// Null until read (and always null off Android).
  bool? _batteryExempt;
  AppLifecycleListener? _resume;

  bool get _isAndroid => widget.isAndroidOverride ?? Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHideContent());
    if (_isAndroid) {
      // Re-read when the user comes back from the system dialog / list.
      _resume = AppLifecycleListener(onResume: () => unawaited(_readBattery()));
      unawaited(_readBattery());
    }
  }

  @override
  void dispose() {
    _resume?.dispose();
    super.dispose();
  }

  Future<void> _loadHideContent() async {
    final value = await NotificationPrivacy.hidesContent();
    if (mounted && !_touched) setState(() => _hideContent = value);
  }

  Future<void> _setHideContent(bool value) async {
    _touched = true;
    final tap = ++_taps;
    setState(() => _hideContent = value);
    try {
      await NotificationPrivacy.setHideContent(value);
    } catch (e) {
      AppLogger.warn('[BackgroundSettings] hide-content not saved: $e');
      // Only the latest tap may revert; show what is actually in effect.
      if (mounted && tap == _taps) {
        setState(
          () => _hideContent = NotificationPrivacy.hideContent.value ?? true,
        );
      }
    }
  }

  Future<void> _readBattery() async {
    try {
      final exempt = await widget.channel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      if (mounted) setState(() => _batteryExempt = exempt);
    } on MissingPluginException {
      // Not wired on this host.
    } catch (e) {
      AppLogger.warn('[BackgroundSettings] battery status failed: $e');
    }
  }

  Future<void> _requestExemption() async {
    try {
      await widget.channel.invokeMethod<void>(
        'requestIgnoreBatteryOptimizations',
      );
    } catch (e) {
      AppLogger.warn('[BackgroundSettings] exemption request failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(title: l10n.backgroundSettingsTitle),
            AppSpacing.verticalSm,
            ..._rows(l10n),
          ],
        ),
      ),
    );
  }

  List<Widget> _rows(AppLocalizations l10n) {
    final exempt = _batteryExempt;
    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        key: SettingsUiKeys.hideNotificationContentSwitch,
        title: Text(l10n.hideNotificationContent),
        subtitle: Text(l10n.hideNotificationContentDesc),
        value: _hideContent,
        onChanged: (v) => unawaited(_setHideContent(v)),
      ),
      if (_isAndroid && exempt != null)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.backgroundRunningTitle),
          subtitle: Text(
            exempt
                ? l10n.backgroundRunningAllowed
                : l10n.backgroundRunningRestricted,
          ),
          trailing: exempt
              ? const Icon(Icons.check_circle_outline)
              : TextButton(
                  key: SettingsUiKeys.backgroundRunningAllowButton,
                  onPressed: () => unawaited(_requestExemption()),
                  child: Text(l10n.backgroundRunningAllow),
                ),
        ),
    ];
  }
}
