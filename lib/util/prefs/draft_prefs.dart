import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

typedef DraftPrefsAccountResolver = Future<String?> Function();
typedef DraftPrefsClock = DateTime Function();
typedef DraftPrefsStringWriter =
    Future<bool> Function(String key, String value);
typedef DraftPrefsStringRemover = Future<bool> Function(String key);

final class StoredConversationDraft {
  const StoredConversationDraft({required this.text, required this.updatedAt});

  final String text;
  final int updatedAt;
}

final class DraftPrefsPortableImportReport {
  const DraftPrefsPortableImportReport({
    required this.imported,
    required this.skippedMalformed,
    required this.writeFailures,
  });

  final int imported;
  final int skippedMalformed;
  final int writeFailures;
}

/// Stores drafts by the complete Tox account address and conversation ID.
class DraftPrefs {
  static const _storagePrefix = 'draft_v2:';
  static const portableBackupSectionKey = '__toxee_portable_drafts_v2';

  DraftPrefs(
    this._prefs, {
    required DraftPrefsAccountResolver activeAccountToxId,
    DraftPrefsClock? clock,
    DraftPrefsStringWriter? stringWriter,
    DraftPrefsStringRemover? stringRemover,
  }) : _activeAccountToxId = activeAccountToxId,
       _clock = clock ?? DateTime.now,
       _stringWriter = stringWriter ?? _prefs.setString,
       _stringRemover = stringRemover ?? _prefs.remove;

  final SharedPreferences _prefs;
  final DraftPrefsAccountResolver _activeAccountToxId;
  final DraftPrefsClock _clock;
  final DraftPrefsStringWriter _stringWriter;
  final DraftPrefsStringRemover _stringRemover;

  Future<StoredConversationDraft?> loadDraft({
    required String accountToxId,
    required String conversationID,
  }) async {
    final account = await _resolveFullAccountToxId(accountToxId);
    final conversation = _canonicalConversationID(conversationID);
    final v2Key = storageKey(
      accountToxId: account,
      conversationID: conversation,
    );
    final stored = _decode(_prefs.getString(v2Key));
    if (stored != null) {
      await _removeLegacyKeysIfOwned(account, conversation);
      return stored;
    }

    final activeAccount = await _activeFullAccountToxId();
    if (activeAccount == null || activeAccount.toUpperCase() != account) {
      return null;
    }

    final legacyKeys = _legacyKeys(activeAccount, conversation);
    for (final legacyKey in legacyKeys) {
      final legacyText = _prefs.getString(legacyKey);
      if (legacyText == null) continue;
      if (legacyText.isEmpty) {
        await _stringRemover(legacyKey);
        return null;
      }

      final migrated = StoredConversationDraft(
        text: legacyText,
        updatedAt: _clock().millisecondsSinceEpoch ~/ 1000,
      );
      if (await _write(v2Key, migrated)) {
        await _removeKeys(legacyKeys);
      }
      return migrated;
    }
    return null;
  }

  Future<void> saveDraft({
    required String accountToxId,
    required String conversationID,
    required String text,
    int? updatedAt,
  }) async {
    final account = await _resolveFullAccountToxId(accountToxId);
    final key = storageKey(
      accountToxId: account,
      conversationID: _canonicalConversationID(conversationID),
    );
    if (text.isEmpty) {
      final conversation = _canonicalConversationID(conversationID);
      if (!await _removeLegacyKeysIfOwned(
        account,
        conversation,
        requireSuccess: true,
      )) {
        throw StateError('Failed to clear legacy conversation draft');
      }
      if (!await _stringRemover(key)) {
        throw StateError('Failed to clear conversation draft');
      }
      return;
    }

    final draft = StoredConversationDraft(
      text: text,
      updatedAt: updatedAt ?? _clock().millisecondsSinceEpoch ~/ 1000,
    );
    if (!await _write(key, draft)) {
      throw StateError('Failed to persist conversation draft');
    }
    await _removeLegacyKeysIfOwned(
      account,
      _canonicalConversationID(conversationID),
    );
  }

  static String storageKey({
    required String accountToxId,
    required String conversationID,
  }) {
    final conversation = _canonicalConversationID(conversationID);
    return '${storagePrefixForAccount(accountToxId: accountToxId)}$conversation';
  }

  static String storagePrefixForAccount({required String accountToxId}) {
    final account = _validateFullAccountToxId(accountToxId);
    return '$_storagePrefix$account:';
  }

  static bool isV2StorageKey(String key) {
    return key.startsWith(_storagePrefix);
  }

  static bool isFullAccountToxId(String value) {
    return _isFullAccountToxId(value.trim());
  }

  static bool isStorageKeyForAccount({
    required String key,
    required String accountToxId,
  }) {
    final account = accountToxId.trim();
    if (!_isFullAccountToxId(account)) return false;
    final prefix = '$_storagePrefix${account.toUpperCase()}:';
    return key.startsWith(prefix) && key.length > prefix.length;
  }

  static String? conversationIdFromStorageKeyForAccount({
    required String key,
    required String accountToxId,
  }) {
    final account = accountToxId.trim();
    if (!_isFullAccountToxId(account)) return null;
    final prefix = '$_storagePrefix${account.toUpperCase()}:';
    if (!key.startsWith(prefix) || key.length <= prefix.length) return null;
    return key.substring(prefix.length);
  }

  static Map<String, String> exportPortableDrafts({
    required SharedPreferences prefs,
    required String accountToxId,
  }) {
    if (!isFullAccountToxId(accountToxId)) return <String, String>{};
    final result = <String, String>{};
    for (final key in prefs.getKeys()) {
      final conversationID = conversationIdFromStorageKeyForAccount(
        key: key,
        accountToxId: accountToxId,
      );
      if (conversationID == null) continue;
      final encodedDraft = prefs.getString(key);
      final draft = _decode(encodedDraft);
      if (draft == null) continue;
      result[conversationID] = _encode(draft);
    }
    return result;
  }

  static Future<DraftPrefsPortableImportReport> importPortableDrafts({
    required SharedPreferences prefs,
    required String accountToxId,
    required Object? portableDrafts,
    DraftPrefsStringWriter? stringWriter,
  }) async {
    if (portableDrafts == null) {
      return const DraftPrefsPortableImportReport(
        imported: 0,
        skippedMalformed: 0,
        writeFailures: 0,
      );
    }
    if (portableDrafts is! Map) {
      return const DraftPrefsPortableImportReport(
        imported: 0,
        skippedMalformed: 1,
        writeFailures: 0,
      );
    }
    if (!isFullAccountToxId(accountToxId)) {
      return DraftPrefsPortableImportReport(
        imported: 0,
        skippedMalformed: portableDrafts.length,
        writeFailures: 0,
      );
    }

    final writer = stringWriter ?? prefs.setString;
    var imported = 0;
    var skippedMalformed = 0;
    var writeFailures = 0;
    for (final entry in portableDrafts.entries) {
      final conversationID = entry.key;
      final encodedDraft = entry.value;
      if (conversationID is! String || encodedDraft is! String) {
        skippedMalformed++;
        continue;
      }
      final draft = _decode(encodedDraft);
      if (conversationID.trim().isEmpty || draft == null) {
        skippedMalformed++;
        continue;
      }

      late final String key;
      try {
        key = storageKey(
          accountToxId: accountToxId,
          conversationID: conversationID,
        );
      } on ArgumentError {
        skippedMalformed++;
        continue;
      }

      try {
        if (await writer(key, _encode(draft))) {
          imported++;
        } else {
          writeFailures++;
        }
      } catch (_) {
        writeFailures++;
      }
    }
    return DraftPrefsPortableImportReport(
      imported: imported,
      skippedMalformed: skippedMalformed,
      writeFailures: writeFailures,
    );
  }

  Future<String> _resolveFullAccountToxId(String accountToxId) async {
    final candidate = accountToxId.trim();
    if (_isFullAccountToxId(candidate)) return candidate.toUpperCase();

    final active = await _activeFullAccountToxId();
    if (candidate.length == 64 &&
        _isHex(candidate) &&
        active != null &&
        active.substring(0, 64).toUpperCase() == candidate.toUpperCase()) {
      return active.toUpperCase();
    }
    throw ArgumentError.value(
      accountToxId,
      'accountToxId',
      'must resolve to the active full 76-character Tox account ID',
    );
  }

  Future<String?> _activeFullAccountToxId() async {
    final active = (await _activeAccountToxId())?.trim();
    return active != null && _isFullAccountToxId(active) ? active : null;
  }

  Future<bool> _write(String key, StoredConversationDraft draft) {
    return _stringWriter(key, _encode(draft));
  }

  Future<bool> _removeLegacyKeysIfOwned(
    String account,
    String conversation, {
    bool requireSuccess = false,
  }) async {
    final activeAccount = await _activeFullAccountToxId();
    if (activeAccount == null || activeAccount.toUpperCase() != account) {
      return true;
    }
    return _removeKeys(
      _legacyKeys(activeAccount, conversation),
      requireSuccess: requireSuccess,
    );
  }

  static List<String> _legacyKeys(String account, String conversation) {
    final prefix = account.substring(0, 16);
    return <String>{
      'draft_${conversation}_$prefix',
      'draft_${conversation}_${prefix.toUpperCase()}',
      'draft_${conversation}_${prefix.toLowerCase()}',
      'draft_$conversation',
    }.toList();
  }

  Future<bool> _removeKeys(
    Iterable<String> keys, {
    bool requireSuccess = false,
  }) async {
    for (final key in keys) {
      if (!_prefs.containsKey(key)) continue;
      final removed = await _stringRemover(key);
      if (!removed && requireSuccess) return false;
    }
    return true;
  }

  static StoredConversationDraft? _decode(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) return null;
      final text = decoded['text'];
      final updatedAt = decoded['updatedAt'];
      if (text is! String || text.isEmpty || updatedAt is! int) return null;
      return StoredConversationDraft(text: text, updatedAt: updatedAt);
    } on FormatException {
      return null;
    }
  }

  static String _encode(StoredConversationDraft draft) {
    return jsonEncode(<String, Object>{
      'text': draft.text,
      'updatedAt': draft.updatedAt,
    });
  }

  static String _validateFullAccountToxId(String accountToxId) {
    final value = accountToxId.trim();
    if (!_isFullAccountToxId(value)) {
      throw ArgumentError.value(
        accountToxId,
        'accountToxId',
        'must be a full 76-character hexadecimal Tox account ID',
      );
    }
    return value.toUpperCase();
  }

  static bool _isFullAccountToxId(String value) {
    return value.length == 76 && _isHex(value);
  }

  static bool _isHex(String value) {
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  static String _canonicalConversationID(String conversationID) {
    final value = conversationID.trim();
    if (value.isEmpty) {
      throw ArgumentError.value(
        conversationID,
        'conversationID',
        'must not be empty',
      );
    }
    return value;
  }
}
