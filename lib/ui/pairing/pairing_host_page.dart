import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:path_provider/path_provider.dart';

import '../../i18n/app_localizations.dart';
import '../../util/account_export_service.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/logger.dart';
import '../../util/pairing/pairing_host.dart';
import '../../util/pairing/pairing_lan.dart';
import 'pairing_status_indicator.dart';

/// Maximum content width for the pairing flow on wide screens. Above this we
/// pad the surrounding scaffold so the QR + verification code never spreads
/// across a 1600pt window.
const double _kMaxContentWidth = 480;

/// Cosmetic background applied to the white QR plate. Even in dark mode the
/// QR scanner expects a high-contrast white surface, so this is intentionally
/// theme-independent (mirrors the same pin in [ContactQrCardGenerator]).
const Color _kQrPlateBackground = Colors.white;

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
    // Use OS temp dir, not the persistent tim2tox profile dir: this file is
    // exported, read, and deleted within a single `_start()` call. Living in
    // `getTemporaryDirectory()` means the OS will clean it up if we crash
    // mid-flow and it won't be backed up to iCloud / iTunes.
    final dir = await getTemporaryDirectory();
    final prefix = toxId.length >= 8 ? toxId.substring(0, 8) : toxId;
    return '${dir.path}${Platform.pathSeparator}pairing_$prefix.tox';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) == true;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pairDeviceHostTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : AppDurations.medium,
                switchInCurve: AppCurves.standard,
                switchOutCurve: AppCurves.standard,
                child: KeyedSubtree(
                  key: ValueKey(_currentStateKey()),
                  child: _buildBody(l10n),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _currentStateKey() {
    if (_completed) return 'completed';
    if (_error != null) return 'error';
    if (_startingUp || _qrUrl == null) return 'startup';
    if (_sas != null) return 'sas';
    return 'qr-ready';
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_completed) {
      return _CenteredMessage(
        state: PairingState.connected,
        message: l10n.pairingHostCompleted,
        actionLabel: l10n.done,
        onAction: () => Navigator.of(context).maybePop(),
      );
    }
    if (_error != null) {
      return _CenteredMessage(
        state: PairingState.error,
        message: _error!,
        actionLabel: l10n.cancel,
        onAction: () => Navigator.of(context).maybePop(),
      );
    }
    if (_startingUp || _qrUrl == null) {
      return _CenteredMessage(
        state: PairingState.scanning,
        message: l10n.pairingWaitingForPeer,
      );
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
          AppSpacing.verticalXl,
          Center(child: _QrPlate(url: _qrUrl!)),
          AppSpacing.verticalXl,
          if (_sas != null) ...[
            _SasBlock(
              sas: _sas!,
              header: l10n.pairingVerifyCodeHeader,
              onConfirm: () => _host?.confirmSas(),
              confirmLabel: l10n.pairingCodesMatch,
              cancelLabel: l10n.cancel,
              onCancel: () => Navigator.of(context).maybePop(),
            ),
          ] else ...[
            _StatusRow(
              state: PairingState.waiting,
              label: l10n.pairingWaitingForPeer,
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
}

/// White QR plate with rounded corners and a subtle accent dot in the center.
class _QrPlate extends StatelessWidget {
  const _QrPlate({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _kQrPlateBackground,
        borderRadius: BorderRadius.circular(AppRadii.card),
        boxShadow: AppThemeConfig.elevationLight,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          QrImageView(
            data: url,
            version: QrVersions.auto,
            size: 260,
            gapless: true,
            backgroundColor: _kQrPlateBackground,
            errorCorrectionLevel: QrErrorCorrectLevel.H,
          ),
          // Tiny brand accent at center — H-level EC tolerates ~30% occlusion.
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _kQrPlateBackground,
              shape: BoxShape.circle,
              border: Border.all(color: cs.primary, width: 2),
            ),
            child: Icon(Icons.lock_outline, size: 14, color: cs.primary),
          ),
        ],
      ),
    );
  }
}

/// Big monospace short-authentication-string display + confirm/cancel actions.
class _SasBlock extends StatelessWidget {
  const _SasBlock({
    required this.sas,
    required this.header,
    required this.onConfirm,
    required this.confirmLabel,
    required this.onCancel,
    required this.cancelLabel,
  });

  final String sas;
  final String header;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final VoidCallback onCancel;
  final String cancelLabel;

  String _format(String sas) {
    if (sas.length != 6) return sas;
    return '${sas.substring(0, 3)} ${sas.substring(3)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          header,
          style: theme.textTheme.titleSmall,
          textAlign: TextAlign.center,
        ),
        AppSpacing.verticalMd,
        Center(
          child: Text(
            _format(sas),
            style: theme.textTheme.displaySmall?.copyWith(
              fontFamily: 'monospace',
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 8,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
        AppSpacing.verticalLg,
        FilledButton.icon(
          icon: const Icon(Icons.check),
          label: Text(confirmLabel),
          onPressed: onConfirm,
        ),
        AppSpacing.verticalSm,
        OutlinedButton(onPressed: onCancel, child: Text(cancelLabel)),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.state, required this.label});
  final PairingState state;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        PairingStatusIndicator(state: state, size: 18),
        AppSpacing.horizontalSm,
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.state,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final PairingState state;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PairingStatusIndicator(state: state, size: 56),
          AppSpacing.verticalLg,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            AppSpacing.verticalLg,
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
