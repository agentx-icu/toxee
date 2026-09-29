import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../call/permission_helper.dart';
import '../../i18n/app_localizations.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';

enum _CameraAccess { checking, granted, denied }

/// Camera QR scanner shared by the Add Contact "Scan QR" page and the pairing
/// page: the live preview, a square viewfinder hint, and a denied/failed state
/// the user can recover from. It owns its [MobileScannerController].
///
/// Why not a bare [MobileScanner]:
/// - With the camera permission denied mobile_scanner shows a bare "Camera
///   permission denied." (debug builds; a generic error in release) and no way
///   out. Here the permission is asked for FIRST, through toxee's own
///   serialised helper, and a denial shows an explanation and a Settings
///   button; the camera is only started once access is granted. (Letting the
///   plugin fail the start instead also leaks: mobile_scanner 6.0.11 subscribes
///   to its platform streams at the top of every `start()`, and neither a
///   failed start nor `dispose()` cancels them.)
/// - mobile_scanner only follows the app lifecycle for a controller it
///   created, so nothing stopped / restarted this camera around backgrounding,
///   and granting access in Settings and coming back left the page on the
///   error until it was reopened. See [didChangeAppLifecycleState].
/// - The old viewfinder was the whole body inset by a margin — a thin strip in
///   landscape or a short split-screen pane. This one stays square.
class QrScannerView extends StatefulWidget {
  const QrScannerView({
    super.key,
    required this.onDetect,
    this.viewfinderColor = Colors.white70,
    @visibleForTesting this.requestCameraPermission,
    @visibleForTesting this.cameraPermissionGranted,
    @visibleForTesting this.openSettings,
  });

  final void Function(BarcodeCapture capture) onDetect;
  final Color viewfinderColor;

  /// Test seams. Production: [CallPermissionHelper.requestCameraForScan]
  /// (may show the OS prompt), `permission_handler`'s camera status (never
  /// prompts), and the app's page in the system Settings.
  final Future<bool> Function()? requestCameraPermission;
  final Future<bool> Function()? cameraPermissionGranted;
  final Future<void> Function()? openSettings;

  /// Below this the frame is not drawn at all (e.g. a pairing page squeezed
  /// by the keyboard in a short landscape window).
  static const double minViewfinderSide = 48;

  /// The viewfinder's side for a preview of [size]: square, inset like the
  /// old frame, capped so it doesn't swallow a tablet, 0 when there is no room.
  static double viewfinderSide(Size size) {
    final side = math.min(size.width, size.height) - 2 * AppSpacing.xxl;
    if (side < minViewfinderSide) return 0;
    return math.min(side, 280);
  }

  @override
  State<QrScannerView> createState() => QrScannerViewState();
}

class QrScannerViewState extends State<QrScannerView>
    with WidgetsBindingObserver {
  MobileScannerController _controller = _newController();
  _CameraAccess _access = _CameraAccess.checking;

  /// Every start / stop / controller swap runs through this chain, so a Retry
  /// double-tap or a resume racing a stop can't interleave them (the plugin's
  /// platform side is one process-wide instance).
  Future<void> _ops = Future<void>.value();

  @visibleForTesting
  MobileScannerController get controller => _controller;

  // autoStart: MobileScanner starts it when it mounts — which happens only
  // once access is granted (it isn't built before). Starting it ourselves
  // races MobileScanner's debug-build hot-restart guard, which force-stops the
  // platform camera from its initState (mobile_scanner.dart initMobileScanner).
  static MobileScannerController _newController() => MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enqueue(() async {
      final granted =
          await (widget.requestCameraPermission ??
              CallPermissionHelper.requestCameraForScan)();
      await _applyAccess(granted);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // MobileScanner stops the camera as it unmounts; dispose() releases the
    // controller (and the plugin's platform side).
    final controller = _controller;
    final restart = _pendingRestart;
    if (restart != null) {
      // A resume restart is still starting the camera: stop it once it has.
      unawaited(restart.then((_) => _stopAndDispose(controller)));
    } else {
      _disposeController(controller);
    }
    super.dispose();
  }

  /// A `start()` this view issued itself (the resume path) that hasn't
  /// returned yet. The controller stays `isInitialized` from its first start,
  /// so [_disposeController] can't see this one.
  Future<void>? _pendingRestart;

  Future<void> _restartCamera() {
    final done = _controller.start().catchError((Object _) {});
    _pendingRestart = done;
    return done.whenComplete(() {
      if (identical(_pendingRestart, done)) _pendingRestart = null;
    });
  }

  static Future<void> _stopAndDispose(MobileScannerController c) async {
    try {
      await c.stop();
    } catch (_) {
      // Reported through the controller state; disposing anyway.
    }
    await c.dispose();
  }

  /// Disposes [controller] — but if its start is still in flight, only once
  /// that start has settled, stopping the camera first. Unmounting mid-start
  /// (e.g. pairing moving on after [stopCamera]'s bounded wait) would
  /// otherwise leave the camera running: MobileScanner's stop and the
  /// plugin's dispose are no-ops until the start has returned, and a disposed
  /// controller no longer hears about it.
  static void _disposeController(MobileScannerController controller) {
    if (controller.value.isInitialized) {
      unawaited(controller.dispose());
      return;
    }
    void onSettled() {
      if (!controller.value.isInitialized) return;
      controller.removeListener(onSettled);
      unawaited(_stopAndDispose(controller));
    }

    controller.addListener(onSettled);
  }

  void _enqueue(Future<void> Function() op) {
    _ops = _ops.then((_) async {
      if (!mounted) return;
      try {
        await op();
      } catch (_) {
        // start()/stop() report platform failures through the controller
        // state; anything else (a disposed controller) is moot.
      }
    });
  }

  /// Granted: builds MobileScanner, which starts the camera as it mounts.
  Future<void> _applyAccess(bool granted) async {
    if (!mounted) return;
    setState(
      () => _access = granted ? _CameraAccess.granted : _CameraAccess.denied,
    );
  }

  /// Stops the camera and keeps it off (the pairing page does this before it
  /// connects, so the preview isn't running during the handshake while this
  /// view animates out). If MobileScanner's start is still in flight, waits
  /// for it (bounded) so the stop can't land before the start completes.
  Future<void> stopCamera() {
    _cameraHeld = true;
    final done = Completer<void>();
    _ops = _ops.then((_) async {
      try {
        if (mounted) {
          await _waitForPendingStart();
          await _controller.stop();
        }
      } catch (_) {
        // Reported through the controller state.
      } finally {
        done.complete();
      }
    });
    return done.future;
  }

  /// Set by [stopCamera]; a later resume must not restart the camera.
  bool _cameraHeld = false;

  /// Access granted but the controller not initialized yet = MobileScanner's
  /// start is (about to be) in flight: wait until it settles either way.
  Future<void> _waitForPendingStart() async {
    if (_access == _CameraAccess.denied) return;
    final controller = _controller;
    if (controller.value.isInitialized) return;
    final settled = Completer<void>();
    void listener() {
      if (controller.value.isInitialized && !settled.isCompleted) {
        settled.complete();
      }
    }

    controller.addListener(listener);
    try {
      await settled.future.timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Start never settled (or access is still being decided); stop anyway.
    } finally {
      controller.removeListener(listener);
    }
  }

  /// Retry after a start failure with a FRESH controller (see the class doc
  /// for why a failed one is not re-started); its MobileScanner (keyed on the
  /// controller) starts it. The failed controller is disposed first: its
  /// dispose() stops the process-wide platform instance, which would stop the
  /// new camera had it already started.
  void _retry() => _enqueue(() async {
    if (_controller.value.error == null) return; // already recovered
    final old = _controller;
    await old.dispose();
    if (!mounted) return;
    setState(() => _controller = _newController());
  });

  /// Lifecycle, as mobile_scanner does for controllers it owns, with one
  /// deliberate difference: nothing happens on `inactive`. On Android a
  /// split-screen pane goes inactive whenever the OTHER app has focus, and on
  /// iOS for Control Center / a system alert — the preview is still on screen.
  /// - hidden: stop a running camera (the app left the screen).
  /// - resumed: a camera we stopped starts again. With access denied, only the
  ///   STATUS is re-read (back from Settings?) — never a new request, which on
  ///   Android would re-open the permission prompt, whose dismissal resumes
  ///   the app again: a loop.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
        _enqueue(() async {
          if (_controller.value.isRunning) await _controller.stop();
        });
      case AppLifecycleState.resumed:
        _enqueue(() async {
          if (_cameraHeld) return;
          switch (_access) {
            case _CameraAccess.denied:
              final granted =
                  await (widget.cameraPermissionGranted ?? _cameraGranted)();
              if (granted) await _applyAccess(true);
            case _CameraAccess.granted:
              final value = _controller.value;
              if (value.isInitialized &&
                  !value.isRunning &&
                  value.error == null) {
                await _restartCamera();
              }
            case _CameraAccess.checking:
              break;
          }
        });
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        break;
    }
  }

  static Future<bool> _cameraGranted() async {
    try {
      return (await Permission.camera.status).isGranted;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _openAppSettings() async {
    await openAppSettings();
  }

  Widget _buildMessage({
    required IconData icon,
    required String text,
    required Key buttonKey,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 40),
              AppSpacing.verticalMd,
              Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white,
                ),
              ),
              AppSpacing.verticalMd,
              FilledButton.tonal(
                key: buttonKey,
                onPressed: onPressed,
                child: Text(buttonLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDenied(AppLocalizations l10n) => _buildMessage(
    icon: Icons.no_photography_outlined,
    text: l10n.scanQrCameraPermissionDenied,
    buttonKey: const ValueKey('qr_scanner_open_settings'),
    buttonLabel: l10n.settings,
    onPressed: () => unawaited((widget.openSettings ?? _openAppSettings)()),
  );

  Widget _buildFailed(AppLocalizations l10n) => _buildMessage(
    icon: Icons.error_outline,
    text: l10n.scanQrCameraUnavailable,
    buttonKey: const ValueKey('qr_scanner_retry'),
    buttonLabel: l10n.retry,
    onPressed: _retry,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    switch (_access) {
      case _CameraAccess.checking:
        return const ColoredBox(color: Colors.black);
      case _CameraAccess.denied:
        return _buildDenied(l10n);
      case _CameraAccess.granted:
        break;
    }
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(
          // A replaced controller needs a new MobileScanner State: it binds
          // (and auto-starts) its controller once, in initState.
          key: ObjectKey(controller),
          controller: controller,
          onDetect: widget.onDetect,
          // Access is settled before the camera starts (and revoking it kills
          // the process on Android); should the plugin still report a denial,
          // it gets the Settings view, any other failure Retry.
          errorBuilder: (context, error, _) =>
              error.errorCode == MobileScannerErrorCode.permissionDenied
              ? _buildDenied(l10n)
              : _buildFailed(l10n),
        ),
        // Only over a live preview: the frame means nothing on an error view.
        ValueListenableBuilder<MobileScannerState>(
          valueListenable: controller,
          builder: (context, state, _) {
            if (state.error != null) return const SizedBox.shrink();
            return IgnorePointer(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = QrScannerView.viewfinderSide(
                    constraints.biggest,
                  );
                  if (side == 0) return const SizedBox.shrink();
                  return Center(
                    child: Container(
                      key: const ValueKey('qr_scanner_viewfinder'),
                      width: side,
                      height: side,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: widget.viewfinderColor,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(AppRadii.card),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ],
    );
  }
}
