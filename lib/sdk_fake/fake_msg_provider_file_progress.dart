// File transfer progress handling for FakeChatMessageProvider.
//
// Originally inline inside the FakeChatMessageProvider constructor as the body
// of `ffi.progressUpdates.listen((progress) { ... })`. Extracted as a `part of`
// method (`_onFileProgress`) to keep behavior identical while reducing
// fake_msg_provider.dart size. The constructor now calls
// `ffi.progressUpdates.listen(_onFileProgress)`.
//
// Concerns covered here:
//   * Matching incoming progress events to in-buffer messages (msgID first,
//     then path/filename fallback — 3-level priority: image → video → file →
//     audio).
//   * Maintaining the `_fileProgress` map (received/total/path).
//   * Updating image/file/video/sound elements as transfers progress and
//     complete, including the temp-path → final-path swap and avoiding the
//     "completed file shows spinner" race for delayed progress_recv events.

part of 'fake_msg_provider.dart';

extension _FakeChatMessageProviderFileProgress on FakeChatMessageProvider {
  void _onFileProgress(({int instanceId, String peerId, String? path, int received, int total, bool isSend, String? msgID}) progress) {
    if (!progress.isSend && progress.path != null) {
      // File receiving progress
      // CRITICAL: Prioritize msgID matching to avoid fileNumber reuse issues
      // Find the message by msgID first (most reliable), then fall back to path matching
      V2TimMessage? matchedMsg;
      String? matchedConvID;

      // Priority 1: Match by msgID if available (most reliable, avoids fileNumber conflicts)
      if (progress.msgID != null && progress.msgID!.isNotEmpty) {
        // P1-23: always record the latest progress in `_fileProgress`,
        // even if the message isn't in `_buffers` yet (it may arrive a
        // tick later via the FakeMessage event). Previously a missing
        // buffer entry caused us to drop the progress entirely and the
        // message never advanced past 0%.
        final isComplete =
            progress.received >= progress.total && progress.total > 0;
        if (isComplete) {
          _fileProgress.remove(progress.msgID);
        } else {
          _fileProgress[progress.msgID!] = (
            received: progress.received,
            total: progress.total,
            path: progress.path,
          );
        }
        for (final entry in _buffers.entries) {
          final convID = entry.key;
          final messages = entry.value;
          try {
            final foundMsg = messages.firstWhere((msg) => msg.msgID == progress.msgID);
            // CRITICAL: Create a copy of the message to avoid modifying the original in _buffers
            // This ensures we work with the latest state from _buffers
            matchedMsg = foundMsg;
            matchedConvID = convID;
            // Skip logging match details - too frequent during file transfer
            break;
          } catch (_) {
            // msgID not found in this conversation, continue
          }
        }
        if (matchedMsg == null) {
          // P1-23: progress is now cached above; just bail out of the
          // emit/update phase. When the FakeMessage event lands, _mapMsg
          // will read `_fileProgress[msgID]` and reflect the right state.
          AppLogger.log(
              '[FakeMessageProvider] msgID=${progress.msgID} not yet in any conversation buffer; cached progress and deferred emit');
          return;
        }
      } else {
        AppLogger.log('[FakeMessageProvider] ⚠️ progress.msgID is null or empty, will use path matching');
      }

      // Priority 2: Fall back to path/filename matching ONLY if msgID was not provided
      // If msgID was provided but not found, we already returned above
      if (matchedMsg == null) {
        // CRITICAL: Extract actual filename, not the full path with fileNumber
        // Path format: .../file_recv/{uid}_{fileKind}_{fileNumber}_{originalFileName}
        // or: /tmp/receiving_{originalFileName}
        String? extractActualFileName(String? path) {
          if (path == null) return null;
          final basename = path.split('/').last;
          // Check if it's a temp path (starts with "receiving_")
          if (basename.startsWith('receiving_')) {
            return basename.substring('receiving_'.length);
          }
          // Check if it's a file_recv path with fileNumber (format: {uid}_{fileKind}_{fileNumber}_{originalFileName})
          if (basename.contains('_') && basename.length > 64) {
            final parts = basename.split('_');
            if (parts.length >= 4) {
              // Extract original filename (everything after the first 3 parts)
              return parts.sublist(3).join('_');
            }
          }
          // Otherwise, use basename as-is
          return basename;
        }

        final progressFileName = extractActualFileName(progress.path);

        for (final entry in _buffers.entries) {
          final convID = entry.key;
          final messages = entry.value;
          for (final msg in messages) {
            final msgFilePath = msg.fileElem?.path ?? msg.imageElem?.path ?? msg.videoElem?.videoPath ?? msg.soundElem?.path;
            final msgFileName = extractActualFileName(msgFilePath);
            // Remove "receiving_" prefix from temp path filename for matching (already handled in extractActualFileName)
            final msgFileNameWithoutPrefix = msgFileName;

            // Match by path (temp path or actual path), filename, or by checking if it's a pending file message
            // Check fileElem, imageElem, videoElem, and soundElem messages
            // Note: New message ID format is timestamp_userID (no file_recv_ prefix)
            // CRITICAL: Prioritize exact path matching, then filename matching
            // IMPORTANT: Only match pending files (no localUrl) to avoid matching completed files
            // This prevents fileNumber reuse from causing completed files to show as receiving
            // CRITICAL: Even for exact path match, skip completed files to prevent false matches when fileNumber is reused
            final isFilePending = msg.fileElem != null &&
                (msg.fileElem!.localUrl == null || msg.fileElem!.localUrl!.isEmpty);
            final isImagePending = msg.imageElem != null &&
                (msg.imageElem!.imageList == null || msg.imageElem!.imageList!.isEmpty ||
                 msg.imageElem!.imageList!.every((img) => img == null || img.localUrl == null || img.localUrl!.isEmpty));
            final isVideoPending = msg.videoElem != null &&
                (msg.videoElem!.localVideoUrl == null || msg.videoElem!.localVideoUrl!.isEmpty);
            final isAudioPending = msg.soundElem != null &&
                (msg.soundElem!.localUrl == null || msg.soundElem!.localUrl!.isEmpty);
            final isFileMatch = msg.fileElem != null && (
              // Exact path match (highest priority) - but only if file is pending
              (isFilePending && msg.fileElem!.path == progress.path) ||
              // Filename match only if file is still pending (no localUrl)
              (isFilePending &&
               (progressFileName != null && msgFileNameWithoutPrefix != null && progressFileName == msgFileNameWithoutPrefix)) ||
              // Filename match (fallback, but only if file is pending)
              (isFilePending &&
               (progressFileName != null && msgFileName != null && progressFileName == msgFileName))
            );
            final isImageMatch = msg.imageElem != null && (
              // Exact path match (highest priority) - but only if image is pending
              (isImagePending && msg.imageElem!.path == progress.path) ||
              // Filename match only if image is still pending (no localUrl in imageList)
              (isImagePending &&
               (progressFileName != null && msgFileNameWithoutPrefix != null && progressFileName == msgFileNameWithoutPrefix)) ||
              // Filename match (fallback, but only if image is pending)
              (isImagePending &&
               (progressFileName != null && msgFileName != null && progressFileName == msgFileName))
            );
            final isVideoMatch = msg.videoElem != null && (
              (isVideoPending && msg.videoElem!.videoPath == progress.path) ||
              (isVideoPending &&
               (progressFileName != null && msgFileNameWithoutPrefix != null && progressFileName == msgFileNameWithoutPrefix)) ||
              (isVideoPending &&
               (progressFileName != null && msgFileName != null && progressFileName == msgFileName))
            );
            final isAudioMatch = msg.soundElem != null && (
              (isAudioPending && msg.soundElem!.path == progress.path) ||
              (isAudioPending &&
               (progressFileName != null && msgFileNameWithoutPrefix != null && progressFileName == msgFileNameWithoutPrefix)) ||
              (isAudioPending &&
               (progressFileName != null && msgFileName != null && progressFileName == msgFileName))
            );
            if (isFileMatch || isImageMatch || isVideoMatch || isAudioMatch) {
              matchedMsg = msg;
              matchedConvID = convID;
              // Skip logging match details - too frequent during file transfer
              break;
            }
          }
          if (matchedMsg != null) {
            break;
          }
        }
      }

      if (matchedMsg != null && matchedConvID != null) {
        // Update progress for this message
        final msgID = matchedMsg.msgID ?? '';
        if (msgID.isNotEmpty) {
          // CRITICAL: Re-fetch the message from _buffers to ensure we have the latest state
          // This is necessary because _buffers may have been updated by a previous progress update
          // or by a file_done event, and matchedMsg may still reference the old object
          if (_buffers.containsKey(matchedConvID)) {
            try {
              final latestMsg = _buffers[matchedConvID]!.firstWhere((msg) => msg.msgID == msgID);
              final oldPath = matchedMsg?.imageElem?.path ?? matchedMsg?.fileElem?.path;
              final newPath = latestMsg.imageElem?.path ?? latestMsg.fileElem?.path;
              final oldLocalUrl = matchedMsg?.imageElem?.imageList?.cast<V2TimImage?>().firstWhere((img) => img?.localUrl != null, orElse: () => null)?.localUrl ?? matchedMsg?.fileElem?.localUrl;
              final newLocalUrl = latestMsg.imageElem?.imageList?.cast<V2TimImage?>().firstWhere((img) => img?.localUrl != null, orElse: () => null)?.localUrl ?? latestMsg.fileElem?.localUrl;
              // Skip logging re-fetch details - too frequent during file transfer
              matchedMsg = latestMsg; // Update matchedMsg to reference the latest state
            } catch (_) {
              // Message not found in _buffers, use original matchedMsg
              AppLogger.log('[FakeMessageProvider] ⚠️ Message not found in _buffers after re-fetch: msgID=$msgID, conv=$matchedConvID');
            }
          }

          // Ensure matchedMsg is not null after re-fetch
          if (matchedMsg == null) return;

          // CRITICAL: Check if file is already complete before processing progress update
          // If file is already complete (has localUrl or path in file_recv/avatars, not in /tmp/receiving_),
          // ignore subsequent progress updates to prevent re-adding to _fileProgress
          // This prevents completed files from showing spinning state when delayed progress_recv events arrive
          // IMPORTANT: Also check progress.received >= progress.total to ensure we don't ignore updates for files still receiving
          final receivedLessThanTotal = progress.received < progress.total && progress.total > 0;
          final hasLocalUrl = (matchedMsg.fileElem != null && matchedMsg.fileElem!.localUrl != null && matchedMsg.fileElem!.localUrl!.isNotEmpty) ||
                              (matchedMsg.imageElem != null && matchedMsg.imageElem!.imageList?.any((img) =>
                                img != null && img.localUrl != null && img.localUrl!.isNotEmpty
                              ) == true) ||
                              (matchedMsg.videoElem != null && matchedMsg.videoElem!.localVideoUrl != null && matchedMsg.videoElem!.localVideoUrl!.isNotEmpty) ||
                              (matchedMsg.soundElem != null && matchedMsg.soundElem!.localUrl != null && matchedMsg.soundElem!.localUrl!.isNotEmpty);
          final hasFinalPath = (matchedMsg.fileElem != null && matchedMsg.fileElem!.path != null && (
                                matchedMsg.fileElem!.path!.contains('/file_recv/') ||
                                matchedMsg.fileElem!.path!.contains('/avatars/')
                              )) ||
                              (matchedMsg.imageElem != null && matchedMsg.imageElem!.path != null && (
                                matchedMsg.imageElem!.path!.contains('/file_recv/') ||
                                matchedMsg.imageElem!.path!.contains('/avatars/')
                              )) ||
                              (matchedMsg.videoElem != null && matchedMsg.videoElem!.videoPath != null && (
                                matchedMsg.videoElem!.videoPath!.contains('/file_recv/') ||
                                matchedMsg.videoElem!.videoPath!.contains('/avatars/')
                              )) ||
                              (matchedMsg.soundElem != null && matchedMsg.soundElem!.path != null && (
                                matchedMsg.soundElem!.path!.contains('/file_recv/') ||
                                matchedMsg.soundElem!.path!.contains('/avatars/')
                              ));

          // CRITICAL: Check isPending status - if message is not pending, it's already complete
          // This is the most reliable indicator that the file transfer is complete
          // Pending status is stored in customElem.data as '{"isPending":true}'
          final customData = matchedMsg.customElem?.data;
          final isPending = customData != null && customData.contains('"isPending":true');
          final isNotPending = !isPending;

          final isAlreadyComplete = (
            // First check: If message is not pending, it's already complete (most reliable)
            isNotPending ||
            // Second check: File has localUrl (definitive completion indicator)
            hasLocalUrl ||
            // Third check: File path is in final location (and not in /tmp/receiving_)
            (hasFinalPath && !receivedLessThanTotal)
          );

          if (isAlreadyComplete) {
            // File is already complete, ignore this progress update to prevent re-adding to _fileProgress
            // CRITICAL: Also remove from _fileProgress if it exists, to prevent UI from showing spinning state
            final hadProgress = _fileProgress.containsKey(msgID);
            if (hadProgress) {
              final oldProgress = _fileProgress[msgID];
              _fileProgress.remove(msgID);
              AppLogger.log('[FakeMessageProvider] ⚠️ File already complete, removed from _fileProgress for msgID=$msgID (old progress: ${oldProgress?.received}/${oldProgress?.total})');
            } else {
              AppLogger.log('[FakeMessageProvider] File already complete, ignoring progress update for msgID=$msgID (no _fileProgress entry)');
            }
            // Skip processing this progress update - don't update _fileProgress or message elements
            // This prevents completed files from showing spinning state when delayed progress_recv events arrive
          } else {
            // CRITICAL: Clear progress when file is complete to prevent UI from showing spinning state
            // If file is complete (received >= total), remove from _fileProgress so UI knows it's done
            final isComplete = progress.received >= progress.total && progress.total > 0;
            if (isComplete) {
              final hadProgress = _fileProgress.containsKey(msgID);
              _fileProgress.remove(msgID);
              AppLogger.log('[FakeMessageProvider] ✅ File complete, cleared progress for msgID=$msgID (hadProgress=$hadProgress)');
            } else {
              final oldProgress = _fileProgress[msgID];
              _fileProgress[msgID] = (
                received: progress.received,
                total: progress.total,
                path: progress.path,
              );
              // Skip logging progress updates - too frequent during file transfer
            }
            // Update file element path if it's still using temp path
            if (matchedMsg.fileElem != null && matchedMsg.fileElem!.path?.startsWith('/tmp/receiving_') == true && progress.path != null) {
            // Recreate the file element with updated path and localUrl to ensure widget updates
            final oldFileElem = matchedMsg.fileElem!;
            final isComplete = progress.received >= progress.total && progress.total > 0;
            final newLocalUrl = isComplete ? progress.path : oldFileElem.localUrl;
            // CRITICAL: Don't use /tmp/receiving_ paths as URL
            final newFileUrl = (progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) ? progress.path : oldFileElem.url;
            // CRITICAL: Only update path if file is complete, otherwise keep temp path to prevent isAlreadyComplete from returning true prematurely
            final newPath = isComplete ? progress.path : oldFileElem.path;
            matchedMsg.fileElem = V2TimFileElem(
              path: newPath, // CRITICAL: Only update path if file is complete, otherwise keep temp path
              fileName: oldFileElem.fileName,
              fileSize: oldFileElem.fileSize ?? progress.total,
              UUID: oldFileElem.UUID,
              url: newFileUrl,
              localUrl: newLocalUrl,
            );
            // CRITICAL: Update the message in _buffers to ensure subsequent progress updates see the updated path/localUrl
            if (_buffers.containsKey(matchedConvID!)) {
              final bufferList = _buffers[matchedConvID]!;
              final bufferIndex = bufferList.indexWhere((m) => m.msgID == msgID);
              if (bufferIndex >= 0) {
                bufferList[bufferIndex] = matchedMsg;
                // Skip logging buffer updates - too frequent during file transfer
              }
            }
            // Skip logging fileElem updates - too frequent during file transfer
            } else if (matchedMsg.fileElem != null && progress.received >= progress.total && progress.total > 0) {
              // File is complete, update localUrl even if path wasn't temp
              final oldFileElem = matchedMsg.fileElem!;
              if (oldFileElem.localUrl == null || oldFileElem.localUrl!.isEmpty) {
                // CRITICAL: Don't use /tmp/receiving_ paths as URL
                final newFileUrl = (progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) ? progress.path : oldFileElem.url;
                matchedMsg.fileElem = V2TimFileElem(
                  path: oldFileElem.path ?? progress.path,
                  fileName: oldFileElem.fileName,
                  fileSize: oldFileElem.fileSize ?? progress.total,
                  UUID: oldFileElem.UUID,
                  url: newFileUrl,
                  localUrl: progress.path,
                );
                // CRITICAL: Update the message in _buffers to ensure subsequent progress updates see the updated path/localUrl
                if (_buffers.containsKey(matchedConvID!)) {
                  final bufferList = _buffers[matchedConvID]!;
                  final bufferIndex = bufferList.indexWhere((m) => m.msgID == msgID);
                  if (bufferIndex >= 0) {
                    bufferList[bufferIndex] = matchedMsg;
                    // Skip logging buffer updates - too frequent during file transfer
                  }
                }
              }
            }
            // Update image element if it's still using temp path
            if (matchedMsg.imageElem != null && matchedMsg.imageElem!.path?.startsWith('/tmp/receiving_') == true && progress.path != null) {
            // Update imageElem path and create/update imageList with localUrl
            final oldImageElem = matchedMsg.imageElem!;
            final isComplete = progress.received >= progress.total && progress.total > 0;
            final newLocalUrl = isComplete ? progress.path : null;
            // CRITICAL: Don't use /tmp/receiving_ paths as URL
            final newImageUrl = (progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) ? progress.path : null;
            // CRITICAL: Only update path if file is complete, otherwise keep temp path to prevent isAlreadyComplete from returning true prematurely
            final newPath = isComplete ? progress.path : oldImageElem.path;
            // Create imageList with localUrl if file is complete
            final imageList = <V2TimImage?>[];
            if (newLocalUrl != null) {
              final thumbImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB);
              thumbImage.localUrl = newLocalUrl;
              if (newImageUrl != null) {
                thumbImage.url = newImageUrl;
              }
              // Preserve UUID if it exists
              if (oldImageElem.imageList != null && oldImageElem.imageList!.isNotEmpty) {
                final oldImg = oldImageElem.imageList!.cast<V2TimImage?>().firstWhere((img) => img?.type == V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB, orElse: () => null);
                if (oldImg?.uuid != null) {
                  thumbImage.uuid = oldImg!.uuid;
                }
              }
              imageList.add(thumbImage);
              final originImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN);
              originImage.localUrl = newLocalUrl;
              if (newImageUrl != null) {
                originImage.url = newImageUrl;
              }
              // Preserve UUID if it exists
              if (oldImageElem.imageList != null && oldImageElem.imageList!.isNotEmpty) {
                final oldImg = oldImageElem.imageList!.cast<V2TimImage?>().firstWhere((img) => img?.type == V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN, orElse: () => null);
                if (oldImg?.uuid != null) {
                  originImage.uuid = oldImg!.uuid;
                }
              }
              imageList.add(originImage);
            } else {
              // File is still receiving, but update imageList to remove temp path URLs
              // Preserve existing imageList structure but filter out temp path URLs
              if (oldImageElem.imageList != null && oldImageElem.imageList!.isNotEmpty) {
                for (final oldImg in oldImageElem.imageList!) {
                  if (oldImg != null) {
                    final newImg = V2TimImage(type: oldImg.type);
                    newImg.uuid = oldImg.uuid;
                    newImg.localUrl = oldImg.localUrl;
                    // CRITICAL: Don't preserve /tmp/receiving_ paths as URL
                    if (oldImg.url != null && !oldImg.url!.startsWith('/tmp/receiving_')) {
                      newImg.url = oldImg.url;
                    }
                    // If url was a temp path but newImageUrl is available, use it
                    else if (newImageUrl != null) {
                      newImg.url = newImageUrl;
                    }
                    newImg.width = oldImg.width;
                    newImg.height = oldImg.height;
                    newImg.size = oldImg.size;
                    imageList.add(newImg);
                  }
                }
              }
            }
            // CRITICAL: If imageList is empty, filter oldImageElem.imageList to remove temp path URLs
            final finalImageList = imageList.isNotEmpty
                ? imageList
                : (oldImageElem.imageList != null
                    ? oldImageElem.imageList!.map((img) {
                        if (img == null) return null;
                        final newImg = V2TimImage(type: img.type);
                        newImg.uuid = img.uuid;
                        newImg.localUrl = img.localUrl;
                        // CRITICAL: Don't preserve /tmp/receiving_ paths as URL
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
                      }).toList()
                    : null);
              matchedMsg.imageElem = V2TimImageElem(
                path: newPath, // CRITICAL: Only update path if file is complete, otherwise keep temp path
                imageList: finalImageList,
              );
              // CRITICAL: Update the message in _buffers to ensure subsequent progress updates see the updated path/localUrl
              if (_buffers.containsKey(matchedConvID!)) {
                final bufferList = _buffers[matchedConvID]!;
                final bufferIndex = bufferList.indexWhere((m) => m.msgID == msgID);
                if (bufferIndex >= 0) {
                  bufferList[bufferIndex] = matchedMsg;
                  // Skip logging buffer updates - too frequent during file transfer
                }
              }
              // Skip logging imageElem updates - too frequent during file transfer
            } else if (matchedMsg.imageElem != null && progress.received >= progress.total && progress.total > 0) {
            // Image is complete, update imageList with localUrl even if path wasn't temp
            final oldImageElem = matchedMsg.imageElem!;
            // Check if imageList already has localUrl
            bool hasLocalUrl = false;
            if (oldImageElem.imageList != null) {
              for (final img in oldImageElem.imageList!) {
                if (img != null && img.localUrl != null && img.localUrl!.isNotEmpty) {
                  hasLocalUrl = true;
                  break;
                }
              }
            }
            AppLogger.log('[FakeMessageProvider] Image complete: msgID=$msgID, hasLocalUrl=$hasLocalUrl, progress.path=${progress.path}, oldImageElem.path=${oldImageElem.path}');
            if (!hasLocalUrl && progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) {
              // Create imageList with localUrl
              AppLogger.log('[FakeMessageProvider] Creating imageList with localUrl for completed image: msgID=$msgID, localUrl=${progress.path}');
              final imageList = <V2TimImage?>[];
              final thumbImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB);
              thumbImage.localUrl = progress.path;
              thumbImage.url = progress.path; // Use valid path as URL
              // Preserve UUID if it exists
              if (oldImageElem.imageList != null && oldImageElem.imageList!.isNotEmpty) {
                final oldImg = oldImageElem.imageList!.cast<V2TimImage?>().firstWhere((img) => img?.type == V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB, orElse: () => null);
                if (oldImg?.uuid != null) {
                  thumbImage.uuid = oldImg!.uuid;
                }
              }
              imageList.add(thumbImage);
              final originImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN);
              originImage.localUrl = progress.path;
              originImage.url = progress.path; // Use valid path as URL
              // Preserve UUID if it exists
              if (oldImageElem.imageList != null && oldImageElem.imageList!.isNotEmpty) {
                final oldImg = oldImageElem.imageList!.cast<V2TimImage?>().firstWhere((img) => img?.type == V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN, orElse: () => null);
                if (oldImg?.uuid != null) {
                  originImage.uuid = oldImg!.uuid;
                }
              }
              imageList.add(originImage);
              matchedMsg.imageElem = V2TimImageElem(
                path: oldImageElem.path ?? progress.path,
                imageList: imageList,
              );
              // CRITICAL: Update the message in _buffers to ensure subsequent progress updates see the updated path/localUrl
              if (_buffers.containsKey(matchedConvID!)) {
                final bufferList = _buffers[matchedConvID]!;
                final bufferIndex = bufferList.indexWhere((m) => m.msgID == msgID);
                if (bufferIndex >= 0) {
                  bufferList[bufferIndex] = matchedMsg;
                  // Skip logging buffer updates - too frequent during file transfer
                }
              }
              // Skip logging imageElem updates - too frequent during file transfer
            } else {
              AppLogger.log('[FakeMessageProvider] ⚠️ Image complete but hasLocalUrl=$hasLocalUrl or progress.path is null/temp: msgID=$msgID, progress.path=${progress.path}');
            }
            }
            // Update video element path if it's still using temp path or is complete
            if (matchedMsg.videoElem != null) {
              final oldVideoElem = matchedMsg.videoElem!;
              final isComplete = progress.received >= progress.total && progress.total > 0;
              final newLocalVideoUrl = isComplete ? progress.path : oldVideoElem.localVideoUrl;
              final newVideoUrl = (progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) ? progress.path : oldVideoElem.videoUrl;
              final newVideoPath = isComplete ? (progress.path ?? oldVideoElem.videoPath) : oldVideoElem.videoPath;
              matchedMsg.videoElem = V2TimVideoElem(
                videoPath: newVideoPath,
                UUID: oldVideoElem.UUID,
                videoSize: oldVideoElem.videoSize ?? progress.total,
                duration: oldVideoElem.duration,
                videoUrl: newVideoUrl,
                localVideoUrl: newLocalVideoUrl,
                snapshotPath: oldVideoElem.snapshotPath,
                snapshotUUID: oldVideoElem.snapshotUUID,
                snapshotUrl: oldVideoElem.snapshotUrl,
                localSnapshotUrl: oldVideoElem.localSnapshotUrl,
              );
              if (_buffers.containsKey(matchedConvID!)) {
                final bufferList = _buffers[matchedConvID]!;
                final bufferIndex = bufferList.indexWhere((m) => m.msgID == msgID);
                if (bufferIndex >= 0) {
                  bufferList[bufferIndex] = matchedMsg;
                }
              }
            }
            // Update sound element path if it's still using temp path or is complete
            if (matchedMsg.soundElem != null) {
              final oldSoundElem = matchedMsg.soundElem!;
              final isComplete = progress.received >= progress.total && progress.total > 0;
              final newLocalUrl = isComplete ? progress.path : oldSoundElem.localUrl;
              final newUrl = (progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) ? progress.path : oldSoundElem.url;
              final newPath = isComplete ? (progress.path ?? oldSoundElem.path) : oldSoundElem.path;
              matchedMsg.soundElem = V2TimSoundElem(
                path: newPath,
                UUID: oldSoundElem.UUID,
                dataSize: oldSoundElem.dataSize ?? progress.total,
                duration: oldSoundElem.duration,
                url: newUrl,
                localUrl: newLocalUrl,
              );
              if (_buffers.containsKey(matchedConvID!)) {
                final bufferList = _buffers[matchedConvID]!;
                final bufferIndex = bufferList.indexWhere((m) => m.msgID == msgID);
                if (bufferIndex >= 0) {
                  bufferList[bufferIndex] = matchedMsg;
                }
              }
            }
            // Trigger stream update to refresh UI
            final messages = _buffers[matchedConvID]!;
            final reversedList = List<V2TimMessage>.from(messages.reversed);
            _ctrls[matchedConvID]?.add(reversedList);
          }
        }
      }
    }
  }
}
