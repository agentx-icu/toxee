import 'package:flutter/material.dart';
import 'interface_style.dart';
import 'prefs.dart';

class AppTheme {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);
  static final ValueNotifier<InterfaceStyle> style = ValueNotifier(
    InterfaceStyle.classic,
  );
  static final Listenable changes = Listenable.merge([mode, style]);
  static Future<void>? _writes;

  static Future<void> initFromPrefs() async {
    final saved = await Prefs.getAppearance();
    style.value = InterfaceStyle.parse(saved['style']);
    mode.value = switch (saved['mode']) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
  }

  static Future<void> _queue(Future<void> Function() write) {
    final previous = _writes;
    final result = previous == null ? write() : previous.then((_) => write());
    late final Future<void> tail;
    void clear() {
      if (identical(_writes, tail)) _writes = null;
    }

    tail = result.then(
      (_) => clear(),
      onError: (Object _, StackTrace __) => clear(),
    );
    _writes = tail;
    return result;
  }

  /// Publish only after the combined durable preference has been accepted.
  static Future<void> setAppearance({
    required InterfaceStyle style,
    required ThemeMode mode,
  }) => _queue(() => _save(style, mode));

  static Future<void> _save(
    InterfaceStyle nextStyle,
    ThemeMode nextMode,
  ) async {
    await Prefs.setAppearance(style: nextStyle.name, mode: nextMode.name);
    style.value = nextStyle;
    mode.value = nextMode;
  }

  static Future<void> set(ThemeMode nextMode) =>
      _queue(() => _save(style.value, nextMode));
}
