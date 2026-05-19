// FakeMessage → V2TimMessage mapping and history loading for
// FakeChatMessageProvider.
//
// Extracted as a `part of` extension to keep behavior identical while reducing
// the size of fake_msg_provider.dart. Holds the three pieces that are
// intertwined:
//   * `_mapCallRecordMsg(m)` — call-record custom-elem mapping.
//   * `_mapMsg(m)` — the main per-message mapping (text/image/file/video/audio,
//     localUrl resolution from `_fileProgress`, isPending/isRead status logic,
//     avatar resolution from caches).
//   * `_loadHistoryForConversation(conv)` — pulls history from
//     `FakeUIKit.instance.messageManager`, replays failed messages from
//     `Tim2ToxFailedMessagePersistence`, and emits the merged list onto the
//     conversation's stream controller.

part of 'fake_msg_provider.dart';

extension _FakeChatMessageProviderMapping on FakeChatMessageProvider {
  /// Map a call record FakeMessage to V2TimMessage with custom element.
  V2TimMessage _mapCallRecordMsg(FakeMessage m) {
    AppLogger.log('[FakeMessageProvider] _mapCallRecordMsg: msgID=${m.msgID}, conv=${m.conversationID}, textLen=${m.text.length}');
    final msg = V2TimMessage(elemType: MessageElemType.V2TIM_ELEM_TYPE_CUSTOM);
    msg.msgID = m.msgID;
    msg.timestamp = (m.timestampMs ~/ 1000);

    // Set userID/groupID from conversationID
    if (m.conversationID.startsWith('c2c_')) {
      msg.userID = m.conversationID.substring(4);
    } else if (m.conversationID.startsWith('group_')) {
      msg.groupID = m.conversationID.substring(6);
    }

    // Call record data stored in text field as JSON
    msg.customElem = V2TimCustomElem(data: m.text, desc: '', extension: '');
    // Readable summary for session list / getMessageSummary (like [image] for image messages)
    final callLabel = TencentCloudChatIntl().localization?.call ?? 'Call';
    msg.textElem = V2TimTextElem(text: '[$callLabel]');

    // Set sender info
    final selfId = UikitDataFacade.currentUser?.userID;
    msg.isSelf = (selfId != null && compareToxIds(m.fromUser, selfId));
    msg.sender = m.fromUser;
    msg.status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
    AppLogger.log('[FakeMessageProvider] _mapCallRecordMsg: elemType=${msg.elemType}, isSelf=${msg.isSelf}, customElem.data=${msg.customElem?.data?.substring(0, 80)}...');

    // Set faceUrl for avatar display
    if (msg.isSelf ?? false) {
      if (_cachedSelfAvatarPath != null && _cachedSelfAvatarPath!.isNotEmpty) {
        msg.faceUrl = _cachedSelfAvatarPath;
      }
    } else {
      final friendAvatarPath = _cachedFriendAvatars[m.fromUser];
      if (friendAvatarPath != null && friendAvatarPath.isNotEmpty) {
        msg.faceUrl = friendAvatarPath;
      }
    }

    return msg;
  }

  V2TimMessage _mapMsg(FakeMessage m) {
    // Special handling for call record messages
    if (m.mediaKind == 'call_record') {
      return _mapCallRecordMsg(m);
    }

    // Determine element type based on mediaKind and filePath
    int elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT;
    if (m.filePath != null && m.mediaKind != null) {
      switch (m.mediaKind) {
        case 'image':
          elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE;
          break;
        case 'video':
          elemType = MessageElemType.V2TIM_ELEM_TYPE_VIDEO;
          break;
        case 'audio':
          elemType = MessageElemType.V2TIM_ELEM_TYPE_SOUND;
          break;
        case 'file':
          elemType = MessageElemType.V2TIM_ELEM_TYPE_FILE;
          break;
        default:
          elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT;
      }
    }

    // P2-4: surface unknown mediaKind payloads with a placeholder text
    // instead of silently falling through as an empty text message. This
    // lets users see *something* even when a new sender uses an
    // unrecognised media kind. Known kinds (image/video/audio/file/
    // call_record) are excluded by the if above.
    const knownKinds = {'image', 'video', 'audio', 'file', 'call_record'};
    final isUnknownCustom = m.mediaKind != null &&
        !knownKinds.contains(m.mediaKind) &&
        elemType == MessageElemType.V2TIM_ELEM_TYPE_TEXT;

    final msg = V2TimMessage(elemType: elemType);
    msg.msgID = m.msgID;
    msg.timestamp = (m.timestampMs ~/ 1000);

    // CRITICAL: For C2C messages, userID should be the receiver (the other person), not the sender
    // For self-sent messages: userID = receiver (the other person), fromUser = selfId
    // For received messages: userID = sender (the other person), fromUser = sender
    // Extract receiver ID from conversationID (c2c_<receiverID>)
    if (m.conversationID.startsWith('c2c_')) {
      final receiverID = m.conversationID.substring(4);
      msg.userID = receiverID;
    } else if (m.conversationID.startsWith('group_')) {
      final groupID = m.conversationID.substring(6);
      msg.groupID = groupID;
    } else {
      // Fallback: use fromUser (for backward compatibility)
      msg.userID = m.fromUser;
    }

    // Set appropriate element based on media type
    if (m.filePath != null && m.mediaKind != null) {
      final file = File(m.filePath!);
      // Use original fileName if available (to avoid showing id-prefixed names), otherwise extract from path
      final fileName = m.fileName ?? m.filePath!.split('/').last;

      switch (m.mediaKind) {
        case 'image':
          // Set image element with local path for UIKit to display
          // Check if this is a receiving file (temporary path indicates receiving)
          final isReceiving = m.filePath != null && m.filePath!.startsWith('/tmp/receiving_');
          final fileExists = m.filePath != null ? file.existsSync() : false;
          // Check if we have progress information for this message
          final progress = _fileProgress[m.msgID];
          // Determine localUrl: if file is complete (not receiving and file exists), set localUrl
          // UIKit uses localUrl in imageList to determine if image is downloaded
          String? localUrl;
          // Priority 1: If isPending is false, file is complete - set localUrl regardless of file existence check
          if (!m.isPending && m.filePath != null && !isReceiving) {
            localUrl = m.filePath;
          } else if (progress != null && progress.received >= progress.total && progress.total > 0) {
            // Progress indicates file is complete
            if (progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) {
              localUrl = progress.path;
            } else if (m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
              localUrl = m.filePath;
            }
          } else if (progress != null && progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) {
            // Progress has a valid path (from file_done or progress_recv), use it even if file is still receiving
            final progressFile = File(progress.path!);
            if (progressFile.existsSync()) {
              localUrl = progress.path;
            }
          } else if (!isReceiving && m.filePath != null && fileExists) {
            // File is complete and exists, set localUrl so UIKit knows it's downloaded
            localUrl = m.filePath;
          } else if (isReceiving && m.filePath != null && fileExists) {
            // File is receiving but already exists (fast transfer), set localUrl so UIKit can display it
            localUrl = m.filePath;
          }
          // CRITICAL: For images, also check if filePath is in file_recv or avatars directory (file already received)
          // This handles the case where file_done event updated the message but _mapMsg is called before progress update
          if (localUrl == null && m.filePath != null && (m.filePath!.contains('/file_recv/') || m.filePath!.contains('/avatars/'))) {
            final file = File(m.filePath!);
            if (file.existsSync()) {
              localUrl = m.filePath;
            }
          }
          // Create imageList with localUrl for UIKit to check hasLocalImage
          // CRITICAL: Also set uuid and url for downloadMessage to work
          final imageList = <V2TimImage?>[];
          // Generate UUID from msgID for download identification
          final imageUuid = m.msgID.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          final imagePath = m.filePath ?? localUrl;
          // CRITICAL: Don't use /tmp/receiving_ paths as URL - they are temporary and will fail when used as online URLs
          // Only use valid local paths (file_recv, avatars) or null if still receiving
          String? imageUrl;
          if (imagePath != null && !imagePath.startsWith('/tmp/receiving_')) {
            // Use local path as URL for Tox protocol (only if not a temp receiving path)
            imageUrl = imagePath;
          } else if (localUrl != null && !localUrl.startsWith('/tmp/receiving_')) {
            // Use localUrl if available and not a temp path
            imageUrl = localUrl;
          }
          // If imageUrl is still null, don't set it (let UIKit handle download)

          if (localUrl != null || (imagePath != null && !imagePath.startsWith('/tmp/receiving_'))) {
            // Create thumb image with localUrl (UIKit checks thumb image by default)
            final thumbImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB);
            thumbImage.uuid = imageUuid;
            if (imageUrl != null) {
              thumbImage.url = imageUrl;
            }
            thumbImage.localUrl = localUrl;
            if (fileExists && m.filePath != null) {
              thumbImage.size = file.lengthSync();
            }
            // P2-2: real width/height parsing would require decoding JPEG/PNG
            // headers — non-trivial without adding a media-decoding dep.
            // Set 0 so the SDK image cache key isn't `nullnull_*` (which
            // collides across distinct images). TODO(P2-2): parse actual
            // dimensions and replace with real values.
            thumbImage.width = 0;
            thumbImage.height = 0;
            imageList.add(thumbImage);
            // Also create origin image with localUrl
            final originImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN);
            originImage.uuid = imageUuid;
            if (imageUrl != null) {
              originImage.url = imageUrl;
            }
            originImage.localUrl = localUrl;
            if (fileExists && m.filePath != null) {
              originImage.size = file.lengthSync();
            }
            originImage.width = 0; // P2-2: see thumb comment above.
            originImage.height = 0;
            imageList.add(originImage);
          } else {
            // Even if localUrl is null, create imageList with uuid for downloadMessage
            // Don't set url if it's a temp receiving path - UIKit will handle download
            final thumbImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB);
            thumbImage.uuid = imageUuid;
            // Only set url if it's not a temp receiving path
            if (imageUrl != null) {
              thumbImage.url = imageUrl;
            }
            imageList.add(thumbImage);
            final originImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN);
            originImage.uuid = imageUuid;
            // Only set url if it's not a temp receiving path
            if (imageUrl != null) {
              originImage.url = imageUrl;
            }
            imageList.add(originImage);
          }
          // CRITICAL: Always create imageElem with imageList, even if imageList is empty
          // This ensures imageElem is not null, which is required for UIKit to render the image
          // CRITICAL: Use localUrl or final path (not temp path) for imageElem.path if available
          // This ensures isAlreadyComplete check can correctly detect completed files
          final imageElemPath = (localUrl != null && !localUrl.startsWith('/tmp/receiving_'))
              ? localUrl
              : ((m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_'))
                  ? m.filePath
                  : m.filePath);
          msg.imageElem = V2TimImageElem(
            path: imageElemPath,
            imageList: imageList.isNotEmpty ? imageList : (imageList.isEmpty ? [] : null),
          );
          // Debug: Log image message creation
          // Also set text element with file name as fallback
          if (m.text.isNotEmpty) {
            msg.textElem = V2TimTextElem(text: m.text);
          } else {
            // Use original fileName if available, otherwise use extracted fileName
            msg.textElem = V2TimTextElem(text: m.fileName ?? fileName);
          }
          break;
        case 'file':
          // Set file element with local path and file name
          // Check if this is a receiving file (temporary path indicates receiving)
          final isReceiving = m.filePath != null && m.filePath!.startsWith('/tmp/receiving_');
          final fileExists = m.filePath != null ? file.existsSync() : false;
          final fileSize = fileExists ? file.lengthSync() : null;
          // Check if we have progress information for this message
          final progress = _fileProgress[m.msgID];
          // Determine localUrl: if file is complete (not receiving and file exists), set localUrl
          // UIKit uses localUrl to determine if file is downloaded
          String? localUrl;
          // Priority 1: If isPending is false, file is complete - set localUrl regardless of file existence check
          // This handles the case where file_done has updated the message but file.existsSync() might fail due to timing
          if (!m.isPending && m.filePath != null && !isReceiving) {
            localUrl = m.filePath;
          } else if (progress != null && progress.received >= progress.total && progress.total > 0) {
            // Progress indicates file is complete - check this BEFORE isReceiving check
            // Use progress.path if available (from progress_recv events), otherwise use m.filePath if it's not a temp path
            if (progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) {
              localUrl = progress.path;
            } else if (m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
              localUrl = m.filePath;
            }
          } else if (isReceiving) {
            // File is still receiving, don't set localUrl yet (UIKit will show progress)
            localUrl = null;
          } else if (m.filePath != null && fileExists) {
            // File is complete and exists, set localUrl so UIKit knows it's downloaded
            localUrl = m.filePath;
          }
          // CRITICAL: For files, also check if filePath is in file_recv or avatars directory (file already received)
          // This handles the case where file_done event updated the message but _mapMsg is called before progress update
          // Similar to image messages, this ensures localUrl is set when file is in file_recv directory
          if (localUrl == null && m.filePath != null && (m.filePath!.contains('/file_recv/') || m.filePath!.contains('/avatars/'))) {
            final file = File(m.filePath!);
            if (file.existsSync()) {
              localUrl = m.filePath;
            }
          }
          // Generate UUID from msgID for download identification
          final fileUuid = m.msgID.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          // CRITICAL: Don't use /tmp/receiving_ paths as URL - they are temporary and will fail when used as online URLs
          // Only use valid local paths (file_recv) or null if still receiving
          String? fileUrl;
          if (m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
            // Use local path as URL for Tox protocol (only if not a temp receiving path)
            fileUrl = m.filePath;
          } else if (localUrl != null && !localUrl.startsWith('/tmp/receiving_')) {
            // Use localUrl if available and not a temp path
            fileUrl = localUrl;
          }
          // If fileUrl is still null, don't set it (let UIKit handle download)

          // CRITICAL: Use localUrl or final path (not temp path) for fileElem.path if available
          // This ensures isAlreadyComplete check can correctly detect completed files
          final fileElemPath = (localUrl != null && !localUrl.startsWith('/tmp/receiving_'))
              ? localUrl
              : ((m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_'))
                  ? m.filePath
                  : m.filePath);
          msg.fileElem = V2TimFileElem(
            path: fileElemPath,
            fileName: fileName,
            UUID: fileUuid, // Required for downloadMessage
            url: fileUrl, // Required for downloadMessage (null if still receiving)
            fileSize: fileSize ?? (progress != null ? progress.total : null),
            localUrl: localUrl,
          );
          // Also set text element with file name
          if (m.text.isNotEmpty) {
            msg.textElem = V2TimTextElem(text: m.text);
          } else {
            msg.textElem = V2TimTextElem(text: fileName);
          }
          break;
        case 'video':
          // Set video element with proper V2TimVideoElem (UIKit expects videoElem for video messages)
          final isReceivingVideo = m.filePath != null && m.filePath!.startsWith('/tmp/receiving_');
          final videoFileExists = m.filePath != null ? file.existsSync() : false;
          final videoFileSize = videoFileExists ? file.lengthSync() : null;
          final videoProgress = _fileProgress[m.msgID];
          // Determine localVideoUrl using same logic as file/image
          String? localVideoUrl;
          if (!m.isPending && m.filePath != null && !isReceivingVideo) {
            localVideoUrl = m.filePath;
          } else if (videoProgress != null && videoProgress.received >= videoProgress.total && videoProgress.total > 0) {
            if (videoProgress.path != null && !videoProgress.path!.startsWith('/tmp/receiving_')) {
              localVideoUrl = videoProgress.path;
            } else if (m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
              localVideoUrl = m.filePath;
            }
          } else if (!isReceivingVideo && m.filePath != null && videoFileExists) {
            localVideoUrl = m.filePath;
          }
          // Check file_recv/avatars directory
          if (localVideoUrl == null && m.filePath != null && (m.filePath!.contains('/file_recv/') || m.filePath!.contains('/avatars/'))) {
            final f = File(m.filePath!);
            if (f.existsSync()) {
              localVideoUrl = m.filePath;
            }
          }
          final videoUuid = m.msgID.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          String? videoUrl;
          if (m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
            videoUrl = m.filePath;
          } else if (localVideoUrl != null && !localVideoUrl.startsWith('/tmp/receiving_')) {
            videoUrl = localVideoUrl;
          }
          final videoElemPath = (localVideoUrl != null && !localVideoUrl.startsWith('/tmp/receiving_'))
              ? localVideoUrl
              : ((m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_'))
                  ? m.filePath
                  : m.filePath);
          msg.videoElem = V2TimVideoElem(
            videoPath: videoElemPath,
            UUID: videoUuid,
            videoSize: videoFileSize ?? (videoProgress != null ? videoProgress.total : null),
            // TODO(P1-11): real duration is not available from the Tox file
            // transfer envelope. Probing via dart:io is non-trivial without
            // adding a media-decoding dep; leave as 0 and wire a real
            // duration after _handleFileDone once a decode helper exists.
            duration: 0,
            videoUrl: videoUrl,
            localVideoUrl: localVideoUrl,
          );
          if (m.text.isNotEmpty) {
            msg.textElem = V2TimTextElem(text: m.text);
          } else {
            msg.textElem = V2TimTextElem(text: fileName);
          }
          break;
        case 'audio':
          // Set sound element with proper V2TimSoundElem (UIKit expects soundElem for audio messages)
          final isReceivingAudio = m.filePath != null && m.filePath!.startsWith('/tmp/receiving_');
          final audioFileExists = m.filePath != null ? file.existsSync() : false;
          final audioFileSize = audioFileExists ? file.lengthSync() : null;
          final audioProgress = _fileProgress[m.msgID];
          // Determine localUrl using same logic as file/image
          String? audioLocalUrl;
          if (!m.isPending && m.filePath != null && !isReceivingAudio) {
            audioLocalUrl = m.filePath;
          } else if (audioProgress != null && audioProgress.received >= audioProgress.total && audioProgress.total > 0) {
            if (audioProgress.path != null && !audioProgress.path!.startsWith('/tmp/receiving_')) {
              audioLocalUrl = audioProgress.path;
            } else if (m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
              audioLocalUrl = m.filePath;
            }
          } else if (!isReceivingAudio && m.filePath != null && audioFileExists) {
            audioLocalUrl = m.filePath;
          }
          // Check file_recv/avatars directory
          if (audioLocalUrl == null && m.filePath != null && (m.filePath!.contains('/file_recv/') || m.filePath!.contains('/avatars/'))) {
            final f = File(m.filePath!);
            if (f.existsSync()) {
              audioLocalUrl = m.filePath;
            }
          }
          final audioUuid = m.msgID.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          String? audioUrl;
          if (m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
            audioUrl = m.filePath;
          } else if (audioLocalUrl != null && !audioLocalUrl.startsWith('/tmp/receiving_')) {
            audioUrl = audioLocalUrl;
          }
          final soundElemPath = (audioLocalUrl != null && !audioLocalUrl.startsWith('/tmp/receiving_'))
              ? audioLocalUrl
              : ((m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_'))
                  ? m.filePath
                  : m.filePath);
          msg.soundElem = V2TimSoundElem(
            path: soundElemPath,
            UUID: audioUuid,
            dataSize: audioFileSize ?? (audioProgress != null ? audioProgress.total : null),
            // TODO(P1-11): real duration is not available from the Tox file
            // transfer envelope. Probing audio length via dart:io is
            // non-trivial without adding a media-decoding dep; leave as 0
            // and wire a real duration after _handleFileDone once a
            // decode helper exists.
            duration: 0,
            url: audioUrl,
            localUrl: audioLocalUrl,
          );
          if (m.text.isNotEmpty) {
            msg.textElem = V2TimTextElem(text: m.text);
          } else {
            msg.textElem = V2TimTextElem(text: fileName);
          }
          break;
        default:
          // For unknown types, use text element
          if (m.text.isNotEmpty) {
            msg.textElem = V2TimTextElem(text: m.text);
          } else if (m.filePath != null) {
            msg.textElem = V2TimTextElem(text: fileName);
          }
      }
    } else {
      // No file path - just set text element
      // CRITICAL: For text messages, always set textElem even if text is empty
      // This ensures text messages have content (even if empty string)
      // For failed messages restored from persistence, text might be empty but we still need textElem
      // Since FakeMessage doesn't have elemType, we determine if it's a text message by checking if there's no filePath
      // If there's no filePath and no mediaKind, it's likely a text message
      if (m.filePath == null && m.mediaKind == null) {
        // This is likely a text message - always set textElem
        msg.textElem = V2TimTextElem(text: m.text.isNotEmpty ? m.text : '');
      } else if (m.text.isNotEmpty) {
        // For other message types, only set textElem if text is not empty
        msg.textElem = V2TimTextElem(text: m.text);
      }
    }

    // P2-4: if mediaKind landed on an unknown value (e.g. a new sender
    // emitted a kind we don't yet recognise), render a placeholder
    // instead of an empty bubble. Preserves the original text in the
    // brackets so power users / log readers can still see what arrived.
    if (isUnknownCustom && (msg.textElem == null || (msg.textElem!.text ?? '').isEmpty)) {
      final preview = m.text.isNotEmpty
          ? (m.text.length > 32 ? m.text.substring(0, 32) : m.text)
          : (m.mediaKind ?? 'unknown');
      msg.textElem = V2TimTextElem(text: '[Unsupported message: $preview]');
    }

    final selfId = UikitDataFacade.currentUser?.userID;
    // Normalize IDs for comparison (Tox IDs can be 64 or 76 characters)
    msg.isSelf = (selfId != null && compareToxIds(m.fromUser, selfId));

    // Set custom data for pending status (if message is pending).
    //
    // P2-3: previously we always overwrote customElem.data, which
    // clobbered legitimate payloads (e.g. call_record JSON) when a
    // pending file/text message happened to also carry customElem.
    // Today the call_record path runs through `_mapCallRecordMsg` and
    // never reaches this branch, but the safety guard makes the
    // invariant explicit: only set the pending marker when there is no
    // existing customElem.data we'd be destroying. We also surface
    // `isPending` via `localCustomInt` so downstream code can read it
    // without parsing JSON. TODO(P2-3): migrate all downstream readers
    // of `'"isPending":true'` to `localCustomInt == 1` and drop the
    // string sentinel entirely.
    if (m.isPending) {
      msg.localCustomInt = 1;
      final existing = msg.customElem?.data;
      if (existing == null || existing.isEmpty) {
        msg.customElem = V2TimCustomElem(data: '{"isPending":true}');
      }
    }

    // Set message status and read receipt status
    // UIKit uses status field: 1=SENDING, 2=SEND_SUCC, 3=SEND_FAIL
    // For self-sent messages, set status based on receipt
    if (msg.isSelf ?? false) {
      if (m.isPending) {
        // Check if this is an old message (likely from before client restart)
        // If message is older than 10 seconds, it's likely a pending message from before restart
        // and should be marked as failed. This handles the case where client restarted
        // and old pending messages are loaded from history.
        final messageAge = DateTime.now().millisecondsSinceEpoch - m.timestampMs;
        if (messageAge > 10000) {
          // Old pending message (likely from before restart) - mark as failed
          msg.status = 3; // V2TIM_MSG_STATUS_SEND_FAIL
        } else {
          // New pending message (just sent, less than 10 seconds old) - mark as sending
          // Note: If message fails to send (e.g., friend is offline), sendMessageFinalPhase
          // will update the status to SEND_FAIL via messageNeedUpdate
          msg.status = 1; // V2TIM_MSG_STATUS_SENDING
        }
      } else if (m.isRead) {
        msg.status = 2; // V2TIM_MSG_STATUS_SEND_SUCC
        msg.isPeerRead = true; // Message has been read
      } else if (m.isReceived) {
        msg.status = 2; // V2TIM_MSG_STATUS_SEND_SUCC
        msg.isPeerRead = false; // Message received but not read yet
      } else {
        msg.status = 2; // V2TIM_MSG_STATUS_SEND_SUCC (default for sent messages)
        msg.isPeerRead = false;
      }
    } else {
      // For received messages, status is always SEND_SUCC
      msg.status = 2; // V2TIM_MSG_STATUS_SEND_SUCC
    }

    // Set faceUrl for avatar display
    // For self messages, use cached avatar path
    // For others' messages, get from friend avatar path storage
    // Note: UIKit now supports local file paths, so we can set faceUrl for all valid paths
    if (msg.isSelf ?? false) {
      if (_cachedSelfAvatarPath != null && _cachedSelfAvatarPath!.isNotEmpty) {
        msg.faceUrl = _cachedSelfAvatarPath;
      }
    } else {
      String? friendAvatarPath = _cachedFriendAvatars[m.fromUser];
      if (friendAvatarPath == null) {
        Prefs.getFriendAvatarPath(m.fromUser).then((avatarPath) {
          if (avatarPath != null && avatarPath.isNotEmpty) {
            _cachedFriendAvatars[m.fromUser] = avatarPath;
          } else {
            _cachedFriendAvatars[m.fromUser] = '';
          }
        });
      } else if (friendAvatarPath.isNotEmpty) {
        msg.faceUrl = friendAvatarPath;
      }
    }

    return msg;
  }

  Future<void> _loadHistoryForConversation(String conversationID) async {
    final mgr = FakeUIKit.instance.messageManager;
    if (mgr == null) {
      return;
    }

    try {
      final hist = await mgr.getHistory(conversationID);

      // Pre-load avatars for all message senders so _mapMsg can set faceUrl synchronously.
      // Without this, the async cache is empty when history messages are first mapped,
      // causing all message bubbles to fall back to the default avatar.
      final ffiInstance = FakeUIKit.instance.im?.ffi;
      final selfId = ffiInstance?.selfId;
      if (_cachedSelfAvatarPath == null) {
        _cachedSelfAvatarPath = await Prefs.getAvatarPath();
      }
      final senderIds = hist.map((h) => h.fromUser).whereType<String>().toSet();
      for (final senderId in senderIds) {
        if (senderId == selfId) continue;
        if (!_cachedFriendAvatars.containsKey(senderId)) {
          final avatarPath = await Prefs.getFriendAvatarPath(senderId);
          _cachedFriendAvatars[senderId] = avatarPath ?? '';
        }
      }

      // Ensure buffer exists (it should be created by streamFor, but create it here if missing)
      if (!_buffers.containsKey(conversationID)) {
        _buffers[conversationID] = <V2TimMessage>[];
      }

      final list = _buffers[conversationID]!;

      // Extract userID and groupID from conversationID for restoring failed messages
      String? userID;
      String? groupID;
      if (conversationID.startsWith('c2c_')) {
        userID = conversationID.substring(4);
      } else if (conversationID.startsWith('group_')) {
        groupID = conversationID.substring(6);
      }

      // P2-6: load the failed-message persistence once and reuse across
      // both passes (restore-missing + restore-failed-status). The
      // previous code re-read SharedPreferences and re-parsed JSON twice
      // per page open; this is now a single fetch.
      List<Map<String, dynamic>> cachedFailedMessages = <Map<String, dynamic>>[];
      try {
        final currentToxId = await Prefs.getCurrentAccountToxId();
        cachedFailedMessages =
            await Tim2ToxFailedMessagePersistence.loadFailedMessages(
          userID: userID,
          groupID: groupID,
          accountToxId: currentToxId,
        );
      } catch (e) {
        AppLogger.logError(
            '[FakeChatMessageProvider] _loadHistoryForConversation: Error loading failed messages: $e',
            e);
      }

      // Restore failed messages from persistence (pass 1: backfill missing
      // history entries with their persisted failed copy).
      try {
        final failedMessagesData = cachedFailedMessages;
        if (failedMessagesData.isNotEmpty) {
          // Create a set of existing message IDs for quick lookup
          // FakeMessage only has msgID, not id
          final existingMsgIDs = hist.map((h) => h.msgID).whereType<String>().toSet();

          for (final failedMsgData in failedMessagesData) {
            final msgID = failedMsgData['msgID'] as String?;
            final id = failedMsgData['id'] as String?;

            // Check if message already exists in history
            // Check by msgID (FakeMessage only has msgID)
            bool messageExists = false;
            if (msgID != null && existingMsgIDs.contains(msgID)) {
              messageExists = true;
            } else if (id != null && existingMsgIDs.contains(id)) {
              // Also check if id matches msgID (some messages use id as msgID)
              messageExists = true;
            }

            // If message doesn't exist in history, add it as a failed message
            if (!messageExists && msgID != null) {
              // CRITICAL: For self-sent failed messages, fromUser should be selfId, not userID (receiver)
              // userID is the receiver (the other person), but fromUser should be the sender (self)
              final ffi = FakeUIKit.instance.im?.ffi;
              final selfId = ffi?.selfId ?? '';
              final isSelf = failedMsgData['isSelf'] as bool? ?? true;
              // For self-sent messages, fromUser should be selfId
              // For received messages, fromUser should be the sender (which would be in userID field)
              final fromUser = isSelf ? selfId : (failedMsgData['userID'] as String? ?? userID ?? '');
              // CRITICAL: Try to recover text content from history if it's empty in persistence
              // This handles the case where text was lost during persistence
              String text = failedMsgData['text'] as String? ?? '';
              if (text.isEmpty) {
                // Try to find the message in history by msgID to recover text
                try {
                  final historyMsg = hist.firstWhere((h) => h.msgID == msgID);
                  if (historyMsg.text.isNotEmpty) {
                    text = historyMsg.text;
                  }
                } catch (e) {
                  // Message not found in history, text remains empty
                }
              }

              // Add to history list as FakeMessage (will be converted to V2TimMessage below)
              hist.add(FakeMessage(
                msgID: msgID,
                conversationID: conversationID,
                fromUser: fromUser,
                text: text,
                timestampMs: (failedMsgData['timestamp'] as int? ?? (DateTime.now().millisecondsSinceEpoch / 1000).ceil()) * 1000,
                isPending: false,
                isReceived: true,
                isRead: false,
              ));
            }
          }
        }
      } catch (e) {
        // Ignore errors during failed message restoration
      }

      // Only clear and reload if we have history messages to load
      // If hist is empty, keep existing messages in buffer (they might not be saved yet)
      if (hist.isNotEmpty) {
        // Preserve messages in buffer that are not in history (e.g., failed messages that weren't saved)
        // These messages have temporary IDs like "created_temp_id-1" and won't be in history
        final historyMsgIDs = hist.map((h) => h.msgID).toSet();

        // Find messages in buffer that are not in history (failed messages, unsent messages, etc.)
        final messagesToPreserve = list.where((msg) {
          final msgID = msg.msgID;
          // Preserve messages with temporary IDs (created_temp_id-*) or messages not in history
          return msgID != null &&
                 (msgID.startsWith('created_temp_id-') ||
                  !historyMsgIDs.contains(msgID));
        }).toList();

        // Clear existing list and add history messages
        list.clear();
        V2TimMessage? latestMessage; // Track the latest message for conversation list update

        // Create a set of failed message IDs for quick lookup.
        // P2-6: reuse the already-loaded `cachedFailedMessages` instead
        // of re-reading SharedPreferences.
        final failedMsgIDs = <String>{};
        final failedMsgDataMap = <String, Map<String, dynamic>>{};
        for (final failedMsgData in cachedFailedMessages) {
          final msgID = failedMsgData['msgID'] as String?;
          final id = failedMsgData['id'] as String?;
          if (msgID != null) {
            failedMsgIDs.add(msgID);
            failedMsgDataMap[msgID] = failedMsgData;
          }
          if (id != null && id != msgID) {
            failedMsgIDs.add(id);
            failedMsgDataMap[id] = failedMsgData;
          }
        }

        for (final h in hist) {
          final msg = _mapMsg(h);
          // If message status is SENDING (1), set it to FAIL (3) since client restarted
          // Messages that were sending when client restarted should be marked as failed
          if (msg.status == 1) {
            msg.status = 3; // V2TIM_MSG_STATUS_SEND_FAIL
          }
          // CRITICAL: Check if message is in failed messages list and restore failed status
          // This ensures that failed messages remain failed even after switching pages and reloading
          // History messages might have success status, but we trust the persistence
          final msgID = msg.msgID;
          final id = msg.id;
          if ((msgID != null && failedMsgIDs.contains(msgID)) ||
              (id != null && failedMsgIDs.contains(id))) {
            // Message is in failed list - mark as failed regardless of current status
            msg.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
            // Also restore textElem if it's missing
            final failedMsgData = failedMsgDataMap[msgID ?? id ?? ''];
            if (failedMsgData != null && msg.textElem == null &&
                (msg.elemType == MessageElemType.V2TIM_ELEM_TYPE_TEXT ||
                 failedMsgData['elemType'] == MessageElemType.V2TIM_ELEM_TYPE_TEXT)) {
              final text = failedMsgData['text'] as String?;
              if (text != null && text.isNotEmpty) {
                msg.textElem = V2TimTextElem(text: text);
                msg.elemList.clear();
                msg.elemList.add(msg.textElem!);
              }
            }
          }
          list.add(msg);
          // Track the latest message (highest timestamp)
          if (latestMessage == null || (msg.timestamp ?? 0) > (latestMessage.timestamp ?? 0)) {
            latestMessage = msg;
          }
        }

        // Add back preserved messages (failed messages, unsent messages, etc.)
        list.addAll(messagesToPreserve);

        // Sort by timestamp ascending (oldest first, newest last)
        list.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));

        // IMPORTANT: Update conversation lastMessage after restoring failed messages
        // This ensures the latest message (including restored failed messages) appears in conversation list
        if (list.isNotEmpty) {
          // Find the actual latest message (after sorting)
          // The list is sorted by timestamp ascending, so the last element is the newest
          final actualLatestMessage = list.last;

          // CRITICAL: Check if there's a failed message in the list that is the latest
          // Failed messages should already be in the list (restored from persistence)
          // If the latest message is failed, we want to use it to update the conversation
          // Otherwise, we use the latest message (which might be a successful message)
          final messageToUse = actualLatestMessage;

          // Ensure userID and groupID are set for conversation identification
          if (messageToUse.userID == null && userID != null) {
            messageToUse.userID = userID;
          }
          if (messageToUse.groupID == null && groupID != null) {
            messageToUse.groupID = groupID;
          }

          // Trigger onReceiveNewMessage to update conversation list
          // This ensures the latest message (including failed messages) appears in the conversation list's second line
          UikitDataFacade.onReceiveNewMessage(messageToUse);
        }
      } else {
        // If no history loaded, check if we have messages in buffer
        // If buffer is empty, this might be a new conversation or history hasn't loaded yet
        // Don't clear the buffer in this case - keep any existing messages
        // But still emit to stream to ensure UI is updated (even if empty)
      }

      // Always emit to stream, even if list is empty
      // This ensures UI is updated when history is loaded (or when no history exists)
      // UIKit's getMessageListForRender reverses the list, but our stream bypasses it
      // So we need to reverse the list before emitting to match UIKit's expected format
      // Reverse: newest first, oldest last (for reverse ListView, index 0 = newest at bottom)
      final ctrl = _ctrls[conversationID];
      if (ctrl != null && !ctrl.isClosed) {
        final reversedList = List<V2TimMessage>.from(list.reversed);
        ctrl.add(reversedList);
      }
    } catch (e) {
      // Ignore errors during history loading
    }
  }
}
