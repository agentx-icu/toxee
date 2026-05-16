import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../i18n/app_localizations.dart';
import '../../util/account_export_service.dart';
import '../../util/app_paths.dart';
import '../../util/app_spacing.dart';
import '../../util/logger.dart';
import '../../util/pairing/pairing_host.dart';
import '../../util/pairing/pairing_lan.dart';

/// Device A page: shows a QR code that Device B scans to pair. Once Device B
/// connects, displays the 6-digit SAS and the "the codes match" confirm
/// button. Sender of the `.tox` blob.
class PairingHostPage extends StatefulWidget {
  const PairingHostPage({
    super.key,
    required this.toxId,
    this.exportServiceForTest,
  });

  /// Tox ID of the account this device is sharing. Used to look up the
  /// `.tox` blob to send.
  final String toxId;

  /// Test seam — production code uses [AccountExportService.exportAccountData]
  /// to write the bytes to a temp file and read them back. The integration
  /// test injects a fixed byte payload.
  final Future<Uint8List> Function()? exportServiceForTest;

  @override
  State<PairingHostPage> createState() => _PairingHostPageState();
}

class _PairingHostPageState extends State<PairingHostPage> {
  PairingHost? _host;
  StreamSubscription<HostEvent>? _sub;
  String? _qrUrl;
  String? _sas;
  String? _error;
  bool _completed = false;
  bool _startingUp = true;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _sub?.cancel();
    // Best-effort cancel; if it's already completed it's a no-op.
    unawaited(_host?.cancel(reason: 'page disposed'));
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final lanIp = await PairingLan.findLanAddress();
      if (lanIp == null) {
        if (!mounted) return;
        setState(() {
          _startingUp = false;
          _error = AppLocalizations.of(context)!.pairingNoLanInterface;
        });
        return;
      }

      final host = PairingHost(
        loadProfileBlob: () async {
          if (widget.exportServiceForTest != null) {
            return widget.exportServiceForTest!();
          }
          // Export to a temp file, read back, delete. Reuses the audited
          // export path so the byte layout matches what the receiving
          // device's importAccountData() expects.
          final tmp = await _tempExportPath(widget.toxId);
          await AccountExportService.exportAccountData(
            toxId: widget.toxId,
            filePath: tmp,
          );
          final bytes = await File(tmp).readAsBytes();
          try {
            await File(tmp).delete();
          } catch (_) {}
          return bytes;
        },
        bindAddress: '0.0.0.0',
      );
      _host = host;
      _sub = host.events.listen(_onEvent, onError: (Object e, StackTrace _) {
        if (!mounted) return;
        setState(() => _error = '$e');
      });
      final url = await host.start(advertiseAddress: lanIp);
      if (!mounted) return;
      setState(() {
        _qrUrl = url;
        _startingUp = false;
      });
    } catch (e, st) {
      AppLogger.logError('[PairingHostPage] start failed', e, st);
      if (!mounted) return;
      setState(() {
        _startingUp = false;
        _error = '$e';
      });
    }
  }

  void _onEvent(HostEvent event) {
    if (!mounted) return;
    switch (event) {
      case HostQrReady(:final url):
        setState(() => _qrUrl = url);
        break;
      case HostAwaitingSas(:final sas):
        setState(() => _sas = sas);
        break;
      case HostCompleted():
        setState(() => _completed = true);
        break;
      case HostFailed(:final reason, :final message):
        setState(() => _error = _localizeFailure(reason, message));
        break;
    }
  }

  String _localizeFailure(HostFailureReason reason, String message) {
    final l10n = AppLocalizations.of(context)!;
    switch (reason) {
      case HostFailureReason.cancelled:
        return l10n.pairingCancelled;
      case HostFailureReason.timeout:
        return l10n.pairingTimeout;
      case HostFailureReason.networkError:
        return l10n.pairingNetworkError(message);
      case HostFailureReason.protocolError:
        return l10n.pairingProtocolError(message);
    }
  }

  static Future<String> _tempExportPath(String toxId) async {
    final dir = await AppPaths.toxProfileDir;
    final prefix = toxId.length >= 8 ? toxId.substring(0, 8) : toxId;
    return '${dir.path}${Platform.pathSeparator}pairing_$prefix.tox';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pairDeviceHostTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: _buildBody(l10n),
        ),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_completed) {
      return _CenteredMessage(
        icon: Icons.check_circle_outline,
        message: l10n.pairingHostCompleted,
        actionLabel: l10n.done,
        onAction: () => Navigator.of(context).maybePop(),
      );
    }
    if (_error != null) {
      return _CenteredMessage(
        icon: Icons.error_outline,
        message: _error!,
        actionLabel: l10n.cancel,
        onAction: () => Navigator.of(context).maybePop(),
      );
    }
    if (_startingUp || _qrUrl == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.pairingHostInstructions,
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          AppSpacing.verticalLg,
          Center(
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: _qrUrl!,
                version: QrVersions.auto,
                size: 280,
                gapless: true,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          AppSpacing.verticalLg,
          if (_sas != null) ...[
            Text(
              l10n.pairingVerifyCodeHeader,
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            AppSpacing.verticalSm,
            Center(
              child: Text(
                _formatSasForDisplay(_sas!),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      letterSpacing: 8,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            AppSpacing.verticalMd,
            FilledButton.icon(
              icon: const Icon(Icons.check),
              label: Text(l10n.pairingCodesMatch),
              onPressed: () => _host?.confirmSas(),
            ),
            AppSpacing.verticalSm,
            OutlinedButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(l10n.cancel),
            ),
          ] else ...[
            Text(
              l10n.pairingWaitingForPeer,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            AppSpacing.verticalSm,
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l10n.cancel),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// "123456" → "123 456" so users can read it aloud cleanly.
  String _formatSasForDisplay(String sas) {
    if (sas.length != 6) return sas;
    return '${sas.substring(0, 3)} ${sas.substring(3)}';
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          AppSpacing.verticalMd,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          AppSpacing.verticalLg,
          FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

