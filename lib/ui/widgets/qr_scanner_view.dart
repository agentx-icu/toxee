import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
///   plugin fail the start instead also leaks: mobile_scanner 7.1 subscribes
///   to its platform streams at the top of every `start()`, and neither a
///   failed start nor `dispose()` cancels them — see `_stopAndDispose`.)
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
  /// double-tap or a resume racing a stop can't interleave them.
  Future<void> _ops = Future<void>.value();

  /// Releases (settle → stop → dispose) of every scanner's retired
  /// controllers, process-wide: the plugin's platform side is ONE instance, so
  /// a retired controller's stop()/dispose() stops whatever camera is running.
  /// A MobileScanner is only built once this chain has drained (null).
  static Future<void>? _pendingReleases;

  /// Whether a MobileScanner was built for [_controller]. It starts the
  /// controller as it mounts, so only then can a start be in flight.
  bool _scannerBuilt = false;

  /// Retry has taken the failed controller's MobileScanner out of the tree
  /// and is releasing it.
  bool _releasing = false;

  /// App hidden (backgrounded): the camera must be off until resumed.
  bool _hidden = switch (WidgetsBinding.instance.lifecycleState) {
    AppLifecycleState.hidden || AppLifecycleState.paused => true,
    _ => false,
  };

  /// Set by [stopCamera]; the camera stays off for good (a resume included).
  bool _cameraHeld = false;

  bool get _cameraWanted => !_hidden && !_cameraHeld;

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
    _controller.addListener(_onControllerChanged);
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
    _controller.removeListener(_onControllerChanged);
    // Not a bare dispose(): see [_release].
    _release(_controller, started: _scannerBuilt);
    super.dispose();
  }

  /// mobile_scanner 7.1 only reports `isRunning` once the platform start has
  /// returned, so a stop asked for during a start (hidden, [stopCamera]) is a
  /// no-op then. Instead, whenever the controller reports a running camera
  /// that is not wanted — the start landed late — stop it right away.
  void _onControllerChanged() {
    _cancelFailedStart(_controller);
    if (_controller.value.isRunning && !_cameraWanted) _enqueue(_stopIfRunning);
  }

  Future<void> _stopIfRunning() async {
    if (_controller.value.isRunning) await _controller.stop();
  }

  /// Completes once [c]'s start has settled (running or failed). Only for a
  /// controller a MobileScanner was built for: nothing else starts it.
  static Future<void> _settled(MobileScannerController c) {
    bool isSettled() => c.value.isInitialized && !c.value.isStarting;
    if (isSettled()) return Future<void>.value();
    final done = Completer<void>();
    void listener() {
      if (!isSettled() || done.isCompleted) return;
      c.removeListener(listener);
      done.complete();
    }

    c.addListener(listener);
    return done.future;
  }

  /// Retires [c] on the process-wide [_pendingReleases] chain: waits for a
  /// start still in flight (MobileScanner's stop and the plugin's dispose are
  /// no-ops until it returns, and a disposed controller no longer hears about
  /// it), stops it, then disposes it. Deliberately unbounded: releasing
  /// early would let a late cleanup stop a newer scanner's camera; a platform
  /// start that never returns has wedged the (single) camera session anyway.
  static void _release(MobileScannerController c, {required bool started}) {
    final previous = _pendingReleases;
    late final Future<void> release;
    release =
        () async {
              if (previous != null) await previous;
              if (started) await _settled(c);
              await _stopAndDispose(c);
            }()
            .catchError((Object _) {})
            .whenComplete(() {
              if (identical(_pendingReleases, release)) {
                _pendingReleases = null;
              }
            });
    _pendingReleases = release;
  }

  /// Controllers whose start failed (see [_cancelFailedStart]).
  static final Expando<bool> _failedStarts = Expando('qrScannerFailedStart');

  /// A failed start leaves two things behind in mobile_scanner 7.1.4:
  /// - Dart: start() subscribes to the platform event streams before it asks
  ///   the platform, and only stop() of a RUNNING controller cancels them —
  ///   never dispose(), and a failed start leaves isRunning false, so its
  ///   stop() is a no-op. Worse, while they live, a torch / zoom / orientation
  ///   event rewrites the state through copyWith, which drops `error`: the
  ///   Retry view would vanish over a dead preview. So as soon as a failure
  ///   is seen, the controller is marked running for one stop() — the only
  ///   public way to cancel them — and the error is put back.
  /// - native: see [_stopAndDispose].
  static void _cancelFailedStart(MobileScannerController c) {
    final value = c.value;
    final error = value.error;
    if (error == null || !value.isInitialized || value.isRunning) return;
    if (value.isStarting || _failedStarts[c] == true) return;
    _failedStarts[c] = true;
    c.value = value.copyWith(isRunning: true, error: error);
    // Its synchronous part cancels the subscriptions; the platform stop is a
    // no-op (the Dart side never got a texture id).
    unawaited(c.stop());
    c.value = c.value.copyWith(error: error);
  }

  /// A failed start's native leftovers: iOS registers the texture and creates
  /// the capture session before its error returns, Android may have bound the
  /// camera, and the Dart side never learnt a texture id, so no stop() reaches
  /// them — the next start then fails as "already started" (debug builds
  /// hide this: MobileScanner force-stops before each start there). Such a
  /// controller is force-stopped on release; [_pendingReleases] keeps that
  /// from meeting another scanner's camera.
  static Future<void> _stopAndDispose(MobileScannerController c) async {
    _cancelFailedStart(c); // a retired controller whose start just failed
    try {
      await c.stop();
      if (_failedStarts[c] == true) {
        await _scannerMethods.invokeMethod<void>('stop', {'force': true});
      }
    } catch (_) {
      // Reported through the controller state; disposing anyway.
    }
    await c.dispose();
  }

  /// mobile_scanner's method channel (the plugin's own force-stop uses it).
  static const _scannerMethods = MethodChannel(
    'dev.steenbakker.mobile_scanner/scanner/method',
  );

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

  /// Granted: builds MobileScanner, which starts the camera as it mounts —
  /// once earlier scanners' controllers are released (see [_pendingReleases]).
  Future<void> _applyAccess(bool granted) async {
    final releases = _pendingReleases;
    if (granted && releases != null) await releases;
    if (!mounted) return;
    setState(
      () => _access = granted ? _CameraAccess.granted : _CameraAccess.denied,
    );
  }

  /// Stops the camera and keeps it off (the pairing page does this before it
  /// connects, so the preview isn't running during the handshake while this
  /// view animates out). A start still in flight is waited for, however long
  /// it takes: both plugins can have the camera live before their start
  /// replies, and until it does there is nothing to stop — returning early
  /// would let the handshake begin with the camera on. (A start that never
  /// replies leaves the page waiting but interactive: the user can go back.)
  Future<void> stopCamera() {
    _cameraHeld = true;
    final done = Completer<void>();
    _ops = _ops.then((_) async {
      try {
        if (mounted) {
          if (_scannerBuilt) await _settled(_controller);
          await _stopIfRunning();
        }
      } catch (_) {
        // Reported through the controller state.
      } finally {
        done.complete();
      }
    });
    return done.future;
  }

  /// Retry after a start failure with a FRESH controller; its MobileScanner
  /// (keyed on the controller) starts it. The failed one is released first —
  /// out of the tree (a rebuild after its dispose would throw), then stopped
  /// and disposed, since its dispose() stops the process-wide platform
  /// instance, which would stop the new camera had it already started.
  void _retry() => _enqueue(() async {
    if (_controller.value.error == null) return; // already recovered
    setState(() => _releasing = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return; // dispose() released it
    final old = _controller..removeListener(_onControllerChanged);
    _release(old, started: _scannerBuilt);
    // Not built while releasing; while hidden / held, build() keeps its
    // MobileScanner (and so its start) back until the camera is wanted.
    _controller = _newController()..addListener(_onControllerChanged);
    _scannerBuilt = false;
    final releases = _pendingReleases;
    if (releases != null) await releases;
    if (!mounted) return;
    setState(() => _releasing = false);
  });

  /// Lifecycle, as mobile_scanner does for controllers it owns, with one
  /// deliberate difference: nothing happens on `inactive`. On Android a
  /// split-screen pane goes inactive whenever the OTHER app has focus, and on
  /// iOS for Control Center / a system alert — the preview is still on screen.
  /// - hidden: the camera must be off — stopped now, or as soon as a start
  ///   in flight lands ([_onControllerChanged]).
  /// - resumed: a camera we stopped starts again. With access denied, only the
  ///   STATUS is re-read (back from Settings?) — never a new request, which on
  ///   Android would re-open the permission prompt, whose dismissal resumes
  ///   the app again: a loop.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
        _hidden = true;
        _enqueue(_stopIfRunning);
      case AppLifecycleState.resumed:
        _hidden = false;
        _enqueue(() async {
          if (_cameraHeld) return;
          switch (_access) {
            case _CameraAccess.denied:
              final granted =
                  await (widget.cameraPermissionGranted ?? _cameraGranted)();
              if (granted) await _applyAccess(true);
            case _CameraAccess.granted:
              if (!_scannerBuilt) {
                // Access (or a Retry) arrived while hidden: build it now.
                setState(() {});
                return;
              }
              final value = _controller.value;
              // Not while a start is in flight (it would throw
              // controllerInitializing), nor after a failure (Retry's job).
              if (_hidden ||
                  !value.isInitialized ||
                  value.isRunning ||
                  value.isStarting ||
                  value.error != null) {
                return;
              }
              await _controller.start();
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
        // Not while releasing (Retry), and a MobileScanner starts its
        // controller as it mounts: not while the camera isn't wanted.
        if (_releasing || (!_scannerBuilt && !_cameraWanted)) {
          return const ColoredBox(color: Colors.black);
        }
    }
    final controller = _controller;
    _scannerBuilt = true;
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
          errorBuilder: (context, error) =>
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
