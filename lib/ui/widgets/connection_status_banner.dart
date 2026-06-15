import 'package:flutter/material.dart';

import '../../util/app_theme_config.dart';
import '../../util/design_tokens.dart';
import '../../util/logger.dart';

/// Thin global banner that reflects Tox-network connection status.
///
/// **API**: composable — pass [statusStream] (a `Stream<bool>` of `isConnected`
/// ticks) and optionally [initialIsConnected] to skip the connecting flash.
/// `FfiChatService.isConnected` + `FfiChatService.connectionStatusStream`
/// (already wired through the app — see `lib/ui/settings/sidebar.dart`) satisfy
/// this contract.
///
/// **States**: null → connecting (surfaceContainerLow + progress);
/// true → online (`SizedBox.shrink`); false → offline (warning amber tint +
/// retry). A dropped connection is recoverable, so it reads as a warning rather
/// than a hard error.
/// 32 dp tall, fade+size via [AnimatedSwitcher] using [AppDurations.medium];
/// collapses to [Duration.zero] when `MediaQuery.disableAnimationsOf` is true.
///
/// Not auto-mounted anywhere by design.
class ConnectionStatusBanner extends StatelessWidget {
  const ConnectionStatusBanner({
    super.key,
    required this.statusStream,
    this.initialIsConnected,
    this.onRetry,
  });

  final Stream<bool> statusStream;
  final bool? initialIsConnected;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) == true;
    return StreamBuilder<bool>(
      stream: statusStream,
      initialData: initialIsConnected,
      builder: (context, snapshot) {
        final Widget child;
        if (snapshot.hasError) {
          // Surfacing a dead stream as "offline (unknown)" is safer than
          // sitting in "Connecting…" forever. Sub-label distinguishes this
          // from a normal disconnect so users (and bug reports) can tell.
          AppLogger.logError(
            '[ConnectionStatusBanner] statusStream error — '
            'rendering offline-unknown',
            snapshot.error,
            snapshot.stackTrace,
          );
          child = _Banner(
            key: const ValueKey('offline-error'),
            kind: _Kind.offline,
            sublabelOverride: 'Network status unavailable',
            onRetry: onRetry,
          );
        } else if (!snapshot.hasData) {
          child = const _Banner(key: ValueKey('connecting'), kind: _Kind.connecting);
        } else if (snapshot.data == true) {
          child = const SizedBox.shrink(key: ValueKey('online'));
        } else {
          child = _Banner(
            key: const ValueKey('offline'),
            kind: _Kind.offline,
            onRetry: onRetry,
          );
        }
        return AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : AppDurations.medium,
          switchInCurve: AppCurves.enter,
          switchOutCurve: AppCurves.exit,
          transitionBuilder: (c, anim) => FadeTransition(
            opacity: anim,
            child: SizeTransition(sizeFactor: anim, axisAlignment: -1, child: c),
          ),
          child: child,
        );
      },
    );
  }
}

enum _Kind { connecting, offline }

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.kind,
    this.onRetry,
    this.sublabelOverride,
  });
  final _Kind kind;
  final VoidCallback? onRetry;
  final String? sublabelOverride;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final isOffline = kind == _Kind.offline;
    // Offline is a recoverable warning, not a hard error: amber tint + amber
    // icon, but the label stays on a high-contrast neutral foreground so it
    // clears the 4.5:1 readability bar (amber-on-amber-tint would fail it).
    final warning = DesignTokens.resolve(
      brightness,
      DesignTokens.warningLight,
      DesignTokens.warningDark,
    );
    final bg = isOffline
        ? warning.withValues(alpha: 0.16)
        : cs.surfaceContainerLow;
    final fg = isOffline ? cs.onSurface : cs.onSurfaceVariant;
    final label = sublabelOverride ??
        (isOffline ? 'Disconnected' : 'Connecting to Tox network…');

    final row = Row(
      children: [
        const SizedBox(width: 12),
        if (isOffline)
          Icon(Icons.cloud_off, size: 16, color: warning)
        else
          const SizedBox(width: 64, child: LinearProgressIndicator(minHeight: 2)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: fg,
                  fontWeight: isOffline ? FontWeight.w500 : null,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isOffline && onRetry != null) ...[
          const SizedBox(width: 8),
          Icon(Icons.refresh, size: 16, color: warning),
          const SizedBox(width: 12),
        ],
      ],
    );

    final body = SizedBox(height: 32, child: row);
    if (isOffline) {
      return Material(
        color: bg,
        child: InkWell(onTap: onRetry, child: body),
      );
    }
    return ColoredBox(color: bg, child: body);
  }
}
