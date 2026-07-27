import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:toxee/util/account_export/restore_transaction.dart';
import 'package:toxee/util/account_export_service.dart';
import 'package:toxee/util/app_paths.dart';
import 'package:toxee/util/prefs.dart';

import 'test_support.dart';

const _toxId =
    'FACEFACEFACEFACEFACEFACEFACEFACEFACEFACEFACEFACEFACEFACEFACEFACEFACEFACEFACE';
const _nickname = 'V2 Secret Nick';
const _status = 'status-secret-v2';
const _profileSecret = 'profile-secret-v2';
const _historySecret = 'history-secret-v2';
const _queueSecret = 'queue-secret-v2';
const _scopedPrefSecret = 'scoped-pref-secret-v2';
const _exportPassword = 'explicit export password';

void main() {
  group('encrypted full backup v2', () {
    late AccountExportTestEnv env;

    setUp(() async {
      env = await setUpAccountExportTestEnv();
      FullBackupRestoreTestHooks.profileIdentityExtractor =
          (Uint8List profileBytes) => _toxId;
    });

    tearDown(() async {
      FullBackupRestoreTestHooks.reset();
      await env.dispose();
    });

    test(
      'requires an explicit non-empty export password before writing',
      () async {
        await _seedAccountPayload();
        final missingPasswordPath = p.join(env.extras, 'missing_password.zip');
        final emptyPasswordPath = p.join(env.extras, 'empty_password.zip');

        await expectLater(
          () => AccountExportService.exportFullBackup(
            toxId: _toxId,
            filePath: missingPasswordPath,
          ),
          throwsA(isA<PasswordRequiredException>()),
        );
        await expectLater(
          () => AccountExportService.exportFullBackup(
            toxId: _toxId,
            password: '',
            filePath: emptyPasswordPath,
          ),
          throwsA(isA<PasswordRequiredException>()),
        );

        expect(File(missingPasswordPath).existsSync(), isFalse);
        expect(File(emptyPasswordPath).existsSync(), isFalse);
      },
    );

    test(
      'keeps account identity and payload secrets out of raw v2 bytes',
      () async {
        await _seedAccountPayload();
        final zipPath = await AccountExportService.exportFullBackup(
          toxId: _toxId,
          password: _exportPassword,
          filePath: p.join(env.extras, 'encrypted_backup.zip'),
        );

        final rawBytes = await File(zipPath).readAsBytes();
        final outerArchive = ZipDecoder().decodeBytes(rawBytes);
        final outerMetadataFile = outerArchive.findFile('metadata.json');
        expect(outerMetadataFile, isNotNull);
        final outerMetadata =
            json.decode(utf8.decode(outerMetadataFile!.content as List<int>))
                as Map<String, dynamic>;

        expect(outerMetadata['formatVersion'], 2);
        expect(outerMetadata.containsKey('toxId'), isFalse);
        expect(outerMetadata.containsKey('nickname'), isFalse);
        expect(outerMetadata.containsKey('scopedPrefs'), isFalse);
        expect(outerMetadata['encryption'], isA<Map<String, dynamic>>());
        expect(outerMetadata['kdf'], isA<Map<String, dynamic>>());
        expect(outerArchive.findFile('tox_profile.tox'), isNull);
        expect(outerArchive.findFile('offline_message_queue.json'), isNull);

        final outerEntryBytes = _archiveFileBytes(outerArchive);
        for (final secret in <String>[
          _toxId,
          _nickname,
          _status,
          _profileSecret,
          _historySecret,
          _queueSecret,
          _scopedPrefSecret,
        ]) {
          expect(
            _containsUtf8(rawBytes, secret),
            isFalse,
            reason: 'raw exported bytes must not expose $secret',
          );
          expect(
            _containsUtf8(outerEntryBytes, secret),
            isFalse,
            reason: 'outer zip entries must not expose $secret',
          );
        }

        final metadata = await AccountExportService.readFullBackupMetadata(
          zipPath,
          password: _exportPassword,
        );
        expect(metadata['toxId'], _toxId);
        expect(metadata['nickname'], _nickname);
      },
    );

    test('default path uses an opaque timestamped filename', () async {
      await _seedAccountPayload();

      final zipPath = await AccountExportService.exportFullBackup(
        toxId: _toxId,
        password: _exportPassword,
      );
      final fileName = p.basename(zipPath);

      expect(p.dirname(zipPath), env.downloads);
      expect(fileName, matches(RegExp(r'^toxee_full_backup_\d+\.zip$')));
      expect(fileName.toLowerCase(), isNot(contains(_nickname.toLowerCase())));
      expect(fileName.toUpperCase(), isNot(contains(_toxId)));
      expect(fileName.toUpperCase(), isNot(contains(_toxId.substring(0, 8))));
    });

    test(
      'wrong or missing import password fails before restoring any files',
      () async {
        await _seedAccountPayload();
        final zipPath = await AccountExportService.exportFullBackup(
          toxId: _toxId,
          password: _exportPassword,
          filePath: p.join(env.extras, 'wrong_password_backup.zip'),
        );
        await _removeAccountPayloadFromDisk();

        await expectLater(
          () => AccountExportService.readFullBackupMetadata(zipPath),
          throwsA(isA<PasswordRequiredException>()),
        );
        await expectLater(
          () => AccountExportService.importFullBackup(
            filePath: zipPath,
            password: 'wrong password',
          ),
          throwsA(isA<InvalidBackupPasswordException>()),
        );

        final profileDir = await AppPaths.getProfileDirectoryForToxId(_toxId);
        final historyDir = await AppPaths.getAccountChatHistoryPath(_toxId);
        final queuePath = await AppPaths.getAccountOfflineQueueFilePath(_toxId);
        expect(
          File(AppPaths.profileFileInDirectory(profileDir)).existsSync(),
          isFalse,
        );
        expect(
          File(p.join(historyDir, 'conversation.json')).existsSync(),
          isFalse,
        );
        expect(File(queuePath).existsSync(), isFalse);
      },
    );

    test(
      'rejects attacker-controlled KDF iterations before restore writes',
      () async {
        await _seedAccountPayload();
        final sourcePath = await AccountExportService.exportFullBackup(
          toxId: _toxId,
          password: _exportPassword,
          filePath: p.join(env.extras, 'iteration_source.zip'),
        );
        await _removeAccountPayloadFromDisk();
        final tamperedPath = await _writeTamperedV2Backup(
          sourcePath: sourcePath,
          outputPath: p.join(env.extras, 'huge_iterations.zip'),
          mutate: (metadata) {
            final kdf = metadata['kdf'] as Map<String, dynamic>;
            kdf['iterations'] = 1 << 40;
          },
        );

        await expectLater(
          () => AccountExportService.importFullBackup(
            filePath: tamperedPath,
            password: _exportPassword,
          ),
          throwsA(isA<InvalidBackupFormatException>()),
        );
        await _expectNoRestoredPayload();
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    for (final parameter in <String>['kdf algorithm', 'cipher']) {
      test('rejects unsupported $parameter before restore writes', () async {
        await _seedAccountPayload();
        final sourcePath = await AccountExportService.exportFullBackup(
          toxId: _toxId,
          password: _exportPassword,
          filePath: p.join(env.extras, 'algorithm_source.zip'),
        );
        await _removeAccountPayloadFromDisk();
        final tamperedPath = await _writeTamperedV2Backup(
          sourcePath: sourcePath,
          outputPath: p.join(
            env.extras,
            'wrong_${parameter.replaceAll(' ', '_')}.zip',
          ),
          mutate: (metadata) {
            if (parameter == 'kdf algorithm') {
              final kdf = metadata['kdf'] as Map<String, dynamic>;
              kdf['algorithm'] = 'PBKDF2-HMAC-SHA512';
            } else {
              final encryption = metadata['encryption'] as Map<String, dynamic>;
              encryption['cipher'] = 'AES-CBC';
            }
          },
        );

        await expectLater(
          () => AccountExportService.importFullBackup(
            filePath: tamperedPath,
            password: _exportPassword,
          ),
          throwsA(isA<InvalidBackupFormatException>()),
        );
        await _expectNoRestoredPayload();
      });
    }

    for (final field in <String>['salt', 'nonce', 'MAC', 'macBits']) {
      test('rejects wrong $field length before restore writes', () async {
        await _seedAccountPayload();
        final sourcePath = await AccountExportService.exportFullBackup(
          toxId: _toxId,
          password: _exportPassword,
          filePath: p.join(env.extras, 'length_source.zip'),
        );
        await _removeAccountPayloadFromDisk();
        final tamperedPath = await _writeTamperedV2Backup(
          sourcePath: sourcePath,
          outputPath: p.join(env.extras, 'wrong_${field.toLowerCase()}.zip'),
          mutate: (metadata) {
            final kdf = metadata['kdf'] as Map<String, dynamic>;
            final encryption = metadata['encryption'] as Map<String, dynamic>;
            switch (field) {
              case 'salt':
                kdf['salt'] = base64Encode(Uint8List(31));
                break;
              case 'nonce':
                encryption['nonce'] = base64Encode(Uint8List(11));
                break;
              case 'MAC':
                encryption['mac'] = base64Encode(Uint8List(15));
                break;
              case 'macBits':
                encryption['macBits'] = 120;
                break;
            }
          },
        );

        await expectLater(
          () => AccountExportService.importFullBackup(
            filePath: tamperedPath,
            password: _exportPassword,
          ),
          throwsA(isA<InvalidBackupFormatException>()),
        );
        await _expectNoRestoredPayload();
      });
    }

    test('v1 plaintext backup import remains read-only compatible', () async {
      final legacyZipPath = p.join(env.extras, 'legacy_v1.zip');
      await _writeLegacyV1Backup(legacyZipPath);

      final metadata = await AccountExportService.readFullBackupMetadata(
        legacyZipPath,
      );
      expect(metadata['toxId'], _toxId);
      expect(metadata['nickname'], 'Legacy Nick');

      final result = await AccountExportService.importFullBackup(
        filePath: legacyZipPath,
      );
      expect(result['toxId'], _toxId);
      expect(result['nickname'], 'Legacy Nick');

      final historyDir = await AppPaths.getAccountChatHistoryPath(_toxId);
      expect(
        await File(p.join(historyDir, 'legacy.json')).readAsString(),
        contains('legacy-history'),
      );
    });

    test(
      'failed final rename cleans its stage and preserves foreign temp files',
      () async {
        await _seedAccountPayload();
        final occupiedTarget = Directory(p.join(env.extras, 'occupied.zip'));
        await occupiedTarget.create();
        final staleTemp = File('${occupiedTarget.path}.tmp');
        await staleTemp.writeAsString('stale temp bytes');

        await expectLater(
          () => AccountExportService.exportFullBackup(
            toxId: _toxId,
            password: _exportPassword,
            filePath: occupiedTarget.path,
          ),
          throwsA(isA<FileSystemException>()),
        );

        expect(occupiedTarget.existsSync(), isTrue);
        expect(staleTemp.existsSync(), isTrue);
        final ownedStages = await Directory(env.extras).list().where((entry) {
          return entry.path.startsWith('${occupiedTarget.path}.tmp.');
        }).toList();
        expect(ownedStages, isEmpty);
      },
    );
  });
}

Future<void> _seedAccountPayload() async {
  await Prefs.addAccount(
    toxId: _toxId,
    nickname: _nickname,
    statusMessage: _status,
  );
  await Prefs.setCurrentAccountToxId(_toxId);
  await Prefs.setPinned({_scopedPrefSecret});

  final profileDir = await AppPaths.getProfileDirectoryForToxId(_toxId);
  await Directory(profileDir).create(recursive: true);
  await File(
    AppPaths.profileFileInDirectory(profileDir),
  ).writeAsBytes(Uint8List.fromList(utf8.encode(_profileSecret)));

  final historyDir = await AppPaths.getAccountChatHistoryPath(_toxId);
  await Directory(historyDir).create(recursive: true);
  await File(
    p.join(historyDir, 'conversation.json'),
  ).writeAsString(jsonEncode({'message': _historySecret}));

  final queuePath = await AppPaths.getAccountOfflineQueueFilePath(_toxId);
  await File(queuePath).parent.create(recursive: true);
  await File(queuePath).writeAsString(jsonEncode({'queued': _queueSecret}));
}

Future<void> _removeAccountPayloadFromDisk() async {
  for (final path in <String>[
    await AppPaths.getProfileDirectoryForToxId(_toxId),
    await AppPaths.getAccountDataRoot(_toxId),
  ]) {
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }
}

Future<void> _expectNoRestoredPayload() async {
  final profileDir = await AppPaths.getProfileDirectoryForToxId(_toxId);
  final historyDir = await AppPaths.getAccountChatHistoryPath(_toxId);
  final queuePath = await AppPaths.getAccountOfflineQueueFilePath(_toxId);
  expect(
    File(AppPaths.profileFileInDirectory(profileDir)).existsSync(),
    isFalse,
  );
  expect(File(p.join(historyDir, 'conversation.json')).existsSync(), isFalse);
  expect(File(queuePath).existsSync(), isFalse);
}

Future<String> _writeTamperedV2Backup({
  required String sourcePath,
  required String outputPath,
  required void Function(Map<String, dynamic> metadata) mutate,
}) async {
  final source = ZipDecoder().decodeBytes(await File(sourcePath).readAsBytes());
  final metadataFile = source.findFile('metadata.json');
  if (metadataFile == null) {
    throw StateError('Encrypted test backup is missing metadata.json');
  }
  final metadata =
      json.decode(utf8.decode(metadataFile.content as List<int>))
          as Map<String, dynamic>;
  mutate(metadata);

  final metadataBytes = utf8.encode(jsonEncode(metadata));
  final tampered = Archive()
    ..addFile(
      ArchiveFile(
        'metadata.json',
        metadataBytes.length,
        Uint8List.fromList(metadataBytes),
      ),
    );
  for (final file in source.files) {
    if (!file.isFile || file.name == 'metadata.json') continue;
    final bytes = Uint8List.fromList(file.content as List<int>);
    tampered.addFile(ArchiveFile(file.name, bytes.length, bytes));
  }
  final zipBytes = ZipEncoder().encode(tampered);
  await File(outputPath).writeAsBytes(zipBytes, flush: true);
  return outputPath;
}

Future<void> _writeLegacyV1Backup(String zipPath) async {
  final archive = Archive();
  final metadata = <String, dynamic>{
    'formatVersion': 1,
    'toxId': _toxId,
    'nickname': 'Legacy Nick',
    'statusMessage': 'Legacy Status',
    'exportDate': DateTime.now().toIso8601String(),
    'scopedPrefs': <String, dynamic>{},
  };
  final metadataBytes = utf8.encode(
    const JsonEncoder.withIndent('  ').convert(metadata),
  );
  archive.addFile(
    ArchiveFile(
      'metadata.json',
      metadataBytes.length,
      Uint8List.fromList(metadataBytes),
    ),
  );
  final historyBytes = utf8.encode('{"message":"legacy-history"}');
  archive.addFile(
    ArchiveFile(
      'chat_history/legacy.json',
      historyBytes.length,
      Uint8List.fromList(historyBytes),
    ),
  );
  final zipBytes = ZipEncoder().encode(archive);
  await File(zipPath).writeAsBytes(zipBytes, flush: true);
}

Uint8List _archiveFileBytes(Archive archive) {
  final chunks = <List<int>>[];
  var length = 0;
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final bytes = file.content as List<int>;
    chunks.add(bytes);
    length += bytes.length;
  }
  final out = Uint8List(length);
  var offset = 0;
  for (final chunk in chunks) {
    out.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return out;
}

bool _containsUtf8(List<int> bytes, String needle) {
  return utf8.decode(bytes, allowMalformed: true).contains(needle);
}
