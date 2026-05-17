import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_skill/flutter_skill.dart';

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
import 'sdk_fake/fake_uikit_core.dart';
import 'util/theme_controller.dart';
import 'util/locale_controller.dart';
import 'i18n/app_localizations.dart';
import 'util/logger.dart';
import 'call/call_overlay.dart';
import 'call/call_effects_listener.dart';
import 'util/app_theme_config.dart';
import 'util/app_component_themes.dart';
import 'util/account_service.dart';
import 'package:tencent_cloud_chat_common/data/theme/tencent_cloud_chat_theme.dart';
import 'startup/startup_outcome.dart';
import 'startup/startup_session_use_case.dart';
import 'startup/startup_step.dart';

import 'bootstrap/app_bootstrap.dart';
import 'bootstrap/app_bootstrap_result.dart';

/// Routes print() output to AppLogger. Parses TCCF lines (TencentCloudChatLog)
/// so level and body are normalized instead of duplicating timestamp in body.
void _routePrintToLogger(String line) {
  // TCCF:2026-02-11 03:48:47 PM:TencentCloudChatMessageSDK:debug:{ addUIKitListener 1770796127319 }
  final tccfMatch = RegExp(
          r'^TCCF:(?:\d{4}-\d{2}-\d{2} \d{1,2}:\d{2}:\d{2} [AP]M):([^:]+):(debug|info|error|all):\{ (.*) \}$')
      .firstMatch(line);
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

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Debug-only: expose the running app to Claude Code via the flutter_skill
      // MCP server (tap / enter_text / screenshot / hot_reload). kDebugMode is
      // a compile-time const false in profile/release builds, so the call is
      // tree-shaken out of non-debug binaries.
      if (kDebugMode) {
        FlutterSkillBinding.ensureInitialized();
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
        case AppBootstrapUpgradeRequired(:final storedVersion, :final currentVersion):
          runApp(UpgradeRequiredApp(
            storedVersion: storedVersion,
            currentVersion: currentVersion,
          ));
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
      BuildContext context, Widget child, ScrollableDetails details) {
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

class _EchoUIKitAppState extends State<EchoUIKitApp> {
  @override
  void initState() {
    super.initState();
    AppTheme.mode.addListener(_syncUIKitThemeBrightness);
    _syncUIKitThemeBrightness();
  }

  void _syncUIKitThemeBrightness() {
    final mode = AppTheme.mode.value;
    final brightness =
        mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
    TencentCloudChatTheme.init(brightness: brightness);
  }

  @override
  void dispose() {
    AppTheme.mode.removeListener(_syncUIKitThemeBrightness);
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
            } catch (_) {}
            return TencentCloudChatMaterialApp(
              title: 'Toxee',
              debugShowCheckedModeBanner: false,
              scrollBehavior: const _AppScrollBehavior(),
              themeAnimationDuration: const Duration(milliseconds: 400),
              theme: _buildLightTheme(),
              darkTheme: _buildDarkTheme(),
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
                    return content;
                  },
                );
              },
              home: const _StartupGate(),
            );
          },
        );
      },
    );
  }
}

// ──────────────────────────────────────────────
//  Theme builders
// ──────────────────────────────────────────────
//
// Both light and dark trees share the same text hierarchy + component-level
// theming surface; the only differences are brightness, color seed, and
// scaffold background. Component themes are sourced from [AppComponentThemes]
// so each surface (AppBar, Button, Card, Dialog, Sheet, Input, etc.) gets
// the same radius/padding/elevation rhythm in both modes.

ThemeData _buildLightTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: AppThemeConfig.primaryColor,
    scaffoldBackgroundColor: AppThemeConfig.lightScaffoldBackground,
  );
  return _applyAppTheming(base);
}

ThemeData _buildDarkTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: AppThemeConfig.primaryColorDark,
    scaffoldBackgroundColor: AppThemeConfig.darkScaffoldBackground,
  );
  return _applyAppTheming(base);
}

/// Apply the toxee text hierarchy + component themes on top of a brightness-
/// seeded [ThemeData]. Component themes are merged with the prior manual
/// overrides via `copyWith` so any explicit value on the existing AppBar /
/// Card / Button / Input themes still wins. (`scrolledUnderElevation: 1` from
/// the AppBar component theme is preserved because the prior config didn't
/// set it; `elevation: 1` from the prior Card config is preserved because the
/// `.copyWith(elevation: 1)` chain applies after the new base.)
ThemeData _applyAppTheming(ThemeData base) {
  final cs = base.colorScheme;
  final brightness = base.brightness;
  return base.copyWith(
    // Inter-style hierarchy: titles use weight + tight tracking for
    // presence, body sits at 15-16pt for comfortable reading, small labels
    // gain positive tracking for legibility. We `merge` onto the base text
    // theme so M3's brightness-aware colors (onSurface for titles/body,
    // onSurfaceVariant for labels) are preserved while we override only
    // font size/weight/tracking/leading.
    textTheme: base.textTheme.merge(const TextTheme(
      headlineSmall: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          height: 1.25),
      titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          height: 1.3),
      titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          height: 1.35),
      titleSmall: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
          height: 1.4),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5),
      bodyMedium: TextStyle(fontSize: 15, height: 1.5),
      bodySmall:
          TextStyle(fontSize: 13, letterSpacing: 0.1, height: 1.45),
      labelLarge: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1),
      labelMedium: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2),
      labelSmall: TextStyle(
          // 12pt floor for Material 3 (bottom-nav labels use
          // labelSmall — anything below 12 fails the legibility
          // bar on small phone screens).
          fontSize: 12,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4),
    )),
    // Component themes: the base values come from [AppComponentThemes];
    // any prior manual overrides are reapplied via `copyWith` so existing
    // behavior (e.g. Card elevation: 1, AppBar centerTitle: false) wins.
    appBarTheme: AppComponentThemes.appBarTheme(cs, brightness).copyWith(
      centerTitle: false,
    ),
    elevatedButtonTheme: AppComponentThemes.elevatedButtonTheme(cs),
    filledButtonTheme: AppComponentThemes.filledButtonTheme(cs),
    outlinedButtonTheme: AppComponentThemes.outlinedButtonTheme(cs),
    textButtonTheme: AppComponentThemes.textButtonTheme(cs),
    dialogTheme: AppComponentThemes.dialogTheme(cs),
    bottomSheetTheme: AppComponentThemes.bottomSheetTheme(cs),
    inputDecorationTheme:
        AppComponentThemes.inputDecorationTheme(cs, brightness),
    cardTheme: AppComponentThemes.cardTheme(cs).copyWith(
      // Preserve the prior soft single-layer elevation on cards.
      elevation: 1,
    ),
    chipTheme: AppComponentThemes.chipTheme(cs, brightness),
    snackBarTheme: AppComponentThemes.snackBarTheme(cs),
    dividerTheme: AppComponentThemes.dividerTheme(cs),
    tabBarTheme: AppComponentThemes.tabBarTheme(cs),
    switchTheme: AppComponentThemes.switchTheme(cs),
    checkboxTheme: AppComponentThemes.checkboxTheme(cs),
    radioTheme: AppComponentThemes.radioTheme(cs),
    tooltipTheme: AppComponentThemes.tooltipTheme(cs),
    listTileTheme: AppComponentThemes.listTileTheme(cs),
    // Thin scrollbars across the app. We deliberately leave thumbVisibility
    // unset (rather than always-on) because some UIKit-owned Scrollables
    // don't have a tightly-bound ScrollController, and forcing the
    // Scrollbar to paint there floods the log with "ScrollController has
    // no ScrollPosition attached" assertions on every frame.
    scrollbarTheme: ScrollbarThemeData(
      trackVisibility: WidgetStateProperty.all(false),
      thickness: WidgetStateProperty.all(6.0),
      radius: const Radius.circular(3.0),
    ),
  );
}

class _StartupGate extends StatefulWidget {
  const _StartupGate();
  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  bool _checking = true;
  String? _error;
  bool _waitingForConnection = false;
  Timer? _timeoutTimer;
  StreamSubscription<bool>? _connectionSub;
  StartupStep _currentStep = StartupStep.checkingUserInfo;
  FfiChatService? _serviceWaitingForConnection;
  late final StartupSessionUseCase _startupUseCase;

  @override
  void initState() {
    super.initState();
    _startupUseCase = StartupSessionUseCase();
    _runStartup();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _connectionSub?.cancel();
    if (_serviceWaitingForConnection != null) {
      unawaited(AccountService.teardownCurrentSession(
        service: _serviceWaitingForConnection,
        reEncryptProfile: true,
      ));
    }
    super.dispose();
  }

  void _updateStep(StartupStep step) {
    if (mounted) {
      setState(() {
        _currentStep = step;
      });
    }
  }

  Future<void> _runStartup() async {
    final outcome = await _startupUseCase.execute(
      onStepChanged: _updateStep,
      loadFriends: _loadFriendsInfo,
    );
    if (!mounted) return;
    switch (outcome) {
      case StartupShowLogin():
        setState(() => _checking = false);
        break;
      case StartupShowError(:final message):
        setState(() {
          _error = message;
          _checking = false;
        });
        break;
      case StartupOpenHome(:final service):
        unawaited(HapticFeedback.lightImpact());
        unawaited(Navigator.of(context).pushReplacement(
          AppPageRoute(page: HomePage(service: service)),
        ).then((_) {}));
        break;
      case StartupWaitForConnection(:final service):
        setState(() {
          _waitingForConnection = true;
          _serviceWaitingForConnection = service;
        });
        _waitForConnectionAndNavigate(service);
        break;
    }
  }

  void _waitForConnectionAndNavigate(FfiChatService service) {
    _timeoutTimer = Timer(const Duration(seconds: 20), () {
      if (!mounted) return;
      _connectionSub?.cancel();
      _updateStep(StartupStep.completed);
      unawaited(Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        _serviceWaitingForConnection = null;
        unawaited(Navigator.of(context).pushReplacement(
          AppPageRoute(page: HomePage(service: service)),
        ).then((_) {}));
      }));
    });

    _connectionSub = service.connectionStatusStream.listen((isConnected) {
      if (!isConnected || !mounted || !_waitingForConnection) return;
      _timeoutTimer?.cancel();
      _connectionSub?.cancel();
      _updateStep(StartupStep.loadingFriends);
      unawaited(_onConnectionReady(service));
    });
  }

  Future<void> _onConnectionReady(FfiChatService service) async {
    await _loadFriendsInfo(service);
    if (!mounted) return;
    _updateStep(StartupStep.completed);
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _serviceWaitingForConnection = null;
    unawaited(HapticFeedback.lightImpact());
    unawaited(Navigator.of(context).pushReplacement(
      AppPageRoute(page: HomePage(service: service)),
    ).then((_) {}));
  }

  Future<void> _loadFriendsInfo(FfiChatService service) async {
    try {
      AppLogger.log('[StartupGate] Loading friends information...');

      // Trigger FakeIM to refresh conversations and contacts
      // This ensures friend list is loaded before entering HomePage
      if (FakeUIKit.instance.im != null) {
        // Refresh conversations to load friend list
        await FakeUIKit.instance.im!.refreshConversations();
        // Refresh contacts to update friend status
        await FakeUIKit.instance.im!.refreshContacts();
      }

      // Wait for friend online status to be updated
      // Poll friend list multiple times to ensure we get the latest online status
      // This is important because Tox needs time to establish connections and detect online status
      const maxAttempts =
          12; // 12 attempts * 500ms = 6 seconds max (increased from 3 seconds)
      const pollInterval = Duration(milliseconds: 500);

      for (int attempt = 0; attempt < maxAttempts; attempt++) {
        await Future.delayed(pollInterval);

        // Get current friend list to check if we have online status
        final friends = await service.getFriendList();

        // Check if we have at least one friend with online status detected
        // If we have friends, check if any have online status or if we've waited enough
        bool hasOnlineStatus = false;
        if (friends.isNotEmpty) {
          // Check if any friend has online status (meaning we've detected at least one online friend)
          // OR if we've waited long enough (attempt >= 6, meaning 3 seconds)
          // This ensures we don't wait forever if all friends are offline
          hasOnlineStatus = friends.any((f) => f.online) || attempt >= 6;

          if (hasOnlineStatus || attempt >= maxAttempts - 1) {
            // We have online status or we've waited long enough
            AppLogger.log(
                '[StartupGate] Friends info loaded: ${friends.length} friends, ${friends.where((f) => f.online).length} online');
            // Refresh contacts one more time to ensure UI has latest status
            if (FakeUIKit.instance.im != null) {
              await FakeUIKit.instance.im!.refreshContacts();
            }
            break;
          }
        } else if (attempt >= 4) {
          // If no friends after 2 seconds, proceed anyway (user might not have friends)
          AppLogger.log('[StartupGate] No friends found, proceeding...');
          break;
        }
      }
    } catch (e) {
      // Log error but don't block startup
      AppLogger.logError(
          '[StartupGate] Error loading friends info: $e', e, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking || _waitingForConnection) {
      return StartupLoadingScreen(
        currentStep: _currentStep,
        errorMessage: _error,
        onRetry: _error != null ? _runStartup : null,
        onGoToLogin: _error != null
            ? () {
                Navigator.of(context).pushReplacement(
                  AppPageRoute(page: const LoginPage()),
                );
              }
            : null,
      );
    }
    if (_error != null) {
      return StartupLoadingScreen(
        currentStep: _currentStep,
        errorMessage: _error,
        onRetry: _runStartup,
        onGoToLogin: () {
          Navigator.of(context).pushReplacement(
            AppPageRoute(page: const LoginPage()),
          );
        },
      );
    }
    // Fall back to registration when no local data
    return const LoginPage();
  }
}

