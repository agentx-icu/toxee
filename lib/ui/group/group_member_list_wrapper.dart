// Wrapper to refresh member list before opening the member list page
import 'dart:async';

import 'package:flutter/material.dart';

// ignore: directives_ordering
import '../widgets/safe_dialog_pop.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat_common.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_group_member_list.dart';
import '../../i18n/app_localizations.dart';
import '../../sdk_fake/fake_uikit_core.dart';
import '../../sdk_fake/uikit_data_facade.dart';
import '../../util/group_member_last_seen_cache.dart';
import '../../util/logger.dart';
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
  int _emptyRetries = 0; // Bounded re-fetches when a fresh NGC group returns an empty member list

  void _enrichAvatars(List<V2TimGroupMemberFullInfo> members) {
    final contactList = UikitDataFacade.contactList;
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
        // Reset the empty-retry budget for the NEW group — otherwise a State
        // reused across groups could exhaust it on the first group and leave a
        // later group with no empty-list retries.
        _emptyRetries = 0;
      });
      // An in-flight fetch for the previous group is harmless: it snapshots
      // its own groupID at entry and will abort after the await when it sees
      // widget.groupInfo.groupID has changed. Re-enter unconditionally.
      _refreshMemberList();
    }
  }

  Future<void> _refreshMemberList() async {
    // Snapshot at entry. After every await we re-check that the widget is
    // still bound to the same group; otherwise a stale fetch from a previous
    // group would poison the new group's state.
    final groupID = widget.groupInfo.groupID;

    // Prevent duplicate concurrent calls. _hasLoaded is reset in
    // didUpdateWidget when the group changes, so this guard does not block
    // legitimate cross-group refreshes. We deliberately do NOT also gate on
    // `_isRefreshing` here: when didUpdateWidget re-enters with a stale call
    // still in flight, the stale call will see groupID != widget.groupInfo
    // .groupID after its await and abort, so a concurrent re-entry is safe.
    if (_hasLoaded) {
      return;
    }

    _isRefreshing = true;
    bool succeeded = false;
    try {
      // Call data layer directly to get fresh data from native
      // (bypass GroupMemberListDebouncer to avoid stale cached data)
      final updatedList = await UikitDataFacade.loadGroupMemberList(
        groupID: groupID,
        loadGroupAdminAndOwnerOnly: false,
      );

      if (!mounted || groupID != widget.groupInfo.groupID) {
        return;
      }

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
          await ffi.messageHistoryPersistence.loadHistory(groupID);
        }
      } catch (e) {
        AppLogger.warn(
            '[GroupMemberListWrapper] history load failed; time map will be empty: $e');
      }
      if (!mounted || groupID != widget.groupInfo.groupID) return;
      final timeMap = _buildLastMessageTimeMap(groupID);
      if (!mounted || groupID != widget.groupInfo.groupID) return;
      setState(() {
        _currentMemberList = dedupedList;
        _lastMessageTimeMap = timeMap;
        _isLoading = false;
        // Only LATCH _hasLoaded on a NON-EMPTY load. A freshly-created same-host
        // NGC group can momentarily return an empty member list (the founder /
        // self row lags one fetch); latching that empty would render a permanent
        // blank member page with no retry. Leaving _hasLoaded false lets a
        // rebuild / the scheduled retry below re-fetch until the self row lands.
        _hasLoaded = dedupedList.isNotEmpty;
      });
      succeeded = true;
      if (dedupedList.isEmpty && _emptyRetries < 6) {
        _emptyRetries++;
        Future.delayed(const Duration(milliseconds: 700), () {
          if (mounted &&
              !_hasLoaded &&
              groupID == widget.groupInfo.groupID) {
            unawaited(_refreshMemberList());
          }
        });
      }
    } catch (e, st) {
      // A thrown FFI/native error used to leave _isLoading true forever
      // because only _isRefreshing was reset in the finally. Surface the
      // failure to the empty-state path instead of an infinite shimmer.
      AppLogger.logError(
          '[GroupMemberListWrapper] member fetch failed for $groupID', e, st);
    } finally {
      _isRefreshing = false;
      // On any non-success exit (exception or early return because the
      // widget was reused for a different group while in flight) we still
      // need to drop the loading shimmer so the UI can render the empty
      // state or the next group's content.
      if (!succeeded && mounted && groupID == widget.groupInfo.groupID) {
        setState(() {
          _isLoading = false;
        });
      }
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
                onPressed: () => popDialogIfCurrent(context),
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
                onPressed: () => popDialogIfCurrent(context),
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
