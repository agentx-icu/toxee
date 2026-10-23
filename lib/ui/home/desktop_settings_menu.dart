import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../util/async_task.dart';

/// A menu command belongs to one visible, initialized account route. A queued
/// native command from the previous route/account cannot target its successor.
final class DesktopSettingsMenuCommands {
  DesktopSettingsMenuCommands({
    MethodChannel channel = const MethodChannel('toxee/desktop_menu'),
  }) : _channel = channel;

  static final instance = DesktopSettingsMenuCommands();
  final MethodChannel _channel;
  int _serial = 0;
  int? _owner;
  VoidCallback? _openSettings;

  VoidCallback bind(VoidCallback openSettings) {
    final owner = ++_serial;
    _owner = owner;
    _openSettings = openSettings;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'openSettings') throw MissingPluginException();
      if (call.arguments == _owner) _openSettings?.call();
    });
    _publishOwner(owner);
    return () {
      if (_owner != owner) return;
      _owner = null;
      _openSettings = null;
      _publishOwner(null);
    };
  }

  void _publishOwner(int? owner) => observeBackgroundTask(
    _channel.invokeMethod<void>('setSettingsOwner', owner),
    'desktop_settings_menu',
  );
}

/// Native Preferences is disabled until session initialization completes and
/// whenever another route/dialog covers Home. The Flutter shortcut and native
/// command receive the same existing settings navigation action.
class DesktopSettingsMenu extends StatefulWidget {
  const DesktopSettingsMenu({
    super.key,
    required this.ready,
    required this.onOpenSettings,
    required this.child,
  });
  final bool ready;
  final VoidCallback onOpenSettings;
  final Widget child;

  @override
  State<DesktopSettingsMenu> createState() => _DesktopSettingsMenuState();
}

class _DesktopSettingsMenuState extends State<DesktopSettingsMenu> {
  VoidCallback? _release;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _synchronize();
  }

  @override
  void didUpdateWidget(DesktopSettingsMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    _synchronize();
  }

  bool get _available =>
      widget.ready &&
      defaultTargetPlatform == TargetPlatform.macOS &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  void _synchronize() {
    if (_available) {
      _release ??= DesktopSettingsMenuCommands.instance.bind(() {
        if (mounted && _available) widget.onOpenSettings();
      });
    } else {
      _release?.call();
      _release = null;
    }
  }

  @override
  void dispose() {
    _release?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
