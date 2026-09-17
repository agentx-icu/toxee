// Translation-completeness gate for the app ARBs (lib/l10n) and the UIKit fork
// ARBs (tencent_cloud_chat_intl/lib/language_arb).
//
// gen-l10n never fails on a missing translation: it silently compiles the
// English template value into every locale that lacks the key. That is how
// ja/ko shipped ~110 English strings, zh_Hans overrode correct Chinese with
// English, and zh_Hant fell back to Simplified Chinese — all with a green
// build. These checks make each of those a test failure.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _appDir = 'lib/l10n';
const _uikitDir =
    'third_party/chat-uikit-flutter/tencent_cloud_chat_intl/lib/language_arb';

/// Locales that must carry every template key themselves. zh_Hans is not in
/// the list: gen-l10n resolves it through `zh`, so it only needs overrides.
const _completeLocales = ['zh', 'zh_Hant', 'ja', 'ko', 'ar'];

/// Keys whose value is legitimately identical to English in other languages
/// (brand names, or template keys no UI reads).
const _sameAsEnglishAllowed = {
  // `english` is the language picker's endonym, shown as-is in every locale.
  'app': {'english', 'upgradeAppTitle', 'online', 'offline'},
  'uikit': {'english', 'tencentCloudChat', 'weChat', 'tGWA'},
};

/// Characters that only exist in Simplified Chinese among those our Chinese
/// copy uses (derived with OpenCC s2tw over the zh ARBs). Left out because they
/// are also correct Traditional characters: 台 (平台), 占 (占用), 云 (云云),
/// 于 (surname). 后 stays: in UI copy it is virtually always 以后/之后.
const _simplifiedOnly =
    '与丢两个临为么义书产亲仅从们会传伤体储关兽内册写准击则刚创删别务动区协单历参双'
    '发变号叹后吗听启员响国图场坏墙声处备复头夹实审对导将尝属帐帧并庆应开弹强归当录态恶惊惧'
    '户执扫扬扰护拥拦择挂换据摄数断无旧时昵显暂机权条来标档检欢气没浅测满点热爱状猪现电画盘'
    '着码确离称筛签简类红约级纸线组经结给络绝统继续维缀编网联腾节获装见观规视认讨让议讯记讶'
    '许论设访证识词译试话该详语误说请读谨责败账质贴资赞跃转载较辑输达过运还这进连适选邮释钟'
    '钥钮铃链销锁错键长闭问间阅队阳随隐静页顶须领频题风馈验髅麦龇';

/// Cantonese colloquial particles and vocabulary (揀 = pick) — zh_Hant is
/// written Taiwan Mandarin.
const _cantoneseParticles = '咗嘅唔喺哋嚟冇揀';

Map<String, String> _values(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync()) as Map;
  return {
    for (final e in decoded.entries)
      if (!(e.key as String).startsWith('@') && e.value is String)
        e.key as String: e.value as String,
  };
}

String _arb(String set, String locale) =>
    set == 'app' ? '$_appDir/app_$locale.arb' : '$_uikitDir/l10n_$locale.arb';

/// True when [value] still reads as English prose (brand/protocol tokens and
/// placeholders removed).
bool _readsAsEnglish(String value) {
  final stripped = value
      .replaceAll(RegExp(r'\{[^}]*\}'), '')
      .replaceAll(
        RegExp(
          r'Toxee|toxee|Tox ID|Tox|qTox|IRC|DHT|UDP|TCP|IPv[46]|LAN|QR|P2P|'
          r'Wi-?Fi|URL|PIN|SDK',
        ),
        '',
      );
  return RegExp(r'[A-Za-z]{3,}').hasMatch(stripped);
}

void main() {
  for (final set in ['app', 'uikit']) {
    group('$set ARBs', () {
      final en = _values(_arb(set, 'en'));

      for (final locale in _completeLocales) {
        test('$locale translates every template key', () {
          final values = _values(_arb(set, locale));
          final missing = en.keys.where((k) => !values.containsKey(k)).toList();
          expect(
            missing,
            isEmpty,
            reason: '$locale would render these in English',
          );
        });

        test('$locale has no value left in English', () {
          final values = _values(_arb(set, locale));
          final english = [
            for (final e in values.entries)
              if (e.value == en[e.key] &&
                  _readsAsEnglish(e.value) &&
                  !_sameAsEnglishAllowed[set]!.contains(e.key))
                e.key,
          ];
          expect(english, isEmpty);
        });
      }

      test('zh_Hans never overrides zh with English', () {
        final zh = _values(_arb(set, 'zh'));
        final hans = _values(_arb(set, 'zh_Hans'));
        final overrides = [
          for (final e in hans.entries)
            if (e.value == en[e.key] &&
                zh[e.key] != null &&
                zh[e.key] != e.value &&
                _readsAsEnglish(e.value))
              e.key,
        ];
        expect(overrides, isEmpty);
      });

      test('zh_Hant is Traditional Chinese, not Simplified or Cantonese', () {
        final hant = _values(_arb(set, 'zh_Hant'));
        final offenders = <String, String>{};
        for (final e in hant.entries) {
          final bad = e.value.runes
              .map(String.fromCharCode)
              .where(
                (c) =>
                    _simplifiedOnly.contains(c) ||
                    _cantoneseParticles.contains(c),
              )
              .toSet();
          if (bad.isNotEmpty) offenders[e.key] = bad.join();
        }
        expect(offenders, isEmpty);
      });

      test('ja and ko contain no Chinese-only text', () {
        // e.g. ja/ko `modifyRemark` shipped as the Chinese 修改备注. Language
        // names in the picker are endonyms and exempt.
        const endonyms = {
          'simplifiedChinese',
          'traditionalChinese',
          'japanese',
        };
        // Simplified forms that are also standard Japanese kanji (shinjitai).
        const alsoJapanese = '会体内写参号国声属当数断旧来点画着静';
        final han = RegExp(r'[\u4e00-\u9fff]');
        final offenders = <String>[
          for (final e in _values(_arb(set, 'ko')).entries)
            if (!endonyms.contains(e.key) && han.hasMatch(e.value))
              'ko.${e.key}',
          for (final e in _values(_arb(set, 'ja')).entries)
            if (!endonyms.contains(e.key) &&
                e.value.runes
                    .map(String.fromCharCode)
                    .any(
                      (c) =>
                          _simplifiedOnly.contains(c) &&
                          !alsoJapanese.contains(c),
                    ))
              'ja.${e.key}',
        ];
        expect(offenders, isEmpty);
      });

      test('translations keep the template placeholders', () {
        // Top-level ICU argument names only: `{num, plural, one {…}}` yields
        // `num`, never the branch text.
        Set<String> names(String s) {
          final out = <String>{};
          var depth = 0;
          var start = -1;
          for (var i = 0; i < s.length; i++) {
            if (s[i] == '{') {
              if (depth == 0) start = i + 1;
              depth++;
            } else if (s[i] == '}') {
              depth--;
              if (depth == 0 && start >= 0) {
                out.add(s.substring(start, i).split(RegExp(r'[,\s]')).first);
              }
            }
          }
          return out;
        }

        final problems = <String>[];
        for (final locale in [..._completeLocales, 'zh_Hans']) {
          final values = _values(_arb(set, locale));
          for (final e in values.entries) {
            final template = en[e.key];
            if (template == null) continue;
            if (!names(template).containsAll(names(e.value))) {
              problems.add('$locale.${e.key}');
            }
          }
        }
        expect(problems, isEmpty);
      });
    });
  }
}
