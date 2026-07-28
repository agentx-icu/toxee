part of '../main.dart';

typedef StartupGateLoadFriendsFn =
    Future<void> Function(FfiChatService service);
typedef StartupGateNavigateHomeFn =
    Future<void> Function(BuildContext context, FfiChatService service);
typedef StartupGateTouchAccountLoginTimeFn =
    Future<void> Function(String toxId);

/// Owns the activation lease returned by [StartupSessionUseCase] until Home is
/// synchronously scheduled or startup is abandoned.
class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    this.startupUseCase,
    this.loadFriends,
    this.navigateHome,
    this.teardownSession,
    this.touchAccountLoginTime,
    this.connectionTimeout = const Duration(seconds: 20),
    this.completionDelay = const Duration(milliseconds: 500),
  });

  final StartupSessionUseCase? startupUseCase;
  final StartupGateLoadFriendsFn? loadFriends;
  final StartupGateNavigateHomeFn? navigateHome;
  final StartupTeardownSessionFn? teardownSession;
  final StartupGateTouchAccountLoginTimeFn? touchAccountLoginTime;
  final Duration connectionTimeout;
  final Duration completionDelay;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  bool _checking = true;
  bool _startupInProgress = false;
  String? _error;
  bool _waitingForConnection = false;
  Timer? _timeoutTimer;
  StreamSubscription<bool>? _connectionSub;
  StartupStep _currentStep = StartupStep.checkingUserInfo;
  _StartupActivationLease? _ownedActivation;
  late final StartupSessionUseCase _startupUseCase;
  late final StartupGateLoadFriendsFn _loadFriends;
  late final StartupGateNavigateHomeFn _navigateHome;
  late final StartupTeardownSessionFn _teardownSession;
  late final StartupGateTouchAccountLoginTimeFn _touchAccountLoginTime;

  Widget _buildHomePage(FfiChatService service) => HomePage(service: service);

  @override
  void initState() {
    super.initState();
    _startupUseCase = widget.startupUseCase ?? StartupSessionUseCase();
    _loadFriends = widget.loadFriends ?? _loadFriendsInfo;
    _navigateHome = widget.navigateHome ?? _defaultNavigateHome;
    _teardownSession =
        widget.teardownSession ?? AccountService.teardownCurrentSession;
    _touchAccountLoginTime =
        widget.touchAccountLoginTime ?? Prefs.touchAccountLoginTime;
    _runStartup();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    unawaited(_connectionSub?.cancel());
    _connectionSub = null;
    final activation = _ownedActivation;
    if (activation != null) {
      unawaited(
        _teardownAndRollback(activation, reason: 'startup gate dispose'),
      );
    }
    super.dispose();
  }

  Future<void> _defaultNavigateHome(
    BuildContext context,
    FfiChatService service,
  ) {
    return Navigator.of(context)
        .pushReplacement(AppPageRoute(page: _buildHomePage(service)))
        .then<void>((_) {});
  }

  void _updateStep(StartupStep step) {
    if (mounted) {
      setState(() {
        _currentStep = step;
      });
    }
  }

  Future<void> _runStartup() async {
    if (_startupInProgress) return;
    _startupInProgress = true;
    final needsRebuild = _error != null || !_checking || _waitingForConnection;
    void resetLoadingState() {
      _error = null;
      _checking = true;
      _waitingForConnection = false;
    }

    if (needsRebuild) {
      setState(resetLoadingState);
    } else {
      resetLoadingState();
    }
    try {
      final outcome = await _startupUseCase.execute(
        onStepChanged: _updateStep,
        loadFriends: _loadFriends,
      );
      if (!mounted) {
        await _cleanupUnmountedOutcome(outcome);
        return;
      }
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
        case StartupOpenHome(:final service, :final activation):
          final lease = _StartupActivationLease(service, activation);
          _ownedActivation = lease;
          _claimAndFinalizeHome(lease);
          break;
        case StartupWaitForConnection(:final service, :final activation):
          final lease = _StartupActivationLease(service, activation);
          _ownedActivation = lease;
          setState(() {
            _waitingForConnection = true;
          });
          _waitForConnectionAndNavigate(service);
          break;
      }
    } finally {
      _startupInProgress = false;
    }
  }

  Future<void> _cleanupUnmountedOutcome(StartupOutcome outcome) async {
    switch (outcome) {
      case StartupOpenHome(:final service, :final activation):
      case StartupWaitForConnection(:final service, :final activation):
        await _teardownAndRollback(
          _StartupActivationLease(service, activation),
          reason: 'startup completed after gate unmounted',
        );
      case StartupShowLogin() || StartupShowError():
        return;
    }
  }

  void _waitForConnectionAndNavigate(FfiChatService service) {
    _timeoutTimer = Timer(widget.connectionTimeout, () {
      final lease = _claimWaitingActivation(service);
      if (lease == null) return;
      _updateStep(StartupStep.completed);
      unawaited(_finalizeAfterDelay(lease));
    });

    _connectionSub = service.connectionStatusStream.listen((isConnected) {
      if (!isConnected) return;
      final lease = _claimWaitingActivation(service);
      if (lease == null) return;
      _updateStep(StartupStep.loadingFriends);
      unawaited(_onConnectionReady(lease));
    });
  }

  _StartupActivationLease? _claimWaitingActivation(FfiChatService service) {
    if (!mounted) return null;
    final lease = _ownedActivation;
    if (lease == null || !identical(lease.service, service) || !lease.claim()) {
      return null;
    }
    _waitingForConnection = false;
    _cancelConnectionWaiters();
    return lease;
  }

  void _claimAndFinalizeHome(_StartupActivationLease lease) {
    if (!lease.claim()) return;
    unawaited(_finalizeClaimedHome(lease));
  }

  Future<void> _onConnectionReady(_StartupActivationLease lease) async {
    try {
      await _loadFriends(lease.service);
      if (!mounted) {
        await _teardownAndRollback(
          lease,
          reason: 'startup gate unmounted while loading friends',
        );
        return;
      }
      _updateStep(StartupStep.completed);
      await _delayBeforeHome();
      if (!mounted) {
        await _teardownAndRollback(
          lease,
          reason: 'startup gate unmounted before Home navigation',
        );
        return;
      }
      await _finalizeClaimedHome(lease);
    } catch (error) {
      SafeDiagnostics.logFailure(
        '[StartupGate] pre-navigation friend loading failed',
        error,
      );
      await _teardownAndRollback(lease, reason: 'friend loading failure');
      _showPreNavigationError(error);
    }
  }

  Future<void> _finalizeAfterDelay(_StartupActivationLease lease) async {
    await _delayBeforeHome();
    if (!mounted) {
      await _teardownAndRollback(
        lease,
        reason: 'startup gate unmounted after connection timeout',
      );
      return;
    }
    await _finalizeClaimedHome(lease);
  }

  Future<void> _delayBeforeHome() async {
    if (widget.completionDelay > Duration.zero) {
      await Future<void>.delayed(widget.completionDelay);
    }
  }

  Future<void> _finalizeClaimedHome(_StartupActivationLease lease) async {
    if (!mounted) {
      await _teardownAndRollback(
        lease,
        reason: 'startup gate unmounted during Home finalization',
      );
      return;
    }
    try {
      // Navigator lookup and route insertion happen synchronously. The Future
      // represents Home's lifetime and must not keep the activation open.
      final homeLifetime = _navigateHome(context, lease.service);
      unawaited(homeLifetime);
      lease.commit();
      if (identical(_ownedActivation, lease)) {
        _ownedActivation = null;
      }
      unawaited(HapticFeedback.lightImpact());
      unawaited(_touchLoginTimeAfterCommit(lease.service));
    } catch (error) {
      SafeDiagnostics.logFailure(
        '[StartupGate] synchronous Home navigation failed',
        error,
      );
      await _teardownAndRollback(
        lease,
        reason: 'synchronous Home navigation failure',
      );
      _showPreNavigationError(error);
    }
  }

  Future<void> _touchLoginTimeAfterCommit(FfiChatService service) async {
    try {
      final touchId = service.getSelfToxId() ?? service.selfId;
      await _touchAccountLoginTime(touchId);
    } catch (error) {
      SafeDiagnostics.logFailure(
        '[StartupGate] last-login touch after activation commit failed',
        error,
      );
    }
  }

  Future<void> _teardownAndRollback(
    _StartupActivationLease lease, {
    required String reason,
  }) async {
    if (!lease.beginCleanup()) return;
    if (identical(_ownedActivation, lease)) {
      _ownedActivation = null;
    }
    _waitingForConnection = false;
    _cancelConnectionWaiters();
    try {
      await _teardownSession(service: lease.service, reEncryptProfile: true);
    } catch (cleanupError) {
      SafeDiagnostics.logFailure(
        '[StartupGate] teardown failed reason=$reason',
        cleanupError,
      );
    }
    try {
      await lease.activation.rollback();
    } catch (rollbackError) {
      SafeDiagnostics.logFailure(
        '[StartupGate] activation rollback failed reason=$reason',
        rollbackError,
      );
    }
  }

  void _cancelConnectionWaiters() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
    final connectionSub = _connectionSub;
    _connectionSub = null;
    if (connectionSub != null) {
      unawaited(connectionSub.cancel());
    }
  }

  void _showPreNavigationError(Object error) {
    if (!mounted) return;
    setState(() {
      _error = SafeDiagnostics.describeError(error);
      _checking = false;
      _waitingForConnection = false;
    });
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
              '[StartupGate] Friends info loaded: ${friends.length} friends, ${friends.where((f) => f.online).length} online',
            );
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
    } catch (error) {
      SafeDiagnostics.logFailure(
        '[StartupGate] friend information loading failed',
        error,
      );
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
                Navigator.of(
                  context,
                ).pushReplacement(AppPageRoute(page: const LoginPage()));
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
          Navigator.of(
            context,
          ).pushReplacement(AppPageRoute(page: const LoginPage()));
        },
      );
    }
    // Fall back to registration when no local data
    return const LoginPage();
  }
}

enum _StartupActivationState { pending, claimed, committed, cleaningUp }

final class _StartupActivationLease {
  _StartupActivationLease(this.service, this.activation);

  final FfiChatService service;
  final AccountActivationTransaction activation;
  _StartupActivationState _state = _StartupActivationState.pending;

  bool claim() {
    if (_state != _StartupActivationState.pending) return false;
    _state = _StartupActivationState.claimed;
    return true;
  }

  void commit() {
    if (_state != _StartupActivationState.claimed) {
      throw StateError('Startup activation committed without a claim');
    }
    activation.commit();
    _state = _StartupActivationState.committed;
  }

  bool beginCleanup() {
    if (_state == _StartupActivationState.committed ||
        _state == _StartupActivationState.cleaningUp) {
      return false;
    }
    _state = _StartupActivationState.cleaningUp;
    return true;
  }
}
