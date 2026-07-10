part of 'package:toxee/util/prefs.dart';

// IRC config/state implementation helpers used by Prefs. Every IRC value is
// account-scoped (the Tox groups backing IRC channels are per-account, so the
// channel list / install flag / config / credentials must be too). The caller
// resolves the account-scoped [key]; these helpers only touch storage.

Future<String> _getIrcServerImpl(SharedPreferences p, String key) async {
  return p.getString(key) ?? 'irc.libera.chat';
}

Future<void> _setIrcServerImpl(
    SharedPreferences p, String key, String server) async {
  await p.setString(key, server);
}

Future<int> _getIrcPortImpl(SharedPreferences p, String key) async {
  return p.getInt(key) ?? 6667;
}

Future<void> _setIrcPortImpl(SharedPreferences p, String key, int port) async {
  await p.setInt(key, port);
}

Future<bool> _getIrcUseSaslImpl(SharedPreferences p, String key) async {
  return p.getBool(key) ?? false;
}

Future<void> _setIrcUseSaslImpl(
    SharedPreferences p, String key, bool useSasl) async {
  await p.setBool(key, useSasl);
}

Future<bool> _getIrcAppInstalledImpl(SharedPreferences p, String key) async {
  return p.getBool(key) ?? false;
}

Future<void> _setIrcAppInstalledImpl(
    SharedPreferences p, String key, bool installed) async {
  await p.setBool(key, installed);
}

Future<List<String>> _getIrcChannelsImpl(SharedPreferences p, String key) async {
  final channelsJson = p.getString(key);
  if (channelsJson == null || channelsJson.isEmpty) return [];
  try {
    final List<dynamic> decoded = jsonDecode(channelsJson);
    return decoded.cast<String>();
  } catch (_) {
    return [];
  }
}

Future<void> _setIrcChannelsImpl(
    SharedPreferences p, String key, List<String> channels) async {
  await p.setString(key, jsonEncode(channels));
}
