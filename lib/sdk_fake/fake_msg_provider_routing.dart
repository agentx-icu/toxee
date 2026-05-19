// Stream-routing / per-conversation dedup logic for FakeChatMessageProvider.
//
// Originally inline inside the FakeChatMessageProvider constructor as the body
// of `FakeUIKit.instance.eventBusInstance.on<FakeMessage>(FakeIM.topicMessage).listen(...)`.
// Extracted as a `part of` method (`_onTopicMessage`) so the constructor can
// just hook it up via `.listen(_onTopicMessage)`.
//
// Concerns covered here:
//   * Per-conversation buffer maintenance keyed by `m.conversationID`.
//   * Avatar pre-loading so the first map call has a cached friend avatar.
//   * Existing-by-msgID update path (file_done / progress / status transitions),
//     including the messageNeedUpdate writes via `UikitDataFacade`
//     (forwards to `TencentCloudChat.instance.dataInstance.messageData`).
//   * `created_temp_id-*` dedup with the ~2s window (actually <5s) for resends.
//   * `_mapMsgWithFailedCheck` — wraps `_mapMsg` and restores SEND_FAIL status
//     from `Tim2ToxFailedMessagePersistence`.

part of 'fake_msg_provider.dart';

extension _FakeChatMessageProviderRouting on FakeChatMessageProvider {
  Future<void> _onTopicMessage(FakeMessage m) async {
    final conv = m.conversationID;
    AppLogger.log('[FakeMessageProvider] EventBus received: msgID=${m.msgID}, conv=$conv, mediaKind=${m.mediaKind}, fromUser=${m.fromUser}');
    final list = _buffers.putIfAbsent(conv, () => <V2TimMessage>[]);
    // Pre-load avatar if not in cache to ensure new messages show correct avatar immediately
    // Note: FakeMessage doesn't have isSelf, so we check by comparing fromUser with selfId
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi != null) {
      final isSelf = m.fromUser == ffi.selfId;
      if (!isSelf && _cachedFriendAvatars[m.fromUser] == null) {
        try {
          final avatarPath = await Prefs.getFriendAvatarPath(m.fromUser);
          if (avatarPath != null && avatarPath.isNotEmpty) {
            _cachedFriendAvatars[m.fromUser] = avatarPath;
          } else {
            _cachedFriendAvatars[m.fromUser] = '';
          }
        } catch (e) {
          _cachedFriendAvatars[m.fromUser] = '';
        }
      }
    }
    final mappedMsg = await _mapMsgWithFailedCheck(m);
    // Check if message already exists by msgID
    final existingIndex = list.indexWhere((msg) => msg.msgID == mappedMsg.msgID);
    if (existingIndex >= 0) {
      // Message exists - update it (important for file_done updates that change filePath and isPending)
      // CRITICAL: If file is complete (isPending=false and filePath is not in /tmp/receiving_), clear _fileProgress
      // This ensures UI doesn't show spinning state for completed files
      if (!m.isPending && m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
        final hadProgress = _fileProgress.containsKey(mappedMsg.msgID);
        if (hadProgress) {
          final oldProgress = _fileProgress[mappedMsg.msgID];
          _fileProgress.remove(mappedMsg.msgID);
          AppLogger.log('[FakeMessageProvider] ✅ File completed via file_done, removed from _fileProgress for msgID=${mappedMsg.msgID}, filePath=${m.filePath} (old progress: ${oldProgress?.received}/${oldProgress?.total})');
        } else {
          AppLogger.log('[FakeMessageProvider] File completed via file_done for msgID=${mappedMsg.msgID}, filePath=${m.filePath} (no _fileProgress entry)');
        }
      } else {
        AppLogger.log('[FakeMessageProvider] File message update: msgID=${mappedMsg.msgID}, isPending=${m.isPending}, filePath=${m.filePath}');
      }
      list[existingIndex] = mappedMsg;
      // Sort by timestamp ascending (oldest first, newest last)
      list.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
      // UIKit's getMessageListForRender reverses the list, but our stream bypasses it
      // So we need to reverse the list before emitting to match UIKit's expected format
      // Reverse: newest first, oldest last (for reverse ListView, index 0 = newest at bottom)
      // Always create new message objects for the reversed list to ensure Flutter detects changes
      final reversedList = List<V2TimMessage>.from(list.map((msg) {
        // Always create a new message object to ensure Flutter detects the change
        // This is especially important for file messages where localUrl changes
        // CRITICAL: Use mappedMsg.elemType if this is the updated message, otherwise use msg.elemType
        final elemType = (msg.msgID == mappedMsg.msgID) ? mappedMsg.elemType : msg.elemType;
        final newMsg = V2TimMessage(elemType: elemType);
        // Copy all properties
        newMsg.msgID = msg.msgID;
        newMsg.userID = msg.userID;
        newMsg.timestamp = msg.timestamp;
        newMsg.isSelf = msg.isSelf;
        newMsg.sender = msg.sender;
        newMsg.groupID = msg.groupID;
        newMsg.textElem = msg.textElem;
        // CRITICAL: Recreate imageElem to ensure Flutter detects changes in imageList.localUrl
        // This is essential for images that are updated after file_done event
        if (msg.imageElem != null) {
          final oldImageElem = msg.imageElem!;
          // CRITICAL: If this is the updated message (msg.msgID == mappedMsg.msgID), use mappedMsg.imageElem directly
          // Otherwise, use msg.imageElem (which may have been updated by _mapMsg if msg == mappedMsg)
          String? effectiveLocalUrl;
          // Priority 1: Check if msg is the updated message, use mappedMsg.imageElem directly
          if (msg.msgID == mappedMsg.msgID && mappedMsg.imageElem != null) {
            final mappedImageElem = mappedMsg.imageElem!;
            // Check mappedMsg.imageElem.path
            if (mappedImageElem.path != null && (mappedImageElem.path!.contains('/avatars/') || mappedImageElem.path!.contains('/file_recv/'))) {
              final file = File(mappedImageElem.path!);
              if (file.existsSync()) {
                effectiveLocalUrl = mappedImageElem.path;
              }
            }
            // Check mappedMsg.imageElem.imageList.localUrl
            if (effectiveLocalUrl == null && mappedImageElem.imageList != null) {
              for (final img in mappedImageElem.imageList!) {
                if (img != null && img.localUrl != null && img.localUrl!.isNotEmpty) {
                  effectiveLocalUrl = img.localUrl;
                  break;
                }
              }
            }
            // Use mappedMsg.imageElem directly if it has imageList with localUrl
            if (effectiveLocalUrl != null) {
              // Create new imageList with updated localUrl
              // CRITICAL: Preserve uuid and url from mappedMsg.imageElem if available
              String? preservedUuid;
              String? preservedUrl;
              if (mappedImageElem.imageList != null) {
                for (final img in mappedImageElem.imageList!) {
                  if (img != null && img.uuid != null) {
                    preservedUuid = img.uuid;
                    break;
                  }
                }
                for (final img in mappedImageElem.imageList!) {
                  if (img != null && img.url != null && !img.url!.startsWith('/tmp/receiving_')) {
                    preservedUrl = img.url;
                    break;
                  }
                }
              }
              final thumbImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB);
              thumbImage.localUrl = effectiveLocalUrl;
              if (preservedUuid != null) {
                thumbImage.uuid = preservedUuid;
              }
              if (preservedUrl != null) {
                thumbImage.url = preservedUrl;
              } else if (effectiveLocalUrl != null && !effectiveLocalUrl.startsWith('/tmp/receiving_')) {
                // Use localUrl as url if it's not a temp path
                thumbImage.url = effectiveLocalUrl;
              }
              final newImageList = [thumbImage];
              final originImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN);
              originImage.localUrl = effectiveLocalUrl;
              if (preservedUuid != null) {
                originImage.uuid = preservedUuid;
              }
              if (preservedUrl != null) {
                originImage.url = preservedUrl;
              } else if (effectiveLocalUrl != null && !effectiveLocalUrl.startsWith('/tmp/receiving_')) {
                // Use localUrl as url if it's not a temp path
                originImage.url = effectiveLocalUrl;
              }
              newImageList.add(originImage);
              newMsg.imageElem = V2TimImageElem(
                path: mappedImageElem.path,
                imageList: newImageList,
              );
              AppLogger.log('[FakeMessageProvider] Updated imageElem for msgID=${msg.msgID}: path=${mappedImageElem.path}, localUrl=$effectiveLocalUrl, newMsg.imageElem.path=${newMsg.imageElem?.path}');
            } else {
              // Use mappedMsg.imageElem as-is (it should have been set correctly by _mapMsg)
              // CRITICAL: Always create new V2TimImage objects to ensure Flutter detects changes
              // CRITICAL: Must copy uuid field for downloadMessage to work
              // CRITICAL: Don't preserve /tmp/receiving_ paths as url - they will fail when used as online URLs
              newMsg.imageElem = V2TimImageElem(
                path: mappedImageElem.path,
                imageList: mappedImageElem.imageList?.map((img) {
                  if (img == null) return null;
                  final newImg = V2TimImage(type: img.type);
                  newImg.uuid = img.uuid; // CRITICAL: Copy uuid for downloadMessage
                  newImg.localUrl = img.localUrl;
                  // Only preserve url if it's not a temporary receiving path
                  if (img.url != null && !img.url!.startsWith('/tmp/receiving_')) {
                    newImg.url = img.url;
                  }
                  // If url was a temp path but localUrl is available and not a temp path, use localUrl as url
                  else if (img.localUrl != null && !img.localUrl!.startsWith('/tmp/receiving_')) {
                    newImg.url = img.localUrl;
                  }
                  newImg.width = img.width;
                  newImg.height = img.height;
                  newImg.size = img.size;
                  return newImg;
                }).toList(),
              );
              final mappedImageList = mappedImageElem.imageList;
              String? mappedLocalUrl;
              if (mappedImageList != null) {
                for (final img in mappedImageList) {
                  if (img != null && img.localUrl != null && img.localUrl!.isNotEmpty) {
                    mappedLocalUrl = img.localUrl;
                    break;
                  }
                }
              }
              AppLogger.log('[FakeMessageProvider] Updated imageElem for msgID=${msg.msgID}: path=${mappedImageElem.path}, imageList.localUrl=$mappedLocalUrl, newMsg.imageElem.path=${newMsg.imageElem?.path}');
            }
          } else {
            // Not the updated message, use msg.imageElem (which may have been updated by _mapMsg)
            // Check oldImageElem.path
            if (oldImageElem.path != null && (oldImageElem.path!.contains('/avatars/') || oldImageElem.path!.contains('/file_recv/'))) {
              final file = File(oldImageElem.path!);
              if (file.existsSync()) {
                effectiveLocalUrl = oldImageElem.path;
              }
            }
            // Check oldImageElem.imageList.localUrl
            if (effectiveLocalUrl == null && oldImageElem.imageList != null) {
              for (final img in oldImageElem.imageList!) {
                if (img != null && img.localUrl != null && img.localUrl!.isNotEmpty) {
                  effectiveLocalUrl = img.localUrl;
                  break;
                }
              }
            }
            // Recreate imageList with new V2TimImage objects to ensure Flutter detects changes
            List<V2TimImage?>? newImageList;
            if (effectiveLocalUrl != null) {
              // Create new imageList with updated localUrl
              // CRITICAL: Preserve uuid and url from oldImageElem.imageList if available
              String? preservedUuid;
              String? preservedUrl;
              if (oldImageElem.imageList != null) {
                for (final img in oldImageElem.imageList!) {
                  if (img != null && img.uuid != null) {
                    preservedUuid = img.uuid;
                    break;
                  }
                }
                for (final img in oldImageElem.imageList!) {
                  if (img != null && img.url != null && !img.url!.startsWith('/tmp/receiving_')) {
                    preservedUrl = img.url;
                    break;
                  }
                }
              }
              final thumbImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB);
              thumbImage.localUrl = effectiveLocalUrl;
              if (preservedUuid != null) {
                thumbImage.uuid = preservedUuid;
              }
              if (preservedUrl != null) {
                thumbImage.url = preservedUrl;
              } else if (effectiveLocalUrl != null && !effectiveLocalUrl.startsWith('/tmp/receiving_')) {
                // Use localUrl as url if it's not a temp path
                thumbImage.url = effectiveLocalUrl;
              }
              newImageList = [thumbImage];
              final originImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN);
              originImage.localUrl = effectiveLocalUrl;
              if (preservedUuid != null) {
                originImage.uuid = preservedUuid;
              }
              if (preservedUrl != null) {
                originImage.url = preservedUrl;
              } else if (effectiveLocalUrl != null && !effectiveLocalUrl.startsWith('/tmp/receiving_')) {
                // Use localUrl as url if it's not a temp path
                originImage.url = effectiveLocalUrl;
              }
              newImageList.add(originImage);
            } else if (oldImageElem.imageList != null) {
              // No localUrl available, but preserve existing imageList structure
              // CRITICAL: Must copy uuid field for downloadMessage to work
              // CRITICAL: Don't preserve /tmp/receiving_ paths as url - they will fail when used as online URLs
              newImageList = oldImageElem.imageList!.map((img) {
                if (img == null) return null;
                final newImg = V2TimImage(type: img.type);
                newImg.uuid = img.uuid; // CRITICAL: Copy uuid for downloadMessage
                newImg.localUrl = img.localUrl;
                // Only preserve url if it's not a temporary receiving path
                if (img.url != null && !img.url!.startsWith('/tmp/receiving_')) {
                  newImg.url = img.url;
                }
                // If url was a temp path but localUrl is available and not a temp path, use localUrl as url
                else if (img.localUrl != null && !img.localUrl!.startsWith('/tmp/receiving_')) {
                  newImg.url = img.localUrl;
                }
                newImg.width = img.width;
                newImg.height = img.height;
                newImg.size = img.size;
                return newImg;
              }).toList();
            }
            newMsg.imageElem = V2TimImageElem(
              path: oldImageElem.path,
              imageList: newImageList,
            );
          }
        } else {
          // No imageElem in original message, but check if mappedMsg has imageElem
          // This handles the case where message type changed or imageElem was added
          if (msg.msgID == mappedMsg.msgID && mappedMsg.imageElem != null) {
            // Use mappedMsg.imageElem directly
            newMsg.imageElem = mappedMsg.imageElem;
          } else {
            newMsg.imageElem = msg.imageElem;
          }
        }
        // Handle videoElem: use mappedMsg if this is the updated message
        if (msg.msgID == mappedMsg.msgID && mappedMsg.videoElem != null) {
          newMsg.videoElem = mappedMsg.videoElem;
        } else {
          newMsg.videoElem = msg.videoElem;
        }
        // Handle soundElem: use mappedMsg if this is the updated message
        if (msg.msgID == mappedMsg.msgID && mappedMsg.soundElem != null) {
          newMsg.soundElem = mappedMsg.soundElem;
        } else {
          newMsg.soundElem = msg.soundElem;
        }
        // CRITICAL: Recreate fileElem to ensure Flutter detects changes in localUrl
        // This is essential for file messages that are updated after file reception
        if (msg.fileElem != null) {
          final oldFileElem = msg.fileElem!;
          // CRITICAL: If this is the updated message (msg.msgID == mappedMsg.msgID), use mappedMsg.fileElem directly
          // Otherwise, ensure we preserve localUrl if file is already received
          if (msg.msgID == mappedMsg.msgID && mappedMsg.fileElem != null) {
            // Use mappedMsg.fileElem directly (it should have been set correctly by _mapMsg)
            newMsg.fileElem = mappedMsg.fileElem;
          } else {
            // Not the updated message, but ensure we preserve localUrl if file is already received
            // Check if fileElem.path is in file_recv directory (file already received)
            String? preservedLocalUrl = oldFileElem.localUrl;
            if (preservedLocalUrl == null || preservedLocalUrl.isEmpty) {
              // Try to recover localUrl from path if it's in file_recv directory
              if (oldFileElem.path != null && (oldFileElem.path!.contains('/file_recv/') || oldFileElem.path!.contains('/avatars/'))) {
                final file = File(oldFileElem.path!);
                if (file.existsSync()) {
                  preservedLocalUrl = oldFileElem.path;
                }
              }
            }
            // Recreate fileElem with preserved localUrl
            // CRITICAL: Don't preserve /tmp/receiving_ paths as url - they will fail when used as online URLs
            String? preservedUrl = oldFileElem.url;
            if (preservedUrl != null && preservedUrl.startsWith('/tmp/receiving_')) {
              // If url is a temp path, use localUrl as url if available and not a temp path
              if (preservedLocalUrl != null && !preservedLocalUrl.startsWith('/tmp/receiving_')) {
                preservedUrl = preservedLocalUrl;
              } else {
                preservedUrl = null; // Don't set url if it's a temp path
              }
            }
            newMsg.fileElem = V2TimFileElem(
              path: oldFileElem.path,
              fileName: oldFileElem.fileName,
              UUID: oldFileElem.UUID,
              url: preservedUrl,
              fileSize: oldFileElem.fileSize,
              localUrl: preservedLocalUrl ?? oldFileElem.localUrl, // Preserve localUrl if available
            );
          }
        } else {
          newMsg.fileElem = msg.fileElem;
        }
        newMsg.customElem = msg.customElem;
        newMsg.status = msg.status;
        newMsg.nameCard = msg.nameCard;
        newMsg.friendRemark = msg.friendRemark;
        newMsg.nickName = msg.nickName;
        newMsg.seq = msg.seq;
        newMsg.id = msg.id;
        return newMsg;
      }).toList().reversed);
      // DEBUG: Log the updated message's imageElem.path before emitting
      AppLogger.log('[FakeMessageProvider] About to emit reversedList to stream: conv=$conv, reversedList.length=${reversedList.length}, mappedMsg.msgID=${mappedMsg.msgID}');
      bool foundUpdatedMsg = false;
      for (final msg in reversedList) {
        if (msg.msgID == mappedMsg.msgID) {
          foundUpdatedMsg = true;
          AppLogger.log('[FakeMessageProvider] Found updated message in reversedList: msgID=${msg.msgID}, imageElem=${msg.imageElem != null ? "not null" : "null"}');
          if (msg.imageElem != null) {
            final imageList = msg.imageElem!.imageList;
            String? localUrl;
            if (imageList != null) {
              for (final img in imageList) {
                if (img != null && img.localUrl != null && img.localUrl!.isNotEmpty) {
                  localUrl = img.localUrl;
                  break;
                }
              }
            }
            AppLogger.log('[FakeMessageProvider] Emitting updated message to stream: msgID=${msg.msgID}, imageElem.path=${msg.imageElem!.path}, imageList.length=${imageList?.length ?? 0}, imageList.localUrl=$localUrl');
          } else {
            // Only warn if this is supposed to be an image message (elemType is IMAGE)
            // For file messages, imageElem being null is expected
            if (msg.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
              AppLogger.log('[FakeMessageProvider] WARNING: Updated image message found but imageElem is null!');
            }
          }
          break;
        }
      }
      if (!foundUpdatedMsg) {
        AppLogger.log('[FakeMessageProvider] WARNING: Updated message (msgID=${mappedMsg.msgID}) NOT found in reversedList! reversedList contains: ${reversedList.map((m) => m.msgID).join(", ")}');
      }
      AppLogger.log('[FakeMessageProvider] Calling _ctrls[$conv]?.add(reversedList) - controller exists: ${_ctrls[conv] != null}');
      _ctrls[conv]?.add(reversedList);
      AppLogger.log('[FakeMessageProvider] Successfully added reversedList to stream for conv=$conv');

      // CRITICAL: Send messageNeedUpdate event to UIKit to trigger widget refresh
      // This is essential for images that are updated after file_done event
      // UIKit's TencentCloudChatMessageImage widget listens for messageNeedUpdate events
      // to detect changes in imageElem.path and imageList.localUrl
      try {
        // Find the updated message in reversedList
        final updatedMsg = reversedList.firstWhere(
          (msg) => msg.msgID == mappedMsg.msgID,
          orElse: () => mappedMsg,
        );

        // Only send messageNeedUpdate if the message has imageElem or fileElem with updated path
        if (updatedMsg.imageElem != null) {
          final imagePath = updatedMsg.imageElem!.path;
          final hasLocalUrl = updatedMsg.imageElem!.imageList?.any((img) =>
            img != null && img.localUrl != null && img.localUrl!.isNotEmpty
          ) ?? false;

          // Send messageNeedUpdate if path is in avatars or file_recv directory (file received)
          if (imagePath != null && (imagePath.contains('/avatars/') || imagePath.contains('/file_recv/')) && hasLocalUrl) {
            AppLogger.log('[FakeMessageProvider] Sending messageNeedUpdate event for msgID=${updatedMsg.msgID}, path=$imagePath');
            UikitDataFacade.setMessageNeedUpdate(updatedMsg);
            // Extract userID/groupID from conversationID
            String? userID;
            String? groupID;
            if (conv.startsWith('c2c_')) {
              userID = conv.substring(4);
            } else if (conv.startsWith('group_')) {
              groupID = conv.substring(6);
            }
            UikitDataFacade.notifyMessageNeedUpdate(
              userID: userID,
              groupID: groupID,
            );
          }
        } else if (updatedMsg.fileElem != null) {
          // Also send messageNeedUpdate for file messages when file is received
          final filePath = updatedMsg.fileElem!.path;
          final hasLocalUrl = updatedMsg.fileElem!.localUrl != null && updatedMsg.fileElem!.localUrl!.isNotEmpty;

          // Check if message isPending status changed (from true to false) - this indicates file completion
          final customData = updatedMsg.customElem?.data;
          final isPending = customData != null && customData.contains('"isPending":true');
          final isNotPending = !isPending;

          // Send messageNeedUpdate if:
          // 1. File path is in file_recv/avatars directory and has localUrl (file received)
          // 2. OR file has localUrl and isPending is false (file completed, may be in Downloads directory)
          // This ensures UI updates even when file is moved to Downloads directory
          final shouldUpdate = (filePath != null && (filePath.contains('/file_recv/') || filePath.contains('/avatars/')) && hasLocalUrl) ||
                               (hasLocalUrl && isNotPending);

          if (shouldUpdate) {
            AppLogger.log('[FakeMessageProvider] Sending messageNeedUpdate event for file msgID=${updatedMsg.msgID}, path=$filePath, localUrl=${updatedMsg.fileElem!.localUrl}, isPending=$isPending');
            UikitDataFacade.setMessageNeedUpdate(updatedMsg);
            // Extract userID/groupID from conversationID
            String? userID;
            String? groupID;
            if (conv.startsWith('c2c_')) {
              userID = conv.substring(4);
            } else if (conv.startsWith('group_')) {
              groupID = conv.substring(6);
            }
            UikitDataFacade.notifyMessageNeedUpdate(
              userID: userID,
              groupID: groupID,
            );
          }
        } else if (updatedMsg.videoElem != null) {
          // Send messageNeedUpdate for video messages when file is received
          final videoPath = updatedMsg.videoElem!.videoPath;
          final hasLocalVideoUrl = updatedMsg.videoElem!.localVideoUrl != null && updatedMsg.videoElem!.localVideoUrl!.isNotEmpty;
          final customData = updatedMsg.customElem?.data;
          final isPending = customData != null && customData.contains('"isPending":true');
          final shouldUpdate = (videoPath != null && (videoPath.contains('/file_recv/') || videoPath.contains('/avatars/')) && hasLocalVideoUrl) ||
                               (hasLocalVideoUrl && !isPending);
          if (shouldUpdate) {
            AppLogger.log('[FakeMessageProvider] Sending messageNeedUpdate event for video msgID=${updatedMsg.msgID}, path=$videoPath, localVideoUrl=${updatedMsg.videoElem!.localVideoUrl}');
            UikitDataFacade.setMessageNeedUpdate(updatedMsg);
            String? userID;
            String? groupID;
            if (conv.startsWith('c2c_')) {
              userID = conv.substring(4);
            } else if (conv.startsWith('group_')) {
              groupID = conv.substring(6);
            }
            UikitDataFacade.notifyMessageNeedUpdate(
              userID: userID,
              groupID: groupID,
            );
          }
        } else if (updatedMsg.soundElem != null) {
          // Send messageNeedUpdate for audio messages when file is received
          final soundPath = updatedMsg.soundElem!.path;
          final hasLocalUrl = updatedMsg.soundElem!.localUrl != null && updatedMsg.soundElem!.localUrl!.isNotEmpty;
          final customData = updatedMsg.customElem?.data;
          final isPending = customData != null && customData.contains('"isPending":true');
          final shouldUpdate = (soundPath != null && (soundPath.contains('/file_recv/') || soundPath.contains('/avatars/')) && hasLocalUrl) ||
                               (hasLocalUrl && !isPending);
          if (shouldUpdate) {
            AppLogger.log('[FakeMessageProvider] Sending messageNeedUpdate event for audio msgID=${updatedMsg.msgID}, path=$soundPath, localUrl=${updatedMsg.soundElem!.localUrl}');
            UikitDataFacade.setMessageNeedUpdate(updatedMsg);
            String? userID;
            String? groupID;
            if (conv.startsWith('c2c_')) {
              userID = conv.substring(4);
            } else if (conv.startsWith('group_')) {
              groupID = conv.substring(6);
            }
            UikitDataFacade.notifyMessageNeedUpdate(
              userID: userID,
              groupID: groupID,
            );
          }
        }
      } catch (e) {
        // Ignore errors during messageNeedUpdate event emission
        AppLogger.log('[FakeMessageProvider] Error sending messageNeedUpdate: $e');
      }
    } else {
      // Message doesn't exist by msgID - check if there's a temporary message (created_temp_id-*)
      // that matches by content and timestamp (for resend scenarios)
      // This prevents duplicate messages when resending: the temporary message will be replaced
      // by the real message from FakeMessage event
      int? tempMsgIndex;
      final mappedText = mappedMsg.textElem?.text ?? '';
      final mappedTimestamp = mappedMsg.timestamp ?? 0;
      for (int i = 0; i < list.length; i++) {
        final msg = list[i];
        final msgMsgID = msg.msgID;
        final msgStatus = msg.status;
        // Check if this is a temporary message (created_temp_id-*) with status SENDING
        if (msgMsgID != null &&
            msgMsgID.startsWith('created_temp_id-') &&
            msgStatus == MessageStatus.V2TIM_MSG_STATUS_SENDING) {
          // Check if content and timestamp match (within 5 seconds tolerance for resend)
          final msgText = msg.textElem?.text ?? '';
          final msgTimestamp = msg.timestamp ?? 0;
          if (msgText == mappedText &&
              (mappedTimestamp - msgTimestamp).abs() < 5000) {
            tempMsgIndex = i;
            break;
          }
        }
      }

      if (tempMsgIndex != null) {
        // Found a temporary message that matches - replace it with the real message
        // This handles the resend scenario where a temporary message was inserted
        // and then FakeMessage event arrives with the real msgID
        list[tempMsgIndex] = mappedMsg;
        // Sort by timestamp ascending (oldest first, newest last)
        list.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
        // Emit updated list
        final reversedList = List<V2TimMessage>.from(list.reversed);
        _ctrls[conv]?.add(reversedList);
      } else {
        // New message - add it
        list.add(mappedMsg);
        // Sort by timestamp ascending (oldest first, newest last)
        list.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
        // UIKit's getMessageListForRender reverses the list, but our stream bypasses it
        // So we need to reverse the list before emitting to match UIKit's expected format
        // Reverse: newest first, oldest last (for reverse ListView, index 0 = newest at bottom)
        final reversedList = List<V2TimMessage>.from(list.reversed);
        AppLogger.log('[FakeMessageProvider] New msg added: msgID=${mappedMsg.msgID}, conv=$conv, elemType=${mappedMsg.elemType}, bufferSize=${list.length}, ctrlExists=${_ctrls[conv] != null}');
        _ctrls[conv]?.add(reversedList);
      }
    }
  }

  /// Map FakeMessage to V2TimMessage, checking failed persistence to preserve failed status
  Future<V2TimMessage> _mapMsgWithFailedCheck(FakeMessage m) async {
    final msg = _mapMsg(m);

    // P2-7: every incoming message used to re-read SharedPreferences and
    // re-decode the failed-message JSON to check a single msgID. We now
    // keep an in-memory Set<String> of failed IDs and only refresh it
    // when it's marked dirty (initial load, save, remove). Hot incoming
    // paths are now O(1).
    try {
      // Extract userID/groupID from conversationID
      String? userID;
      String? groupID;
      if (m.conversationID.startsWith('c2c_')) {
        userID = m.conversationID.substring(4);
      } else if (m.conversationID.startsWith('group_')) {
        groupID = m.conversationID.substring(6);
      }

      // Refresh the cache when dirty. We pre-load *all* keys so the
      // single Set covers every conversation in this account; the
      // marginal cost is the same as the previous per-conversation
      // read, but amortised across the whole session.
      if (_failedCacheDirty || _failedMsgIDsCache == null) {
        final currentToxId = await Prefs.getCurrentAccountToxId();
        final failedMessagesData =
            await Tim2ToxFailedMessagePersistence.loadFailedMessages(
          userID: userID,
          groupID: groupID,
          accountToxId: currentToxId,
        );
        final fresh = <String>{};
        for (final data in failedMessagesData) {
          final mid = data['msgID'] as String?;
          final id = data['id'] as String?;
          if (mid != null && mid.isNotEmpty) fresh.add(mid);
          if (id != null && id.isNotEmpty) fresh.add(id);
        }
        _failedMsgIDsCache = fresh;
        _failedCacheDirty = false;
      }

      if (_failedMsgIDsCache != null &&
          _failedMsgIDsCache!.contains(m.msgID)) {
        msg.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
      }
    } catch (e) {
      // If check fails, continue with normal mapping
    }

    return msg;
  }
}
