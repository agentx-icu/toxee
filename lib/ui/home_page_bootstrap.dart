part of 'home_page.dart';

extension _HomePageBootstrap on _HomePageState {
  Future<void> _initAfterSessionReady() async {
    await SessionRuntimeCoordinator(service: widget.service).ensureInitialized();
    if (!mounted) return;
    AppLogger.debug('[HomePage] HYBRID MODE: Binary replacement + Platform interface');

    TimSdkInitializer.ensureInitialized().then((_) {
      _initBinaryReplacementPersistenceHook();
      if (!mounted) return;
      TencentCloudChat.instance.chatSDKInstance.groupSDK.initGroupListener();
      AppLogger.debug('[HomePage] Registered UIKit group listener for GroupTipsEvent dispatch');
      TencentCloudChat.instance.chatSDKInstance.contactSDK.initFriendListener();
      AppLogger.debug('[HomePage] Registered UIKit friendship listener for friend event dispatch');
    }).catchError((e, stackTrace) {
      AppLogger.logError('[HomePage] Failed to initialize TIMManager SDK: $e', e, stackTrace);
    });

    ChatDataProviderRegistry.provider ??= FakeChatDataProvider(ffiService: widget.service);
    ChatMessageProviderRegistry.provider ??= FakeChatMessageProvider();

    final basic = TencentCloudChat.instance.dataInstance.basic;
    basic.addUsedComponent(conv_pkg.TencentCloudChatConversationManager.register());

    if (widget.service.selfId.isNotEmpty) {
      AppLogger.debug('[HomePage] initState: Registering sticker plugin early (before message component)');
      _tryRegisterStickerPluginSync();
    }

    final messageRegisterResult = msg_pkg.TencentCloudChatMessageManager.register();
    basic.addUsedComponent((
      componentEnum: messageRegisterResult.componentEnum,
      widgetBuilder: ({required Map<String, dynamic> options}) {
        final userID = options["userID"] as String?;
        final groupID = options["groupID"] as String?;
        if (userID == null && groupID == null) {
          return const SizedBox.shrink();
        }
        final conversationID = groupID != null ? 'group_$groupID' : (userID != null ? 'c2c_$userID' : 'none');
        final widgetKey = _messageWidgetKeys[conversationID] ?? UniqueKey();
        final messageKey = ValueKey('msg-$conversationID-$_messageWidgetKeyCounter-${widgetKey.hashCode}');
        return msg_pkg.TencentCloudChatMessage(
          key: messageKey,
          options: TencentCloudChatMessageOptions(
            userID: userID,
            groupID: groupID,
            topicID: options["topicID"],
            targetMessage: options["targetMessage"],
          ),
        );
      },
    ));

    basic.addUsedComponent(contact_pkg.TencentCloudChatContactManager.register());

    contact_pkg.TencentCloudChatContactManager.builder.setBuilders(
      groupMemberListPageBuilder: ({required V2TimGroupInfo groupInfo, required List<V2TimGroupMemberFullInfo> memberInfoList}) {
        return GroupMemberListWrapper(groupInfo: groupInfo, memberInfoList: memberInfoList);
      },
    );

    final searchRegisterResult = search_pkg.CustomSearchManager.register();
    basic.addUsedComponent((
      componentEnum: searchRegisterResult.componentEnum,
      widgetBuilder: searchRegisterResult.widgetBuilder,
    ));

    basic.notifyListener(TencentCloudChatBasicDataKeys.addUsedComponent as dynamic);

    AppLogger.debug('[HomePage] initState: Calling _ensureStickerPluginRegistered');
    _ensureStickerPluginRegistered();
    _connectionStatusSub = widget.service.connectionStatusStream.listen((connected) async {
      AppLogger.log('[HomePage] Connection status changed: connected=$connected, selfId=${widget.service.selfId}');
      unawaited(_updateTray());
      if (connected) {
        final selfId = widget.service.selfId;
        AppLogger.debug('[HomePage] Connection established: Checking plugin registration - _stickerPluginRegistered=$_stickerPluginRegistered, selfId=$selfId, isEmpty=${selfId.isEmpty}');
        if (!_stickerPluginRegistered && selfId.isNotEmpty) {
          AppLogger.debug('[HomePage] Connection established: Scheduling plugin registration');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              AppLogger.debug('[HomePage] Connection established: PostFrameCallback executing, calling _tryRegisterStickerPlugin');
              _tryRegisterStickerPlugin();
            } else {
              AppLogger.debug('[HomePage] Connection established: PostFrameCallback skipped - not mounted');
            }
          });
        } else {
          AppLogger.debug('[HomePage] Connection established: Skipping plugin registration - already registered or selfId empty');
        }
        Future.delayed(const Duration(milliseconds: 2000), () async {
          if (mounted) {
            await _syncPersistedFriendsToTox();
          }
        });
      }
    });
    _bag.add(() => _connectionStatusSub?.cancel());

    if (PlatformUtils.isDesktop) {
      _loadBootstrapServiceStatus();
      _bootstrapServiceStatusTimer = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _loadBootstrapServiceStatus(),
      );
      _bag.add(() => _bootstrapServiceStatusTimer?.cancel());
    }

    _conversationDataSub = TencentCloudChat.instance.eventBusInstance
        .on<TencentCloudChatConversationData<dynamic>>("TencentCloudChatConversationData")
        ?.listen((data) {
      if (data.currentUpdatedFields == TencentCloudChatConversationDataKeys.currentConversation) {
        final currentConv = data.currentConversation;
        if (currentConv != null) {
          final conversationID = currentConv.conversationID;
          if (_currentConversationID != conversationID) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              if (mounted && _currentConversationID != conversationID) {
                _bootstrapSetState(() {
                  _messageWidgetKeys.clear();
                  _currentConversationID = conversationID;
                  _messageWidgetKeyCounter++;
                  _messageWidgetKeys[conversationID] = UniqueKey();
                });
              }
            });
          }
        }
      }
      if (data.currentUpdatedFields == TencentCloudChatConversationDataKeys.totalUnreadCount) {
        unawaited(_updateTray());
      }
    });
    _bag.add(() => _conversationDataSub?.cancel());

    _contactDataSub = TencentCloudChat.instance.eventBusInstance
        .on<TencentCloudChatContactData<dynamic>>("TencentCloudChatContactData")
        ?.listen((data) {
      if (data.currentUpdatedFields == TencentCloudChatContactDataKeys.groupList) {
        if (kDebugMode) debugPrint('[HomePage] Group list updated, refreshing conversations');
        Future.delayed(const Duration(milliseconds: 100), () {
          FakeUIKit.instance.im?.refreshConversations().catchError((e, stackTrace) {
            AppLogger.logError('[HomePage] Error refreshing conversations after group list update', e, stackTrace);
          });
        });
      }
      if (data.currentUpdatedFields == TencentCloudChatContactDataKeys.applicationCount ||
          data.currentUpdatedFields == TencentCloudChatContactDataKeys.applicationList) {
        unawaited(_updateTray());
      }
    });
    _bag.add(() => _contactDataSub?.cancel());

    _groupProfileDataSub = TencentCloudChat.instance.eventBusInstance
        .on<TencentCloudChatGroupProfileData<dynamic>>("TencentCloudChatGroupProfileData")
        ?.listen((data) async {
      if (data.currentUpdatedFields == TencentCloudChatGroupProfileDataKeys.membersChange) {
        final groupID = data.updateGroupID;
        if (groupID.isNotEmpty) {
          final lastChangeTime = _lastMembersChangeTime[groupID];
          if (lastChangeTime != null) {
            final timeSinceLastChange = DateTime.now().difference(lastChangeTime);
            if (timeSinceLastChange < _HomePageState._minMembersChangeInterval) {
              if (kDebugMode) debugPrint('[HomePage] Ignoring rapid membersChange event for group $groupID (${timeSinceLastChange.inMilliseconds}ms ago)');
              return;
            }
          }
          _lastMembersChangeTime[groupID] = DateTime.now();
        }
      }
      if (data.currentUpdatedFields == TencentCloudChatGroupProfileDataKeys.quitGroup) {
        final groupID = data.updateGroupID;
        if (kDebugMode) debugPrint('[HomePage] Group quit/dismissed: $groupID, removing from lists');

        final savedGroups = await Prefs.getGroups();
        if (savedGroups.contains(groupID)) {
          savedGroups.remove(groupID);
          await Prefs.setGroups(savedGroups);
          if (kDebugMode) debugPrint('[HomePage] Removed group $groupID from Prefs.getGroups()');
        }

        final convId = 'group_$groupID';
        final conversationData = TencentCloudChat.instance.dataInstance.conversation;
        if (_currentConversationID == convId) {
          if (kDebugMode) debugPrint('[HomePage] Quit group $groupID is currently open, clearing chat window');
          conversationData.currentConversation = null;
          if (mounted) {
            _bootstrapSetState(() {
              _currentConversationID = null;
            });
          }
        }

        conversationData.removeConversation([convId]);
        if (kDebugMode) debugPrint('[HomePage] Removed conversation $convId from conversation list');

        FakeUIKit.instance.eventBusInstance.emit(FakeIM.topicGroupDeleted, FakeGroupDeleted(groupID: groupID));
        if (kDebugMode) debugPrint('[HomePage] Emitted FakeGroupDeleted event for group $groupID');
      } else if (data.currentUpdatedFields == TencentCloudChatGroupProfileDataKeys.builder) {
        final groupProfileData = TencentCloudChat.instance.dataInstance.groupProfile;
        if (groupProfileData.updateGroupID.isEmpty || groupProfileData.updateGroupInfo.groupID.isEmpty) {
          Future.microtask(() async {
            final currentConv = TencentCloudChat.instance.dataInstance.conversation.currentConversation;
            String? targetGroupID;
            V2TimGroupInfo? targetGroupInfo;

            if (currentConv?.groupID != null && currentConv!.groupID!.isNotEmpty) {
              targetGroupID = currentConv.groupID!;
            } else {
              final convList = TencentCloudChat.instance.dataInstance.conversation.conversationList;
              for (final conv in convList) {
                if (conv.groupID != null && conv.groupID!.isNotEmpty) {
                  targetGroupID = conv.groupID!;
                  break;
                }
              }
            }

            if (targetGroupID != null && targetGroupID.isNotEmpty) {
              final contactData = TencentCloudChat.instance.dataInstance.contact;
              targetGroupInfo = contactData.getGroupInfo(targetGroupID);

              if (targetGroupInfo.groupID.isEmpty) {
                final groupList = contactData.groupList;
                final foundGroup = groupList.firstWhere(
                  (g) => g.groupID == targetGroupID,
                  orElse: () => V2TimGroupInfo(groupID: '', groupType: ''),
                );
                if (foundGroup.groupID.isNotEmpty) {
                  targetGroupInfo = foundGroup;
                }
              }

              if (targetGroupInfo.groupID.isEmpty) {
                final groupName = await Prefs.getGroupName(targetGroupID);
                final groupAvatar = await Prefs.getGroupAvatar(targetGroupID);
                targetGroupInfo = V2TimGroupInfo(
                  groupID: targetGroupID,
                  groupType: "Work",
                  groupName: groupName ?? targetGroupID,
                  faceUrl: groupAvatar,
                );
              }

              groupProfileData.updateGroupID = targetGroupID;
              groupProfileData.updateGroupInfo = targetGroupInfo;
            }
          });
        }
      }
    });
    _bag.add(() => _groupProfileDataSub?.cancel());

    conv_pkg.TencentCloudChatConversationManager.config.setConfigs(useDesktopMode: true);

    msg_pkg.TencentCloudChatMessageManager.config.setConfigs(
      showSelfAvatar: createDefaultValue(true),
      showOthersAvatar: createDefaultValue(true),
      enableParseMarkdown: createDefaultValue(true),
      enableAutoReportReadStatusForComingMessages: createDefaultValue(true),
      enabledGroupTypesForMessageReadReceipt: createDefaultValue<List<String>>(
        [GroupType.Work, GroupType.Public, GroupType.Meeting, GroupType.Community],
      ),
      attachmentConfig: createDefaultValue(
        TencentCloudChatMessageAttachmentConfig(
          enableSendImage: false,
          enableSendVideo: false,
          enableSendFile: true,
          enableSearch: false,
        ),
      ),
      defaultMessageMenuConfig: createDefaultValue(
        TencentCloudChatMessageDefaultMessageMenuConfig(
          enableMessageSelect: true,
          enableMessageForward: true,
          enableMessageCopy: true,
          enableMessageQuote: true,
          enableMessageRecall: true,
          enableMessageDeleteForSelf: true,
          enableGroupMessageReceipt: true,
        ),
      ),
      defaultMessageSelectionOperationsConfig: createDefaultValue(
        TencentCloudChatMessageDefaultMessageSelectionOptionsConfig(
          enableMessageForwardIndividually: true,
          enableMessageForwardCombined: true,
          enableMessageDeleteForSelf: true,
        ),
      ),
      additionalAttachmentOptionsForMobile: ({String? userID, String? groupID, String? topicID}) {
        final appL10n = AppLocalizations.of(context)!;
        final photoLabel = appL10n.photo;
        final videoLabel = appL10n.video;
        return [
          TencentCloudChatMessageGeneralOptionItem(
            icon: Icons.photo_outlined,
            label: photoLabel,
            onTap: ({Offset? offset}) async {
              await _sendMedia(context, userId: userID, groupId: groupID, type: _MediaPickType.image);
            },
          ),
          TencentCloudChatMessageGeneralOptionItem(
            icon: Icons.videocam_outlined,
            label: videoLabel,
            onTap: ({Offset? offset}) async {
              await _sendMedia(context, userId: userID, groupId: groupID, type: _MediaPickType.video);
            },
          ),
        ];
      },
      additionalInputControlBarOptionsForDesktop: ({String? userID, String? groupID, String? topicID}) {
        return _buildDesktopInputOptions(context, userID: userID, groupID: groupID);
      },
    );

    msg_pkg.TencentCloudChatMessageManager.builder.setBuilders(
      messageNoChatBuilder: () => const TencentCloudChatMessageNoChat(),
      messageHeaderBuilder: ({
        Key? key,
        required MessageHeaderBuilderWidgets widgets,
        required MessageHeaderBuilderData data,
        required MessageHeaderBuilderMethods methods,
      }) {
        return msg_header.TencentCloudChatMessageHeader(
          key: key,
          data: data,
          methods: methods,
          widgets: MessageHeaderBuilderWidgets(
            messageHeaderProfileImage: widgets.messageHeaderProfileImage,
            messageHeaderActions: widgets.messageHeaderActions,
            messageHeaderMessagesSelectMode: widgets.messageHeaderMessagesSelectMode,
            messageHeaderInfo: _ToxeeMessageHeaderInfo(
              userID: data.userID,
              groupID: data.groupID,
              conversation: data.conversation,
              showUserOnlineStatus: data.showUserOnlineStatus,
              getUserOnlineStatus: methods.getUserOnlineStatus,
              getGroupMembersInfo: methods.getGroupMembersInfo,
            ),
          ),
        );
      },
      messageInputBuilder: ({
        Key? key,
        MessageInputBuilderWidgets? widgets,
        required MessageInputBuilderData data,
        required MessageInputBuilderMethods methods,
      }) {
        final basic = TencentCloudChat.instance.dataInstance.basic;
        final hasStickerPlugin = basic.hasPlugins("sticker");
        final stickerPluginInstance = basic.getPlugin("sticker")?.pluginInstance;

        AppLogger.debug('[HomePage] messageInputBuilder: Dynamically checking plugin - hasStickerPlugin=$hasStickerPlugin, instance=${stickerPluginInstance != null}');

        final updatedData = MessageInputBuilderData(
          userID: data.userID,
          groupID: data.groupID,
          topicID: data.topicID,
          attachmentOptions: data.attachmentOptions,
          inSelectMode: data.inSelectMode,
          enableReplyWithMention: data.enableReplyWithMention,
          status: data.status,
          selectedMessages: data.selectedMessages,
          repliedMessage: data.repliedMessage,
          desktopMentionBoxPositionX: data.desktopMentionBoxPositionX,
          desktopMentionBoxPositionY: data.desktopMentionBoxPositionY,
          isGroupAdmin: data.isGroupAdmin,
          activeMentionIndex: data.activeMentionIndex,
          currentFilteredMembersListForMention: data.currentFilteredMembersListForMention,
          groupMemberList: data.groupMemberList,
          membersNeedToMention: data.membersNeedToMention,
          specifiedMessageText: data.specifiedMessageText,
          currentConversationShowName: data.currentConversationShowName,
          hasStickerPlugin: hasStickerPlugin,
          stickerPluginInstance: stickerPluginInstance,
        );

        return TencentCloudChatMessageInput(
          key: key,
          data: updatedData,
          methods: methods,
          widgets: widgets,
        );
      },
      messageItemBuilder: ({
        Key? key,
        MessageItemBuilderWidgets? widgets,
        required MessageItemBuilderData data,
        required MessageItemBuilderMethods methods,
      }) {
        final defaultWidget = widgets?.messageItemView ??
            TencentCloudChatMessageItemBuilders.getMessageItemBuilder(
              key: key,
              data: data,
              methods: methods,
            );

        final isGroupMessage = data.groupID != null && data.groupID!.isNotEmpty;
        final isSelfMessage = data.message.isSelf ?? false;
        final msgID = data.message.msgID ?? '';

        if (isGroupMessage && isSelfMessage && msgID.isNotEmpty) {
          final receiverCount = FakeUIKit.instance.messageManager?.getMessageReceiverCount(msgID) ?? 0;

          if (receiverCount > 0) {
            final scheme = Theme.of(context).colorScheme;
            return Stack(
              children: [
                defaultWidget,
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: () => _showMessageReceiversDialog(context, msgID, data.groupID!),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs + 2, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(AppThemeConfig.badgeBorderRadius),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.visibility_outlined,
                            size: 14,
                            color: scheme.onPrimary,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            '$receiverCount',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: scheme.onPrimary,
                                  fontWeight: FontWeight.w600,
                                  height: 1.0,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
        }

        return defaultWidget;
      },
    );

    final eventHandlers = conv_pkg.TencentCloudChatConversationManager.eventHandlers;
    final uiEventHandlers = eventHandlers.uiEventHandlers;

    uiEventHandlers.setEventHandlers(
      onTapConversationItem: ({
        required TencentCloudChatMessageOptions messageOptions,
        required V2TimConversation conversation,
        required bool inDesktopMode,
      }) async {
        final conversationID = conversation.conversationID;
        if (conversationID.isNotEmpty) {
          widget.service.setActivePeer(conversationID);
        }

        final convData = TencentCloudChat.instance.dataInstance.conversation;
        convData.currentConversation = conversation;

        return false;
      },
    );

    basic.updateInitializedStatus(status: true);
    basic.updateLoginStatus(status: true);
    final selfId = widget.service.selfId;
    AppLogger.debug('[HomePage] _buildHomePage: Setting current user info, selfId=$selfId');
    basic.updateCurrentUserInfo(userFullInfo: V2TimUserFullInfo(userID: selfId));

    if (!_stickerPluginRegistered && selfId.isNotEmpty) {
      AppLogger.debug('[HomePage] _buildHomePage: Scheduling sticker plugin registration, selfId=$selfId');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          AppLogger.debug('[HomePage] _buildHomePage: PostFrameCallback executing, calling _tryRegisterStickerPlugin');
          _tryRegisterStickerPlugin();
        } else {
          AppLogger.debug('[HomePage] _buildHomePage: PostFrameCallback skipped - not mounted');
        }
      });
    } else {
      AppLogger.debug('[HomePage] _buildHomePage: Skipping plugin registration - _stickerPluginRegistered=$_stickerPluginRegistered, selfId.isEmpty=${selfId.isEmpty}');
    }

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        final hasPluginAfter = basic.hasPlugins("sticker");
        final pluginAfter = basic.getPlugin("sticker");
        AppLogger.debug('[HomePage] _buildHomePage: Plugin status after 500ms - hasPlugin=$hasPluginAfter, plugin=${pluginAfter != null}, instance=${pluginAfter?.pluginInstance}');
      }
    });

    final provider = ChatDataProviderRegistry.provider;
    if (provider != null) {
      provider.getInitialConversations().then((list) {
        TencentCloudChat.instance.dataInstance.conversation.buildConversationList(list, 'external_init');
      });
      provider.conversationStream.listen((list) {
        TencentCloudChat.instance.dataInstance.conversation.buildConversationList(list, 'external_stream');
      });
      provider.totalUnreadStream.listen((total) {
        TencentCloudChat.instance.dataInstance.conversation.setTotalUnreadCount(total);
      });
    } else {
      TencentCloudChatConversationController.instance.init();
    }

    Future.delayed(const Duration(milliseconds: 100), () async {
      if (mounted) {
        await _load();
        if (widget.service.isConnected) {
          await _syncPersistedFriendsToTox();
        }
        await _loadPersistedGroupsIntoUIKit();
        if (FakeUIKit.instance.im != null) {
          FakeUIKit.instance.im!.refreshContacts().catchError((e) {
            // Silently handle errors
          });
        }
      }
    });

    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
    _bag.add(() => _refreshTimer?.cancel());
    unawaited(_loadLocalFriends());

    final toxId = widget.service.selfId;
    if (toxId.isNotEmpty) {
      Prefs.getAutoAcceptFriends(toxId).then((value) {
        if (mounted) {
          _bootstrapSetState(() => _autoAcceptFriends = value);
        }
      });
      Prefs.getAutoAcceptGroupInvites(toxId).then((value) {
        if (mounted) {
          _bootstrapSetState(() => _autoAcceptGroupInvites = value);
          widget.service.setAutoAcceptGroupInvites(value);
        }
      });
    }

    _checkIrcAppStatus();
    _msgSub = widget.service.messages.listen((m) {
      if (widget.service.selfId == m.fromUserId) return;
      if (!mounted) return;
      _bootstrapSetState(() {});
      unawaited(_updateTray());
    });
    _bag.add(() => _msgSub?.cancel());

    _progressUpdatesSub = widget.service.progressUpdates.listen((progress) {
      if (!mounted) return;
    });
    _bag.add(() => _progressUpdatesSub?.cancel());

    _friendsSub = FakeUIKit.instance.eventBusInstance.on<List<FakeUser>>(FakeIM.topicContacts).listen((list) async {
      final mapped = await Future.wait(list.map((u) async {
        final avatarPath = await Prefs.getFriendAvatarPath(u.userID);
        final faceUrl = (avatarPath != null && avatarPath.isNotEmpty) ? avatarPath : null;
        return V2TimFriendInfo(
          userID: u.userID,
          friendRemark: u.nickName,
          userProfile: V2TimUserFullInfo(
            userID: u.userID,
            nickName: u.nickName,
            faceUrl: faceUrl,
            selfSignature: u.status.isNotEmpty ? u.status : null,
          ),
        );
      }));
      TencentCloudChat.instance.dataInstance.contact.buildFriendList(mapped, "home");
      final freshUserIds = list.map((u) => u.userID).toSet();
      final currentContactList = TencentCloudChat.instance.dataInstance.contact.contactList;
      final staleUserIds = currentContactList
          .where((c) => !freshUserIds.contains(c.userID))
          .map((c) => c.userID)
          .where((id) => id.isNotEmpty)
          .toList();
      if (staleUserIds.isNotEmpty) {
        TencentCloudChat.instance.dataInstance.contact.deleteFromFriendList(staleUserIds, 'home_sync');
      }
      final statuses = list
          .map((u) => V2TimUserStatus(userID: u.userID, statusType: u.online ? 1 : 0, onlineDevices: const []))
          .toList();
      if (statuses.isNotEmpty) {
        TencentCloudChat.instance.dataInstance.contact.buildUserStatusList(statuses, "home");
      }

      final groups = widget.service.knownGroups;
      for (final gid in groups) {
        final savedName = await Prefs.getGroupName(gid);
        final savedAvatar = await Prefs.getGroupAvatar(gid);
        final groupInfo = V2TimGroupInfo(
          groupID: gid,
          groupType: "work",
          groupName: savedName,
          faceUrl: savedAvatar,
        );
        TencentCloudChat.instance.dataInstance.contact.addGroupInfoToJoinedGroupList(groupInfo);
      }

      final friendIds = list.map((u) {
        final id = u.userID.trim();
        return id.length > 64 ? id.substring(0, 64) : id;
      }).toSet();
      if (mounted) {
        _bootstrapSetState(() {
          _localFriends = friendIds;
        });
      }
    });
    _bag.add(() => _friendsSub?.cancel());

    if (FakeUIKit.instance.im != null) {
      FakeUIKit.instance.im!.forceRefreshContacts().catchError((e) {
        AppLogger.debug('[HomePage] forceRefreshContacts after _friendsSub error: $e');
      });
    }

    _appsSub = FakeUIKit.instance.eventBusInstance.on<List<FakeFriendApplication>>(FakeIM.topicFriendApps).listen((list) async {
      final mapped =
          list.map((a) => V2TimFriendApplication(userID: a.userID, addWording: a.wording, type: 1, nickname: "", faceUrl: "")).toList();
      TencentCloudChat.instance.dataInstance.contact.buildApplicationList(mapped, "home");
      TencentCloudChat.instance.dataInstance.contact.setApplicationUnreadCount(mapped);
      _pendingFriendApps = List<V2TimFriendApplication>.from(mapped);
      if (_autoAcceptFriends && mapped.isNotEmpty) {
        _acceptFriendApplications(mapped).catchError((e) {
          // Silently handle errors during async friend acceptance
        });
      }
      if (mounted) _bootstrapSetState(() {});
      unawaited(_updateTray());
    });
    _bag.add(() => _appsSub?.cancel());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_updateTray());
    });

    _contactBuilderOverride = ContactBuilderOverrideHandle.capture();
    _bag.add(() => _contactBuilderOverride?.restore());

    final originalContentBuilder = _contactBuilderOverride!.originalContentBuilder;
    final originalStateBuilder = _contactBuilderOverride!.originalStateBuilder;
    final originalDeleteBuilder = _contactBuilderOverride!.originalDeleteBuilder;

    contact_pkg.TencentCloudChatContactManager.builder.setBuilders(
      userProfileContentBuilder: ({required V2TimUserFullInfo userFullInfo}) {
        return originalContentBuilder(userFullInfo: userFullInfo);
      },
      userProfileStateButtonBuilder: ({required V2TimUserFullInfo userFullInfo}) {
        return originalStateBuilder(userFullInfo: userFullInfo);
      },
      userProfileDeleteButtonBuilder: ({required V2TimUserFullInfo userFullInfo}) {
        final friendIDList = TencentCloudChat.instance.dataInstance.contact.contactList
            .map((e) => normalizeToxId(e.userID))
            .toSet();
        final normalizedUserID = normalizeToxId(userFullInfo.userID ?? '');
        final isFriend = friendIDList.contains(normalizedUserID);

        if (isFriend) {
          return originalDeleteBuilder(userFullInfo: userFullInfo);
        } else {
          return _buildAddFriendButton(userFullInfo);
        }
      },
    );
  }
}

/// Replacement for TencentCloudChatMessageHeaderInfo that fixes the
/// Expanded-in-MainAxisSize.min layout bug causing the status row to get 0 height.
class _ToxeeMessageHeaderInfo extends StatefulWidget {
  final bool Function({required String userID}) getUserOnlineStatus;
  final List<V2TimGroupMemberFullInfo> Function() getGroupMembersInfo;
  final String? userID;
  final String? groupID;
  final V2TimConversation? conversation;
  final bool showUserOnlineStatus;

  const _ToxeeMessageHeaderInfo({
    required this.getUserOnlineStatus,
    required this.getGroupMembersInfo,
    this.userID,
    this.groupID,
    this.conversation,
    required this.showUserOnlineStatus,
  });

  @override
  State<_ToxeeMessageHeaderInfo> createState() =>
      _ToxeeMessageHeaderInfoState();
}

class _ToxeeMessageHeaderInfoState extends State<_ToxeeMessageHeaderInfo> {
  String _getStatusText(BuildContext context) {
    final conv = widget.conversation;
    if (conv == null) return '';
    // C2C: show online/offline
    if (conv.type == 1) {
      final uid = conv.userID ?? widget.userID ?? '';
      if (uid.isNotEmpty) {
        final isOnline = widget.getUserOnlineStatus(userID: uid);
        final tL10n = TencentCloudChatLocalizations.of(context);
        final appL10n = AppLocalizations.of(context);
        return isOnline
            ? (tL10n?.online ?? appL10n?.statusOnline ?? 'Online')
            : (tL10n?.offline ?? appL10n?.statusOffline ?? 'Offline');
      }
    } else {
      // Group: show member count if > 2
      final members = widget.getGroupMembersInfo();
      if (members.length > 2) {
        final tL10n = TencentCloudChatLocalizations.of(context);
        final firstName = members[0].nickName ?? members[0].userID;
        return tL10n?.groupSubtitle(members.length, firstName) ??
            '${members.length} members';
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final statusText = _getStatusText(context);
    final displayName = widget.conversation?.showName ??
        widget.userID ??
        TencentCloudChatLocalizations.of(context)?.chat ??
        '';
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            displayName,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: textStyle.standardLargeText,
              fontWeight: FontWeight.bold,
              color: colorTheme.primaryTextColor,
            ),
          ),
          if (widget.showUserOnlineStatus && statusText.isNotEmpty)
            Text(
              statusText,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: textStyle.standardSmallText,
                color: colorTheme.secondaryTextColor,
              ),
            ),
        ],
      ),
    );
  }
}
