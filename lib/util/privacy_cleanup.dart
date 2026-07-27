import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_paths.dart';
import 'logger.dart';
import 'tox_utils.dart';

final class AccountPrivacyCleanup {
  const AccountPrivacyCleanup._();

  static const String _failedMessagesBase =
      'tencent_cloud_chat_failed_messages';
  static const int _legacyToxIdPrefixLength = 16;
  static const String _currentAccountKey = 'current_account_tox_id';
  static const String _nicknameKey = 'self_nickname';
  static const String _statusMessageKey = 'self_status_msg';
  static const String _avatarPathKey = 'self_avatar_path';
  static const String _deprecatedFlatLogName = 'flutter_client.log';

  static Future<void> purgeDeletedAccountResidue({
    required String toxId,
    required bool deletedCurrentAccount,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _purgeDiagnosticLogs();
    await _removeFailedMessagePrefs(prefs, toxId);
    await _removeLegacyCurrentAccountPrefs(
      prefs: prefs,
      toxId: toxId,
      deletedCurrentAccount: deletedCurrentAccount,
    );
  }

  static Future<void> _purgeDiagnosticLogs() async {
    final appSupport = await AppPaths.applicationSupportPath;
    final logsDir = await AppPaths.logsDir;
    final flatLog = File(p.join(appSupport, _deprecatedFlatLogName));
    AppLogger.closeLogSinkForDeletion();
    try {
      if (await logsDir.exists()) {
        await logsDir.delete(recursive: true);
      }
      if (await flatLog.exists()) {
        await flatLog.delete();
      }
      await logsDir.create(recursive: true);
      await AppLogger.openFreshLogSink(await AppPaths.logFilePath);
    } catch (_) {
      await _tryReopenLogSink();
      rethrow;
    }
  }

  static Future<void> _tryReopenLogSink() async {
    try {
      final logsDir = await AppPaths.logsDir;
      await logsDir.create(recursive: true);
      await AppLogger.openFreshLogSink(await AppPaths.logFilePath);
    } catch (_) {}
  }

  static Future<void> _removeFailedMessagePrefs(
    SharedPreferences prefs,
    String toxId,
  ) async {
    await prefs.remove(_failedMessageKey(toxId));
    final legacyKey = _legacyFailedMessageKey(toxId);
    if (legacyKey != null) {
      await prefs.remove(legacyKey);
    }
  }

  static Future<void> _removeLegacyCurrentAccountPrefs({
    required SharedPreferences prefs,
    required String toxId,
    required bool deletedCurrentAccount,
  }) async {
    if (!deletedCurrentAccount) return;
    final current = prefs.getString(_currentAccountKey);
    if (current != null &&
        current.isNotEmpty &&
        !compareToxIds(current, toxId)) {
      return;
    }
    await Future.wait(<Future<bool>>[
      prefs.remove(_nicknameKey),
      prefs.remove(_statusMessageKey),
      prefs.remove(_avatarPathKey),
      if (current != null && compareToxIds(current, toxId))
        prefs.remove(_currentAccountKey),
    ]);
  }

  static String _failedMessageKey(String toxId) {
    return '${_failedMessagesBase}_$toxId';
  }

  static String? _legacyFailedMessageKey(String toxId) {
    if (toxId.length < _legacyToxIdPrefixLength) return null;
    return '${_failedMessagesBase}_${toxId.substring(0, _legacyToxIdPrefixLength)}';
  }
}
