import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:toxee/util/prefs.dart';
import 'package:toxee/util/interface_style.dart';
import 'package:toxee/util/theme_controller.dart';

class RefusingStore extends SharedPreferencesStorePlatform {
  RefusingStore(this.inner);
  final SharedPreferencesStorePlatform inner;
  bool refuse = false;
  bool fail = false;
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes++;
    if (gate != null) await gate!.future;
    if (fail) throw Exception('disk unavailable');
    return refuse ? false : inner.setValue(type, key, value);
  }

  @override
  Future<Map<String, Object>> getAll() => inner.getAll();
  @override
  Future<bool> remove(String key) => inner.remove(key);
  @override
  Future<bool> clear() => inner.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late RefusingStore store;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'system'});
    store = RefusingStore(SharedPreferencesStorePlatform.instance);
    SharedPreferencesStorePlatform.instance = store;
    await Prefs.initialize(await SharedPreferences.getInstance());
    await AppTheme.initFromPrefs();
  });
  tearDown(() => SharedPreferencesStorePlatform.instance = store.inner);
  test(
    'failed theme write preserves the applied mode and reports failure',
    () async {
      store.refuse = true;
      await expectLater(AppTheme.set(ThemeMode.dark), throwsException);
      expect(AppTheme.mode.value, ThemeMode.system);
      expect(await Prefs.getThemeMode(), 'system');
    },
  );
  test('style and brightness survive restart as one preference', () async {
    await AppTheme.setAppearance(
      style: InterfaceStyle.paper,
      mode: ThemeMode.dark,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(jsonDecode(prefs.getString('appearance_settings')!), {
      'version': 1,
      'style': 'paper',
      'mode': 'dark',
    });
    AppTheme.style.value = InterfaceStyle.classic;
    AppTheme.mode.value = ThemeMode.system;
    await AppTheme.initFromPrefs();
    expect(AppTheme.style.value, InterfaceStyle.paper);
    expect(AppTheme.mode.value, ThemeMode.dark);
  });
  test('legacy brightness loads with classic identity', () async {
    await (await SharedPreferences.getInstance()).setString(
      'theme_mode',
      'dark',
    );
    await AppTheme.initFromPrefs();
    expect(AppTheme.style.value, InterfaceStyle.classic);
    expect(AppTheme.mode.value, ThemeMode.dark);
  });
  test('invalid stored value types do not break startup', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('appearance_settings', 7);
    await prefs.setBool('theme_mode', false);
    await AppTheme.initFromPrefs();
    expect(AppTheme.style.value, InterfaceStyle.classic);
    expect(AppTheme.mode.value, ThemeMode.system);
  });
  test('corrupt or unsupported preference falls back safely', () async {
    final prefs = await SharedPreferences.getInstance();
    for (final raw in [
      '{broken',
      '{"version":2,"style":"paper","mode":"dark"}',
      '{"version":1,"style":"missing","mode":"dark"}',
      '{"version":1,"style":"paper","mode":"unknown"}',
    ]) {
      await prefs.setString('appearance_settings', raw);
      await AppTheme.initFromPrefs();
      expect(AppTheme.style.value, InterfaceStyle.classic);
      expect(AppTheme.mode.value, ThemeMode.system);
    }
  });
  test(
    'failure retains both applied and durable values and can retry',
    () async {
      await AppTheme.setAppearance(
        style: InterfaceStyle.night,
        mode: ThemeMode.light,
      );
      for (final throwing in [false, true]) {
        store.refuse = !throwing;
        store.fail = throwing;
        await expectLater(
          AppTheme.setAppearance(
            style: InterfaceStyle.cartoon,
            mode: ThemeMode.dark,
          ),
          throwsException,
        );
        expect(AppTheme.style.value, InterfaceStyle.night);
        expect(AppTheme.mode.value, ThemeMode.light);
        expect(await Prefs.getAppearance(), {
          'style': 'night',
          'mode': 'light',
        });
      }
      store.refuse = store.fail = false;
      await AppTheme.setAppearance(
        style: InterfaceStyle.cartoon,
        mode: ThemeMode.dark,
      );
      expect(await Prefs.getAppearance(), {'style': 'cartoon', 'mode': 'dark'});
    },
  );
  test('queued brightness change retains the latest committed style', () async {
    store.gate = Completer<void>();
    final first = AppTheme.setAppearance(
      style: InterfaceStyle.modern,
      mode: ThemeMode.dark,
    );
    final next = AppTheme.set(ThemeMode.light);
    await Future<void>.delayed(Duration.zero);
    expect(store.writes, 1);
    expect(AppTheme.style.value, InterfaceStyle.classic);
    expect(AppTheme.mode.value, ThemeMode.system);
    store.gate!.complete();
    await Future.wait([first, next]);
    expect(await Prefs.getAppearance(), {'style': 'modern', 'mode': 'light'});
    expect(store.writes, 2);
  });
}
