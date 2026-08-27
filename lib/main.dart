import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_skill/flutter_skill.dart';
import 'package:marionette_flutter/marionette_flutter.dart';
import 'package:mcp_toolkit/mcp_toolkit.dart';

import 'ui/widgets/app_page_route.dart';
import 'package:tencent_cloud_chat_common/widgets/material_app.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_intl/tencent_cloud_chat_intl.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'ui/login_page.dart';
import 'ui/home_page.dart';
import 'ui/startup_loading_screen.dart';
import 'ui/upgrade_required_screen.dart';
import 'ui/testing/l3_debug_tools.dart';
import 'ui/testing/ui_drive_tools.dart';
import 'sdk_fake/fake_uikit_core.dart';
import 'util/theme_controller.dart';
import 'util/locale_controller.dart';
import 'i18n/app_localizations.dart';
import 'util/logger.dart';
import 'util/platform_utils.dart';
import 'util/responsive_layout.dart';
import 'call/call_overlay.dart';
import 'call/call_effects_listener.dart';
import 'navigation/active_conversation_route_observer.dart';
import 'navigation/app_navigation.dart';
import 'ui/app_theme_data.dart';
import 'util/app_theme_config.dart';
import 'util/account_service.dart';
import 'util/prefs.dart';
import 'util/safe_diagnostics.dart';
import 'util/send_failure_notifier.dart';
import 'package:tencent_cloud_chat_common/data/theme/tencent_cloud_chat_theme.dart';
import 'startup/startup_outcome.dart';
import 'startup/startup_session_use_case.dart';
import 'startup/startup_step.dart';

import 'bootstrap/app_bootstrap.dart';
import 'bootstrap/app_bootstrap_result.dart';
import 'ui/widgets/desktop_window_frame.dart';
part 'startup/startup_gate.dart';

/// Routes print() output to AppLogger. Parses TCCF lines (TencentCloudChatLog)
/// so level and body are normalized instead of duplicating timestamp in body.
void _routePrintToLogger(String line) {
  // TCCF:2026-02-11 03:48:47 PM:TencentCloudChatMessageSDK:debug:{ addUIKitListener 1770796127319 }
  final tccfMatch = RegExp(
    r'^TCCF:(?:\d{4}-\d{2}-\d{2} \d{1,2}:\d{2}:\d{2} [AP]M):([^:]+):(debug|info|error|all):\{ (.*) \}$',
  ).firstMatch(line);
  if (tccfMatch != null) {
    final component = tccfMatch.group(1)!.trim();
    final level = tccfMatch.group(2)!;
    final body = tccfMatch.group(3)!.trim();
    final logBody = '$component: $body';
    switch (level) {
      case 'debug':
        AppLogger.debug(logBody);
        break;
      case 'info':
        AppLogger.info(logBody);
        break;
      case 'error':
        AppLogger.error(logBody);
        break;
      case 'all':
      default:
        AppLogger.info(logBody);
    }
    return;
  }
  AppLogger.info(line);
}

/// Selects which Flutter MCP binding to install at startup. Compile-time
/// const so unused branches tree-shake out of release builds. Values:
///   skill     — flutter_skill (default; additive, layered on stock binding)
///   marionette — MarionetteBinding (REPLACES WidgetsFlutterBinding; exclusive)
///   stock     — plain Flutter (no flutter_skill, useful for isolating mcp_toolkit)
/// mcp_toolkit (Arenukvern) is always layered on top in debug mode regardless,
/// because it does not install its own binding.
/// Pass with: flutter run --dart-define=MCP_BINDING=marionette
const _mcpBinding = String.fromEnvironment(
  'MCP_BINDING',
  defaultValue: 'skill',
);

Future<void> main() async {
  await runZonedGuarded(
    () async {
      // Step 1: install the binding. Marionette REPLACES WidgetsFlutterBinding
      // and must be the first ensureInitialized() call in the process; any
      // prior WidgetsFlutterBinding.ensureInitialized() trips the binding
      // singleton assertion. Other modes use the stock binding.
      if (kDebugMode && _mcpBinding == 'marionette') {
        MarionetteBinding.ensureInitialized(
          MarionetteConfiguration(
            // Custom toxee/UIKit widgets that marionette's builtin list does
            // not know about. String-based matching keeps main.dart from
            // importing 60+ classes; the agent harness only needs enough
            // coverage to drive the chat flow.
            isInteractiveWidget: (type) {
              final n = type.toString();
              return n.startsWith('TencentCloudChat') ||
                  n.startsWith('TUIKit') ||
                  n.endsWith('Button') ||
                  n.endsWith('Item') ||
                  n.endsWith('Dialog') ||
                  n.endsWith('Tile') ||
                  n.contains('LoginActionCard');
            },
          ),
        );
      } else {
        WidgetsFlutterBinding.ensureInitialized();
      }

      // Step 2: additive MCP layers — both register `dart:developer` service
      // extensions in their own namespaces, so they can coexist with any
      // binding (or with each other). kDebugMode tree-shakes these out of
      // profile/release builds.
      if (kDebugMode && _mcpBinding == 'skill') {
        // autoEnableIndicators:false — the visual tap-indicator overlay (the
        // animated particle/character effect flutter_skill draws on each tap)
        // is a human-watching debug aid the automated harness never needs, AND
        // it can throw mid-paint: its _ParticleEffectPainter feeds an
        // out-of-[0,1] value to Color.withOpacity, which asserts during the
        // paint phase and aborts the ENTIRE frame — blanking the whole window
        // (sidebar included) until restart. Leaving the overlay off removes
        // that whole failure mode; the service extensions (tap/enterText/…)
        // are unaffected. Re-enable at runtime via
        // `ext.flutter.flutter_skill.enableIndicators` if a visual trace is
        // ever wanted.
        FlutterSkillBinding.ensureInitialized(autoEnableIndicators: false);
      }
      if (kDebugMode) {
        MCPToolkitBinding.instance
          ..initialize()
          ..initializeFlutterToolkit();
        // L3 test-only debug MCP tools (deterministic send, state dump).
        // No-op unless TOXEE_L3_TEST is set (injected by run_toxee.sh on the
        // canonical L3 launch). See lib/ui/testing/l3_debug_tools.dart.
        registerL3DebugToolsIfEnabled();
        // UNGATED real-pointer-event tools (scroll/drag/secondary-tap) for the
        // real-UI sweep campaign. Debug-only, no test-account gate — pure input
        // plumbing usable on fresh accounts. See lib/ui/testing/ui_drive_tools.dart.
        registerUiDriveToolsIfDebug();
      }

      final result = await AppBootstrap.initialize();

      FlutterError.onError = (FlutterErrorDetails details) {
        // Capture the widget that triggered the error and (for RenderFlex
        // overflow) the offending RenderObject's brief description. Without
        // this, the log only sees the message ("A RenderFlex overflowed by
        // N pixels") with no clue which widget is at fault.
        final libraryAndContext = StringBuffer()
          ..write('Flutter Error: ${details.exception}');
        final ctx = details.context;
        if (ctx != null) {
          libraryAndContext.write(' (context: ${ctx.toString()})');
        }
        final lib = details.library;
        if (lib != null && lib.isNotEmpty) {
          libraryAndContext.write(' [library: $lib]');
        }
        AppLogger.logError(
          libraryAndContext.toString(),
          details.exception,
          details.stack,
        );
        final info = StringBuffer();
        details.informationCollector?.call().forEach((node) {
          final s = node.toString();
          if (s.trim().isNotEmpty) info.writeln(s);
        });
        if (info.isNotEmpty) {
          AppLogger.error('Flutter Error details:\n${info.toString().trim()}');
        }
        FlutterError.presentError(details);
      };

      ui.PlatformDispatcher.instance.onError =
          (Object error, StackTrace stack) {
            AppLogger.logError('Uncaught async error', error, stack);
            return true;
          };

      switch (result) {
        case AppBootstrapSuccess():
          AppLogger.log('Running app...');
          runApp(const EchoUIKitApp());
        case AppBootstrapUpgradeRequired(
          :final storedVersion,
          :final currentVersion,
        ):
          runApp(
            UpgradeRequiredApp(
              storedVersion: storedVersion,
              currentVersion: currentVersion,
            ),
          );
      }
    },
    (Object error, StackTrace stack) {
      try {
        AppLogger.logError('Uncaught error in zone', error, stack);
      } catch (e) {
        // If logging itself fails (e.g. StackOverflow from deep Future chains),
        // fall back to stderr which doesn't allocate or call DateTime.
        try {
          stderr.writeln('[ZONE ERROR] $error');
        } catch (_) {}
      }
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        _routePrintToLogger(line);
      },
    ),
  );
}

/// Default [MaterialScrollBehavior] auto-wraps every desktop Scrollable in a
/// [Scrollbar] bound to the [PrimaryScrollController]. UIKit-owned Scrollables
/// typically run with their own controller (or none), so the auto-attached
/// Scrollbar can't find a [ScrollPosition] and the framework asserts every
/// frame ("Scrollbar's ScrollController has no ScrollPosition attached").
/// Skip the auto-wrap when the [Scrollable] didn't pass an explicit controller;
/// downstream widgets that DO supply one (and the dedicated Scrollbar widgets
/// the UIKit puts around its lists) still render normally.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (details.controller == null) {
      return child;
    }
    return super.buildScrollbar(context, child, details);
  }
}

class EchoUIKitApp extends StatefulWidget {
  const EchoUIKitApp({super.key});
  @override
  State<EchoUIKitApp> createState() => _EchoUIKitAppState();
}

class _EchoUIKitAppState extends State<EchoUIKitApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    AppTheme.mode.addListener(_syncUIKitThemeBrightness);
    _syncUIKitThemeBrightness();
    // The UIKit conversation app-bar has its own brightness toggle. Route it
    // through AppTheme (our single source of truth) so the Material ThemeData
    // — scaffold background, bottom nav — switches together with the UIKit
    // colors instead of leaving half the screen in the old theme. AppTheme's
    // listener above then syncs the UIKit brightness back.
    TencentCloudChatTheme.onBrightnessToggleRequest = _toggleThemeBrightness;
    // Observe app lifecycle so we can re-emit the unread total on resume,
    // keeping the OS dock/launcher badge accurate when the user reads or
    // dismisses messages on another device while toxee is backgrounded.
    // The bus emit fans out to BadgeService (debounced) — see
    // lib/notifications/badge_service.dart.
    WidgetsBinding.instance.addObserver(this);
  }

  void _syncUIKitThemeBrightness() {
    final mode = AppTheme.mode.value;
    // For ThemeMode.system, resolve against the actual OS brightness — the old
    // code always fell back to light, so a system-dark device showed the Material
    // dark theme but a light UIKit colorTheme (mismatched app-bar / list rows).
    final isDark =
        mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    TencentCloudChatTheme.init(
      brightness: isDark ? Brightness.dark : Brightness.light,
    );
  }

  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    // ThemeMode.system follows the OS setting: when the OS flips light/dark the
    // Material app rebuilds automatically, but the UIKit colorTheme singleton
    // must be re-synced (and its change event fired) or half the surfaces keep
    // the old brightness.
    if (AppTheme.mode.value == ThemeMode.system) {
      _syncUIKitThemeBrightness();
    }
  }

  /// Flips whatever brightness is currently *visible* to its opposite, picking
  /// an explicit light/dark mode (resolving `system` against the OS) so the
  /// in-UIKit toggle always produces a visible change and keeps both theme
  /// systems in sync.
  void _toggleThemeBrightness() {
    final mode = AppTheme.mode.value;
    final isDark =
        mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
                Brightness.dark);
    unawaited(AppTheme.set(isDark ? ThemeMode.light : ThemeMode.dark));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // `detached` is the only trace an app-initiated exit (SystemNavigator.pop,
    // a terminate request) leaves in the log; the others are cheap and rare.
    AppLogger.info('[EchoUIKitApp] lifecycle -> ${state.name}');
    if (state == AppLifecycleState.resumed) {
      try {
        FakeUIKit.instance.im?.refreshUnreadTotal();
      } catch (e, st) {
        AppLogger.logError(
          '[EchoUIKitApp] refreshUnreadTotal on resume failed',
          e,
          st,
        );
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppTheme.mode.removeListener(_syncUIKitThemeBrightness);
    if (TencentCloudChatTheme.onBrightnessToggleRequest ==
        _toggleThemeBrightness) {
      TencentCloudChatTheme.onBrightnessToggleRequest = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Theme and locale are already initialized in main() before runApp()
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.mode,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<Locale>(
          valueListenable: AppLocale.locale,
          builder: (context, locale, __) {
            // Sync app locale to UIKit immediately so chat, contact, profile, and
            // group list see the new language before any child builds.
            try {
              TencentCloudChatIntl().setLocale(locale);
            } catch (e) {
              // setLocale runs on every rebuild — log at warn so we see the
              // failure without spamming severe for an arguably best-effort sync.
              AppLogger.warn('[App] TencentCloudChatIntl.setLocale failed: $e');
            }
            return TencentCloudChatMaterialApp(
              title: 'Toxee',
              navigatorKey: appNavigatorKey,
              // Hand the ScaffoldMessenger key to the root app so SDK
              // callbacks (which live outside the widget tree) can surface
              // send-failure toasts via [SendFailureNotifier].
              scaffoldMessengerKey: SendFailureNotifier.scaffoldMessengerKey,
              debugShowCheckedModeBanner: false,
              scrollBehavior: const _AppScrollBehavior(),
              themeAnimationDuration: const Duration(milliseconds: 400),
              // Unbind the ACTIVE conversation when the pushed chat route
              // leaves the stack. Compact/phone shells push that route instead
              // of binding a master-detail pane, and nothing used to clear the
              // binding on the way back — which suppressed that peer's unread
              // count indefinitely. See the observer's doc comment.
              navigatorObservers: [ActiveConversationRouteObserver()],
              theme: buildLightTheme(),
              darkTheme: buildDarkTheme(),
              themeMode: themeMode,
              locale: locale,
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                TencentCloudChatLocalizations.delegate, // UIKit i18n delegate
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) {
                final brightness = Theme.of(context).brightness;
                final backgroundColor = brightness == Brightness.dark
                    ? AppThemeConfig.darkScaffoldBackground
                    : AppThemeConfig.lightScaffoldBackground;
                return ValueListenableBuilder<bool>(
                  valueListenable: FakeUIKit.instance.callSystemReady,
                  builder: (context, ready, _) {
                    Widget content = Container(
                      color: backgroundColor,
                      child: child,
                    );
                    if (ready) {
                      final callState = FakeUIKit.instance.callStateNotifier;
                      final callManager = FakeUIKit.instance.callServiceManager;
                      if (callState != null && callManager != null) {
                        content = CallEffectsListener(
                          callState: callState,
                          manager: callManager,
                          child: CallOverlay(
                            callState: callState,
                            manager: callManager,
                            child: content,
                          ),
                        );
                      }
                    }
                    // Frameless desktop window: inject the OS window-control
                    // inset into MediaQuery for the WHOLE app — routed pages
                    // (their AppBar/SafeArea reserve it) AND the call overlay
                    // (its SafeArea reserves it) — so page headers and call
                    // controls sit clear of the macOS traffic lights (top-left)
                    // or the Windows/Linux caption buttons (top-right). HomePage
                    // opts back out on macOS so its rail/list/chat fill to the
                    // top edge under the lights; on Windows/Linux it keeps the
                    // inset so the body clears the top-right caption buttons.
                    if (PlatformUtils.isDesktop) {
                      // Capture the pre-injection subtree in a FINAL local. The
                      // Builder closure must not close over the mutable `content`
                      // (reassigned to DesktopWindowFrame just below) — otherwise
                      // it rebuilds itself forever -> StackOverflow red screen.
                      final injectedChild = content;
                      content = Builder(
                        builder: (ctx) {
                          final mq = MediaQuery.of(ctx);
                          return MediaQuery(
                            data: mq.copyWith(
                              padding: mq.padding.copyWith(
                                top:
                                    mq.padding.top +
                                    ResponsiveLayout.desktopTitleBarInset(),
                              ),
                            ),
                            child: injectedChild,
                          );
                        },
                      );
                    }
                    if (PlatformUtils.isDesktop) {
                      content = DesktopWindowFrame(child: content);
                    }
                    return content;
                  },
                );
              },
              home: const StartupGate(),
            );
          },
        );
      },
    );
  }
}
