import 'dart:async';

import 'package:flutter/material.dart';

import '../../i18n/app_localizations.dart';
import '../../navigation/app_navigation.dart';
import '../../util/outgoing_media.dart';

/// Shows a video conversion before sending (checklist M2): progress, and a
/// Cancel that stops the send. Closes itself when the conversion ends.
class MediaTranscodeDialog extends StatefulWidget {
  const MediaTranscodeDialog({
    super.key,
    required this.handle,
    required this.done,
  });

  static const cancelKey = Key('media_transcode_cancel');

  final MediaTranscodeHandle handle;
  final Future<void> done;

  /// [MediaTranscodePresenter] over the app's root navigator. Each dialog
  /// removes its own route when its conversion ends — with two conversions
  /// at once, the one finishing first may not be on top.
  static void present(MediaTranscodeHandle handle, Future<void> done) {
    final navigator = appNavigatorKey.currentState;
    final context = appNavigatorKey.currentContext;
    if (navigator == null || context == null) return;
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MediaTranscodeDialog(handle: handle, done: done),
    );
    unawaited(navigator.push(route));
    unawaited(
      done.whenComplete(() {
        if (route.isActive) navigator.removeRoute(route);
      }),
    );
  }

  @override
  State<MediaTranscodeDialog> createState() => _MediaTranscodeDialogState();
}

class _MediaTranscodeDialogState extends State<MediaTranscodeDialog> {
  bool _cancelling = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(l10n.videoConverting),
        content: ValueListenableBuilder<double>(
          valueListenable: widget.handle.progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.videoConvertingDesc),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: value > 0 ? value : null),
              const SizedBox(height: 8),
              Text('${(value * 100).round()}%', textAlign: TextAlign.end),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: MediaTranscodeDialog.cancelKey,
            onPressed: _cancelling
                ? null
                : () {
                    setState(() => _cancelling = true);
                    unawaited(widget.handle.cancel());
                  },
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }
}
