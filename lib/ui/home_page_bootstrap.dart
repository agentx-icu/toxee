part of 'home_page.dart';

extension _HomePageBootstrap on _HomePageState {
  void _installContactProfileBuilders() {
    // Only override the delete-button slot: when the user is a friend we
    // render the upstream default widget directly; otherwise we render the
    // toxee "Add Friend" affordance. Content + state slots are left null so
    // the manager falls through to upstream defaults — no pass-through
    // closure needed (which would otherwise round-trip through the manager
    // and recurse on restore).
    contact_pkg.TencentCloudChatContactManager.builder.setBuilders(
      userProfileDeleteButtonBuilder:
          ({required V2TimUserFullInfo userFullInfo}) {
            final friendIDList = UikitDataFacade.contactList
                .map((e) => normalizeToxId(e.userID))
                .toSet();
            final normalizedUserID = normalizeToxId(userFullInfo.userID ?? '');
            final isFriend = friendIDList.contains(normalizedUserID);

            if (isFriend) {
              return TencentCloudChatUserProfileDeleteButton(
                userFullInfo: userFullInfo,
              );
            } else {
              return _buildAddFriendButton(userFullInfo);
            }
          },
      // Wrap the upstream chat-button row (Send Message + Voice + Video
      // tiles) with [UiKeys.friendProfileSendMessageButton] so UI
      // automation can tap "Send Message" from the friend profile without
      // patching the UIKit fork. The tile's own onTap (which calls
      // `onNavigateToChat` and routes via toxee's `onTapContactItem`
      // handler) is preserved by delegating to the upstream widget.
      userProfileChatButtonBuilder:
          ({
            required V2TimUserFullInfo userFullInfo,
            VoidCallback? startVideoCall,
            VoidCallback? startVoiceCall,
            bool? isNavigatedFromChat,
          }) {
            return KeyedSubtree(
              key: UiKeys.friendProfileSendMessageButton,
              child: TencentCloudChatUserProfileChatButton(
                userFullInfo: userFullInfo,
                startVideoCall: startVideoCall,
                startVoiceCall: startVoiceCall,
                isNavigatedFromChat: isNavigatedFromChat,
              ),
            );
          },
      contactItemContentBuilder: (friend) => KeyedSubtree(
        key: UiKeys.contactListTile(friend.userID),
        child: TencentCloudChatContactItemContent(friend: friend),
      ),
      contactApplicationItemContentBuilder: (application) =>
          ContactApplicationItemContentOverride(application: application),
      contactGroupListItemContentBuilder: (group) => KeyedSubtree(
        key: UiKeys.groupListTile(group.groupID),
        child: TencentCloudChatContactGroupItemContent(group: group),
      ),
      // setBuilders is destructive (any slot not passed is nulled) — re-supply
      // the app-bar-name override (including the trailing `NewEntryButton`)
      // here so it stays mounted after the post-contacts-load override is
      // applied, and so a later route-dispose restore can be healed by
      // calling this helper again (restored-account boot path).
      contactAppBarNameBuilder: ({String? title}) => ContactAppBarNameOverride(
        title: title,
        trailing: NewEntryButton(
          onAddFriend: _showAddFriendDialog,
          onCreateGroup: _showAddGroupDialog,
          onJoinIrcChannel: _ircAppInstalled ? _showJoinIrcChannelDialog : null,
        ),
      ),
    );
  }

  Future<void> _initAfterSessionReady() async {
    await SessionRuntimeCoordinator(
      service: widget.service,
    ).ensureInitialized();
    if (!mounted) return;
    AppLogger.debug(
      '[HomePage] HYBRID MODE: Binary replacement + Platform interface',
    );

    try {
      await TimSdkInitializer.ensureInitialized();
    } catch (e, stackTrace) {
      AppLogger.logError(
        '[HomePage] Failed to initialize TIMManager SDK: $e',
        e,
        stackTrace,
      );
      // Unstick UIKit's splash so the user isn't staring at a blank initializing
      // screen, then surface a visible error so they know to restart. Skipping
      // the rest of init keeps us from registering listeners on a half-built SDK.
      UikitDataFacade.updateInitializedStatus(true);
      UikitDataFacade.updateLoginStatus(true);
      _initErrorMessage = 'Chat SDK initialization failed: $e';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final msg = _initErrorMessage;
        if (msg == null) return;
        _showErrorSnackBar(msg);
      });
      return;
    }
    // BinaryReplacementHistoryHook is now installed inside
    // SessionRuntimeCoordinator.ensureInitialized() — same atomic init
    // block as the platform — to close the platform-installed-but-hook-
    // not-installed window. Don't re-install here.
    if (!mounted) return;
    TencentCloudChat.instance.chatSDKInstance.groupSDK.initGroupListener();
    AppLogger.debug(
      '[HomePage] Registered UIKit group listener for GroupTipsEvent dispatch',
    );
    TencentCloudChat.instance.chatSDKInstance.contactSDK.initFriendListener();
    AppLogger.debug(
      '[HomePage] Registered UIKit friendship listener for friend event dispatch',
    );

    // Wire send-failure toast on the SDK callbacks trigger. The handler is
    // idempotent against multiple registrations (we deregister on dispose via
    // _bag) and dedups bursts of the same error code internally. Note: SDK
    // callbacks register on a singleton, so re-init after logout/login flows
    // would otherwise stack listeners — _bag.add ensures cleanup.
    final sdkFailureCallback = TencentCloudChatCallbacks(
      onTencentCloudChatSDKFailedCallback: SendFailureNotifier.handleSdkFailure,
    );
    TencentCloudChat.instance.callbacks.addCallback(sdkFailureCallback);
    _bag.add(
      () => TencentCloudChat.instance.callbacks.removeCallback(
        sdkFailureCallback,
      ),
    );

    ChatDataProviderRegistry.provider ??= FakeChatDataProvider(
      ffiService: widget.service,
    );
    // REUSE the single provider created by FakeUIKit.startWithFfi (which the
    // startup gate ran before this HomePage built, so it is non-null here).
    // Constructing a fresh FakeChatMessageProvider() here used to create a
    // SECOND instance: both it and FakeUIKit.messageProvider subscribed to the
    // FakeMessage bus, so every inbound message was appended to two buffers and
    // rendered twice (live double-bubble). Sharing the one instance also closes
    // a teardown leak — FakeUIKit.dispose() disposes its messageProvider, so a
    // separate registry instance never got its bus subscription cancelled.
    final sharedMessageProvider = FakeUIKit.instance.messageProvider;
    if (sharedMessageProvider == null) {
      // Invariant violation: startWithFfi should have created it before now.
      // Log loudly (codex review) — the fallback keeps the UI alive but a
      // standalone provider here would re-introduce the double-subscription,
      // so this must be investigated rather than silently tolerated.
      AppLogger.logError(
        '[HomePage] FakeUIKit.messageProvider null at _initAfterSessionReady '
        '— startWithFfi ordering invariant violated; falling back to a '
        'standalone provider (risks double-subscription). Investigate startup '
        'ordering.',
      );
    }
    ChatMessageProviderRegistry.provider ??=
        sharedMessageProvider ?? FakeChatMessageProvider();

    UikitDataFacade.addUsedComponent(
      conv_pkg.TencentCloudChatConversationManager.register(),
    );

    if (widget.service.selfId.isNotEmpty) {
      AppLogger.debug(
        '[HomePage] initState: Registering sticker plugin early (before message component)',
      );
      _tryRegisterStickerPluginSync();
    }

    final messageRegisterResult =
        msg_pkg.TencentCloudChatMessageManager.register();
    UikitDataFacade.addUsedComponent((
      componentEnum: messageRegisterResult.componentEnum,
      widgetBuilder: ({required Map<String, dynamic> options}) {
        final userID = options["userID"] as String?;
        final groupID = options["groupID"] as String?;
        if (userID == null && groupID == null) {
          return const SizedBox.shrink();
        }
        final conversationID = groupID != null
            ? 'group_$groupID'
            : (userID != null ? 'c2c_$userID' : 'none');
        final widgetKey = _messageWidgetKeys[conversationID] ?? UniqueKey();
        final messageKey = ValueKey(
          'msg-$conversationID-$_messageWidgetKeyCounter-${widgetKey.hashCode}',
        );
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

    UikitDataFacade.addUsedComponent(
      contact_pkg.TencentCloudChatContactManager.register(),
    );

    contact_pkg.TencentCloudChatContactManager.builder.setBuilders(
      groupMemberListPageBuilder:
          ({
            required V2TimGroupInfo groupInfo,
            required List<V2TimGroupMemberFullInfo> memberInfoList,
          }) {
            return GroupMemberListWrapper(
              groupInfo: groupInfo,
              memberInfoList: memberInfoList,
            );
          },
      contactItemContentBuilder: (friend) => KeyedSubtree(
        key: UiKeys.contactListTile(friend.userID),
        child: TencentCloudChatContactItemContent(friend: friend),
      ),
      contactApplicationItemContentBuilder: (application) =>
          ContactApplicationItemContentOverride(application: application),
      contactGroupListItemContentBuilder: (group) => KeyedSubtree(
        key: UiKeys.groupListTile(group.groupID),
        child: TencentCloudChatContactGroupItemContent(group: group),
      ),
      // Suppress UIKit's built-in `Icons.maps_ugc_outlined` MenuAnchor in the
      // contacts-tab title row. Tencent-IM's "Add Contact" / "Add Group" flows
      // search by userID and don't work on Tox; toxee's own `NewEntryButton`
      // (Tox ID/QR, Create Group, Join IRC) is mounted inside the override's
      // `trailing` slot — same visual position as the upstream icon, but
      // routed through the Tox-aware dialogs.
      contactAppBarNameBuilder: ({String? title}) => ContactAppBarNameOverride(
        title: title,
        trailing: NewEntryButton(
          onAddFriend: _showAddFriendDialog,
          onCreateGroup: _showAddGroupDialog,
          onJoinIrcChannel: _ircAppInstalled ? _showJoinIrcChannelDialog : null,
        ),
      ),
    );

    final searchRegisterResult = search_pkg.CustomSearchManager.register();
    UikitDataFacade.addUsedComponent((
      componentEnum: searchRegisterResult.componentEnum,
      widgetBuilder: searchRegisterResult.widgetBuilder,
    ));

    UikitDataFacade.notifyAddUsedComponent();

    AppLogger.debug(
      '[HomePage] initState: Calling _ensureStickerPluginRegistered',
    );
    _ensureStickerPluginRegistered();
    // P1-C3: if the user is still offline 30s after the home page comes up
    // — meaning the startup 20s connection wait already elapsed without us
    // hearing back from the DHT — surface a banner so they know something
    // is wrong instead of staring at an indefinite "Connecting…" state.
    // The timer is cancelled the moment we get conn:success, and re-armed
    // on every offline transition so a transient network blip after
    // initial success doesn't pop the banner.
    void scheduleNoConnectionBanner() {
      _noConnectionBannerTimer?.cancel();
      _noConnectionBannerTimer = Timer(const Duration(seconds: 30), () {
        if (!mounted) return;
        if (widget.service.isConnected) return;
        final usedFallback = BootstrapNodesService.lastFetchUsedFallback;
        _showSnackBar(
          usedFallback
              ? 'Cannot reach the DHT. Using fallback bootstrap nodes — your network may be blocking UDP, or the nodes are down.'
              : 'Cannot reach the DHT after 30s. Check your network connection.',
        );
      });
    }

    scheduleNoConnectionBanner();
    _bag.add(() {
      _noConnectionBannerTimer?.cancel();
      _noConnectionBannerTimer = null;
    });
    _connectionStatusSub = widget.service.connectionStatusStream.listen((
      connected,
    ) async {
      AppLogger.log(
        '[HomePage] Connection status changed: connected=$connected, selfId=${widget.service.selfId}',
      );
      unawaited(_updateTray());
      if (!connected) {
        scheduleNoConnectionBanner();
      } else {
        _noConnectionBannerTimer?.cancel();
        _noConnectionBannerTimer = null;
      }
      if (connected) {
        final selfId = widget.service.selfId;
        AppLogger.debug(
          '[HomePage] Connection established: Checking plugin registration - _stickerPluginRegistered=$_stickerPluginRegistered, selfId=$selfId, isEmpty=${selfId.isEmpty}',
        );
        if (!_stickerPluginRegistered && selfId.isNotEmpty) {
          AppLogger.debug(
            '[HomePage] Connection established: Scheduling plugin registration',
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              AppLogger.debug(
                '[HomePage] Connection established: PostFrameCallback executing, calling _tryRegisterStickerPlugin',
              );
              _tryRegisterStickerPlugin();
            } else {
              AppLogger.debug(
                '[HomePage] Connection established: PostFrameCallback skipped - not mounted',
              );
            }
          });
        } else {
          AppLogger.debug(
            '[HomePage] Connection established: Skipping plugin registration - already registered or selfId empty',
          );
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
        .on<TencentCloudChatConversationData<dynamic>>(
          "TencentCloudChatConversationData",
        )
        ?.listen((data) {
          if (data.currentUpdatedFields ==
              TencentCloudChatConversationDataKeys.currentConversation) {
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
                    unawaited(
                      NotificationService.instance.clearConversationGroup(
                        conversationID,
                      ),
                    );
                  }
                });
              }
            }
          }
          if (data.currentUpdatedFields ==
              TencentCloudChatConversationDataKeys.totalUnreadCount) {
            unawaited(_updateTray());
          }
        });
    _bag.add(() => _conversationDataSub?.cancel());

    _contactDataSub = TencentCloudChat.instance.eventBusInstance
        .on<TencentCloudChatContactData<dynamic>>("TencentCloudChatContactData")
        ?.listen((data) {
          if (data.currentUpdatedFields ==
              TencentCloudChatContactDataKeys.groupList) {
            if (kDebugMode)
              debugPrint(
                '[HomePage] Group list updated, refreshing conversations',
              );
            Future.delayed(const Duration(milliseconds: 100), () {
              FakeUIKit.instance.im?.refreshConversations().catchError((
                e,
                stackTrace,
              ) {
                AppLogger.logError(
                  '[HomePage] Error refreshing conversations after group list update',
                  e,
                  stackTrace,
                );
              });
            });
          }
          if (data.currentUpdatedFields ==
                  TencentCloudChatContactDataKeys.applicationCount ||
              data.currentUpdatedFields ==
                  TencentCloudChatContactDataKeys.applicationList) {
            unawaited(_updateTray());
          }
        });
    _bag.add(() => _contactDataSub?.cancel());

    _groupProfileDataSub = TencentCloudChat.instance.eventBusInstance
        .on<TencentCloudChatGroupProfileData<dynamic>>(
          "TencentCloudChatGroupProfileData",
        )
        ?.listen((data) async {
          if (data.currentUpdatedFields ==
              TencentCloudChatGroupProfileDataKeys.membersChange) {
            final groupID = data.updateGroupID;
            if (groupID.isNotEmpty) {
              final lastChangeTime = _lastMembersChangeTime[groupID];
              if (lastChangeTime != null) {
                final timeSinceLastChange = DateTime.now().difference(
                  lastChangeTime,
                );
                if (timeSinceLastChange <
                    _HomePageState._minMembersChangeInterval) {
                  if (kDebugMode)
                    debugPrint(
                      '[HomePage] Ignoring rapid membersChange event for group $groupID (${timeSinceLastChange.inMilliseconds}ms ago)',
                    );
                  return;
                }
              }
              _lastMembersChangeTime[groupID] = DateTime.now();
            }
          }
          if (data.currentUpdatedFields ==
              TencentCloudChatGroupProfileDataKeys.quitGroup) {
            final groupID = data.updateGroupID;
            if (kDebugMode)
              debugPrint(
                '[HomePage] Group quit/dismissed: $groupID, removing from lists',
              );

            final savedGroups = await Prefs.getGroups();
            if (savedGroups.contains(groupID)) {
              savedGroups.remove(groupID);
              await Prefs.setGroups(savedGroups);
              if (kDebugMode)
                debugPrint(
                  '[HomePage] Removed group $groupID from Prefs.getGroups()',
                );
            }

            final convId = 'group_$groupID';
            if (_currentConversationID == convId) {
              if (kDebugMode)
                debugPrint(
                  '[HomePage] Quit group $groupID is currently open, clearing chat window',
                );
              UikitDataFacade.currentConversation = null;
              if (mounted) {
                _bootstrapSetState(() {
                  _currentConversationID = null;
                });
              }
            }

            UikitDataFacade.removeConversation([convId]);
            if (kDebugMode)
              debugPrint(
                '[HomePage] Removed conversation $convId from conversation list',
              );

            FakeUIKit.instance.eventBusInstance.emit(
              FakeIM.topicGroupDeleted,
              FakeGroupDeleted(groupID: groupID),
            );
            if (kDebugMode)
              debugPrint(
                '[HomePage] Emitted FakeGroupDeleted event for group $groupID',
              );
          } else if (data.currentUpdatedFields ==
              TencentCloudChatGroupProfileDataKeys.builder) {
            if (UikitDataFacade.updateGroupID.isEmpty ||
                UikitDataFacade.updateGroupInfo.groupID.isEmpty) {
              Future.microtask(() async {
                final currentConv = UikitDataFacade.currentConversation;
                String? targetGroupID;
                V2TimGroupInfo? targetGroupInfo;

                if (currentConv?.groupID != null &&
                    currentConv!.groupID!.isNotEmpty) {
                  targetGroupID = currentConv.groupID!;
                } else {
                  final convList = UikitDataFacade.conversationList;
                  for (final conv in convList) {
                    if (conv.groupID != null && conv.groupID!.isNotEmpty) {
                      targetGroupID = conv.groupID!;
                      break;
                    }
                  }
                }

                if (targetGroupID != null && targetGroupID.isNotEmpty) {
                  targetGroupInfo = UikitDataFacade.getGroupInfo(targetGroupID);

                  if (targetGroupInfo.groupID.isEmpty) {
                    final groupList = UikitDataFacade.groupList;
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
                    final groupAvatar = await Prefs.getGroupAvatar(
                      targetGroupID,
                    );
                    targetGroupInfo = V2TimGroupInfo(
                      groupID: targetGroupID,
                      groupType: "Work",
                      groupName: groupName ?? targetGroupID,
                      faceUrl: groupAvatar,
                    );
                  }

                  UikitDataFacade.updateGroupID = targetGroupID;
                  UikitDataFacade.updateGroupInfo = targetGroupInfo;
                }
              });
            }
          }
        });
    _bag.add(() => _groupProfileDataSub?.cancel());

    // Initial useDesktopMode is derived from the current breakpoint so phones
    // don't briefly render the two-column layout before the post-frame
    // `forceDesktopLayout` reconciliation in `build()` flips it back.
    // TODO(responsive): sync with breakpoint changes — `build()` already calls
    // `setConfigs(forceDesktopLayout: ...)` on threshold crossings; this only
    // sets the boot-time default.
    final bootUseDesktopMode = ResponsiveLayout.shouldShowMasterDetail(context);
    conv_pkg.TencentCloudChatConversationManager.config.setConfigs(
      useDesktopMode: bootUseDesktopMode,
    );

    msg_pkg.TencentCloudChatMessageManager.config.setConfigs(
      showSelfAvatar: createDefaultValue(true),
      showOthersAvatar: createDefaultValue(true),
      enableParseMarkdown: createDefaultValue(true),
      enableAutoReportReadStatusForComingMessages: createDefaultValue(true),
      enabledGroupTypesForMessageReadReceipt: createDefaultValue<List<String>>([
        GroupType.Work,
        GroupType.Public,
        GroupType.Meeting,
        GroupType.Community,
      ]),
      attachmentConfig: createDefaultValue(
        TencentCloudChatMessageAttachmentConfig(
          enableSendImage: false,
          enableSendVideo: false,
          enableSendFile: false,
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
      additionalAttachmentOptionsForMobile:
          ({String? userID, String? groupID, String? topicID}) {
            final appL10n = AppLocalizations.of(context)!;
            final fileLabel = appL10n.file;
            final photoLabel = appL10n.photo;
            final videoLabel = appL10n.video;
            return [
              TencentCloudChatMessageGeneralOptionItem(
                icon: Icons.attach_file,
                label: fileLabel,
                onTap: ({Offset? offset}) async {
                  await _sendMedia(
                    context,
                    userId: userID,
                    groupId: groupID,
                    type: _MediaPickType.file,
                  );
                },
              ),
              TencentCloudChatMessageGeneralOptionItem(
                icon: Icons.photo_outlined,
                label: photoLabel,
                onTap: ({Offset? offset}) async {
                  await _sendMedia(
                    context,
                    userId: userID,
                    groupId: groupID,
                    type: _MediaPickType.image,
                  );
                },
              ),
              TencentCloudChatMessageGeneralOptionItem(
                icon: Icons.videocam_outlined,
                label: videoLabel,
                onTap: ({Offset? offset}) async {
                  await _sendMedia(
                    context,
                    userId: userID,
                    groupId: groupID,
                    type: _MediaPickType.video,
                  );
                },
              ),
            ];
          },
      additionalInputControlBarOptionsForDesktop:
          ({String? userID, String? groupID, String? topicID}) {
            return _buildDesktopInputOptions(
              context,
              userID: userID,
              groupID: groupID,
            );
          },
    );

    msg_pkg.TencentCloudChatMessageManager.builder.setBuilders(
      messageNoChatBuilder: () => const TencentCloudChatMessageNoChat(),
      messageHeaderBuilder:
          ({
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
                messageHeaderMessagesSelectMode:
                    widgets.messageHeaderMessagesSelectMode,
                messageHeaderInfo: ToxeeMessageHeaderInfo(
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
      messageInputBuilder:
          ({
            Key? key,
            MessageInputBuilderWidgets? widgets,
            required MessageInputBuilderData data,
            required MessageInputBuilderMethods methods,
          }) {
            final hasStickerPlugin = UikitDataFacade.hasPlugin("sticker");
            final stickerPluginInstance = UikitDataFacade.getPlugin(
              "sticker",
            )?.pluginInstance;

            AppLogger.debug(
              '[HomePage] messageInputBuilder: Dynamically checking plugin - hasStickerPlugin=$hasStickerPlugin, instance=${stickerPluginInstance != null}',
            );

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
              currentFilteredMembersListForMention:
                  data.currentFilteredMembersListForMention,
              groupMemberList: data.groupMemberList,
              membersNeedToMention: data.membersNeedToMention,
              specifiedMessageText: data.specifiedMessageText,
              currentConversationShowName: data.currentConversationShowName,
              hasStickerPlugin: hasStickerPlugin,
              stickerPluginInstance: stickerPluginInstance,
            );

            // Wrap the upstream message input with a stable [UiKeys.chatInputTextField]
            // boundary so UI automation (marionette, flutter_test) can target the
            // composer without patching the UIKit fork. NOTE: this key wraps the
            // *whole* input row (text field + attachment + send affordances on
            // mobile). Marionette's `enterText` will deliver to the focused
            // descendant TextField; on desktop, send is keyboard-driven (no
            // separate tappable Send button). See [UiKeys.chatSendButton] doc.
            return KeyedSubtree(
              key: UiKeys.chatInputTextField,
              child: TencentCloudChatMessageInput(
                key: key,
                data: updatedData,
                methods: methods,
                widgets: widgets,
              ),
            );
          },
      messageItemBuilder:
          ({
            Key? key,
            MessageItemBuilderWidgets? widgets,
            required MessageItemBuilderData data,
            required MessageItemBuilderMethods methods,
          }) {
            final defaultWidget =
                widgets?.messageItemView ??
                TencentCloudChatMessageItemBuilders.getMessageItemBuilder(
                  key: key,
                  data: data,
                  methods: methods,
                );

            final isGroupMessage =
                data.groupID != null && data.groupID!.isNotEmpty;
            final isSelfMessage = data.message.isSelf ?? false;
            final msgID = data.message.msgID ?? '';

            if (isGroupMessage && isSelfMessage && msgID.isNotEmpty) {
              final receiverCount =
                  FakeUIKit.instance.messageManager?.getMessageReceiverCount(
                    msgID,
                  ) ??
                  0;

              if (receiverCount > 0) {
                final scheme = Theme.of(context).colorScheme;
                return Stack(
                  children: [
                    defaultWidget,
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => _showMessageReceiversDialog(
                            context,
                            msgID,
                            data.groupID!,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xs + 2,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(
                                AppThemeConfig.badgeBorderRadius,
                              ),
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
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: scheme.onPrimary,
                                        fontWeight: FontWeight.w600,
                                        height: 1.0,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                ),
                              ],
                            ),
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

    conv_pkg.TencentCloudChatConversationManager.builder.setBuilders(
      conversationItemContentBuilder: (conversation) => KeyedSubtree(
        key: UiKeys.conversationListTile(conversation.conversationID),
        child: TencentCloudChatConversationItemContent(
          conversation: conversation,
        ),
      ),
    );
    _bag.add(
      () => conv_pkg.TencentCloudChatConversationManager.builder.setBuilders(),
    );

    final eventHandlers =
        conv_pkg.TencentCloudChatConversationManager.eventHandlers;
    final uiEventHandlers = eventHandlers.uiEventHandlers;

    uiEventHandlers.setEventHandlers(
      onTapConversationItem:
          ({
            required TencentCloudChatMessageOptions messageOptions,
            required V2TimConversation conversation,
            required bool inDesktopMode,
          }) async {
            final conversationID = conversation.conversationID;
            if (conversationID.isNotEmpty) {
              widget.service.setActivePeer(conversationID);
            }

            UikitDataFacade.currentConversation = conversation;

            return false;
          },
    );

    UikitDataFacade.updateInitializedStatus(true);
    UikitDataFacade.updateLoginStatus(true);
    final selfId = widget.service.selfId;
    AppLogger.debug(
      '[HomePage] _buildHomePage: Setting current user info, selfId=$selfId',
    );
    UikitDataFacade.updateCurrentUserInfo(V2TimUserFullInfo(userID: selfId));

    if (!_stickerPluginRegistered &&
        !_stickerPluginRegistrationScheduled &&
        selfId.isNotEmpty) {
      AppLogger.debug(
        '[HomePage] _buildHomePage: Scheduling sticker plugin registration, selfId=$selfId',
      );
      // Set the scheduled flag immediately so any rebuilds before the post-
      // frame callback fires don't enqueue more callbacks.
      _stickerPluginRegistrationScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          AppLogger.debug(
            '[HomePage] _buildHomePage: PostFrameCallback executing, calling _tryRegisterStickerPlugin',
          );
          _tryRegisterStickerPlugin();
        } else {
          AppLogger.debug(
            '[HomePage] _buildHomePage: PostFrameCallback skipped - not mounted',
          );
        }
      });
    } else {
      AppLogger.debug(
        '[HomePage] _buildHomePage: Skipping plugin registration - _stickerPluginRegistered=$_stickerPluginRegistered, selfId.isEmpty=${selfId.isEmpty}',
      );
    }

    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        final hasPluginAfter = UikitDataFacade.hasPlugin("sticker");
        final pluginAfter = UikitDataFacade.getPlugin("sticker");
        AppLogger.debug(
          '[HomePage] _buildHomePage: Plugin status after 500ms - hasPlugin=$hasPluginAfter, plugin=${pluginAfter != null}, instance=${pluginAfter?.pluginInstance}',
        );
      }
    });

    final provider = ChatDataProviderRegistry.provider;
    if (provider != null) {
      unawaited(
        provider
            .getInitialConversations()
            .then((list) {
              UikitDataFacade.buildConversationList(list, 'external_init');
            })
            .catchError((e, st) {
              AppLogger.logError(
                '[HomePage] getInitialConversations failed',
                e,
                st,
              );
            }),
      );
      _convProviderSub = provider.conversationStream.listen((list) {
        UikitDataFacade.buildConversationList(list, 'external_stream');
      });
      _bag.add(() => _convProviderSub?.cancel());
      _unreadProviderSub = provider.totalUnreadStream.listen((total) {
        UikitDataFacade.setTotalUnreadCount(total);
      });
      _bag.add(() => _unreadProviderSub?.cancel());
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
          FakeUIKit.instance.im!.refreshContacts().catchError((e, st) {
            AppLogger.logError(
              '[HomePage] refreshContacts after initial load failed',
              e,
              st,
            );
          });
        }
        // Register the OS-notification listener AFTER the initial history /
        // contacts load completes so historical messages don't fire banners
        // on first launch. The listener is idempotent — calling register()
        // twice is a no-op (see NotificationMessageListener._registered).
        if (mounted) {
          unawaited(
            NotificationMessageListener.forService(widget.service).register(
              onConversationTapped: (payload) {
                _routeToNotificationPayload(payload);
              },
            ),
          );
        }
      }
    });

    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
    _bag.add(() => _refreshTimer?.cancel());
    unawaited(_loadLocalFriends());

    final toxId = widget.service.accountKey;
    if (toxId.isNotEmpty) {
      Prefs.getAutoAcceptFriends(toxId).then((value) {
        if (mounted) {
          _bootstrapSetState(() => _autoAcceptFriends = value);
        }
      });
      // The Pref→(UI mirror + native-gate push), its order, and its mounted-guard
      // are extracted to `loadAndApplyAutoAcceptGroupInvites` so they are
      // L1-testable (S47) without pumping HomePage. mirrorToUi runs before the
      // push (matching the original order so a throwing FFI setter can't drop
      // the UI mirror — codex).
      unawaited(
        loadAndApplyAutoAcceptGroupInvites(
          widget.service,
          toxId,
          isStillMounted: () => mounted,
          mirrorToUi: (value) =>
              _bootstrapSetState(() => _autoAcceptGroupInvites = value),
        ),
      );
    }

    // S46/S47: let the L3 surface drive the LIVE auto-accept setters (cached
    // flag + Prefs + accept-pending), not just Prefs. No-op unless the L3 test
    // surface is enabled; cleared via _bag on dispose.
    registerL3AutoAcceptApplier((key, value) async {
      if (key == 'autoAcceptFriends') {
        await _setAutoAcceptFriends(value);
      } else if (key == 'autoAcceptGroupInvites') {
        await _setAutoAcceptGroupInvites(value);
      }
    });
    _bag.add(() => registerL3AutoAcceptApplier(null));
    registerL3HomeShellApplier((tab) async {
      final normalized = tab.trim().toLowerCase();
      final nextIndex = switch (normalized) {
        'contacts' => 1,
        'applications' => 2,
        'settings' => 3,
        _ => 0,
      };
      if (normalized == 'contacts') {
        _installContactProfileBuilders();
      }
      widget.service.setActivePeer(null);
      UikitDataFacade.currentConversation = null;
      if (mounted) {
        _bootstrapSetState(() {
          _index = nextIndex;
          _currentConversationID = null;
          _messageWidgetKeys.clear();
          _messageWidgetKeyCounter++;
          _inContactProfileContext = false;
        });
      }
    });
    _bag.add(() => registerL3HomeShellApplier(null));
    registerL3HomeShellSnapshotReader(() {
      final tab = switch (_index) {
        1 => 'contacts',
        2 => 'applications',
        3 => 'settings',
        _ => 'chats',
      };
      return {
        'tab': tab,
        'index': _index,
        'currentConversationId': _currentConversationID,
        'inContactProfileContext': _inContactProfileContext,
      };
    });
    _bag.add(() => registerL3HomeShellSnapshotReader(null));
    registerL3OpenAddFriendDialogInvoker(() async {
      if (!mounted) return false;
      // Fire-and-forget: PUSH the dialog and return immediately. Awaiting
      // showDialog() here would not complete until the dialog is DISMISSED,
      // which stalls the l3_open_add_friend_dialog service-extension response
      // (mcp_toolkit only replies once the handler future resolves), hanging any
      // caller that opens-then-drives. The hook's contract is "open, then fill +
      // submit through real UI", so the open call must return as soon as the
      // dialog is on screen.
      unawaited(_showAddFriendDialog());
      return true;
    });
    _bag.add(() => registerL3OpenAddFriendDialogInvoker(null));
    registerL3OpenAddGroupDialogInvoker(() async {
      if (!mounted) return false;
      // Same fire-and-forget contract as the add-friend invoker above.
      unawaited(_showAddGroupDialog());
      return true;
    });
    _bag.add(() => registerL3OpenAddGroupDialogInvoker(null));
    registerL3OpenGroupAddMemberInvoker((groupId) async {
      if (!mounted) return false;
      // Same fire-and-forget contract as the dialog invokers above: PUSH the
      // real add-member screen and return as soon as it is on screen so the
      // l3_open_group_add_member service-extension response is not blocked
      // until the screen is popped.
      return _openGroupAddMember(groupId);
    });
    _bag.add(() => registerL3OpenGroupAddMemberInvoker(null));
    registerL3OpenGroupMemberListInvoker((groupId) async {
      if (!mounted) return false;
      // Same fire-and-forget contract as the add-member invoker above: PUSH the
      // real member-list page and return as soon as it is on screen so the
      // l3_open_group_member_list service-extension response is not blocked
      // until the page is popped. The member rows / kick menu / scroll are then
      // driven through the real member-list UI.
      return _openGroupMemberList(groupId);
    });
    _bag.add(() => registerL3OpenGroupMemberListInvoker(null));
    registerL3OpenConversationMenuInvoker((conversationId, {action}) async {
      if (!mounted) return false;
      // Resolve the conversation from the live UIKit list (the same source the
      // sidebar renders and l3_dump_state reports). The menu's
      // pin/mark-read/delete branches only need conversationID + isPinned +
      // unreadCount, all carried on the V2TimConversation.
      V2TimConversation? target;
      for (final conv in UikitDataFacade.conversationList) {
        if (conv.conversationID == conversationId) {
          target = conv;
          break;
        }
      }
      if (target == null) return false;
      if (action != null) {
        // Deterministic path: dispatch the SAME production handler the visual
        // menu's onSelected runs (pin/mark_read/delete), bypassing the
        // PopupMenuItem tap (flutter_skill double-fires InkWell-backed items —
        // fatal for the pin toggle). `delete` still raises the real confirm
        // dialog, awaited internally; fire-and-forget so the l3 response is not
        // blocked on that dialog (same contract as the menu-open path below).
        unawaited(_dispatchConversationMenuAction(target, action));
        return true;
      }
      // Fixed in-bounds anchor (the real menu is cursor-positioned; any offset
      // renders the same keyed PopupMenuItems). Fire-and-forget:
      // _showConversationContextMenu awaits showMenu until DISMISSED, so awaiting
      // here would block the l3 response (same contract as the dialog invokers).
      unawaited(_showConversationContextMenu(target, const Offset(200, 200)));
      return true;
    });
    _bag.add(() => registerL3OpenConversationMenuInvoker(null));

    _checkIrcAppStatus();
    _msgSub = widget.service.messages.listen((m) {
      if (widget.service.selfId == m.fromUserId) return;
      if (!mounted) return;
      // Note: no setState here — UIKit's own data layer drives unread badges
      // and conversation rows via EventBus. The previous empty setState() was
      // a no-op that forced a full HomePage rebuild every message.
      unawaited(_updateTray());
    });
    _bag.add(() => _msgSub?.cancel());

    _progressUpdatesSub = widget.service.progressUpdates.listen((progress) {
      if (!mounted) return;
    });
    _bag.add(() => _progressUpdatesSub?.cancel());

    _friendsSub = FakeUIKit.instance.eventBusInstance
        .on<List<FakeUser>>(FakeIM.topicContacts)
        .listen((list) async {
          // CR-08: capture the session this listener was bound to. On account
          // switch the old HomePage is disposed and a new one with a different
          // service replaces it; an in-flight async body that already passed an
          // `await` must not keep writing into the new session's global FakeUIKit
          // / UikitDataFacade state. Re-check after every await before any global
          // write. The try/catch keeps a Prefs throw from becoming an unhandled
          // Future error on the async onData.
          final boundService = widget.service;
          bool stillCurrent() =>
              mounted && identical(widget.service, boundService);
          try {
            final mapped = await Future.wait(
              list.map((u) async {
                final avatarPath = await Prefs.getFriendAvatarPath(u.userID);
                final faceUrl = (avatarPath != null && avatarPath.isNotEmpty)
                    ? avatarPath
                    : null;
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
              }),
            );
            if (!stillCurrent()) return;
            UikitDataFacade.buildFriendList(mapped, "home");
            final freshUserIds = list.map((u) => u.userID).toSet();
            final currentContactList = UikitDataFacade.contactList;
            final staleUserIds = currentContactList
                .where((c) => !freshUserIds.contains(c.userID))
                .map((c) => c.userID)
                .where((id) => id.isNotEmpty)
                .toList();
            if (staleUserIds.isNotEmpty) {
              UikitDataFacade.deleteFromFriendList(staleUserIds, 'home_sync');
            }
            final statuses = list
                .map(
                  (u) => V2TimUserStatus(
                    userID: u.userID,
                    statusType: u.online ? 1 : 0,
                    onlineDevices: const [],
                  ),
                )
                .toList();
            if (statuses.isNotEmpty) {
              UikitDataFacade.buildUserStatusList(statuses, "home");
            }

            if (!stillCurrent()) return;
            final groups = widget.service.knownGroups;
            for (final gid in groups) {
              final savedName = await Prefs.getGroupName(gid);
              final savedAvatar = await Prefs.getGroupAvatar(gid);
              if (!stillCurrent()) return;
              final groupInfo = V2TimGroupInfo(
                groupID: gid,
                groupType: "work",
                groupName: savedName,
                faceUrl: savedAvatar,
              );
              UikitDataFacade.addGroupInfoToJoinedGroupList(groupInfo);
            }

            final friendIds = list.map((u) {
              final id = u.userID.trim();
              return id.length > 64 ? id.substring(0, 64) : id;
            }).toSet();
            if (stillCurrent()) {
              _bootstrapSetState(() {
                _localFriends = friendIds;
              });
            }
          } catch (e, st) {
            AppLogger.logError('[HomePage] contacts listener failed', e, st);
          }
        });
    _bag.add(() => _friendsSub?.cancel());

    if (FakeUIKit.instance.im != null) {
      FakeUIKit.instance.im!.forceRefreshContacts().catchError((e) {
        AppLogger.debug(
          '[HomePage] forceRefreshContacts after _friendsSub error: $e',
        );
      });
    }

    _appsSub = FakeUIKit.instance.eventBusInstance
        .on<List<FakeFriendApplication>>(FakeIM.topicFriendApps)
        .listen((list) async {
          // CR-08: same session guard as _friendsSub. Bail before any global
          // write if this HomePage was disposed or replaced by another account's
          // session, and wrap the body so a throw never escapes as an unhandled
          // Future error.
          final boundService = widget.service;
          bool stillCurrent() =>
              mounted && identical(widget.service, boundService);
          try {
            if (!stillCurrent()) return;
            final mapped = list.map((a) {
              final inferredNickname = inferFriendRequestNicknameFromWording(
                a.wording,
              );
              return V2TimFriendApplication(
                userID: a.userID,
                addWording: a.wording,
                type: 1,
                nickname: inferredNickname,
                faceUrl: null,
              );
            }).toList();
            UikitDataFacade.buildApplicationList(mapped, "home");
            UikitDataFacade.setApplicationUnreadCount(mapped);
            _pendingFriendApps = List<V2TimFriendApplication>.from(mapped);
            // P1-D3: fire an OS-level notification for any application userID we
            // have not yet notified about in this session. Auto-accept users won't
            // see the banner because we silently accept below before the user
            // would have time to read it — that's acceptable; the snackbar at
            // accept-time covers them.
            if (!_autoAcceptFriends) {
              for (final app in mapped) {
                final uid = app.userID;
                if (uid.isEmpty) continue;
                if (_notifiedFriendReqUserIds.contains(uid)) continue;
                _notifiedFriendReqUserIds.add(uid);
                final senderName = resolveFriendRequestDisplayName(
                  userId: uid,
                  nickname: app.nickname,
                  wording: app.addWording,
                );
                unawaited(
                  NotificationService.instance.showFriendRequestNotification(
                    senderId: uid,
                    senderName: senderName,
                    requestMessage: app.addWording ?? '',
                  ),
                );
              }
            }
            // If applications were withdrawn / accepted / rejected on this device
            // before we recorded them, prune the dedup set so a fresh request from
            // the same peer can re-notify later in the session.
            final currentIds = mapped.map((a) => a.userID).toSet();
            _notifiedFriendReqUserIds.removeWhere(
              (id) => !currentIds.contains(id),
            );
            if (_autoAcceptFriends && mapped.isNotEmpty) {
              _acceptFriendApplications(mapped).catchError((e, st) {
                AppLogger.logError(
                  '[HomePage] auto-accept friend applications failed',
                  e,
                  st,
                );
              });
            }
            // No setState — UIKit's contact data layer drives application-row UI;
            // tray update still needs to fire on each apps event.
            unawaited(_updateTray());
          } catch (e, st) {
            AppLogger.logError('[HomePage] friend apps listener failed', e, st);
          }
        });
    _bag.add(() => _appsSub?.cancel());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_updateTray());
    });

    _contactBuilderOverride = ContactBuilderOverrideHandle.capture();
    _bag.add(() => _contactBuilderOverride?.restore());

    _installContactProfileBuilders();

    _groupBuilderOverride = GroupProfileBuilderOverrideHandle.capture();
    _bag.add(() => _groupBuilderOverride?.restore());
    _groupBuilderOverride!.installOverrides();
  }

  /// Routes a notification payload (`c2c_<toxId>` or `group_<groupId>`) to the
  /// matching conversation using the same plumbing the conversation-list tap
  /// uses (`_selectConversation` → `UikitDataFacade.currentConversation`).
  ///
  /// Cold-start safety: when the tap fires before the conversation list has
  /// loaded (replayed launch payload), `_selectConversation` constructs a stub
  /// V2TimConversation so the chat view can open immediately. We additionally
  /// schedule a single retry once the list populates so the conversation gets
  /// rebound to the real entry (proper showName, lastMessage, unreadCount).
  void _routeToNotificationPayload(String payload) {
    if (!mounted) return;
    String? peerId;
    String? groupId;
    if (payload.startsWith('group_')) {
      groupId = payload.substring('group_'.length);
    } else if (payload.startsWith('c2c_')) {
      peerId = payload.substring('c2c_'.length);
    } else if (payload.startsWith('missed_call:')) {
      // Tox calls are 1:1 only, so a missed_call payload always maps to a c2c
      // conversation with the caller. There's no dedicated call-records view —
      // call records are persisted as messages in that c2c chat, so opening
      // the conversation lands the user on the missed-call entry.
      peerId = payload.substring('missed_call:'.length);
    } else {
      AppLogger.warn(
        '[HomePage] Notification payload has unknown prefix: $payload',
      );
      return;
    }
    if ((peerId == null || peerId.isEmpty) &&
        (groupId == null || groupId.isEmpty)) {
      AppLogger.warn(
        '[HomePage] Notification payload empty after strip: $payload',
      );
      return;
    }

    final listEmpty = UikitDataFacade.conversationList.isEmpty;
    // Use _openChat (not _selectConversation) so the home shell also flips
    // to the Chats tab (_index = 0). Without this, tapping a notification
    // while on Settings/Contacts sets currentConversation but the user
    // still sees the previous tab and the tap looks dead.
    _openChat(peerId: peerId, groupId: groupId);

    if (!listEmpty) return;
    // Cold-start path: list hadn't loaded yet, so the call above only set a
    // stub conversation. Wait for the list to populate (one shot, capped at
    // 2s) and re-select so the chat view picks up the real entry.
    StreamSubscription<TencentCloudChatConversationData<dynamic>>? sub;
    Timer? timeout;
    void cleanup() {
      sub?.cancel();
      sub = null;
      timeout?.cancel();
      timeout = null;
    }

    sub = TencentCloudChat.instance.eventBusInstance
        .on<TencentCloudChatConversationData<dynamic>>(
          "TencentCloudChatConversationData",
        )
        ?.listen((data) {
          if (data.currentUpdatedFields !=
              TencentCloudChatConversationDataKeys.conversationList) {
            return;
          }
          if (UikitDataFacade.conversationList.isEmpty) return;
          cleanup();
          if (!mounted) return;
          _openChat(peerId: peerId, groupId: groupId);
        });
    timeout = Timer(const Duration(seconds: 2), () {
      if (sub == null) return;
      cleanup();
      AppLogger.debug(
        '[HomePage] Notification routing: conversation list still empty after 2s, keeping stub for payload=$payload',
      );
    });
  }
}
