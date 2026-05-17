import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../i18n/app_localizations.dart';
import '../../util/account_export_service.dart';
import '../../util/app_paths.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/logger.dart';
import '../../util/pairing/pairing_client.dart';
import 'pairing_status_indicator.dart';

/// Max horizontal width for the pairing client surface — mirrors the host
/// page so the two flows feel symmetric on tablet / desktop windows.
const double _kMaxContentWidth = 480;

/// Color of the camera viewfinder frame overlay. White-on-camera-preview is
/// the universal scanner convention regardless of theme.
const Color _kViewfinderStroke = Color(0x99FFFFFF);

/// Device B page: scans the QR code emitted by Device A's [PairingHostPage]
/// (or accepts a pasted URL on desktop where camera scanning is awkward).
class PairingClientPage extends StatefulWidget {
  const PairingClientPage({
    super.key,
    this.materializeProfileForTest,
  });

  /// Test seam — production code writes the plaintext to a temp `.tox` file
  /// and calls [AccountExportService.importAccountData], returning the
  /// extracted toxId. Tests inject a deterministic toxId without disk I/O.
  final Future<String> Function(Uint8List)? materializeProfileForTest;

  @override
  State<PairingClientPage> createState() => _PairingClientPageState();
}

class _PairingClientPageState extends State<PairingClientPage> {
  PairingClient? _client;
  StreamSubscription<ClientEvent>? _sub;
  MobileScannerController? _scannerController;
  String? _sas;
  String? _error;
  String? _completedToxId;
  bool _connecting = false;
  final _pasteController = TextEditingController();

  // Desktop platforms get a paste-URL fallback because typical desktop setups
  // either lack a webcam or have one that's awkward to point at a phone.
  bool get _supportsCameraScan =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    if (_supportsCameraScan) {
      _scannerController = MobileScannerController(
        formats: const [BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.normal,
      );
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(_client?.cancel(reason: 'page disposed'));
    _scannerController?.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _onUrlReceived(String url) async {
    if (_connecting || _client != null) return;
    setState(() => _connecting = true);

    final client = PairingClient(
      materializeProfile: (plaintext) async {
        if (widget.materializeProfileForTest != null) {
          return widget.materializeProfileForTest!(plaintext);
        }
        // Write to a temp file then hand to the audited importAccountData
        // path. That extracts the toxId, prompts for an inner password if
        // the blob itself is password-encrypted, and writes the profile to
        // the per-account directory.
        final tmpDir = await AppPaths.toxProfileDir;
        final tmpPath =
            '${tmpDir.path}${Platform.pathSeparator}pairing_incoming.tox';
        await File(tmpPath).writeAsBytes(plaintext);
        try {
          final res = await AccountExportService.importAccountData(
            filePath: tmpPath,
          );
          final toxId = res['toxId'] as String?;
          if (toxId == null || toxId.isEmpty) {
            throw Exception('Imported profile had no toxId');
          }
          return toxId;
        } finally {
          try {
            await File(tmpPath).delete();
          } catch (_) {}
        }
      },
    );
    _client = client;
    _sub = client.events.listen(_onEvent);
    // Stop the camera so the preview doesn't fight us during handshake.
    try {
      await _scannerController?.stop();
    } catch (_) {}
    try {
      await client.connect(url);
    } catch (e, st) {
      AppLogger.logError('[PairingClientPage] connect threw', e, st);
      if (mounted) {
        setState(() {
          _error = '$e';
          _connecting = false;
        });
      }
    }
  }

  void _onEvent(ClientEvent event) {
    if (!mounted) return;
    switch (event) {
      case ClientAwaitingSas(:final sas):
        setState(() {
          _sas = sas;
          _connecting = false;
        });
        break;
      case ClientCompleted(:final toxId):
        setState(() => _completedToxId = toxId);
        break;
      case ClientFailed(:final reason, :final message):
        setState(() {
          _error = _localizeFailure(reason, message);
          _connecting = false;
        });
        break;
    }
  }

  String _localizeFailure(ClientFailureReason reason, String message) {
    final l10n = AppLocalizations.of(context)!;
    switch (reason) {
      case ClientFailureReason.invalidUrl:
        return l10n.pairingInvalidUrl(message);
      case ClientFailureReason.cancelled:
        return l10n.pairingCancelled;
      case ClientFailureReason.timeout:
        return l10n.pairingTimeout;
      case ClientFailureReason.lanUnreachable:
        return message; // already actionable from PairingClient._formatLanError
      case ClientFailureReason.networkError:
        return l10n.pairingNetworkError(message);
      case ClientFailureReason.decryptionFailed:
        return l10n.pairingDecryptFailed;
      case ClientFailureReason.protocolError:
        return l10n.pairingProtocolError(message);
    }
  }

  void _onScannedBarcode(BarcodeCapture capture) {
    if (_client != null) return; // already started
    for (final code in capture.barcodes) {
      final value = code.rawValue;
      if (value == null || value.isEmpty) continue;
      // The scanner fires repeatedly while a QR is in view; gate on _client.
      _onUrlReceived(value);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final reduceMotion =
        MediaQuery.maybeDisableAnimationsOf(context) == true;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.pairDeviceClientTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
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
    );
  }

  String _currentStateKey() {
    if (_completedToxId != null) return 'completed';
    if (_error != null) return 'error';
    if (_sas != null) return 'sas';
    if (_connecting) return 'connecting';
    return 'scan';
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_completedToxId != null) {
      return _CenteredMessage(
        state: PairingState.connected,
        message: l10n.pairingClientCompleted,
        actionLabel: l10n.done,
        onAction: () => Navigator.of(context).maybePop(true),
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
    if (_sas != null) {
      return _buildSasView(l10n);
    }
    if (_connecting) {
      return _CenteredMessage(
        state: PairingState.connecting,
        message: l10n.pairingClientCompleted, // generic "working" string
      );
    }
    return _buildScannerOrPaste(l10n);
  }

  Widget _buildScannerOrPaste(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Column(
      children: [
        if (_supportsCameraScan && _scannerController != null)
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onScannedBarcode,
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      margin: const EdgeInsets.all(AppSpacing.xxl),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _kViewfinderStroke,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(AppRadii.card),
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  top: AppSpacing.lg,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: PairingStatusIndicator(
                      state: PairingState.scanning,
                      size: 32,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text(
              l10n.pairingClientPasteInstructions,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_supportsCameraScan)
                Text(
                  l10n.pairingClientScanInstructions,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              AppSpacing.verticalMd,
              TextField(
                controller: _pasteController,
                textAlignVertical: TextAlignVertical.center,
                decoration: InputDecoration(
                  labelText: l10n.pairingPasteUrlLabel,
                  hintText: 'tox://pair?key=...',
                ),
                onSubmitted: _onUrlReceived,
              ),
              AppSpacing.verticalMd,
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: Text(l10n.cancel),
                    ),
                  ),
                  AppSpacing.horizontalSm,
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final v = _pasteController.text.trim();
                        if (v.isNotEmpty) _onUrlReceived(v);
                      },
                      child: Text(l10n.pairingConnectButton),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSasView(AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const PairingStatusIndicator(state: PairingState.connecting, size: 48),
          AppSpacing.verticalLg,
          Text(
            l10n.pairingVerifyCodeHeader,
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          AppSpacing.verticalMd,
          Text(
            _formatSasForDisplay(_sas!),
            style: theme.textTheme.displaySmall?.copyWith(
              fontFamily: 'monospace',
              fontFeatures: const [FontFeature.tabularFigures()],
              letterSpacing: 8,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          AppSpacing.verticalMd,
          Text(
            l10n.pairingVerifyCodeInstructions,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          AppSpacing.verticalLg,
          FilledButton.icon(
            icon: const Icon(Icons.check),
            label: Text(l10n.pairingCodesMatch),
            onPressed: () => _client?.confirmSas(),
          ),
          AppSpacing.verticalSm,
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }

  String _formatSasForDisplay(String sas) {
    if (sas.length != 6) return sas;
    return '${sas.substring(0, 3)} ${sas.substring(3)}';
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
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PairingStatusIndicator(state: state, size: 56),
            AppSpacing.verticalLg,
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            if (actionLabel != null && onAction != null) ...[
              AppSpacing.verticalLg,
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
