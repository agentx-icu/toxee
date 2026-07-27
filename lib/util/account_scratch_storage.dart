import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tim2tox_dart/interfaces/scratch_file_service.dart';

import 'app_paths.dart';
import 'prefs.dart';

/// Account-owned storage for regenerable message and media helpers.
class AccountScratchStorage
    implements ScratchFileService, ChatScratchFileProvider {
  AccountScratchStorage({
    required String accountToxId,
    required String accountDataRoot,
  }) : accountToxId = accountToxId.trim(),
       accountDataRoot = p.normalize(p.absolute(accountDataRoot)),
       _accountAvailable = true {
    if (this.accountToxId.isEmpty) {
      throw ArgumentError.value(
        accountToxId,
        'accountToxId',
        'Must not be empty',
      );
    }
  }

  /// Fail-closed owner for the short registration bootstrap before Tox has
  /// generated an account address. That service is never exposed to UIKit and
  /// is replaced with a full-ID owner immediately after identity discovery.
  AccountScratchStorage.unavailableUntilAccountKnown()
    : accountToxId = '',
      accountDataRoot = '',
      _accountAvailable = false;

  static const Duration defaultTimeToLive = Duration(days: 7);

  final String accountToxId;
  final String accountDataRoot;
  final bool _accountAvailable;
  Future<void> _operationTail = Future<void>.value();
  int _temporaryFileSequence = 0;

  String get scratchRoot {
    _requireAccountAvailable();
    return p.join(accountDataRoot, 'scratch');
  }

  @override
  Future<String> writeScratchBytes({
    required String category,
    required String suggestedFileName,
    required Uint8List bytes,
  }) {
    return writeBytesToScratch(
      bytes,
      category: category,
      suggestedFileName: suggestedFileName,
    );
  }

  @override
  Future<String> writeBytesToScratch(
    Uint8List bytes, {
    required String category,
    required String suggestedFileName,
  }) {
    _requireAccountAvailable();
    return _serialized(() async {
      final destination = await _prepareDestination(
        category,
        suggestedFileName,
      );
      final temporary = File(_temporaryPath(destination));
      try {
        await _writeBytesExclusively(temporary, bytes);
        await _replaceAtomically(temporary, destination);
        return destination.path;
      } finally {
        if (await temporary.exists()) {
          await temporary.delete();
        }
      }
    });
  }

  @override
  Future<String> copyFileToScratch(
    String sourcePath, {
    required String category,
    required String suggestedFileName,
  }) {
    _requireAccountAvailable();
    return _serialized(() async {
      final source = File(sourcePath);
      if (await FileSystemEntity.type(source.path, followLinks: true) !=
          FileSystemEntityType.file) {
        throw ArgumentError.value(
          sourcePath,
          'sourcePath',
          'Source is not a file',
        );
      }

      final destination = await _prepareDestination(
        category,
        suggestedFileName,
      );
      final temporary = File(_temporaryPath(destination));
      try {
        await temporary.create(exclusive: true);
        final temporaryHandle = await temporary.open(mode: FileMode.writeOnly);
        try {
          await for (final chunk in source.openRead()) {
            await temporaryHandle.writeFrom(chunk);
          }
          await temporaryHandle.flush();
        } finally {
          await temporaryHandle.close();
        }
        if (await source.length() != await temporary.length()) {
          throw const FileSystemException('Scratch copy length mismatch');
        }
        await _replaceAtomically(temporary, destination);
        return destination.path;
      } finally {
        if (await temporary.exists()) {
          await temporary.delete();
        }
      }
    });
  }

  @override
  Future<void> deleteScratchFile(String filePath) {
    _requireAccountAvailable();
    return _serialized(() async {
      final root = p.normalize(p.absolute(scratchRoot));
      final candidate = p.normalize(p.absolute(filePath));
      if (!p.isWithin(root, candidate)) {
        throw ArgumentError.value(
          filePath,
          'filePath',
          'Path is outside scratch root',
        );
      }

      final type = await FileSystemEntity.type(candidate, followLinks: false);
      if (type == FileSystemEntityType.notFound) return;
      if (type == FileSystemEntityType.directory) {
        throw ArgumentError.value(
          filePath,
          'filePath',
          'Directories are not scratch files',
        );
      }

      final canonicalRoot = await _canonicalScratchRoot();
      final canonicalCandidate = await File(candidate).resolveSymbolicLinks();
      if (!p.isWithin(canonicalRoot, canonicalCandidate)) {
        throw StateError('Scratch file resolves outside the owned root');
      }
      await File(candidate).delete();
      try {
        await File(candidate).parent.delete();
      } on FileSystemException {
        // The item directory is not empty or is being used by another process.
      }
    });
  }

  Future<File> _prepareDestination(String category, String basename) async {
    final safeCategory = _sanitizeSegment(category, fallback: 'misc');
    final safeBasename = _sanitizeSegment(basename, fallback: 'scratch.bin');
    final canonicalRoot = await _canonicalScratchRoot();
    final categoryDirectory = Directory(p.join(scratchRoot, safeCategory));
    await _createDirectoryWithoutLink(categoryDirectory.path);
    final canonicalCategory = await categoryDirectory.resolveSymbolicLinks();
    if (!p.isWithin(canonicalRoot, canonicalCategory)) {
      throw StateError('Scratch category resolves outside the owned root');
    }

    final itemDirectory = await categoryDirectory.createTemp('item_');
    final canonicalItem = await itemDirectory.resolveSymbolicLinks();
    if (!p.isWithin(canonicalCategory, canonicalItem)) {
      await itemDirectory.delete(recursive: true);
      throw StateError('Scratch item directory resolves outside its category');
    }
    final destination = File(p.join(itemDirectory.path, safeBasename));
    if (await FileSystemEntity.type(destination.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('Scratch destination must not be a symbolic link');
    }
    return destination;
  }

  Future<String> _canonicalScratchRoot() async {
    await _createDirectoryWithoutLink(accountDataRoot);
    final canonicalAccountRoot = await Directory(
      accountDataRoot,
    ).resolveSymbolicLinks();
    await _createDirectoryWithoutLink(scratchRoot);
    final canonicalRoot = await Directory(scratchRoot).resolveSymbolicLinks();
    if (!p.isWithin(canonicalAccountRoot, canonicalRoot)) {
      throw StateError('Scratch root resolves outside the account root');
    }
    return canonicalRoot;
  }

  static Future<void> _createDirectoryWithoutLink(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('Scratch directory must not be a symbolic link: $path');
    }
    await Directory(path).create(recursive: true);
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw StateError('Scratch path is not a directory: $path');
    }
  }

  String _temporaryPath(File destination) {
    _temporaryFileSequence += 1;
    return p.join(
      destination.parent.path,
      '.${p.basename(destination.path)}.tmp.$pid.$_temporaryFileSequence',
    );
  }

  static Future<void> _replaceAtomically(
    File temporary,
    File destination,
  ) async {
    await temporary.rename(destination.path);
  }

  static Future<void> _writeBytesExclusively(
    File temporary,
    Uint8List bytes,
  ) async {
    await temporary.create(exclusive: true);
    final handle = await temporary.open(mode: FileMode.writeOnly);
    try {
      await handle.writeFrom(bytes);
      await handle.flush();
    } finally {
      await handle.close();
    }
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _operationTail = _operationTail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static String _sanitizeSegment(String value, {required String fallback}) {
    var result = value.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    result = result.replaceAll(RegExp(r'\.{2,}'), '_');
    result = result.replaceAll(RegExp(r'^\.+'), '');
    if (result.isEmpty || result == '.' || result == '..') return fallback;
    return result;
  }

  void _requireAccountAvailable() {
    if (!_accountAvailable) {
      throw StateError(
        'Scratch storage is unavailable before account creation',
      );
    }
  }

  /// Removes expired files only from exact app-owned scratch directories.
  static Future<void> cleanupExpired({
    required String applicationSupportRoot,
    String? configuredDownloadsRoot,
    String? systemTempRoot,
    Duration timeToLive = defaultTimeToLive,
    DateTime? now,
  }) async {
    final cutoff = (now ?? DateTime.now()).subtract(timeToLive);
    final accountData = Directory(
      p.join(applicationSupportRoot, 'account_data'),
    );
    if (await accountData.exists()) {
      await for (final account in accountData.list(followLinks: false)) {
        if (account is! Directory) continue;
        await _cleanupExactRoot(
          root: Directory(p.join(account.path, 'scratch')),
          trustedParent: accountData,
          cutoff: cutoff,
        );
      }
    }

    final tempRoot = Directory(systemTempRoot ?? Directory.systemTemp.path);
    await _cleanupExactRoot(
      root: Directory(p.join(tempRoot.path, 'toxee_avatar_cache')),
      trustedParent: tempRoot,
      cutoff: cutoff,
    );

    final downloadsPath = configuredDownloadsRoot?.trim();
    if (downloadsPath != null && downloadsPath.isNotEmpty) {
      final downloadsRoot = Directory(downloadsPath);
      await _cleanupExactRoot(
        root: Directory(p.join(downloadsRoot.path, 'toxee_image_paste')),
        trustedParent: downloadsRoot,
        cutoff: cutoff,
      );
    }
  }

  static Future<void> cleanupExpiredAtStartup() async {
    final configuredDownloads = await Prefs.getDownloadsDirectory();
    await cleanupExpired(
      applicationSupportRoot: await AppPaths.applicationSupportPath,
      configuredDownloadsRoot: configuredDownloads,
    );
  }

  static Future<void> _cleanupExactRoot({
    required Directory root,
    required Directory trustedParent,
    required DateTime cutoff,
  }) async {
    if (!await root.exists() || !await trustedParent.exists()) return;
    if (await FileSystemEntity.type(root.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }

    final canonicalParent = await trustedParent.resolveSymbolicLinks();
    final canonicalRoot = await root.resolveSymbolicLinks();
    if (!p.isWithin(canonicalParent, canonicalRoot)) return;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final canonicalFile = await entity.resolveSymbolicLinks();
      if (!p.isWithin(canonicalRoot, canonicalFile)) continue;
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        await entity.delete();
      }
    }
  }
}
