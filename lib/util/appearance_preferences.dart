import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppearancePreferences {
  AppearancePreferences._();
  static const _key = 'appearance_settings';
  static const _legacyKey = 'theme_mode';
  static Future<void>? _appearanceWrites;

  /// Appearance is one atomic device preference, never account-scoped.
  static Map<String, String> read(SharedPreferences p) {
    try {
      final raw = p.get(_key);
      final value = raw is String ? jsonDecode(raw) : null;
      if (value is Map &&
          value['version'] == 1 &&
          _validStyle(value['style']) &&
          _validThemeMode(value['mode'])) {
        return {
          'style': value['style'] as String,
          'mode': value['mode'] as String,
        };
      }
    } catch (_) {
      // Corrupt or future-version preferences fall back to the legacy mode.
    }
    final legacy = p.get(_legacyKey);
    return {
      'style': 'classic',
      'mode': _validThemeMode(legacy) ? legacy as String : 'system',
    };
  }

  static bool _validStyle(Object? value) =>
      const ['classic', 'modern', 'night', 'paper', 'cartoon'].contains(value);
  static bool _validThemeMode(Object? value) =>
      const ['system', 'light', 'dark'].contains(value);

  static Future<void> _queueAppearance(Future<void> Function() write) {
    final previous = _appearanceWrites;
    final result = previous == null ? write() : previous.then((_) => write());
    late final Future<void> tail;
    void clear() {
      if (identical(_appearanceWrites, tail)) _appearanceWrites = null;
    }

    tail = result.then(
      (_) => clear(),
      onError: (Object _, StackTrace __) => clear(),
    );
    _appearanceWrites = tail;
    return result;
  }

  static Future<void> _writeAppearance(
    SharedPreferences p,
    String style,
    String mode,
  ) async {
    try {
      final saved = await p.setString(
        _key,
        jsonEncode({'version': 1, 'style': style, 'mode': mode}),
      );
      if (!saved) throw Exception('Appearance preference write refused');
    } catch (_) {
      // SharedPreferences updates its cache before the platform accepts a
      // write. Restore durable values before exposing the failure.
      try {
        await p.reload();
      } catch (_) {}
      rethrow;
    }
  }

  static Future<void> write(
    SharedPreferences p, {
    required String style,
    required String mode,
  }) {
    if (!_validStyle(style) || !_validThemeMode(mode)) {
      return Future.error(ArgumentError('Invalid appearance preference'));
    }
    return _queueAppearance(() => _writeAppearance(p, style, mode));
  }

  /// Compatibility entry point: changing brightness retains the saved style.
  static Future<void> writeMode(SharedPreferences p, String mode) =>
      _queueAppearance(() async {
        final current = read(p);
        await _writeAppearance(
          p,
          current['style']!,
          _validThemeMode(mode) ? mode : 'system',
        );
      });
}
