import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../notifications/notification_access.dart';
import '../testing/ui_keys_home.dart';
import '../../util/app_spacing.dart';

/// The Chats-tab notice shown while system notifications cannot alert the
/// user in the background — the only way a backgrounded Tox session surfaces
/// messages and calls, since there is no push server.
///
/// Not dismissible: it disappears as soon as the problem is fixed (the
/// monitor re-reads on resume from system settings), and it is the one place
/// the problem is surfaced, so hiding it would bury it. Renders nothing when
/// access is [NotificationAccess.ok] and on desktops (the monitor stays ok).
///
/// Wraps the Chats tab ([child]) and sits above it. While shown it takes the
/// status-bar inset itself and removes it from [child], whose app bar would
/// otherwise pad it a second time. The widget structure is the same whether
/// or not the notice shows, so [child] is never rebuilt from scratch (which
/// would drop its state, e.g. a focused composer).
class NotificationAccessBanner extends StatefulWidget {
  const NotificationAccessBanner({
    super.key,
    required this.child,
    NotificationAccessMonitor? monitor,
    Future<void> Function(NotificationAccess access)? openSettings,
  }) : _monitor = monitor,
       _openSettings = openSettings;

  final Widget child;
  final NotificationAccessMonitor? _monitor;
  final Future<void> Function(NotificationAccess access)? _openSettings;

  @override
  State<NotificationAccessBanner> createState() =>
      _NotificationAccessBannerState();
}

class _NotificationAccessBannerState extends State<NotificationAccessBanner> {
  NotificationAccessMonitor get _monitor =>
      widget._monitor ?? NotificationAccessMonitor.instance;

  @override
  void initState() {
    super.initState();
    _monitor.start();
  }

  static String _message(AppLocalizations l10n, NotificationAccess access) =>
      switch (access) {
        NotificationAccess.appOff => l10n.notificationAccessAppOff,
        NotificationAccess.callsChannelOff => l10n.notificationAccessCallsOff,
        NotificationAccess.fullScreenIntentOff =>
          l10n.notificationAccessFullScreenOff,
        NotificationAccess.messagesOff => l10n.notificationAccessMessagesOff,
        NotificationAccess.otherChannelsOff => l10n.notificationAccessOtherOff,
        NotificationAccess.alertsOff => l10n.notificationAccessAlertsOff,
        NotificationAccess.provisional => l10n.notificationAccessProvisional,
        NotificationAccess.ok => '',
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NotificationAccess>(
      valueListenable: _monitor.access,
      builder: (context, access, _) {
        final shown = access != NotificationAccess.ok;
        return Column(
          children: [
            if (shown) _notice(context, access) else const SizedBox.shrink(),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: shown,
                child: widget.child,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _notice(BuildContext context, NotificationAccess access) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final open = widget._openSettings ?? openNotificationSettings;
    return Material(
      key: HomeUiKeys.notificationAccessBanner,
      color: scheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Icon(
                Icons.notifications_off_outlined,
                size: 18,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _message(l10n, access),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
              TextButton(
                key: HomeUiKeys.notificationAccessSettings,
                onPressed: () => unawaited(open(access)),
                child: Text(l10n.notificationAccessOpenSettings),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
