// Wrapper to refresh member list before opening the member list page
import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat_common.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_group_member_list.dart';
import '../../i18n/app_localizations.dart';
import '../../sdk_fake/fake_uikit_core.dart';
import '../../util/group_member_last_seen_cache.dart';
import '../../util/responsive_layout.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/loading_shimmer.dart';

class GroupMemberListWrapper extends StatefulWidget {
  final V2TimGroupInfo groupInfo;
  final List<V2TimGroupMemberFullInfo> memberInfoList;

  const GroupMemberListWrapper({
    Key? key,
    required this.groupInfo,
    required this.memberInfoList,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => GroupMemberListWrapperState();
}

class GroupMemberListWrapperState extends TencentCloudChatState<GroupMemberListWrapper> {
  List<V2TimGroupMemberFullInfo> _currentMemberList = [];
  Map<String, int> _lastMessageTimeMap = {};
  bool _isLoading = true;
  bool _isRefreshing = false; // Prevent duplicate calls
  bool _hasLoaded = false; // Track if we've already loaded to prevent reloads on widget rebuilds

  void _enrichAvatars(List<V2TimGroupMemberFullInfo> members) {
    final contactList = TencentCloudChat.instance.dataInstance.contact.contactList;
    final friendFaceUrls = <String, String>{};
    final friendNickNames = <String, String>{};
    for (final friend in contactList) {
      final faceUrl = friend.userProfile?.faceUrl;
      if (faceUrl != null && faceUrl.isNotEmpty) {
        friendFaceUrls[friend.userID] = faceUrl;
      }
      final nickName = friend.userProfile?.nickName;
      if (nickName != null && nickName.isNotEmpty) {
        friendNickNames[friend.userID] = nickName;
      }
    }
    for (final member in members) {
      if (member.faceUrl == null || member.faceUrl!.isEmpty) {
        member.faceUrl = friendFaceUrls[member.userID];
      }
      if (member.nickName == null || member.nickName!.isEmpty) {
        member.nickName = friendNickNames[member.userID];
      }
    }
  }

  Map<String, int> _buildLastMessageTimeMap(String groupID) {
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi == null) return {};
    // Cached: built lazily on first read for this group, then kept up to
    // date by the FakeIM message bus. Saves re-iterating the full group
    // history on every member-list mount.
    return GroupMemberLastSeenCache.instance.getOrBuild(groupID, ffi);
  }

  @override
  void initState() {
    super.initState();
    _refreshMemberList();
  }

  @override
  void didUpdateWidget(GroupMemberListWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the same widget element is reused for a DIFFERENT group (Flutter
    // recycles State across config changes), we must drop the old member
    // list and re-fetch. Previously we gated this on `!_hasLoaded`, which
    // meant we never re-fetched after the first load and the user kept
    // seeing the previous group's members.
    if (oldWidget.groupInfo.groupID != widget.groupInfo.groupID) {
      setState(() {
        _currentMemberList = [];
        _lastMessageTimeMap = {};
        _isLoading = true;
        _hasLoaded = false;
      });
      _refreshMemberList();
    }
  }

  Future<void> _refreshMemberList() async {
    // Prevent duplicate calls within the same widget instance + groupID.
    // didUpdateWidget resets _hasLoaded when the groupID changes so this
    // guard does not block legitimate cross-group refreshes.
    if (_isRefreshing || _hasLoaded) {
      return;
    }

    _isRefreshing = true;
    try {
      // Call data layer directly to get fresh data from native
      // (bypass GroupMemberListDebouncer to avoid stale cached data)
      final updatedList = await TencentCloudChat.instance.dataInstance.groupProfile
          .loadGroupMemberList(
        groupID: widget.groupInfo.groupID,
        loadGroupAdminAndOwnerOnly: false,
      );

      if (mounted) {
        // Deduplicate by userID (defense in depth)
        final seen = <String>{};
        final dedupedList = updatedList
            .whereType<V2TimGroupMemberFullInfo>()
            .where((m) => seen.add(m.userID))
            .toList();
        _enrichAvatars(dedupedList);
        // Load group history from disk so in-memory cache is populated before building time map
        try {
          final ffi = FakeUIKit.instance.im?.ffi;
          if (ffi != null) {
            await ffi.messageHistoryPersistence.loadHistory(widget.groupInfo.groupID);
          }
        } catch (_) {
          // Ignore load errors; time map will be empty
        }
        final timeMap = _buildLastMessageTimeMap(widget.groupInfo.groupID);
        if (!mounted) return;
        setState(() {
          _currentMemberList = dedupedList;
          _lastMessageTimeMap = timeMap;
          _isLoading = false;
          _hasLoaded = true; // Mark as loaded to prevent reloads
        });
      }
    } finally {
      _isRefreshing = false;
    }
  }

  @override
  Widget defaultBuilder(BuildContext context) {
    if (_isLoading || _isRefreshing) {
      return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Scaffold(
          appBar: AppBar(
            leadingWidth: 56 + ResponsiveLayout.responsiveHorizontalPadding(context),
            leading: Padding(
              // EdgeInsetsDirectional so the back-button gutter flips for RTL.
              padding: EdgeInsetsDirectional.only(start: ResponsiveLayout.responsiveHorizontalPadding(context)),
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_ios_rounded),
                color: colorTheme.primaryColor,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              ),
            ),
            scrolledUnderElevation: 0.0,
          ),
          body: const SafeArea(
            child: LoadingShimmer(itemCount: 10, itemHeight: 56),
          ),
        ),
      );
    }

    // Empty-state guard: when both the freshly-loaded list and the
    // widget-provided list are empty, UIKit's member list falls through to a
    // blank panel. Render a real empty state instead.
    if (_currentMemberList.isEmpty && widget.memberInfoList.isEmpty) {
      return TencentCloudChatThemeWidget(
        build: (context, colorTheme, textStyle) => Scaffold(
          appBar: AppBar(
            leadingWidth: 56 + ResponsiveLayout.responsiveHorizontalPadding(context),
            leading: Padding(
              padding: EdgeInsetsDirectional.only(start: ResponsiveLayout.responsiveHorizontalPadding(context)),
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_ios_rounded),
                color: colorTheme.primaryColor,
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              ),
            ),
            scrolledUnderElevation: 0.0,
          ),
          body: SafeArea(
            child: EmptyStateWidget(
              icon: Icons.group_outlined,
              title: AppLocalizations.of(context)?.noGroupMembers ??
                  'No members yet',
            ),
          ),
        ),
      );
    }

    // Use the original implementation with refreshed member list
    return TencentCloudChatGroupMemberList(
      groupInfo: widget.groupInfo,
      memberInfoList: _currentMemberList.isNotEmpty ? _currentMemberList : widget.memberInfoList,
      lastMessageTimeMap: _lastMessageTimeMap,
    );
  }
}
