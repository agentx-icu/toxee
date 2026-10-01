part of 'sidebar.dart';

class _ContactSidebarItem extends StatefulWidget {
  const _ContactSidebarItem({
    super.key,
    required this.context,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final BuildContext context;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_ContactSidebarItem> createState() => _ContactSidebarItemState();
}

class _ContactSidebarItemState extends State<_ContactSidebarItem> {
  StreamSubscription<TencentCloudChatContactData<dynamic>>? _contactDataSub;
  int _applicationUnreadCount = 0;
  bool _isHovered = false;
  bool get _disableAnims => MediaQuery.disableAnimationsOf(context);

  @override
  void initState() {
    super.initState();
    // Listen to contact data changes to get application unread count
    final contactDataStream = TencentCloudChat.instance.eventBusInstance
        .on<TencentCloudChatContactData<dynamic>>(
          "TencentCloudChatContactData",
        );
    _contactDataSub = contactDataStream?.listen((data) {
      if (data.currentUpdatedFields ==
              TencentCloudChatContactDataKeys.applicationCount ||
          data.currentUpdatedFields ==
              TencentCloudChatContactDataKeys.applicationList) {
        if (mounted) {
          setState(() {
            _applicationUnreadCount = data.applicationUnreadCount;
          });
        }
      }
    });
    // Get initial count
    _applicationUnreadCount = UikitDataFacade.applicationUnreadCount;
  }

  @override
  void dispose() {
    _contactDataSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Compact 72px rail (landscape phone — NOT tablet; tablets are `isDesktop`
    // and get the 200pt labelled rail): icon-only, label hidden + surfaced as
    // a tooltip. Wide rail: icon + ellipsised label.
    final compact = ResponsiveLayout.isCompactRail(context);
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        final palette = AppTheme.style.value.palette(theme.brightness);
        final geometry = AppTheme.style.value.geometry;
        final baseColor = palette.muted;
        final selColor = palette.primary;
        final bg = widget.selected
            ? palette.selected
            : (_isHovered
                  ? theme.colorScheme.onSurface.withValues(alpha: 0.04)
                  : Colors.transparent);
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(geometry.controlRadius),
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: _disableAnims ? Duration.zero : AppDurations.fast,
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 52),
                padding: EdgeInsets.symmetric(
                  vertical: 10,
                  horizontal: compact ? 8 : 18,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  border: widget.selected && geometry.outlineWidth > 0
                      ? Border.all(
                          color: palette.controlBorder,
                          width: geometry.outlineWidth,
                        )
                      : null,
                  boxShadow: widget.selected && geometry.shadowOffset > 0
                      ? [
                          BoxShadow(
                            color: palette.controlBorder,
                            offset: Offset(
                              geometry.shadowOffset,
                              geometry.shadowOffset,
                            ),
                          ),
                        ]
                      : null,
                  borderRadius: BorderRadius.circular(geometry.controlRadius),
                ),
                child: Row(
                  mainAxisAlignment: compact
                      ? MainAxisAlignment.center
                      : MainAxisAlignment.start,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _compactTooltip(
                          enabled: compact,
                          message: widget.label,
                          child: Icon(
                            widget.icon,
                            size: 23,
                            color: widget.selected ? selColor : baseColor,
                          ),
                        ),
                        if (_applicationUnreadCount > 0)
                          Positioned(
                            top: -5,
                            right: -6,
                            child: UnconstrainedBox(
                              child: Builder(
                                builder: (context) {
                                  final displayText =
                                      _applicationUnreadCount > 99
                                      ? "99+"
                                      : "$_applicationUnreadCount";
                                  return Semantics(
                                    label:
                                        AppLocalizations.of(
                                          context,
                                        )?.unreadMessagesSemantics(
                                          _applicationUnreadCount,
                                        ) ??
                                        'Unread messages: $_applicationUnreadCount',
                                    container: true,
                                    child: ExcludeSemantics(
                                      child: Container(
                                        constraints: const BoxConstraints(
                                          minWidth: 16,
                                        ),
                                        height: 16,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: AppSpacing.xs,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colorTheme
                                              .conversationItemUnreadCountBgColor,
                                          borderRadius: BorderRadius.circular(
                                            AppThemeConfig.badgeBorderRadius,
                                          ),
                                        ),
                                        child: Center(
                                          child: Text(
                                            displayText,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                                  color: palette.onUnread,
                                                  fontWeight: FontWeight.w600,
                                                  height: 1.0,
                                                  fontSize: 12,
                                                ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 14),
                      // Flexible + ellipsis so a long label ("Applications")
                      // or a longer localized string can never overflow the
                      // rail (was the "RIGHT OVERFLOWED BY 17 PIXELS" bug).
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: widget.selected ? selColor : baseColor,
                            fontWeight: widget.selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
