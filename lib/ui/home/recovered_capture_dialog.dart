import 'dart:io';

import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../util/camera_capture_recovery.dart';
import '../widgets/safe_dialog_pop.dart';

/// Asks whether to send a photo / video taken, or a file picked, before
/// Android reclaimed the app (checklist M9). Pops true (send) or false (discard); nothing goes out
/// unseen.
class RecoveredCaptureDialog extends StatelessWidget {
  const RecoveredCaptureDialog({
    super.key,
    required this.capture,
    required this.peerName,
  });

  static const sendKey = Key('recovered_capture_send');
  static const discardKey = Key('recovered_capture_discard');

  final RecoveredCapture capture;
  final String peerName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final fileName = capture.name ?? capture.path.split('/').last;
    final preview = capture.isFile
        ? Icon(Icons.insert_drive_file_outlined, size: 72, color: scheme.primary)
        : capture.isVideo
        ? Icon(Icons.videocam_outlined, size: 72, color: scheme.primary)
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(capture.path),
              fit: BoxFit.contain,
              cacheHeight: 480,
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.image_outlined, size: 72, color: scheme.primary),
            ),
          );
    return AlertDialog(
      title: Text(
        capture.isFile
            ? l10n.recoveredFileTitle
            : capture.isVideo
            ? l10n.recoveredVideoTitle
            : l10n.recoveredPhotoTitle,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: preview,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            capture.isFile
                ? l10n.recoveredFileBody(fileName, peerName)
                : l10n.recoveredCaptureBody(peerName),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: discardKey,
          onPressed: () => popDialogIfCurrent(context, false),
          child: Text(l10n.recoveredCaptureDiscard),
        ),
        FilledButton(
          key: sendKey,
          onPressed: () => popDialogIfCurrent(context, true),
          child: Text(l10n.recoveredCaptureSend),
        ),
      ],
    );
  }
}
