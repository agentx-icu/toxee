import 'dart:io' show File;

import 'package:flutter/material.dart';
import '../util/app_spacing.dart';
import '../util/app_theme_config.dart';
import '../util/responsive_layout.dart';
import 'call_avatar_controller.dart';
import 'call_ui_shell.dart';

// ──────────────────────────────────────────────────────────────────────────────
//  Call-surface palette
//
//  The call screen always renders on the dark slate-900 background defined by
//  `kCallBackgroundBase`, regardless of the app's light/dark mode (consistent
//  with how Telegram / Signal / Meet handle calls). These constants are the
//  on-dark equivalents of the slate text + divider tokens in AppThemeConfig.
// ──────────────────────────────────────────────────────────────────────────────

/// Primary foreground on the dark call surface — slate-200, the same token
/// AppThemeConfig uses for `primaryTextColorDark`.
const Color _kCallForeground = Color(0xFFE2E8F0);

/// Muted foreground for subtitles / metadata on the call surface — slate-400.
const Color _kCallMutedForeground = Color(0xFF94A3B8);

/// Hairline border on the dark call surface — slate-700.
const Color _kCallHairline = Color(0xFF334155);

/// Surface for an idle (non-selected) action button — slate-800.
const Color _kCallDockSurface = Color(0xFF1E293B);

/// Surface for a selected action button — primary tinted (blue-500 @ 16%).
Color get _kCallDockSelectedSurface =>
    AppThemeConfig.primaryColorDark.withValues(alpha: 0.16);

/// Returns the first character of [name] for avatar display (uppercase for a–z).
/// Uses [String.characters] so emoji and CJK work correctly.
String callAvatarInitial(String name) {
  if (name.isEmpty) return '?';
  final first = name.characters.first;
  if (first.length == 1) {
    final code = first.codeUnitAt(0);
    if (code >= 0x61 && code <= 0x7A) return first.toUpperCase();
  }
  return first;
}

/// Avatar for call screens: loads real user image from [Prefs.getFriendAvatarPath]
/// when [userId] is set, otherwise shows [callAvatarInitial(name)].
class CallUserAvatar extends StatefulWidget {
  const CallUserAvatar({
    super.key,
    this.userId,
    this.controller,
    required this.name,
    required this.radius,
    required this.fontSize,
  });

  final String? userId;
  final CallAvatarController? controller;
  final String name;
  final double radius;
  final double fontSize;

  @override
  State<CallUserAvatar> createState() => _CallUserAvatarState();
}

class _CallUserAvatarState extends State<CallUserAvatar> {
  late final CallAvatarController _ownedController;
  late CallAvatarController _controller;

  @override
  void initState() {
    super.initState();
    _ownedController = CallAvatarController();
    _bindController(widget.controller ?? _ownedController);
    _controller.loadForUser(widget.userId);
  }

  void _bindController(CallAvatarController controller) {
    _controller = controller;
    _controller.addListener(_onControllerChanged);
  }

  void _unbindController() {
    _controller.removeListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didUpdateWidget(CallUserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextController = widget.controller ?? _ownedController;
    if (!identical(oldWidget.controller ?? _ownedController, nextController)) {
      _unbindController();
      _bindController(nextController);
    }
    if (oldWidget.userId != widget.userId) {
      _controller.loadForUser(widget.userId);
    }
  }

  @override
  void dispose() {
    _unbindController();
    _ownedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = _controller.avatarPath;
    final hasImage = _controller.hasAvatarImage;
    return CircleAvatar(
      radius: widget.radius,
      // Slate-700 so the fallback initial still feels part of the dark surface.
      backgroundColor: _kCallHairline,
      backgroundImage: hasImage && path != null ? FileImage(File(path)) : null,
      child: hasImage
          ? null
          : Text(
              callAvatarInitial(widget.name),
              style: TextStyle(
                fontSize: widget.fontSize,
                color: _kCallForeground,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

/// Descriptor for a single action in the call dock.
///
/// State precedence in the renderer: `destructive` > `affirmative` > `selected`
/// > neutral. `affirmative` is used for accept-call style buttons (successColor
/// fill, white icon) — visually weightier than a normal selected toggle.
class CallDockAction {
  const CallDockAction({
    required this.icon,
    required this.label,
    this.destructive = false,
    this.affirmative = false,
    this.selected = false,
    this.enabled = true,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool destructive;
  final bool affirmative;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;
}

/// Thin top status bar for call screens: title, subtitle, optional trailing action.
class CallTopStatusBar extends StatelessWidget {
  const CallTopStatusBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.qualityIndicator,
    this.trailingIcon,
    this.onTrailingPressed,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? qualityIndicator;
  final IconData? trailingIcon;
  final VoidCallback? onTrailingPressed;

  @override
  Widget build(BuildContext context) {
    final fontSize = ResponsiveLayout.responsiveFontSize(context);
    final padding = ResponsiveLayout.responsiveHorizontalPadding(context);
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: padding,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, SizedBox(width: padding)],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: (textTheme.titleMedium ?? const TextStyle()).copyWith(
                    color: _kCallForeground,
                    fontSize: 16 * fontSize,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: (textTheme.bodySmall ?? const TextStyle()).copyWith(
                      color: _kCallMutedForeground,
                      fontSize: 13 * fontSize,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (qualityIndicator != null) ...[
            qualityIndicator!,
            SizedBox(width: padding),
          ],
          if (trailingIcon != null)
            IconButton(
              icon: Icon(trailingIcon, color: _kCallMutedForeground, size: 22),
              onPressed: onTrailingPressed,
              splashRadius: 22,
            ),
        ],
      ),
    );
  }
}

/// Action dock for call controls: mute, video, speaker, hang up.
///
/// Buttons are circular (56–64px depending on viewport), with a slate-800
/// neutral surface by default, a primary-tinted surface when selected, and a
/// solid errorColor surface when destructive. The dock itself has no chrome —
/// each button sits on the call surface directly, in the Telegram/Meet style.
class CallActionDock extends StatelessWidget {
  const CallActionDock({
    super.key,
    required this.actions,
  });

  final List<CallDockAction> actions;

  @override
  Widget build(BuildContext context) {
    final buttonSize = ResponsiveLayout.responsiveValue<double>(
      context,
      mobile: 56,
      tablet: 60,
      desktop: 64,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: AppSpacing.lg,
        runSpacing: AppSpacing.md,
        children: actions
            .map((a) => _CallDockButton(action: a, diameter: buttonSize))
            .toList(),
      ),
    );
  }
}

class _CallDockButton extends StatefulWidget {
  const _CallDockButton({
    required this.action,
    required this.diameter,
  });

  final CallDockAction action;
  final double diameter;

  @override
  State<_CallDockButton> createState() => _CallDockButtonState();
}

class _CallDockButtonState extends State<_CallDockButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final fontSize = ResponsiveLayout.responsiveFontSize(context);
    final textTheme = Theme.of(context).textTheme;
    final a = widget.action;
    final isDestructive = a.destructive;
    final isAffirmative = a.affirmative && !isDestructive;
    final isSelected = a.selected && !isDestructive && !isAffirmative;
    final isEnabled = a.enabled && a.onPressed != null;

    // Background fill per state.
    final Color backgroundColor;
    if (isDestructive) {
      backgroundColor = AppThemeConfig.errorColor;
    } else if (isAffirmative) {
      backgroundColor = AppThemeConfig.successColor;
    } else if (isSelected) {
      backgroundColor = _kCallDockSelectedSurface;
    } else {
      backgroundColor = _kCallDockSurface;
    }

    // Icon color per state.
    final Color iconColor;
    if (isDestructive || isAffirmative) {
      iconColor = Colors.white;
    } else if (isSelected) {
      iconColor = AppThemeConfig.primaryColorDark;
    } else if (isEnabled) {
      iconColor = _kCallForeground;
    } else {
      iconColor = _kCallMutedForeground.withValues(alpha: 0.5);
    }

    // Hairline border for neutral buttons only — destructive / affirmative /
    // selected variants are filled and don't need an edge.
    final Border? border = (isDestructive || isAffirmative || isSelected)
        ? null
        : Border.all(color: _kCallHairline);

    final labelColor = isEnabled
        ? _kCallMutedForeground
        : _kCallMutedForeground.withValues(alpha: 0.5);

    // Affirmative actions (accept call) get a 12% size bump so they read as
    // the primary CTA next to the destructive reject button.
    final double effectiveDiameter =
        isAffirmative ? widget.diameter * 1.12 : widget.diameter;
    // Solid (filled) variants get a subtle drop shadow so they feel raised
    // above the slate-900 surface.
    final List<BoxShadow>? shadows =
        (isDestructive || isAffirmative)
            ? [
                BoxShadow(
                  color: backgroundColor.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ]
            : null;

    return SizedBox(
      width: widget.diameter + 24,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 150ms press scale to 0.96, matches established interaction feel.
          AnimatedScale(
            scale: _pressed && isEnabled ? 0.96 : 1.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: GestureDetector(
              onTapDown: isEnabled ? (_) => _setPressed(true) : null,
              onTapCancel: isEnabled ? () => _setPressed(false) : null,
              onTapUp: isEnabled ? (_) => _setPressed(false) : null,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: isEnabled ? a.onPressed : null,
                  child: Container(
                    width: effectiveDiameter,
                    height: effectiveDiameter,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      shape: BoxShape.circle,
                      border: border,
                      boxShadow: shadows,
                    ),
                    child: Icon(
                      a.icon,
                      color: iconColor,
                      size: effectiveDiameter * 0.42,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            a.label,
            style: (textTheme.bodySmall ?? const TextStyle()).copyWith(
              color: labelColor,
              fontSize: 11 * fontSize,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Centered identity stage for audio-only or ringing: avatar, title, subtitle.
class CallIdentityStage extends StatelessWidget {
  const CallIdentityStage({
    super.key,
    required this.avatar,
    required this.title,
    this.subtitle,
    this.secondaryNote,
  });

  final Widget avatar;
  final String title;
  final String? subtitle;
  final String? secondaryNote;

  @override
  Widget build(BuildContext context) {
    final fontSize = ResponsiveLayout.responsiveFontSize(context);
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            style: (textTheme.headlineSmall ?? const TextStyle()).copyWith(
              color: _kCallForeground,
              fontSize: 22 * fontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              subtitle!,
              style: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
                color: _kCallMutedForeground,
                fontSize: 14 * fontSize,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (secondaryNote != null && secondaryNote!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              secondaryNote!,
              style: (textTheme.bodySmall ?? const TextStyle()).copyWith(
                color: _kCallMutedForeground.withValues(alpha: 0.8),
                fontSize: 12 * fontSize,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Video stage: remote content area and optional local preview card with stable key.
class CallVideoStage extends StatelessWidget {
  const CallVideoStage({
    super.key,
    required this.remoteContent,
    this.localPreviewCard,
  });

  final Widget remoteContent;
  final Widget? localPreviewCard;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        remoteContent,
        if (localPreviewCard != null) localPreviewCard!,
      ],
    );
  }
}

/// Compact card for floating call window: title, subtitle, optional leading, hang-up action.
class CallCompactCard extends StatelessWidget {
  const CallCompactCard({
    super.key,
    required this.title,
    required this.subtitle,
    this.leading,
    this.thumbnail,
    required this.onHangUp,
  });

  final String title;
  final String subtitle;
  final Widget? leading;
  final Widget? thumbnail;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, AppSpacing.horizontalSm],
          if (thumbnail != null && leading == null) ...[
            thumbnail!,
            AppSpacing.horizontalSm,
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: (textTheme.bodyMedium ?? const TextStyle()).copyWith(
                    color: _kCallForeground,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: (textTheme.bodySmall ?? const TextStyle()).copyWith(
                    color: _kCallMutedForeground,
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Compact end-call button — matches the destructive dock-button feel
          // but sized down for the floating widget footprint.
          Material(
            color: AppThemeConfig.errorColor,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onHangUp,
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  Icons.call_end,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RingingCallScene extends StatelessWidget {
  const RingingCallScene({
    super.key,
    required this.userId,
    required this.name,
    required this.primarySubtitle,
    this.secondaryNote,
    required this.bottomBar,
    required this.onMinimize,
    required this.avatarRadius,
    required this.avatarFontSize,
  });

  final String? userId;
  final String name;
  final String primarySubtitle;
  final String? secondaryNote;
  final Widget bottomBar;
  final VoidCallback onMinimize;
  final double avatarRadius;
  final double avatarFontSize;

  @override
  Widget build(BuildContext context) {
    return CallSceneShell(
      topBar: CallTopStatusBar(
        key: const ValueKey('call-top-bar'),
        title: name,
        subtitle: primarySubtitle,
        trailingIcon: Icons.picture_in_picture_alt,
        onTrailingPressed: onMinimize,
      ),
      bottomBar: bottomBar,
      child: CallIdentityStage(
        avatar: CallUserAvatar(
          userId: userId,
          name: name,
          radius: avatarRadius,
          fontSize: avatarFontSize,
        ),
        title: name,
        subtitle: primarySubtitle,
        secondaryNote: secondaryNote,
      ),
    );
  }
}
