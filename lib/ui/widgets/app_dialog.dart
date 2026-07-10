import 'package:flutter/material.dart';

import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/platform_utils.dart';

/// A system-style modal dialog surface: a titled, window-like card whose close
/// button follows the host-OS window convention — top-left on macOS, top-right
/// on Windows/Linux (and the mobile/web fallbacks). On desktop the title bar
/// doubles as a drag handle so the dialog can be repositioned like a real
/// window.
///
/// Use inside a `showDialog(builder: ...)`. Provide the dialog body as [child];
/// the body keeps its own padding / scroll view / action buttons — [AppDialog]
/// supplies only the chrome (title bar + framed surface). Do **not** repeat the
/// title inside [child]; the title bar already renders it.
class AppDialog extends StatefulWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    this.onClose,
    this.maxWidth = 520,
    this.maxHeight,
    this.closeButtonKey,
    this.titleTrailing,
  });

  /// Title shown in the system-style title bar.
  final String title;

  /// Dialog body (keeps its own padding / scrolling / action row).
  final Widget child;

  /// Invoked when the close button is tapped. Defaults to
  /// `Navigator.of(context).maybePop()`.
  final VoidCallback? onClose;

  /// Max content width (callers pass their responsive width here).
  final double maxWidth;

  /// Max content height; defaults to 90% of the viewport height.
  final double? maxHeight;

  /// Optional key on the close button (e.g. to preserve a UI-automation key).
  final Key? closeButtonKey;

  /// Optional widget placed in the title bar next to the close button, on the
  /// side opposite the OS-native close corner.
  final Widget? titleTrailing;

  @override
  State<AppDialog> createState() => _AppDialogState();
}

class _AppDialogState extends State<AppDialog> {
  Offset _offset = Offset.zero;

  // The window-like drag affordance only makes sense on desktop.
  bool get _draggable => PlatformUtils.isDesktop;

  void _handleClose() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final closeButton = IconButton(
      key: widget.closeButtonKey,
      icon: const Icon(Icons.close, size: 18),
      onPressed: _handleClose,
      color: scheme.onSurfaceVariant,
      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      visualDensity: VisualDensity.compact,
      splashRadius: 18,
    );

    final titleText = Text(
      widget.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );

    // Close button sits in the top-right on every platform (macOS, Windows,
    // Linux, mobile) — a single consistent placement rather than mirroring the
    // OS window convention.
    final barChildren = <Widget>[
      Expanded(child: titleText),
      if (widget.titleTrailing != null) ...[
        widget.titleTrailing!,
        AppSpacing.horizontalXs,
      ],
      closeButton,
    ];

    final titleBar = MouseRegion(
      cursor: _draggable ? SystemMouseCursors.grab : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: _draggable
            ? (details) => setState(() => _offset += details.delta)
            : null,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
          ),
          child: Row(children: barChildren),
        ),
      ),
    );

    final media = MediaQuery.sizeOf(context);
    return Transform.translate(
      offset: _offset,
      child: Dialog(
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppThemeConfig.cardBorderRadius),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: widget.maxWidth,
            maxHeight: widget.maxHeight ?? media.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              titleBar,
              Flexible(child: widget.child),
            ],
          ),
        ),
      ),
    );
  }
}
