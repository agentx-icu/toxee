part of 'home_page.dart';

// Camera capture from a chat, and the recovery of a capture whose process
// Android reclaimed while the system camera was in front (checklist M9).
// Split out of `home_page.dart` (at its complexity pin).

extension _HomePageCapture on _HomePageState {
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

  /// Registers the OS-notification listener (idempotent), then offers a
  /// recovered capture. In that order: the listener replays a launch
  /// notification's route, which must not end up on top of the dialog.
  Future<void> _registerNotificationsThenRecoverCapture() async {
    try {
      await NotificationMessageListener.forService(widget.service).register(
        onConversationTapped: (payload) {
          _routeToNotificationPayload(payload);
        },
      );
      await Future<void>.delayed(Duration.zero); // let the replay run first
    } finally {
      if (mounted) await _offerRecoveredCapture();
    }
  }

  /// Offers a capture recovered after a reclaim to the account it was taken
  /// for: reopens its chat and asks before anything is sent. Send goes to the
  /// recorded peer, whatever chat is open meanwhile.
  Future<void> _offerRecoveredCapture() async {
    final RecoveredCapture? pending;
    try {
      await CameraCaptureRecovery.stage();
      pending = await CameraCaptureRecovery.pendingFor(
        widget.service.accountKey,
      );
    } catch (e) {
      AppLogger.warn('[HomePage] capture recovery unavailable: $e');
      return;
    }
    if (pending == null || !mounted) return;
    final capture = pending;
    _routeToNotificationPayload('c2c_${capture.userId}');
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
      type: capture.isVideo ? _MediaPickType.video : _MediaPickType.image,
      selectedPath: capture.path,
    );
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
