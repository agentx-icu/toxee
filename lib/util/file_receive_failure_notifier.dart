import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:tim2tox_dart/service/file_receive_failure.dart';

import '../i18n/app_localizations.dart';
import '../ui/widgets/app_snackbar.dart';
import 'app_l10n.dart';
import 'logger.dart';
import 'send_failure_notifier.dart';

/// Tells the user when an incoming file could not be received — above all
/// because the device is out of storage (checklist M5).
///
/// Without this a full disk was invisible: the transfer stalled until a 180 s
/// idle sweep flipped the bubble to "failed" with no reason, and a manual
/// download refused for space only logged the error (the UIKit download
/// utility ignores the returned code). `FfiChatService.fileReceiveFailures`
/// now carries every local receive failure (write error mid-transfer, accept
/// refused because the file cannot fit, finalization failure); this shows it
/// as an error toast on the app-wide messenger (same one SendFailureNotifier
/// uses, see its docs for why `showErrorOnBuilder`), deduplicated per
/// file+reason for a few seconds.
///
/// Shared Dart: Android, iOS and desktop alike.
class FileReceiveFailureNotifier {
  FileReceiveFailureNotifier._();

  static const Duration _dedupWindow = Duration(seconds: 3);
  static final Map<String, DateTime> _lastShown = <String, DateTime>{};

  @visibleForTesting
  static void resetForTests() => _lastShown.clear();

  /// Starts listening to [service] for this session; returns the disposer for
  /// the session's DisposableBag.
  static void Function() startForSession(FfiChatService service) {
    final sub = service.fileReceiveFailures.listen(show);
    return () => unawaited(sub.cancel());
  }

  /// The toast text for [failure] (display-site localization).
  static String messageFor(AppLocalizations l10n, FileReceiveFailure failure) {
    final name = failure.fileName;
    final hasName = name != null && name.isNotEmpty;
    return switch (failure.reason) {
      FileReceiveFailureReason.noSpace =>
        hasName ? l10n.fileReceiveNoSpace(name) : l10n.fileReceiveNoSpaceUnnamed,
      FileReceiveFailureReason.io =>
        hasName ? l10n.fileReceiveFailed(name) : l10n.fileReceiveFailedUnnamed,
    };
  }

  static void show(FileReceiveFailure failure) {
    final messenger = SendFailureNotifier.scaffoldMessengerKey.currentState;
    if (messenger == null) {
      AppLogger.warn(
        '[FileReceiveFailureNotifier] receive failed (${failure.reason.name}) but no scaffoldMessenger is mounted',
      );
      return;
    }
    final key = '${failure.msgID ?? failure.fileName}:${failure.reason.name}';
    final now = DateTime.now();
    final last = _lastShown[key];
    if (last != null && now.difference(last) < _dedupWindow) return;
    _lastShown[key] = now;
    AppSnackBar.showErrorOnBuilder(
      messenger,
      (context) =>
          messageFor(AppLocalizations.of(context) ?? currentAppL10n(), failure),
    );
  }
}
