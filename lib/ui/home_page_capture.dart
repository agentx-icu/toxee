part of 'home_page.dart';

// Camera capture from a chat, the recovery of a capture whose process
// Android reclaimed while the system camera was in front (checklist M9), and
// preparing outgoing media (M2).
// Split out of `home_page.dart` (at its complexity pin).

extension _HomePageCapture on _HomePageState {
  /// Sends [path] to [userId], HEIC as JPEG and HEVC as H.264 (M2): desktop
  /// peers often cannot show them. False when the user cancelled the
  /// conversion; throws [MediaConversionException] when it failed.
  Future<bool> _sendPreparedMedia(String userId, String path) async {
    final String prepared;
    try {
      prepared = await OutgoingMedia.prepare(
        path,
        accountKey: widget.service.accountKey,
      );
    } on MediaConversionCancelled {
      return false;
    }
    await widget.service.sendFile(userId, prepared);
    return true;
  }

  Future<void> _showCameraMediaOptions(
    BuildContext context, {
    String? userId,
    String? groupId,
  }) async {
    if ((userId == null || userId.isEmpty) &&
        (groupId == null || groupId.isEmpty)) {
      final current = UikitDataFacade.currentConversation;
      userId = current?.userID;
      groupId = current?.groupID;
    }

    final cameraLabel =
        TencentCloudChatLocalizations.of(context)?.camera ?? 'Camera';
    if (groupId != null && groupId.isNotEmpty) {
      _showSnackBar(
        AppLocalizations.of(context)!.sendingToGroupsNotSupported(cameraLabel),
      );
      return;
    }

    final peerId = userId;
    final accountKey = widget.service.accountKey;
    await TencentCloudChatMessageCamera.showCameraOptions(
      context: context,
      // Android may reclaim toxee while the camera is in front: remember the
      // chat so the result can be offered again after restart (M9).
      onCaptureStarting: ({required bool isVideo}) async {
        if (peerId == null || peerId.isEmpty) return;
        await CameraCaptureRecovery.remember(
          accountKey: accountKey,
          userId: peerId,
        );
      },
      onCaptureEnded: CameraCaptureRecovery.forget,
      onSendImage: ({required String imagePath}) {
        if (!mounted) return;
        unawaited(
          _sendMedia(
            context,
            userId: userId,
            type: _MediaPickType.image,
            selectedPath: imagePath,
          ),
        );
      },
      onSendVideo: ({required String videoPath}) {
        if (!mounted) return;
        unawaited(
          _sendMedia(
            context,
            userId: userId,
            type: _MediaPickType.video,
            selectedPath: videoPath,
          ),
        );
      },
    );
  }

  /// Startup routing once the session is ready. Registers the OS
  /// notification listener (idempotent; it replays a launch notification's
  /// route), then opens, in this precedence:
  ///
  /// 1. the launch notification's destination (the user's explicit action);
  /// 2. else the chat of a capture recovered after a reclaim (M9);
  /// 3. else the chat open when the OS reclaimed the app (B6).
  ///
  /// Only then is the open chat tracked for the next reclaim: the saved
  /// marker is read before anything could overwrite it. A recovered capture's
  /// dialog comes last, over whatever won.
  Future<void> _registerNotificationsThenRecoverCapture() async {
    var launchRouted = false;
    try {
      await NotificationMessageListener.forService(widget.service).register(
        onConversationTapped: (payload) {
          launchRouted = true;
          _routeToNotificationPayload(payload);
        },
      );
      await Future<void>.delayed(Duration.zero); // let the replay run first
    } catch (e) {
      AppLogger.warn('[HomePage] notification listener: $e');
    }
    if (!mounted) return;
    final account = widget.service.accountKey;
    final restoration = OpenChatRestoration();
    final saved = await restoration.readSaved(account);
    final capture = await _stageRecoveredCapture();
    if (!mounted) return;
    if (!launchRouted) {
      if (capture != null) {
        _routeToNotificationPayload('c2c_${capture.userId}');
      } else if (saved != null) {
        final group = saved.groupID;
        _routeToNotificationPayload(
          group != null && group.isNotEmpty
              ? 'group_$group'
              : 'c2c_${saved.userID}',
        );
      }
    }
    _trackOpenChat(restoration, account);
    if (capture != null) await _offerRecoveredCapture(capture);
  }

  /// Keeps the conversation on screen in the restoration data (B6): after
  /// every navigation, every right-pane selection (which changes no route),
  /// and — as a backup — when the app turns inactive, before the OS saves
  /// state.
  void _trackOpenChat(OpenChatRestoration restoration, String account) {
    void snapshot() {
      if (mounted) restoration.save(account, _masterDetail.visibleChat());
    }

    void afterChange() =>
        WidgetsBinding.instance.addPostFrameCallback((_) => snapshot());
    final routes = _masterDetail.tracker.revision..addListener(afterChange);
    final selection = TencentCloudChat.instance.eventBusInstance
        .on<TencentCloudChatConversationData<dynamic>>(
          "TencentCloudChatConversationData",
        )
        ?.listen((data) {
          if (data.currentUpdatedFields ==
              TencentCloudChatConversationDataKeys.currentConversation) {
            afterChange();
          }
        });
    final lifecycle = AppLifecycleListener(onInactive: snapshot);
    _bag.add(() {
      routes.removeListener(afterChange);
      unawaited(selection?.cancel());
      lifecycle.dispose();
      restoration.save(account, null); // logged out: nothing to come back to
    });
  }

  /// A capture recovered after a reclaim for this account, if any (M9).
  Future<RecoveredCapture?> _stageRecoveredCapture() async {
    try {
      await CameraCaptureRecovery.stage();
      await CameraCaptureRecovery.stageFilePick();
      return await CameraCaptureRecovery.pendingFor(widget.service.accountKey);
    } catch (e) {
      AppLogger.warn('[HomePage] capture recovery unavailable: $e');
      return null;
    }
  }

  /// Asks before anything is sent. Send goes to the recorded peer, whatever
  /// chat is open meanwhile.
  Future<void> _offerRecoveredCapture(RecoveredCapture capture) async {
    final send = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          RecoveredCaptureDialog(capture: capture, peerName: _peerName(capture.userId)),
    );
    if (send == null || !mounted) return; // unanswered: offered again later
    await CameraCaptureRecovery.resolve(capture, sent: send);
    if (!send || !mounted) return;
    await _sendMedia(
      context,
      userId: capture.userId,
      type: capture.isFile
          ? _MediaPickType.file
          : capture.isVideo
          ? _MediaPickType.video
          : _MediaPickType.image,
      selectedPath: capture.path,
    );
  }

  /// Runs the system file picker for [userId]'s chat. On Android the pick is
  /// kept natively in case the process is reclaimed while the picker is in
  /// front (M9, [LostFilePickChannel]).
  Future<String?> _pickForChat(
    String? userId,
    Future<String?> Function() pick,
  ) async {
    if (userId == null || userId.isEmpty) return pick();
    await LostFilePickChannel.arm(
      accountKey: widget.service.accountKey,
      userId: userId,
    );
    try {
      return await pick();
    } finally {
      await LostFilePickChannel.disarm();
    }
  }

  String _peerName(String userId) {
    for (final friend in UikitDataFacade.contactList) {
      if (friend.userID != userId) continue;
      final remark = friend.friendRemark;
      if (remark != null && remark.isNotEmpty) return remark;
      final nick = friend.userProfile?.nickName;
      if (nick != null && nick.isNotEmpty) return nick;
    }
    return userId.length > 12 ? '${userId.substring(0, 12)}…' : userId;
  }
}
