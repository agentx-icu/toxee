import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../util/logger.dart';

/// OS-level notifications for incoming messages.
///
/// Cross-platform plumbing:
/// - macOS:   UNUserNotificationCenter (DarwinInitializationSettings)
/// - iOS:     UNUserNotificationCenter (DarwinInitializationSettings)
/// - Android: NotificationManager + dedicated channel + per-conversation
///            inbox-style grouping (avoids one-notification-per-message
///            spam when a peer sends a burst)
/// - Linux:   libnotify (notify-osd / GNOME / KDE — the plugin auto-detects)
/// - Windows: Toast / AUMID. AUMID is left at the plugin default; if a
///            custom AUMID becomes necessary, configure it in
///            `windows/runner/main.cpp` and pass `appName` here.
///
/// Design constraints (see prompt + `lib/notifications/badge_service.dart`):
/// - All Platform-channel calls are wrapped in try/catch so a missing
///   permission or unsupported launcher never surfaces as an uncaught error.
/// - Notification bodies are clamped to ~80 chars to avoid OS truncation
///   noise. Callers should already pass a short preview.
/// - The tap callback emits the payload to [onSelectStream]; routing on tap
///   is the caller's responsibility (HomePage subscribes when it's mounted
///   and routes to the matching conversation). Don't crash if no listener
///   is registered — late-subscribers get the most recent payload via the
///   broadcast stream's normal semantics, plus [consumeLaunchPayload] for
///   cold-start taps.
///
/// Singleton. [init] is idempotent — safe to call from both
/// [AppBootstrap.initialize] (cold start) and [HomePage._initAfterSessionReady]
/// (post-login, in case bootstrap was skipped for some reason).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const String _androidChannelId = 'toxee_messages';
  static const String _androidChannelName = 'Messages';
  static const String _androidChannelDescription =
      'Notifications for new incoming messages from your tox contacts.';

  // Separate Android notification channel for friend-add applications so the
  // user can mute / tweak importance independently of normal-message banners.
  static const String _androidFriendReqChannelId = 'toxee_friend_requests';
  static const String _androidFriendReqChannelName = 'Friend requests';
  static const String _androidFriendReqChannelDescription =
      'Notifications when someone sends you a friend request.';

  // Dedicated channel for missed-call banners — separate from message and
  // friend-request channels so users can tune importance/sound independently.
  static const String _androidMissedCallChannelId = 'toxee_missed_calls';
  static const String _androidMissedCallChannelName = 'Missed calls';
  static const String _androidMissedCallChannelDescription =
      'Notifications when an incoming call could not be reached or was missed.';

  /// Body truncation cap — keep tight to avoid OS-level ellipsis on Android
  /// (Material You collapses long lines on the lock screen) and macOS Big
  /// Sur-era banners that hard-truncate around 100 chars.
  static const int _maxBodyChars = 80;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _onSelectController =
      StreamController<String>.broadcast();

  bool _initialized = false;
  bool _initializing = false;

  /// Cached Android POST_NOTIFICATIONS decision for the session. `null` =
  /// not yet asked; `true` = granted (either already enabled or the user
  /// just said yes); `false` = the user denied. We never re-prompt within
  /// a session — Material Design says ask once at a contextual moment, and
  /// hammering the user on every message is exactly the anti-pattern. On
  /// non-Android platforms this stays `null` and is never consulted.
  bool? _androidPermissionGranted;

  /// Test seam (S59): force the Android permission-gate code path on a
  /// non-Android test host so the in-app CONSEQUENCE of a denied permission
  /// (no banner shown) is deterministically unit-testable. The OS GRANT itself
  /// (macOS TCC / iOS) is irreducibly OS-owned and out of scope. `null` in
  /// production → the real `Platform.isAndroid`.
  @visibleForTesting
  static bool? debugForceIsAndroid;
  bool get _isAndroidPlatform => debugForceIsAndroid ?? Platform.isAndroid;

  /// Test seam (S59): seed the cached permission result directly. Bypasses
  /// `_ensureAndroidPermission`, whose `AndroidFlutterLocalNotificationsPlugin`
  /// resolution returns null on a non-Android host (which would otherwise force
  /// `granted=true`). Pair with [debugForceIsAndroid].
  @visibleForTesting
  set debugAndroidPermissionGranted(bool? v) => _androidPermissionGranted = v;

  // Per-conversation message accumulator for inbox-style grouping. Cleared
  // when the user opens the conversation (callers tell us via
  // [clearConversationGroup]) or when the system reports the notification
  // tapped/dismissed (best-effort — the plugin's removal callbacks are not
  // available everywhere).
  final Map<String, List<String>> _grouped = <String, List<String>>{};

  // Stable numeric notification IDs per conversation. Android/iOS need a
  // 32-bit int; we hash the conversationID into the lower 31 bits so the
  // value fits even on stricter Java callers and stays stable across runs.
  final Map<String, int> _conversationIdHashCache = <String, int>{};
  int _conversationCounter = 0;

  // Captured cold-start payload (notification that launched the app). Read
  // once by [consumeLaunchPayload] then cleared.
  String? _launchPayload;

  /// Broadcast stream of payloads emitted when a notification is tapped.
  /// Subscribe from the page that knows how to route to a conversation.
  Stream<String> get onSelectStream => _onSelectController.stream;

  /// L3 TEST seam: push a tap [payload] onto [onSelectStream] exactly as the
  /// OS tap handler [_handleNotificationResponse] does, WITHOUT a real banner
  /// or OS-level tap. This drives the SAME subscribers production uses
  /// (`NotificationMessageListener.onConversationTapped` →
  /// `_routeToNotificationPayload` → `_openChat`), so the in-app routing half
  /// of S53 is exercised faithfully; only the OS banner/tap surface is bypassed.
  /// Used by the `l3_simulate_notification_tap` debug tool. No-op on an empty
  /// payload or a closed controller.
  void debugInjectNotificationTap(String payload) {
    if (payload.isEmpty) return;
    if (_onSelectController.isClosed) return;
    _onSelectController.add(payload);
  }

  /// Returns true once [init] has completed successfully on this platform.
  bool get isInitialized => _initialized;

  /// Idempotent. Initializes platform channels and asks for permission on
  /// iOS / macOS. On Android 13+ POST_NOTIFICATIONS is requested lazily on
  /// the first call to [showMessageNotification] via
  /// [_ensureAndroidPermission] — that matches Material Design guidance
  /// (don't ask on cold start, ask in context).
  Future<void> init() async {
    if (_initialized || _initializing) return;
    if (!_platformSupported) {
      AppLogger.debug(
          '[NotificationService] Platform not supported (${Platform.operatingSystem}); skipping');
      _initialized = true;
      return;
    }
    _initializing = true;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      // requestPermissions defaults to false — we drive permission requests
      // ourselves below so the user-visible prompt happens exactly once and
      // we can surface failures via the logger.
      const darwinInit = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const linuxInit =
          LinuxInitializationSettings(defaultActionName: 'Open Toxee');
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
        linux: linuxInit,
      );

      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _handleNotificationResponse,
      );

      // Capture cold-start payload (the user tapped a notification while the
      // app was dead). Subscribers attach later so we cache it and replay
      // on the first listener attach via [consumeLaunchPayload].
      try {
        final details = await _plugin.getNotificationAppLaunchDetails();
        if (details?.didNotificationLaunchApp ?? false) {
          _launchPayload = details?.notificationResponse?.payload;
          if (_launchPayload != null) {
            AppLogger.info(
                '[NotificationService] Cold-start notification payload captured: $_launchPayload');
          }
        }
      } catch (e) {
        // Non-fatal: cold-start launch info is best-effort.
        AppLogger.debug(
            '[NotificationService] getNotificationAppLaunchDetails failed: $e');
      }

      // Android: create the channels up front so the user can manage them
      // from system settings even before the first notification fires.
      if (Platform.isAndroid) {
        final androidImpl = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (androidImpl != null) {
          // NOTE: Android notification channels are immutable once created.
          // Existing installs that already have these channels keep whatever
          // sound/vibration/importance settings the channel was first created
          // with — only fresh installs (or after a clear-data) pick up these
          // explicit values. We set them anyway so new users get sane defaults
          // and so the contract is visible here.
          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              _androidChannelId,
              _androidChannelName,
              description: _androidChannelDescription,
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
            ),
          );
          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              _androidFriendReqChannelId,
              _androidFriendReqChannelName,
              description: _androidFriendReqChannelDescription,
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
            ),
          );
          await androidImpl.createNotificationChannel(
            const AndroidNotificationChannel(
              _androidMissedCallChannelId,
              _androidMissedCallChannelName,
              description: _androidMissedCallChannelDescription,
              importance: Importance.high,
              playSound: true,
              enableVibration: true,
            ),
          );
        }
        // Android 13+ (API 33) requires the POST_NOTIFICATIONS runtime
        // permission. We warm [_ensureAndroidPermission] so the cached state is
        // populated before the first message — but do NOT await it: like iOS,
        // requestNotificationsPermission() shows a modal system dialog whose
        // Future does not complete until the user answers, and AppBootstrap
        // awaits init() before runApp(), so awaiting here would pin the entire
        // app launch behind the permission dialog (blank screen). Fire it
        // unawaited; the lazy await on the first showMessageNotification still
        // gates actual delivery.
        if (_androidApiLevelAtLeast(33)) {
          unawaited(_ensureAndroidPermission());
        }
      }

      // iOS / macOS: ask for alert + badge + sound. CRITICAL: do NOT await the
      // permission prompt. On iOS requestPermissions() shows a *modal* system
      // alert whose Future does not complete until the user answers it. Because
      // AppBootstrap awaits init() before runApp(), awaiting here pins the
      // entire app launch behind the dialog — the user stares at a blank screen
      // until they tap Allow / Don't Allow. Fire it unawaited so startup
      // proceeds immediately; the prompt still appears and we log the outcome
      // (and any error) when it resolves. macOS behaves the same way before the
      // permission has been decided, so it is handled identically.
      if (Platform.isIOS) {
        final iosImpl = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        if (iosImpl != null) {
          unawaited(iosImpl
              .requestPermissions(alert: true, badge: true, sound: true)
              .then(
            (granted) => AppLogger.info(
                '[NotificationService] iOS permission granted=$granted'),
            onError: (Object e) => AppLogger.warn(
                '[NotificationService] iOS permission request failed: $e'),
          ));
        }
      } else if (Platform.isMacOS) {
        final macImpl = _plugin.resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>();
        if (macImpl != null) {
          unawaited(macImpl
              .requestPermissions(alert: true, badge: true, sound: true)
              .then(
            (granted) => AppLogger.info(
                '[NotificationService] macOS permission granted=$granted'),
            onError: (Object e) => AppLogger.warn(
                '[NotificationService] macOS permission request failed: $e'),
          ));
        }
      }

      _initialized = true;
      AppLogger.info('[NotificationService] Initialized on ${Platform.operatingSystem}');
    } catch (e, st) {
      AppLogger.logError(
          '[NotificationService] init() failed; notifications disabled', e, st);
    } finally {
      _initializing = false;
    }
  }

  /// Returns true if the current platform has a working backend.
  bool get _platformSupported {
    if (kIsWeb) return false;
    return Platform.isMacOS ||
        Platform.isIOS ||
        Platform.isAndroid ||
        Platform.isLinux ||
        Platform.isWindows;
  }

  /// Returns and clears the cold-start payload (notification that launched
  /// the app from a killed state), if any. Safe to call multiple times — it
  /// only returns non-null the first time.
  String? consumeLaunchPayload() {
    final p = _launchPayload;
    _launchPayload = null;
    return p;
  }

  /// Post a notification for an incoming message. The plugin returns
  /// synchronously after handing off to the platform channel; we don't
  /// `await` the platform call beyond that point.
  ///
  /// [conversationId] becomes the notification payload (the tap handler
  /// receives it on [onSelectStream]).
  /// [senderName] is the notification title — the contact's nickname or
  /// remark, falling back to the conversation ID where the caller can't
  /// resolve a display name.
  /// [preview] is the message preview body. Long bodies are clamped to 80
  /// chars to avoid OS truncation noise.
  /// [avatarPath] is currently best-effort — only Android attachments are
  /// supported in this implementation; macOS/iOS would require an
  /// attachment file in a sandbox-readable location.
  Future<void> showMessageNotification({
    required String conversationId,
    required String senderName,
    required String preview,
    String? avatarPath,
  }) async {
    if (!_initialized) {
      // Lazy init — _initializing guards against re-entry.
      await init();
    }
    if (!_initialized || !_platformSupported) return;

    // Android 13+ permission gate. If init() ran before the permission was
    // decided (or the user is on a platform where the channel exists but
    // notifications are blocked from system settings), the cached result
    // tells us to bail before queueing a no-op platform call. The contextual
    // prompt fires here for the first message — exactly the moment a banner
    // would otherwise be useful.
    if (_isAndroidPlatform) {
      await _ensureAndroidPermission();
      if (_androidPermissionGranted == false) {
        AppLogger.debug(
            '[NotificationService] Android notifications denied; skipping notify for conv=$conversationId');
        return;
      }
    }

    try {
      // Body cap. Keep word boundary if we can — avoid breaking mid-grapheme
      // by clamping on the rune-level codepoints, then trimming trailing
      // whitespace before appending an ellipsis.
      final clampedBody = _clampBody(preview);

      // Inbox-style grouping: accumulate up to 5 lines per conversation so
      // a burst of "Alice: hi / Alice: there / Alice: are you free?" shows
      // up as one expandable notification, not three separate banners.
      final lines = _grouped.putIfAbsent(conversationId, () => <String>[]);
      lines.add(clampedBody);
      // Don't keep an unbounded list — only the last 5 lines are shown by
      // Android's inbox style; past that, switch the summary to a count.
      if (lines.length > 5) {
        lines.removeRange(0, lines.length - 5);
      }

      final id = _idFor(conversationId);
      final isGrouped = lines.length > 1;
      final summary =
          isGrouped ? '${lines.length} new messages from $senderName' : null;

      // Android inbox style — preserves per-message lines plus a summary
      // count. The summary is shown when the notification is collapsed.
      final androidDetails = AndroidNotificationDetails(
        _androidChannelId,
        _androidChannelName,
        channelDescription: _androidChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.message,
        groupKey: 'toxee.messages.$conversationId',
        styleInformation: isGrouped
            ? InboxStyleInformation(
                List<String>.from(lines),
                contentTitle: senderName,
                summaryText: summary,
              )
            : null,
        // Best-effort large icon when an avatar path is available. We don't
        // ship attachment files for iOS/macOS yet — those need a sandbox
        // copy step that's out of scope for this change.
        largeIcon: (avatarPath != null && avatarPath.isNotEmpty)
            ? FilePathAndroidBitmap(avatarPath)
            : null,
      );

      // iOS / macOS thread identifier collapses multiple notifications from
      // the same conversation into one stack on the Lock Screen / Notification
      // Center. The OS does the grouping for us — no need to maintain our
      // own inbox-style list.
      final darwinDetails = DarwinNotificationDetails(
        threadIdentifier: 'toxee.messages.$conversationId',
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      const linuxDetails = LinuxNotificationDetails(
        category: LinuxNotificationCategory.imReceived,
      );

      final body = isGrouped ? (summary ?? clampedBody) : clampedBody;

      await _plugin.show(
        id,
        senderName,
        body,
        NotificationDetails(
          android: androidDetails,
          iOS: darwinDetails,
          macOS: darwinDetails,
          linux: linuxDetails,
        ),
        payload: conversationId,
      );
    } catch (e, st) {
      // Don't propagate — notifications are best-effort. Logging at warn so
      // a persistent platform issue (denied permission, missing channel) is
      // visible without spamming error on every message.
      AppLogger.warn(
          '[NotificationService] showMessageNotification failed for conv=$conversationId: $e');
      AppLogger.debug('[NotificationService] stack: $st');
    }
  }

  /// Post a notification for an incoming friend-add request.
  ///
  /// The tap payload uses the `friend_req:<userId>` form so the existing
  /// route handler can dispatch to a "new friend" / "contacts" landing
  /// page distinct from a chat conversation.
  ///
  /// Best-effort like [showMessageNotification]: failures are logged and
  /// swallowed.
  Future<void> showFriendRequestNotification({
    required String senderId,
    required String senderName,
    required String requestMessage,
  }) async {
    if (!_initialized) {
      await init();
    }
    if (!_initialized || !_platformSupported) return;

    if (Platform.isAndroid) {
      await _ensureAndroidPermission();
      if (_androidPermissionGranted == false) {
        AppLogger.debug(
            '[NotificationService] Android notifications denied; skipping friend req notify for $senderId');
        return;
      }
    }

    try {
      final clampedBody = _clampBody(
          requestMessage.isEmpty ? '(no message)' : requestMessage);

      final id = _idFor('friend_req:$senderId');

      final androidDetails = AndroidNotificationDetails(
        _androidFriendReqChannelId,
        _androidFriendReqChannelName,
        channelDescription: _androidFriendReqChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.social,
        groupKey: 'toxee.friend_requests',
      );
      const darwinDetails = DarwinNotificationDetails(
        threadIdentifier: 'toxee.friend_requests',
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const linuxDetails = LinuxNotificationDetails(
        category: LinuxNotificationCategory.imReceived,
      );

      await _plugin.show(
        id,
        senderName.isEmpty ? 'New friend request' : 'Friend request: $senderName',
        clampedBody,
        NotificationDetails(
          android: androidDetails,
          iOS: darwinDetails,
          macOS: darwinDetails,
          linux: linuxDetails,
        ),
        payload: 'friend_req:$senderId',
      );
    } catch (e, st) {
      AppLogger.warn(
          '[NotificationService] showFriendRequestNotification failed for $senderId: $e');
      AppLogger.debug('[NotificationService] stack: $st');
    }
  }

  /// Clear any active notifications for [conversationId] and reset the
  /// per-conversation accumulator. Call from the conversation view's
  /// initState — when the user opens the chat the OS-level banners should
  /// disappear.
  Future<void> clearConversationGroup(String conversationId) async {
    _grouped.remove(conversationId);
    if (!_initialized || !_platformSupported) return;
    try {
      await _plugin.cancel(_idFor(conversationId));
    } catch (e) {
      AppLogger.debug(
          '[NotificationService] cancel failed for conv=$conversationId: $e');
    }
  }

  /// Cancels every pending notification — used when logging out or
  /// switching accounts. Stays best-effort.
  Future<void> cancelAll() async {
    _grouped.clear();
    if (!_initialized || !_platformSupported) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      AppLogger.debug('[NotificationService] cancelAll failed: $e');
    }
  }

  /// Clear all per-session inbox state and any pending OS-level banners so a
  /// subsequent account does not inherit the prior account's grouped lines or
  /// notification-id mapping. Safe to call before [init] (the maps are empty);
  /// platform-channel `cancelAll` is a no-op when uninitialized.
  Future<void> resetSessionState() async {
    _grouped.clear();
    _conversationIdHashCache.clear();
    _conversationCounter = 0;
    // Reset the Android POST_NOTIFICATIONS cache so the next signed-in
    // account re-queries OS state (or re-prompts). Without this, "account A
    // denied notifications" silently suppresses banners for account B in
    // the same process.
    _androidPermissionGranted = null;
    await cancelAll();
  }

  /// Post a missed-call notification — used when an incoming call rings out,
  /// is dropped by the network, or the user does not reach the device in time.
  /// Routes through a dedicated Android channel so it is separately tunable
  /// from message/friend-request banners. The payload uses the
  /// `missed_call:<peerId>` form so the existing route handler can dispatch
  /// to the chat with the caller (or, in future, the call history page).
  ///
  /// Best-effort like the other show* methods: failures are logged and
  /// swallowed.
  Future<void> showMissedCallNotification({
    required String peerId,
    required String displayName,
    required bool wasVideo,
  }) async {
    if (!_initialized) {
      await init();
    }
    if (!_initialized || !_platformSupported) return;

    if (Platform.isAndroid) {
      await _ensureAndroidPermission();
      if (_androidPermissionGranted == false) {
        AppLogger.debug(
            '[NotificationService] Android notifications denied; skipping missed-call notify for $peerId');
        return;
      }
    }

    try {
      final title = wasVideo ? 'Missed video call' : 'Missed call';
      final body = displayName.isEmpty ? peerId : displayName;
      final id = _idFor('missed_call:$peerId');

      const androidDetails = AndroidNotificationDetails(
        _androidMissedCallChannelId,
        _androidMissedCallChannelName,
        channelDescription: _androidMissedCallChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.missedCall,
        groupKey: 'toxee.missed_calls',
      );
      const darwinDetails = DarwinNotificationDetails(
        threadIdentifier: 'toxee.missed_calls',
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      const linuxDetails = LinuxNotificationDetails(
        category: LinuxNotificationCategory.imReceived,
      );

      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: androidDetails,
          iOS: darwinDetails,
          macOS: darwinDetails,
          linux: linuxDetails,
        ),
        payload: 'missed_call:$peerId',
      );
    } catch (e, st) {
      AppLogger.warn(
          '[NotificationService] showMissedCallNotification failed for $peerId: $e');
      AppLogger.debug('[NotificationService] stack: $st');
    }
  }

  String _clampBody(String preview) {
    final trimmed = preview.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (trimmed.length <= _maxBodyChars) return trimmed;
    return '${trimmed.substring(0, _maxBodyChars - 1).trimRight()}…';
  }

  int _idFor(String conversationId) {
    final cached = _conversationIdHashCache[conversationId];
    if (cached != null) return cached;
    // Reserve 0 for "anonymous" and use a monotonic counter so the IDs are
    // stable for the session. Hash collisions don't matter because we map
    // through this table — but we also want IDs that fit in a signed 32-bit
    // int (Android's NotificationManager.notify takes a Java int).
    _conversationCounter++;
    final id = _conversationCounter & 0x7fffffff;
    _conversationIdHashCache[conversationId] = id;
    return id;
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    if (_onSelectController.isClosed) return;
    _onSelectController.add(payload);
  }

  /// Lazily asks the user for Android POST_NOTIFICATIONS permission, caching
  /// the answer in [_androidPermissionGranted] so we only prompt once per
  /// session. Returns immediately on non-Android platforms.
  ///
  /// Fast-paths via [areNotificationsEnabled]: if the user already has
  /// notifications turned on (the common case after a relaunch on Android
  /// 13+ where they previously granted, or any pre-Android-13 install
  /// where the OS auto-grants) we skip the popup entirely.
  Future<void>? _androidPermissionInFlight;

  Future<void> _ensureAndroidPermission() {
    if (!Platform.isAndroid || _androidPermissionGranted != null) {
      return Future<void>.value();
    }
    // De-duplicate concurrent callers: init() fires this unawaited (so app
    // startup is not pinned behind the POST_NOTIFICATIONS dialog) while the
    // first showMessageNotification may await it before the cache is set.
    // Sharing one in-flight future stops both paths from racing into a second
    // requestNotificationsPermission() call.
    return _androidPermissionInFlight ??= _runEnsureAndroidPermission();
  }

  Future<void> _runEnsureAndroidPermission() async {
    try {
      final androidImpl = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl == null) {
        // Plugin didn't expose the Android impl — treat as granted to avoid
        // disabling notifications on an environment where we can't even ask.
        _androidPermissionGranted = true;
        return;
      }
      try {
        final alreadyEnabled = await androidImpl.areNotificationsEnabled();
        if (alreadyEnabled == true) {
          _androidPermissionGranted = true;
          AppLogger.info(
              '[NotificationService] Android notifications already enabled');
          return;
        }
        // alreadyEnabled is false or null — ask. The plugin returns true if
        // granted, false if denied, null on platforms / API levels where the
        // request is a no-op (treat null as granted — pre-Android-13).
        final granted = await androidImpl.requestNotificationsPermission();
        _androidPermissionGranted = granted ?? true;
        if (_androidPermissionGranted == true) {
          AppLogger.info(
              '[NotificationService] Android POST_NOTIFICATIONS granted');
        } else {
          AppLogger.warn(
              '[NotificationService] Android POST_NOTIFICATIONS denied — notifications will be silently dropped this session');
        }
      } catch (e, st) {
        // Don't poison the channel on a transient platform-side failure —
        // treat as granted so the user still has a chance of getting banners.
        AppLogger.logError(
            '[NotificationService] _ensureAndroidPermission failed', e, st);
        _androidPermissionGranted = true;
      }
    } finally {
      _androidPermissionInFlight = null;
    }
  }

  /// Returns true if the Android release suggests we're at or above [minApi].
  ///
  /// Currently only used for `minApi == 33` (POST_NOTIFICATIONS), where
  /// `release >= 13` is the correct check. The `30 + (release - 11)` formula
  /// IS NOT a general release→API mapping (Android 12.1 = API 32, Android 15
  /// = API 35, etc. would all be off by 1). Do not reuse this for other
  /// thresholds without first validating against the actual API level via
  /// a native platform channel.
  ///
  /// Parses [Platform.operatingSystemVersion] for the leading integer — on
  /// Android the string is of the form `"<release> <kernel>"` (e.g.
  /// `"13 5.10.81-android13-..."`). When the parse fails we conservatively
  /// return true so the permission gate still runs — the plugin's
  /// [requestNotificationsPermission] is itself a no-op on pre-Android-13,
  /// so an unnecessary call costs nothing.
  bool _androidApiLevelAtLeast(int minApi) {
    if (!Platform.isAndroid) return false;
    try {
      final version = Platform.operatingSystemVersion;
      // The first whitespace-delimited token is the release version on
      // Android (e.g. "13").
      final match = RegExp(r'^\s*(\d+)').firstMatch(version);
      final release = int.tryParse(match?.group(1) ?? '');
      if (release == null) return true; // Unknown — let the plugin decide.
      // Release -> API: 11->30, 12->31/32, 13->33, 14->34, 15->35.
      // This is a coarse approximation; see doc comment above for the
      // strict constraint on which `minApi` values are safe.
      final estimatedApi = 30 + (release - 11);
      return estimatedApi >= minApi;
    } catch (_) {
      return true;
    }
  }

  /// Test-only / shutdown hook. Cancels the broadcast controller.
  @visibleForTesting
  Future<void> disposeForTest() async {
    await _onSelectController.close();
    _grouped.clear();
    _conversationIdHashCache.clear();
    _initialized = false;
    _androidPermissionGranted = null;
  }
}
