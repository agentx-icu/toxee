part of 'home_page.dart';

/// Wires [MasterDetailTransition] to this shell's state (see that class).
extension _HomeMasterDetail on _HomePageState {
  /// Whether the last build used the master-detail layout; null before the
  /// first build.
  bool? get _lastShouldShowMasterDetail => _masterDetail.lastWide;

  MasterDetailTransition _createMasterDetailTransition() =>
      MasterDetailTransition(
        host: MasterDetailHost(
          isMounted: () => mounted,
          isChatsTabIdle: () => _index == 0 && !_inContactProfileContext,
          homeRoute: () => ModalRoute.of(context),
          showsMasterDetailNow: () =>
              ResponsiveLayout.shouldShowMasterDetail(context),
          accountKey: () => widget.service.accountKey,
          wideSelection: () {
            final conversation = UikitDataFacade.currentConversation;
            if (conversation == null) return null;
            return ChatTarget(
              userID: conversation.userID,
              groupID: conversation.groupID,
            );
          },
          rootNavigator: () => Navigator.maybeOf(context, rootNavigator: true),
          applyConfig: (wide) => UikitDataFacade.setConversationConfig(
            useDesktopMode: wide,
            forceDesktopLayout: wide,
          ),
          openChat: (target) {
            // Wide: also rebind the active peer — popping the chat route
            // unbound it and _selectConversation binds only the pane, so
            // unread counting would treat the chat as closed. (The compact
            // branch of _openChat binds by itself.)
            if (ResponsiveLayout.shouldShowMasterDetail(context)) {
              bindActiveConversation(
                service: widget.service,
                peerId: target.userID,
                groupId: target.groupID,
              );
            }
            _openChat(peerId: target.userID, groupId: target.groupID);
          },
        ),
      );
}
