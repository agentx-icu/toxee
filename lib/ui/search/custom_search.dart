import 'dart:async' show Timer;

// ignore: directives_ordering
import '../widgets/safe_dialog_pop.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/search/search_chat_history_window.dart';
import 'package:toxee/ui/widgets/search_utils.dart';
import 'package:toxee/util/responsive_layout.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import '../widgets/app_page_route.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/loading_shimmer.dart';
import '../../sdk_fake/uikit_data_facade.dart';
import '../../util/logger.dart';
import 'package:tencent_cloud_chat_common/chat_sdk/components/tencent_cloud_chat_search_sdk.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_message_options.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_common/router/tencent_cloud_chat_navigator.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_utils.dart';

/// Custom search component to replace tencent_cloud_chat_search
/// Raw (pre-filter) search inputs for the GLOBAL search path. In production
/// these come from the FFI-backed `searchSDK`; the optional
/// [CustomSearch.rawSearchDataOverride] seam lets a test feed them directly so
/// the REAL keyword filter (`_matchesKeywordCaseInsensitive`), row render, and
/// highlight run without the singleton SDK/FFI stack.
typedef RawGlobalSearchData = ({
  List<V2TimFriendInfoResult> contacts,
  List<V2TimGroupInfo> groups,
  List<TencentCloudChatSearchResultItemData> messages,
});

/// Fetches the raw global-search inputs for [keyword].
typedef RawGlobalSearchFetcher = Future<RawGlobalSearchData> Function(
  String keyword,
);

/// Opens the target conversation for a tapped result. In production this drives
/// the UIKit data facade + conversation SDK ([_CustomSearchState._navigateToMessage]);
/// the optional [CustomSearch.onOpenConversation] seam lets a test observe the
/// open-target without the singleton.
typedef OpenConversationCallback = void Function({
  String? userID,
  String? groupID,
  V2TimMessage? targetMessage,
});

class CustomSearch extends StatefulWidget {
  final String? userID;
  final String? groupID;
  final String? keyWord;
  final VoidCallback? closeFunc;

  /// Test seam: when set, replaces the FFI-backed `searchSDK` fetch in the
  /// GLOBAL search path. The real keyword filter + render + highlight still run
  /// on the supplied data. Production leaves this null.
  final RawGlobalSearchFetcher? rawSearchDataOverride;

  /// Test seam: when set, [_CustomSearchState._navigateToMessage] reports the
  /// open-target here instead of mutating the UIKit data facade. Production
  /// leaves this null.
  final OpenConversationCallback? onOpenConversation;

  const CustomSearch({
    super.key,
    this.userID,
    this.groupID,
    this.keyWord,
    this.closeFunc,
    this.rawSearchDataOverride,
    this.onOpenConversation,
  });

  @override
  State<CustomSearch> createState() => _CustomSearchState();
}

class _CustomSearchState extends State<CustomSearch> {
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';
  bool _isSearching = false;
  List<TencentCloudChatSearchResultItemData> _messageSearchResults = [];
  List<V2TimFriendInfoResult> _contactsList = [];
  List<V2TimGroupInfo> _groupsList = [];
  List<V2TimConversation> _conversationFallbackList = [];
  bool _isDesktop(BuildContext context) => ResponsiveLayout.isDesktop(context);
  Timer? _debounceTimer;
  String? _errorMessage;

  /// Cache for incremental contact/group filtering.
  String _lastSearchedKeyword = '';
  List<V2TimFriendInfoResult> _cachedRawContacts = [];
  List<V2TimGroupInfo> _cachedRawGroups = [];

  static bool _matchesKeywordCaseInsensitive(String? value, String keyword) {
    if (value == null || value.isEmpty || keyword.isEmpty) return false;
    return value.toLowerCase().contains(keyword.toLowerCase());
  }

  /// Truncate long IDs (64-char group IDs, 76-char Tox IDs) for display in
  /// `ListTile.subtitle`, where single-line ellipsis would just cut the tail
  /// and hide the suffix entirely. The full ID is still reachable via the
  /// detail page; this is purely a display compaction.
  static String _truncateIdForDisplay(String id) {
    if (id.length <= 20) return id;
    return '${id.substring(0, 8)}…${id.substring(id.length - 8)}';
  }

  // Delegate to shared utilities in SearchUtils.
  static Widget _avatarWidget(String? url, Widget defaultChild) =>
      SearchUtils.avatarWidget(url, defaultChild);
  static Widget _buildHighlightedText(
    String text,
    String keyword,
    TextStyle baseStyle, {
    bool isDark = false,
  }) => SearchUtils.buildHighlightedText(
    text,
    keyword,
    baseStyle,
    isDark: isDark,
  );

  /// Page size when loading history for search; total per conversation is capped by [_maxHistoryMessagesPerConversation].
  static const int _historySearchPageSize = 200;

  /// Max messages to load per conversation so that older history can be searched.
  static const int _maxHistoryMessagesPerConversation = 2000;

  /// Tighter cap for global search across many conversations: 5 pages × 200 = 1000
  /// per conversation, keeping peak memory bounded when scanning every chat.
  static const int _maxHistoryMessagesPerConversationGlobal = 1000;

  /// Search message content: in-memory first, then paginated persisted history so that older messages are included.
  /// Returns result items for conversations that have at least one message whose text/summary contains [keyword] (case-insensitive).
  Future<List<TencentCloudChatSearchResultItemData>> _searchLocalMessageContent(
    String keyword,
  ) async {
    final result = <TencentCloudChatSearchResultItemData>[];
    final conversationList = UikitDataFacade.conversationList;
    final messageSDK = TencentCloudChat.instance.chatSDKInstance.messageSDK;
    final lowerKeyword = keyword.toLowerCase();

    bool messageMatches(V2TimMessage msg) {
      final text = msg.textElem?.text ?? '';
      if (text.toLowerCase().contains(lowerKeyword)) return true;
      final summary = TencentCloudChatUtils.getMessageSummary(
        message: msg,
        needStatus: false,
      );
      return summary.toLowerCase().contains(lowerKeyword);
    }

    for (final c in conversationList) {
      final key = (c.userID != null && c.userID!.isNotEmpty)
          ? c.userID!
          : (c.groupID ?? c.conversationID);
      List<V2TimMessage> list = UikitDataFacade.getMessageList(key: key);
      // Build full list: in-memory (newest) + paginated history (older). Message order is newest-first.
      List<V2TimMessage> allMessages = List<V2TimMessage>.from(list);
      bool foundMatchEarly = false;
      if (c.userID != null || c.groupID != null) {
        try {
          String? lastMsgID = allMessages.isEmpty
              ? null
              : allMessages.last.msgID;
          while (allMessages.length <
              _maxHistoryMessagesPerConversationGlobal) {
            final res = await messageSDK.getHistoryMessageList(
              userID: c.userID,
              groupID: c.groupID,
              count: _historySearchPageSize,
              lastMsgID: lastMsgID,
            );
            if (res.messageList.isEmpty) break;
            allMessages.addAll(res.messageList);
            // Early-break once this conversation has at least one match: we
            // only need to know it has hits to surface it in results — we
            // don't need to scan its entire history.
            if (res.messageList.any(messageMatches)) {
              foundMatchEarly = true;
              break;
            }
            if (res.isFinished) break;
            lastMsgID = res.messageList.last.msgID;
          }
        } catch (e) {
          AppLogger.warn(
            '[CustomSearch] global history pagination failed; keeping partial allMessages: $e',
          );
        }
      }
      final matching = allMessages.where(messageMatches).toList();
      // Mark unused-but-meaningful: foundMatchEarly is informational; keep the
      // variable to make the optimization intent visible to future readers.
      assert(!foundMatchEarly || matching.isNotEmpty);
      if (matching.isNotEmpty) {
        result.add(
          TencentCloudChatSearchResultItemData(
            showName:
                TencentCloudChatUtils.checkString(c.showName) ??
                c.conversationID,
            conversationID: c.conversationID,
            userID: c.userID,
            groupID: c.groupID,
            messageList: matching,
            totalCount: matching.length,
            avatarUrl: c.faceUrl,
          ),
        );
        if (result.length >= 50) break;
      }
    }
    return result;
  }

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.keyWord ?? '';
    _searchKeyword = widget.keyWord ?? '';
    if (_searchKeyword.trim().isNotEmpty) {
      _performSearch();
    }
  }

  @override
  void didUpdateWidget(CustomSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear cache when search scope changes (e.g. switching between global and scoped search).
    if (widget.userID != oldWidget.userID ||
        widget.groupID != oldWidget.groupID) {
      _lastSearchedKeyword = '';
      _cachedRawContacts = [];
      _cachedRawGroups = [];
    }
    if (widget.keyWord != oldWidget.keyWord) {
      _searchController.text = widget.keyWord ?? '';
      _searchKeyword = widget.keyWord ?? '';
      if (_searchKeyword.trim().isNotEmpty) {
        _performSearch();
      } else {
        setState(() {
          _messageSearchResults = [];
          _contactsList = [];
          _groupsList = [];
          _conversationFallbackList = [];
        });
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _isGlobalSearch => widget.userID == null && widget.groupID == null;

  /// When true, the parent (conversation list) provides the search bar and keyWord; we only show results and must not show a second search field.
  bool get _isEmbeddedWithParentSearchBar =>
      _isGlobalSearch && widget.keyWord != null;

  Future<void> _performSearch() async {
    if (_searchKeyword.trim().isEmpty) {
      setState(() {
        _messageSearchResults = [];
        _contactsList = [];
        _groupsList = [];
        _conversationFallbackList = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      if (_isGlobalSearch) {
        final keyword = _searchKeyword.trim();
        final override = widget.rawSearchDataOverride;

        // Use cached contacts/groups when refining an existing query (incremental typing).
        final bool canFilterLocally =
            _lastSearchedKeyword.isNotEmpty &&
            keyword.startsWith(_lastSearchedKeyword);

        List<V2TimFriendInfoResult> rawContacts;
        List<V2TimGroupInfo> rawGroups;
        List<TencentCloudChatSearchResultItemData> rawMessages;

        if (override != null) {
          // Test seam: supply raw inputs; the real filter/render/highlight run
          // below. No singleton SDK/FFI or local-history fallback is touched.
          final data = await override(keyword);
          rawContacts = data.contacts;
          rawGroups = data.groups;
          rawMessages = data.messages;
        } else {
          final searchSDK = TencentCloudChat.instance.chatSDKInstance.searchSDK;
          (int?, String?, List<TencentCloudChatSearchResultItemData>, String?)
          messageResult;
          if (canFilterLocally) {
            rawContacts = _cachedRawContacts;
            rawGroups = _cachedRawGroups;
            messageResult = await searchSDK.searchMessages(keyword: keyword);
          } else {
            final results = await Future.wait([
              searchSDK.searchContacts(keyword),
              searchSDK.searchGroups(keyword),
              searchSDK.searchMessages(keyword: keyword),
            ]);
            rawContacts = results[0] as List<V2TimFriendInfoResult>;
            rawGroups = results[1] as List<V2TimGroupInfo>;
            messageResult =
                results[2]
                    as (
                      int?,
                      String?,
                      List<TencentCloudChatSearchResultItemData>,
                      String?,
                    );
            _cachedRawContacts = rawContacts;
            _cachedRawGroups = rawGroups;
          }
          rawMessages = messageResult.$3;
        }
        _lastSearchedKeyword = keyword;

        final contacts = rawContacts.where((e) {
          final remark = e.friendInfo?.friendRemark;
          final nick = e.friendInfo?.userProfile?.nickName;
          final uid = e.friendInfo?.userID;
          return _matchesKeywordCaseInsensitive(remark, keyword) ||
              _matchesKeywordCaseInsensitive(nick, keyword) ||
              _matchesKeywordCaseInsensitive(uid, keyword);
        }).toList();
        final groups = rawGroups.where((e) {
          return _matchesKeywordCaseInsensitive(e.groupName, keyword) ||
              _matchesKeywordCaseInsensitive(e.groupID, keyword);
        }).toList();
        List<TencentCloudChatSearchResultItemData> messages = rawMessages;

        // When SDK returns no message results, search chat content locally
        // (in-memory + persisted history). Skipped under the test seam, whose
        // supplied messages are authoritative (the seam must not reach the
        // singleton-backed local fallback).
        if (messages.isEmpty && widget.rawSearchDataOverride == null) {
          messages = await _searchLocalMessageContent(keyword);
        }

        List<V2TimConversation> fallback = [];
        if (contacts.isEmpty && groups.isEmpty && messages.isEmpty) {
          final conversationList = UikitDataFacade.conversationList;
          fallback = conversationList.where((c) {
            return _matchesKeywordCaseInsensitive(c.showName, keyword) ||
                _matchesKeywordCaseInsensitive(c.userID, keyword) ||
                _matchesKeywordCaseInsensitive(c.groupID, keyword);
          }).toList();
        }

        if (mounted && _searchKeyword.trim() == keyword) {
          setState(() {
            _contactsList = contacts;
            _groupsList = groups;
            _messageSearchResults = messages;
            _conversationFallbackList = fallback;
            _isSearching = false;
            _errorMessage = null;
          });
        }
      } else {
        final keyword = _searchKeyword.trim();
        final conversationID = widget.groupID != null
            ? 'group_${widget.groupID}'
            : (widget.userID != null ? 'c2c_${widget.userID}' : '');

        if (conversationID.isNotEmpty) {
          final searchMessagesResult = await TencentCloudChat
              .instance
              .chatSDKInstance
              .searchSDK
              .searchMessages(keyword: keyword, conversationID: conversationID);
          var messages = searchMessagesResult.$3;

          // Fallback: search in-memory + paginated persisted history when SDK returns no results.
          if (messages.isEmpty) {
            final key = widget.userID ?? widget.groupID ?? '';
            final messageSDK =
                TencentCloudChat.instance.chatSDKInstance.messageSDK;
            final lowerKeyword = keyword.toLowerCase();
            List<V2TimMessage> list = UikitDataFacade.getMessageList(key: key);
            List<V2TimMessage> allMessages = List<V2TimMessage>.from(list);
            if (widget.userID != null || widget.groupID != null) {
              try {
                String? lastMsgID = allMessages.isEmpty
                    ? null
                    : allMessages.last.msgID;
                while (allMessages.length <
                    _maxHistoryMessagesPerConversation) {
                  final res = await messageSDK.getHistoryMessageList(
                    userID: widget.userID,
                    groupID: widget.groupID,
                    count: _historySearchPageSize,
                    lastMsgID: lastMsgID,
                  );
                  if (res.messageList.isEmpty) break;
                  allMessages.addAll(res.messageList);
                  if (res.isFinished) break;
                  lastMsgID = res.messageList.last.msgID;
                }
              } catch (e) {
                AppLogger.warn(
                  '[CustomSearch] history pagination failed mid-scan: $e',
                );
              }
            }
            final matching = allMessages.where((msg) {
              final text = msg.textElem?.text ?? '';
              if (text.toLowerCase().contains(lowerKeyword)) return true;
              final summary = TencentCloudChatUtils.getMessageSummary(
                message: msg,
                needStatus: false,
              );
              return summary.toLowerCase().contains(lowerKeyword);
            }).toList();
            if (matching.isNotEmpty) {
              final conv = await TencentCloudChat
                  .instance
                  .chatSDKInstance
                  .conversationSDK
                  .getConversation(
                    userID: widget.userID,
                    groupID: widget.groupID,
                  );
              messages = [
                TencentCloudChatSearchResultItemData(
                  showName: conv.showName ?? conversationID,
                  conversationID: conversationID,
                  userID: widget.userID,
                  groupID: widget.groupID,
                  messageList: matching,
                  totalCount: matching.length,
                  avatarUrl: conv.faceUrl,
                ),
              ];
            }
          }

          if (mounted && _searchKeyword.trim() == keyword) {
            setState(() {
              _messageSearchResults = messages;
              _contactsList = [];
              _groupsList = [];
              _conversationFallbackList = [];
              _isSearching = false;
              _errorMessage = null;
            });
          }
        } else {
          if (mounted && _searchKeyword.trim() == keyword) {
            setState(() {
              _messageSearchResults = [];
              _contactsList = [];
              _groupsList = [];
              _conversationFallbackList = [];
              _isSearching = false;
              _errorMessage = null;
            });
          }
        }
      }
    } catch (e) {
      _errorMessage = null; // Will be set below after fallback attempt.
      if (_isGlobalSearch && _searchKeyword.trim().isNotEmpty) {
        final keyword = _searchKeyword.trim();
        final conversationList = UikitDataFacade.conversationList;
        final fallback = conversationList.where((c) {
          return _matchesKeywordCaseInsensitive(c.showName, keyword) ||
              _matchesKeywordCaseInsensitive(c.userID, keyword) ||
              _matchesKeywordCaseInsensitive(c.groupID, keyword);
        }).toList();
        _searchLocalMessageContent(keyword).then((messageResults) {
          if (!mounted || _searchKeyword.trim() != keyword) return;
          setState(() {
            _messageSearchResults = messageResults;
            _contactsList = [];
            _groupsList = [];
            _conversationFallbackList = fallback;
            _isSearching = false;
            _errorMessage = AppLocalizations.of(context)?.searchFailed;
          });
        });
      } else if (mounted) {
        setState(() {
          _messageSearchResults = [];
          _contactsList = [];
          _groupsList = [];
          _conversationFallbackList = [];
          _isSearching = false;
          _errorMessage = AppLocalizations.of(context)?.searchFailed;
        });
      }
    }
  }

  void _navigateToMessage({
    String? userID,
    String? groupID,
    V2TimMessage? targetMessage,
  }) async {
    final openOverride = widget.onOpenConversation;
    if (openOverride != null) {
      // Test seam: observe the open-target instead of mutating the UIKit data
      // facade / hitting the singleton conversation SDK.
      openOverride(
        userID: userID,
        groupID: groupID,
        targetMessage: targetMessage,
      );
      return;
    }
    if (targetMessage != null) {
      UikitDataFacade.currentTargetMessage = targetMessage;
    }
    if (UikitDataFacade.usedComponents.contains(
      TencentCloudChatComponentsEnum.message,
    )) {
      if (!_isDesktop(context)) {
        navigateToMessage(
          context: context,
          options: TencentCloudChatMessageOptions(
            userID: userID,
            groupID: groupID,
            targetMessage: targetMessage,
          ),
        );
      } else {
        final conv = await TencentCloudChat
            .instance
            .chatSDKInstance
            .conversationSDK
            .getConversation(userID: userID, groupID: groupID);
        if (targetMessage != null) {
          UikitDataFacade.currentTargetMessage = targetMessage;
        }
        UikitDataFacade.currentConversation = conv;
        // Desktop binds the tapped conversation into the master-detail right
        // pane via currentConversation, but the global-search overlay is a
        // full-screen pushed route that otherwise stays ON TOP — hiding the
        // chat the user just selected and swallowing sidebar taps until it is
        // dismissed. Close it so the bound chat is revealed (mobile keeps its
        // push-the-message-page behavior, where back returns to the results).
        if (mounted) {
          _closeSearch();
        }
      }
    }
  }

  /// Dismiss the search overlay: prefer the injected [CustomSearch.closeFunc]
  /// (the Cmd/Ctrl+F route passes a `Navigator.pop`), else pop the current
  /// route. Used by both the app-bar close (X) button and the Escape shortcut.
  void _closeSearch({bool deferred = false}) {
    // Only act while this route is still the current (top) route, so a
    // key-repeat / rapid double Escape during dismissal can't pop the page
    // underneath. (Embedded usage has no own route → ModalRoute is the parent,
    // still current, and closeFunc handles the embedded close.)
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      // A CHILD route is on top — e.g. the message drill-down
      // (SearchChatHistoryWindow), which calls onNavigateToMessage (us) BEFORE
      // popping itself. Closing now would no-op and leak the search overlay
      // (codex). Defer ONE frame so the child can pop and this route becomes
      // current, then close. Bounded to a single retry so a child that never
      // pops can't spin (it just falls back to the original no-op). The X
      // button / Escape always run while current, so they never defer.
      if (deferred) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _closeSearch(deferred: true);
      });
      return;
    }
    final close = widget.closeFunc;
    if (close != null) {
      close();
    } else {
      popDialogIfCurrent(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Escape dismisses the search overlay (a desktop convention the pushed
    // route was missing — Escape on the autofocused field had no binding, so
    // users/automation were stuck on it). The autofocused TextField does not
    // consume Escape, so it propagates to this CallbackShortcuts. Mobile keeps
    // using the system back gesture / the keyed close button.
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        // includeRepeats:false — one close per physical press; the route guard
        // in _closeSearch is the belt-and-suspenders backstop.
        const SingleActivator(
          LogicalKeyboardKey.escape,
          includeRepeats: false,
        ): _closeSearch,
      },
      child: Scaffold(
      appBar: _isEmbeddedWithParentSearchBar
          ? AppBar(
              title: Text(l10n.searchResults),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  key: UiKeys.messageSearchCloseButton,
                  icon: const Icon(Icons.close),
                  tooltip: l10n.close,
                  onPressed: _closeSearch,
                ),
                SizedBox(
                  width: ResponsiveLayout.responsiveHorizontalPadding(context),
                ),
              ],
            )
          : AppBar(
              titleSpacing: 0,
              title: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: TextField(
                  key: UiKeys.messageSearchField,
                  controller: _searchController,
                  autofocus: true,
                  // iOS keyboard shows a "Search" return key instead of the
                  // default "Return" — matches the action this field triggers.
                  textInputAction: TextInputAction.search,
                  textAlignVertical: TextAlignVertical.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: l10n.searchHint,
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppThemeConfig.inputBorderRadius,
                      ),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppThemeConfig.inputBorderRadius,
                      ),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(
                        AppThemeConfig.inputBorderRadius,
                      ),
                      borderSide: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchKeyword = value;
                    });
                    _debounceTimer?.cancel();
                    _debounceTimer = Timer(
                      const Duration(milliseconds: 300),
                      _performSearch,
                    );
                  },
                  onSubmitted: (_) => _performSearch(),
                ),
              ),
              actions: [
                IconButton(
                  key: UiKeys.messageSearchCloseButton,
                  icon: const Icon(Icons.close),
                  tooltip: l10n.close,
                  onPressed: _closeSearch,
                ),
                SizedBox(
                  width: ResponsiveLayout.responsiveHorizontalPadding(context),
                ),
              ],
            ),
      body: SafeArea(child: _buildBody(l10n)),
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isSearching) {
      return const LoadingShimmer(itemCount: 8, itemHeight: 56);
    }

    if (_searchKeyword.trim().isEmpty) {
      return EmptyStateWidget(
        icon: Icons.search,
        title: l10n.enterKeywordToSearch,
        subtitle: l10n.searchHintBody,
      );
    }

    final hasContacts = _contactsList.isNotEmpty;
    final hasGroups = _groupsList.isNotEmpty;
    final hasMessages = _messageSearchResults.isNotEmpty;
    final hasFallback = _conversationFallbackList.isNotEmpty;

    if (!hasContacts && !hasGroups && !hasMessages && !hasFallback) {
      return Column(
        children: [
          if (_errorMessage != null) _buildErrorBanner(l10n),
          Expanded(
            child: EmptyStateWidget(
              icon: Icons.search_off,
              title: l10n.noResultsFound,
              subtitle: l10n.noResultsFoundHint,
            ),
          ),
        ],
      );
    }

    // Removed `shrinkWrap: true`: this ListView is returned directly from
    // `_buildBody` into `Scaffold.body` (via SafeArea), so it already gets
    // bounded height from the Scaffold. shrinkWrap defeats lazy item building
    // and re-layouts the entire list on every keystroke — visibly janky on
    // low-end Android with many results.
    return ListView(
      children: [
        if (_errorMessage != null) _buildErrorBanner(l10n),
        if (_isGlobalSearch && (hasContacts || hasGroups || hasMessages))
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            child: Text(
              l10n.searchSummary(
                _contactsList.length,
                _groupsList.length,
                _messageSearchResults.length,
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (hasContacts) _buildSectionHeader(l10n.contacts),
        if (hasContacts)
          ..._contactsList.map((e) {
            final name =
                TencentCloudChatUtils.checkString(e.friendInfo?.friendRemark) ??
                TencentCloudChatUtils.checkString(
                  e.friendInfo?.userProfile?.nickName,
                ) ??
                TencentCloudChatUtils.checkString(e.friendInfo?.userID) ??
                '';
            final uid = e.friendInfo?.userID ?? '';
            final faceUrl = e.friendInfo?.userProfile?.faceUrl;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final titleStyle =
                Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
            return Semantics(
              label: l10n.searchResultContactSemantics(name),
              button: true,
              child: ListTile(
                // Keyed so UI automation taps THIS contact row deterministically
                // (the highlighted title is a RichText, and tapping by name
                // collides with the query text in the search field). onTap opens
                // the C2C chat via _navigateToMessage(userID:).
                key: UiKeys.searchResultContact(uid),
                leading: _avatarWidget(faceUrl, const Icon(Icons.person)),
                title: _buildHighlightedText(
                  name,
                  _searchKeyword.trim(),
                  titleStyle,
                  isDark: isDark,
                ),
                subtitle: Text('${l10n.idLabel} ${_truncateIdForDisplay(uid)}'),
                onTap: () => _navigateToMessage(userID: uid, groupID: null),
              ),
            );
          }),
        if (hasGroups) _buildSectionHeader(l10n.groups),
        if (hasGroups)
          ..._groupsList.map((e) {
            final name =
                TencentCloudChatUtils.checkString(e.groupName) ?? e.groupID;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final titleStyle =
                Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
            return Semantics(
              label: l10n.searchResultGroupSemantics(name),
              button: true,
              child: ListTile(
                // Keyed so UI automation can tap THIS group result row
                // deterministically (tapping by name is ambiguous with the
                // query text in the search field). The row's onTap opens the
                // group chat via _navigateToMessage(groupID:).
                key: UiKeys.searchResultGroup(e.groupID),
                leading: _avatarWidget(e.faceUrl, const Icon(Icons.group)),
                title: _buildHighlightedText(
                  name,
                  _searchKeyword.trim(),
                  titleStyle,
                  isDark: isDark,
                ),
                subtitle: Text(
                  '${l10n.idLabel} ${_truncateIdForDisplay(e.groupID)}',
                ),
                onTap: () =>
                    _navigateToMessage(userID: null, groupID: e.groupID),
              ),
            );
          }),
        if (hasMessages) _buildSectionHeader(l10n.searchSectionMessages),
        if (hasMessages)
          ..._messageSearchResults.map((result) {
            final count = result.totalCount ?? result.messageList.length;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final titleStyle =
                Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
            return Semantics(
              label: l10n.searchResultMessageSemantics(result.showName),
              button: true,
              child: ListTile(
                key: UiKeys.searchResultMessage(result.conversationID),
                leading: _avatarWidget(
                  result.avatarUrl,
                  const Icon(Icons.chat),
                ),
                title: _buildHighlightedText(
                  result.showName,
                  _searchKeyword.trim(),
                  titleStyle,
                  isDark: isDark,
                ),
                subtitle: Text(l10n.messageCount(count)),
                onTap: () {
                  Navigator.of(context)
                      .push<String>(
                        AppPageRoute<String>(
                          page: SearchChatHistoryWindow(
                            initialKeyword: _searchKeyword.trim(),
                            messageSearchResults: _messageSearchResults,
                            initialSelectedResult: result,
                            onNavigateToMessage: _navigateToMessage,
                          ),
                        ),
                      )
                      .then((value) {
                        if (!mounted || value == null) return;
                        final keyword = value.trim();
                        if (keyword.isEmpty) return;
                        setState(() {
                          _searchKeyword = keyword;
                          _searchController.text = keyword;
                        });
                        _performSearch();
                      });
                },
              ),
            );
          }),
        if (hasFallback) _buildSectionHeader(l10n.searchSectionConversations),
        if (hasFallback)
          ..._conversationFallbackList.map((c) {
            final name =
                TencentCloudChatUtils.checkString(c.showName) ??
                c.conversationID;
            final id = (c.userID != null && c.userID!.isNotEmpty)
                ? c.userID!
                : (c.groupID ?? c.conversationID);
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final titleStyle =
                Theme.of(context).textTheme.bodyLarge ?? const TextStyle();
            return Semantics(
              label: l10n.searchResultConversationSemantics(name),
              button: true,
              child: ListTile(
                // Keyed so UI automation taps THIS conversation row (the onTap
                // opens the conversation) without colliding with the query text.
                key: UiKeys.searchResultConversation(c.conversationID),
                leading: _avatarWidget(
                  c.faceUrl,
                  const Icon(Icons.chat_bubble_outline),
                ),
                title: _buildHighlightedText(
                  name,
                  _searchKeyword.trim(),
                  titleStyle,
                  isDark: isDark,
                ),
                subtitle: Text('${l10n.idLabel} ${_truncateIdForDisplay(id)}'),
                onTap: () =>
                    _navigateToMessage(userID: c.userID, groupID: c.groupID),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildErrorBanner(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: Theme.of(context).colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          AppSpacing.horizontalSm,
          Expanded(
            child: Text(
              _errorMessage ?? l10n.searchFailed,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              setState(() => _errorMessage = null);
              _performSearch();
            },
            child: Text(l10n.retry),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: l10n.close,
            onPressed: () => setState(() => _errorMessage = null),
            // 44x44 minimum tap area for mobile (Apple HIG / Material 48dp).
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Custom search manager to replace TencentCloudChatSearchManager
class CustomSearchManager {
  /// Manually declares the usage of the CustomSearch component.
  /// During the `initUIKit` call, add `CustomSearchManager.register` in `usedComponentsRegister` within `components`
  /// if you plan to use this component.
  static ({
    TencentCloudChatComponentsEnum componentEnum,
    TencentCloudChatWidgetBuilder widgetBuilder,
  })
  register() {
    return (
      componentEnum: TencentCloudChatComponentsEnum.search,
      widgetBuilder: ({required Map<String, dynamic> options}) => CustomSearch(
        userID: options["userID"] as String?,
        groupID: options["groupID"] as String?,
        keyWord: options["keyWord"] as String?,
        closeFunc: options["closeFunc"] as VoidCallback?,
      ),
    );
  }
}
