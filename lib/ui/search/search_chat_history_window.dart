import 'package:flutter/material.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/widgets/empty_state_widget.dart';
import 'package:toxee/ui/widgets/search_utils.dart';
import 'package:toxee/ui/widgets/stagger_list_item.dart';
import 'package:toxee/util/responsive_layout.dart';
import 'package:tencent_cloud_chat_common/chat_sdk/components/tencent_cloud_chat_search_sdk.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/utils/tencent_cloud_chat_utils.dart';

/// A two-panel window: top search bar, left = conversations with match count, right = messages with keyword highlight.
/// Tapping a message opens the chat and locates to that message.
class SearchChatHistoryWindow extends StatefulWidget {
  final String initialKeyword;
  final List<TencentCloudChatSearchResultItemData> messageSearchResults;
  final TencentCloudChatSearchResultItemData? initialSelectedResult;
  final void Function({String? userID, String? groupID, V2TimMessage? targetMessage}) onNavigateToMessage;

  const SearchChatHistoryWindow({
    super.key,
    required this.initialKeyword,
    required this.messageSearchResults,
    this.initialSelectedResult,
    required this.onNavigateToMessage,
  });

  @override
  State<SearchChatHistoryWindow> createState() => _SearchChatHistoryWindowState();
}

class _SearchChatHistoryWindowState extends State<SearchChatHistoryWindow> {
  late TextEditingController _searchController;
  late String _filterKeyword;

  /// Index into _filteredResults (not original list).
  int _selectedIndex = 0;

  /// Filtered results: each item is (result, filtered message list for current _filterKeyword).
  List<(TencentCloudChatSearchResultItemData result, List<V2TimMessage> messages)> _filteredResults = [];

  /// Resolved display names for senders (userID -> nickname/remark). Messages from search often lack nickName/friendRemark.
  Map<String, String> _senderDisplayNames = {};

  /// On mobile, when true show message list for selected conversation; when false show conversation list.
  bool _showMobileDetail = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.initialKeyword);
    _filterKeyword = widget.initialKeyword;
    _computeFiltered();
    if (widget.initialSelectedResult != null) {
      final id = _conversationId(widget.initialSelectedResult!);
      final idx = _filteredResults.indexWhere((e) => _conversationId(e.$1) == id);
      if (idx >= 0) _selectedIndex = idx;
    }
    _loadSenderDisplayNames();
  }

  String _conversationId(TencentCloudChatSearchResultItemData r) =>
      r.conversationID;

  static bool _messageMatchesKeyword(V2TimMessage msg, String keyword) {
    if (keyword.isEmpty) return true;
    final k = keyword.toLowerCase();
    final text = msg.textElem?.text ?? '';
    if (text.toLowerCase().contains(k)) return true;
    final summary = TencentCloudChatUtils.getMessageSummary(message: msg, needStatus: false);
    return summary.toLowerCase().contains(k);
  }

  void _computeFiltered() {
    final keyword = _filterKeyword.trim();
    final list = <(TencentCloudChatSearchResultItemData, List<V2TimMessage>)>[];
    for (final result in widget.messageSearchResults) {
      final messages = keyword.isEmpty
          ? result.messageList
          : result.messageList.where((m) => _messageMatchesKeyword(m, keyword)).toList();
      if (messages.isNotEmpty) {
        list.add((result, messages));
      }
    }
    _filteredResults = list;
    if (_selectedIndex >= _filteredResults.length) {
      _selectedIndex = _filteredResults.isEmpty ? 0 : 0;
    }
  }

  /// Load display names for all senders in current _filteredResults via getUsersInfo (messages from search often lack nickName).
  Future<void> _loadSenderDisplayNames() async {
    final senderIds = <String>{};
    for (final e in _filteredResults) {
      for (final msg in e.$2) {
        final id = msg.sender;
        if (id != null && id.isNotEmpty && _senderDisplayNames.containsKey(id) == false) {
          senderIds.add(id);
        }
      }
    }
    if (senderIds.isEmpty) return;
    final res = await TencentCloudChat.instance.chatSDKInstance.manager.getUsersInfo(userIDList: senderIds.toList());
    if (!mounted) return;
    if (res.data != null && res.data!.isNotEmpty) {
      setState(() {
        for (final u in res.data!) {
          final id = u.userID;
          final name = TencentCloudChatUtils.checkString(u.nickName) ?? id ?? '';
          if (id != null && id.isNotEmpty) _senderDisplayNames[id] = name;
        }
      });
    }
  }

  String _getSenderDisplayName(V2TimMessage msg) {
    final id = msg.sender;
    if (id != null && _senderDisplayNames.containsKey(id)) {
      return _senderDisplayNames[id]!;
    }
    return TencentCloudChatUtils.getShowName(msg);
  }

  /// Apply search bar text: if keyword differs from initial, pop with new keyword so parent can run full search; otherwise filter in-place.
  void _applySearchFromField() {
    final newKeyword = _searchController.text.trim();
    if (newKeyword != widget.initialKeyword) {
      Navigator.of(context).pop(newKeyword);
      return;
    }
    setState(() {
      _filterKeyword = newKeyword;
      _computeFiltered();
    });
    _loadSenderDisplayNames();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Avatar: use [defaultChild] only when [url] is null/empty so it is not overlaid on the image.
  static Widget _avatarWidget(String? url, Widget defaultChild) => SearchUtils.avatarWidget(url, defaultChild);

  /// Builds rich text with [keyword] highlighted (case-insensitive).
  /// Delegates to shared [SearchUtils.buildHighlightedText] with maxLines: 2 for message summaries.
  static Widget _buildHighlightedSummary(String summary, String keyword, TextStyle baseStyle, Color highlightColor, {bool isDark = false}) {
    return SearchUtils.buildHighlightedText(summary, keyword, baseStyle, isDark: isDark, maxLines: 2);
  }

  static String _formatTimestamp(V2TimMessage msg) {
    final ts = msg.timestamp;
    if (ts == null || ts <= 0) return '';
    // SDK may give seconds (e.g. 1e9–2e9) or milliseconds; 1970/01/21 indicates seconds was used as ms.
    final ms = ts < 10000000000 ? ts * 1000 : ts;
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  void _openChatAndPop({V2TimMessage? targetMessage}) {
    if (_filteredResults.isEmpty) return;
    final selected = _filteredResults[_selectedIndex].$1;
    widget.onNavigateToMessage(
      userID: selected.userID,
      groupID: selected.groupID,
      targetMessage: targetMessage,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyMedium ?? const TextStyle();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.searchChatHistory),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: TextField(
              controller: _searchController,
              textAlignVertical: TextAlignVertical.center,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: l10n.searchHint,
                prefixIcon: Icon(
                  Icons.search,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppThemeConfig.inputBorderRadius),
                  borderSide: BorderSide(
                    color: theme.colorScheme.primary,
                    width: 1.5,
                  ),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  tooltip: l10n.searchHint,
                  onPressed: () => _applySearchFromField(),
                ),
              ),
              onSubmitted: (_) => _applySearchFromField(),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: _filteredResults.isEmpty
          ? EmptyStateWidget(
              icon: Icons.search_off,
              title: l10n.noResultsFound,
            )
          : ResponsiveLayout.isMobile(context)
              ? _buildMobileLayout(context, l10n, textStyle, theme)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Left: conversation list
                    Expanded(
                      flex: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(
                            right: BorderSide(color: theme.colorScheme.outlineVariant),
                          ),
                        ),
                        child: ListView.builder(
                          itemCount: _filteredResults.length,
                          itemBuilder: (context, index) {
                            final e = _filteredResults[index];
                            final result = e.$1;
                            final count = e.$2.length;
                            final isSelected = index == _selectedIndex;
                            return IntrinsicHeight(
                              child: Row(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: isSelected ? 4 : 0,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  Expanded(
                                    child: ListTile(
                                      selected: isSelected,
                                      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
                                      leading: _avatarWidget(result.avatarUrl, const Icon(Icons.chat)),
                                      title: Text(
                                        result.showName,
                                        style: theme.textTheme.bodyLarge?.copyWith(
                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        l10n.relatedChats(count),
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                      onTap: () {
                                        setState(() => _selectedIndex = index);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    // Right: message list for selected conversation
                    Expanded(
                      flex: 2,
                      child: _buildRightPanel(l10n, textStyle, theme),
                    ),
                  ],
                ),
        ),
    );
  }

  /// Mobile: single-column vertical layout — either conversation list or message list with back.
  /// Vertical-only flow; no left/right split. Result rows are full-width, tappable,
  /// ~68px tall with a 40px avatar, titleSmall nickname, bodySmall onSurfaceVariant snippet.
  Widget _buildMobileLayout(BuildContext context, AppLocalizations l10n, TextStyle textStyle, ThemeData theme) {
    if (_showMobileDetail) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => setState(() => _showMobileDetail = false),
                ),
                Expanded(
                  child: Text(
                    _filteredResults[_selectedIndex].$1.showName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.colorScheme.outlineVariant),
          Expanded(child: _buildRightPanel(l10n, textStyle, theme)),
        ],
      );
    }
    final keyword = _filterKeyword.trim();
    final highlightBase = textStyle.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final disableAnims = MediaQuery.disableAnimationsOf(context);
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      itemCount: _filteredResults.length,
      separatorBuilder: (context, _) => Divider(
        height: 1,
        thickness: 1,
        indent: AppSpacing.lg + 40 + AppSpacing.md,
        color: theme.colorScheme.outlineVariant,
      ),
      itemBuilder: (context, index) {
        final e = _filteredResults[index];
        final result = e.$1;
        final messages = e.$2;
        final count = messages.length;
        final topMessage = messages.isNotEmpty ? messages.first : null;
        final snippet = topMessage != null
            ? TencentCloudChatUtils.getMessageSummary(message: topMessage, needStatus: false)
            : l10n.relatedChats(count);
        final row = InkWell(
          onTap: () {
            setState(() {
              _selectedIndex = index;
              _showMobileDetail = true;
            });
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 68),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: _avatarWidget(result.avatarUrl, const Icon(Icons.chat)),
                  ),
                  AppSpacing.horizontalMd,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                result.showName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (count > 1) ...[
                              AppSpacing.horizontalSm,
                              Semantics(
                                // FOLLOWUP-L10N: needs a
                                // `matchingMessagesSemantics` string in
                                // `lib/i18n/`; hardcoded for now.
                                label: '$count matching messages',
                                container: true,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(AppThemeConfig.badgeBorderRadius),
                                  ),
                                  child: ExcludeSemantics(
                                    child: Text(
                                      '$count',
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        _buildHighlightedSummary(
                          snippet,
                          keyword.isEmpty ? widget.initialKeyword : keyword,
                          (theme.textTheme.bodySmall ?? highlightBase).copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          theme.colorScheme.primary,
                          isDark: theme.brightness == Brightness.dark,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        if (disableAnims || index >= 10) return row;
        return StaggeredListItem(
          index: index,
          staggerDelay: const Duration(milliseconds: 30),
          child: row,
        );
      },
    );
  }

  Widget _buildRightPanel(AppLocalizations l10n, TextStyle textStyle, ThemeData theme) {
    final selected = _filteredResults[_selectedIndex];
    final messages = selected.$2;
    final keyword = _filterKeyword.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  l10n.searchResultsCount(messages.length, keyword.isEmpty ? widget.initialKeyword : keyword),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _openChatAndPop(targetMessage: messages.isNotEmpty ? messages.first : null),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(l10n.openChat),
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppThemeConfig.buttonBorderRadius),
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index];
              final summary = TencentCloudChatUtils.getMessageSummary(message: msg, needStatus: false);
              return ListTile(
                leading: _avatarWidget(msg.faceUrl, Icon(Icons.person, color: theme.colorScheme.onSurfaceVariant)),
                title: Text(
                  _getSenderDisplayName(msg),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: _buildHighlightedSummary(summary, keyword.isEmpty ? widget.initialKeyword : keyword, textStyle, theme.colorScheme.primary, isDark: theme.brightness == Brightness.dark),
                ),
                trailing: Text(
                  _formatTimestamp(msg),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                onTap: () => _openChatAndPop(targetMessage: msg),
              );
            },
          ),
        ),
      ],
    );
  }
}
