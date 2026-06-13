// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// P1 extra — feasible real-app follow-ups from the inventory's "still add"
// bucket. These are intentionally single-instance: they cover app-local
// language/RTL and keyboard search surfaces without mutating friendships.

const _p1ExtraCases = {'ar_rtl_page_walk', 'keyboard_global_search_shortcut'};

bool _isP1ExtraCaseScenario(String scenario) =>
    _p1ExtraCases.contains(scenario);

Future<int> runP1ExtraCase(Inst a, String nickA, String scenario) async {
  await ensureHome(a, nickA);
  var ok = false;
  try {
    ok = switch (scenario) {
      'ar_rtl_page_walk' => await _p1eArRtlPageWalk(a),
      'keyboard_global_search_shortcut' =>
        await _p1eKeyboardGlobalSearchShortcut(a),
      _ => throw ArgumentError('unsupported p1-extra scenario: $scenario'),
    };
  } finally {
    await _p1eNormalize(a);
  }
  print('[pair] ${ok ? 'PASS' : 'FAIL'}: $scenario');
  return ok ? 0 : 1;
}

Future<int> runP1ExtraSweep(Inst a, String nickA) async {
  await ensureHome(a, nickA);
  var passed = 0;
  var failed = 0;

  Future<void> hard(String name, Future<bool> Function() body) async {
    var ok = false;
    try {
      ok = await body();
    } on PermissionBlockedError {
      rethrow;
    } on Object catch (e, st) {
      ok = false;
      print('[sweep] sweep_p1_extra EXCEPTION in $name: $e');
      print(st);
    } finally {
      await _p1eNormalize(a);
    }
    if (ok) {
      passed++;
    } else {
      failed++;
    }
    print('[sweep] sweep_p1_extra ${ok ? 'PASS' : 'FAIL'}: $name');
  }

  await hard('ar_rtl_page_walk', () => _p1eArRtlPageWalk(a));
  await hard(
    'keyboard_global_search_shortcut',
    () => _p1eKeyboardGlobalSearchShortcut(a),
  );

  final endClean = await _p1eNormalize(a);
  if (!endClean) failed++;
  print(
    '[sweep] sweep_p1_extra summary: passed=$passed failed=$failed '
    'endClean=$endClean',
  );
  return failed == 0 ? 0 : 1;
}

Future<bool> _p1eNormalize(Inst inst) async {
  var localeEn = true;
  try {
    localeEn = await _p1RevertLocaleToEnglish(inst);
  } on Object catch (e) {
    localeEn = false;
    print('[sweep] p1-extra normalize: locale revert failed: $e');
  }
  try {
    if (await inst.waitKey('message_search_field', timeoutSecs: 1)) {
      await _closeGlobalSearch(inst);
    }
  } on Object catch (e) {
    print('[sweep] p1-extra normalize: search close best-effort failed: $e');
  }
  try {
    await returnToChatsHome(inst, rounds: 4);
  } on Object catch (e) {
    print('[sweep] p1-extra normalize: return home best-effort failed: $e');
  }
  final st = await inst.dumpState();
  return localeEn && st['languageCode']?.toString() == 'en';
}

/// P1 extra: switch the REAL Settings language expander to Arabic, verify the
/// live app renders Arabic labels across multiple home surfaces, then revert via
/// locale-independent keys. The direct RTL Directionality invariant is still
/// hermetically gated by `test/ui/settings/ar_rtl_smoke_test.dart`; this live
/// case proves the real App shell can be driven into and out of Arabic.
Future<bool> _p1eArRtlPageWalk(Inst inst) async {
  try {
    await _openSettings(inst);
    await _scrollKeyIntoBand(
      inst,
      'settings_language_selector',
      topBand: 110,
      bottomBand: 300,
    );

    var expanded = await inst.keyCenter('settings_language_option_ar') != null;
    for (var attempt = 0; attempt < 4 && !expanded; attempt++) {
      if (!await inst.tapKeyAt('settings_language_selector')) {
        await _scrollKeyIntoBand(
          inst,
          'settings_language_selector',
          topBand: 110,
          bottomBand: 300,
        );
        if (!await inst.tapKeyAt('settings_language_selector')) break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expanded = await inst.waitText('العربية', timeoutSecs: 2);
    }
    if (!expanded) {
      print('[pair] ar_rtl_page_walk: could not expand language selector');
      return false;
    }

    var arTapped = await inst.tapKeyAt('settings_language_option_ar');
    if (!arTapped) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      arTapped = await inst.tapKeyAt('settings_language_option_ar');
    }
    if (!arTapped) {
      print('[pair] ar_rtl_page_walk: العربية option not tappable');
      return false;
    }

    final arPersisted = await _waitStringState(inst, 'languageCode', 'ar');
    if (!arPersisted) {
      print('[pair] ar_rtl_page_walk: languageCode never became ar');
      return false;
    }

    await inst.foreground();
    final settingsAr =
        await inst.waitText('المظهر', timeoutSecs: 6) ||
        await _scrollToText(inst, 'المظهر');
    final sidebarChatsAr = await inst.waitText('الدردشات', timeoutSecs: 6);
    final sidebarContactsAr = await inst.waitText(
      'جهات الاتصال',
      timeoutSecs: 3,
    );
    final sidebarSettingsAr = await inst.waitText('الإعدادات', timeoutSecs: 3);

    final profileOpened = await _openSelfProfile(inst);
    final profileAr =
        profileOpened &&
        (await inst.waitText('الملف الشخصي', timeoutSecs: 6) ||
            await inst.waitText('حفظ الصورة', timeoutSecs: 3));
    final profileClosed = await _closeSelfProfile(inst);
    await inst.shot('/tmp/ui_p1_extra_ar_rtl_${inst.name}.png');

    final reverted = await _p1RevertLocaleToEnglish(inst);
    await _openSettings(inst);
    final enBack =
        await inst.waitText('Appearance', timeoutSecs: 6) ||
        await _scrollToText(inst, 'Appearance');

    print(
      '[pair] ar_rtl_page_walk: arPersisted=$arPersisted '
      'settingsAr=$settingsAr sidebar(chats=$sidebarChatsAr '
      'contacts=$sidebarContactsAr settings=$sidebarSettingsAr) '
      'profile(open=$profileOpened ar=$profileAr closed=$profileClosed) '
      'reverted=$reverted enBack=$enBack',
    );
    return arPersisted &&
        settingsAr &&
        sidebarChatsAr &&
        sidebarContactsAr &&
        sidebarSettingsAr &&
        profileOpened &&
        profileAr &&
        profileClosed &&
        reverted &&
        enBack;
  } finally {
    final guardOk = await _p1RevertLocaleToEnglish(inst);
    if (!guardOk) {
      print('[pair] ar_rtl_page_walk: finally locale revert failed');
    }
  }
}

/// P1 extra: open the global search overlay with the real desktop shortcut,
/// type a no-hit query using the already-autofocused field, assert the real
/// empty state, and record whether Escape alone dismissed the route. Cleanup may
/// fall back to the keyed normalizer, but the asserted search path is keyboard.
Future<bool> _p1eKeyboardGlobalSearchShortcut(Inst inst) async {
  await returnToChatsHome(inst, rounds: 4);
  await inst.foreground();
  try {
    await inst.osaSearchShortcut();
  } on DriveError catch (e) {
    print(
      '[pair] keyboard_global_search_shortcut: shortcut blocked: ${e.message}',
    );
    return false;
  }
  final opened = await inst.waitKey('message_search_field', timeoutSecs: 10);
  if (!opened) {
    print('[pair] keyboard_global_search_shortcut: overlay did not open');
    return false;
  }

  final nonce = 'kbdnohit${DateTime.now().microsecondsSinceEpoch}';
  await Future<void>.delayed(const Duration(milliseconds: 500));
  try {
    await inst.osaClear();
    await inst.osaPaste(nonce);
  } on DriveError catch (e) {
    print('[pair] keyboard_global_search_shortcut: type failed: ${e.message}');
    return false;
  }
  final emptyShown = await inst.waitText('No results found', timeoutSecs: 15);
  await inst.shot('/tmp/ui_p1_extra_keyboard_search_${inst.name}.png');
  if (!emptyShown) {
    print('[pair] keyboard_global_search_shortcut: empty state never rendered');
  }

  var escClosed = false;
  try {
    await inst.osaEscape();
    escClosed = await inst.waitKeyGone('message_search_field', timeoutSecs: 4);
  } on DriveError {
    // Cleanup below will fall back; ESC efficacy is diagnostic, not the hard
    // assertion for this shortcut/search case.
  }
  final closed = escClosed || await _closeGlobalSearch(inst);
  print(
    '[pair] keyboard_global_search_shortcut: opened=$opened '
    'emptyShown=$emptyShown escClosed=$escClosed closed=$closed',
  );
  return opened && emptyShown && closed;
}
