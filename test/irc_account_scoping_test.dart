// Locks the IRC-state account-scoping fix (2026-07-09).
//
// IRC channels map to per-account Tox groups (group names are stored via
// `_scopedKey(baseKey, toxId)`), but the IRC channel list / install flag /
// server config / per-channel nickname used to be stored under GLOBAL keys.
// Switching accounts then surfaced another account's channels as phantom,
// unconnectable entries and leaked config/credentials across accounts. Every
// IRC pref is now account-scoped; this test locks that isolation.
//
// The channel password lives in secure storage, which the plain `flutter test`
// environment does not persist (the FlutterSecureStorageFacade degrades to
// write→no-op / read→null), so it is not asserted here — it uses the identical
// `_scopedKey` path as the nickname, which IS covered.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
  });

  // Distinct 64-char ids with different 16-char prefixes → different scopes.
  final accountA = 'A' * 64;
  final accountB = 'B' * 64;

  test('IRC channels/install/config/nickname are isolated per account',
      () async {
    // Account A joins a channel and configures IRC.
    await Prefs.setCurrentAccountToxId(accountA);
    await Prefs.setIrcAppInstalled(true);
    await Prefs.addIrcChannel('#a-only');
    await Prefs.setIrcServer('irc.a.example');
    await Prefs.setIrcPort(7000);
    await Prefs.setIrcUseSasl(true);
    await Prefs.setIrcChannelNickname('#a-only', 'nick-a');

    expect(await Prefs.getIrcAppInstalled(), isTrue);
    expect(await Prefs.getIrcChannels(), <String>['#a-only']);
    expect(await Prefs.getIrcServer(), 'irc.a.example');
    expect(await Prefs.getIrcPort(), 7000);
    expect(await Prefs.getIrcUseSasl(), isTrue);
    expect(await Prefs.getIrcChannelNickname('#a-only'), 'nick-a');

    // Switch to account B: none of A's IRC state may leak.
    await Prefs.setCurrentAccountToxId(accountB);
    expect(await Prefs.getIrcAppInstalled(), isFalse,
        reason: 'install flag is per-account');
    expect(await Prefs.getIrcChannels(), isEmpty,
        reason: "A's channel list must not appear for B");
    expect(await Prefs.getIrcServer(), 'irc.libera.chat',
        reason: 'server config defaults for a fresh account');
    expect(await Prefs.getIrcPort(), 6667);
    expect(await Prefs.getIrcUseSasl(), isFalse);
    expect(await Prefs.getIrcChannelNickname('#a-only'), isNull,
        reason: "A's nickname must not be visible to B");

    // B configures its own channel independently.
    await Prefs.setIrcAppInstalled(true);
    await Prefs.addIrcChannel('#b-only');
    expect(await Prefs.getIrcChannels(), <String>['#b-only']);

    // Switch back to A: A's original state is intact and unaffected by B.
    await Prefs.setCurrentAccountToxId(accountA);
    expect(await Prefs.getIrcChannels(), <String>['#a-only']);
    expect(await Prefs.getIrcServer(), 'irc.a.example');
    expect(await Prefs.getIrcChannelNickname('#a-only'), 'nick-a');
    expect(await Prefs.getIrcAppInstalled(), isTrue);
  });

  test('IRC getters default and setters no-op with no current account',
      () async {
    // setUp leaves no current account (the mock store is empty).
    expect(await Prefs.getIrcChannels(), isEmpty);
    expect(await Prefs.getIrcAppInstalled(), isFalse);
    expect(await Prefs.getIrcServer(), 'irc.libera.chat');

    // Setters must not throw and must not persist anything reachable.
    await Prefs.setIrcAppInstalled(true);
    await Prefs.addIrcChannel('#orphan');
    await Prefs.setIrcChannelNickname('#orphan', 'x');
    expect(await Prefs.getIrcChannels(), isEmpty);
    expect(await Prefs.getIrcAppInstalled(), isFalse);
    expect(await Prefs.getIrcChannelNickname('#orphan'), isNull);
  });
}
