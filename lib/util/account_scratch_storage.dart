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
    if (!_fullToxIdPattern.hasMatch(this.accountToxId)) {
      throw ArgumentError.value(
        accountToxId,
        'accountToxId',
        'Scratch storage requires the full 76-character Tox ID',
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
  static final RegExp _fullToxIdPattern = RegExp(r'^[0-9a-fA-F]{76}$');
  static final RegExp _categoryPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$',
  );
  static final RegExp _badBasenamePattern = RegExp(r'[/\\:\x00-\x1F\x7F]');

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
        category: category,
        basename: suggestedFileName,
      );
      final temporary = File(_temporaryPath(destination));
      try {
        await _writeBytesExclusively(temporary, bytes);
        await temporary.rename(destination.path);
        return destination.path;
      } finally {
        await _deleteFileBestEffort(temporary);
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
        category: category,
        basename: suggestedFileName,
      );
      final temporary = File(_temporaryPath(destination));
      try {
        await temporary.create(exclusive: true);
        final sink = await temporary.open(mode: FileMode.writeOnly);
        try {
          await for (final chunk in source.openRead()) {
            await sink.writeFrom(chunk);
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (await source.length() != await temporary.length()) {
          throw const FileSystemException('Scratch copy length mismatch');
        }
        await temporary.rename(destination.path);
        return destination.path;
      } finally {
        await _deleteFileBestEffort(temporary);
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
      if (type != FileSystemEntityType.file) {
        throw ArgumentError.value(
          filePath,
          'filePath',
          'Scratch deletion only accepts owned regular files',
        );
      }

      final canonicalRoot = await _canonicalScratchRoot();
      final canonicalCandidate = await File(candidate).resolveSymbolicLinks();
      if (!p.isWithin(canonicalRoot, canonicalCandidate)) {
        throw StateError('Scratch file resolves outside the owned root');
      }
      await File(candidate).delete();
      await _deleteDirectoryBestEffort(Directory(p.dirname(candidate)));
    });
  }

  Future<File> _prepareDestination({
    required String category,
    required String basename,
  }) async {
    _validateCategory(category);
    _validateBasename(basename);

    final canonicalRoot = await _canonicalScratchRoot();
    final categoryDirectory = Directory(p.join(scratchRoot, category));
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
    final destination = File(p.join(itemDirectory.path, basename));
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

  static void _validateCategory(String category) {
    if (!_categoryPattern.hasMatch(category)) {
      throw ArgumentError.value(
        category,
        'category',
        'Scratch category must be a safe path segment',
      );
    }
  }

  static void _validateBasename(String basename) {
    if (basename.isEmpty ||
        basename == '.' ||
        basename == '..' ||
        _badBasenamePattern.hasMatch(basename) ||
        p.basename(basename) != basename) {
      throw ArgumentError.value(
        basename,
        'suggestedFileName',
        'Scratch filename must be a safe basename',
      );
    }
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
    if (await _isRealDirectory(accountData.path)) {
      await for (final account in accountData.list(followLinks: false)) {
        if (account is! Directory) continue;
        if (!_fullToxIdPattern.hasMatch(p.basename(account.path))) continue;
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

    final downloads = configuredDownloadsRoot?.trim();
    if (downloads != null && downloads.isNotEmpty) {
      final downloadsRoot = Directory(downloads);
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
    if (!await _isRealDirectory(root.path) ||
        !await _isRealDirectory(trustedParent.path)) {
      return;
    }

    final canonicalParent = await trustedParent.resolveSymbolicLinks();
    final canonicalRoot = await root.resolveSymbolicLinks();
    if (!p.isWithin(canonicalParent, canonicalRoot)) return;

    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (await FileSystemEntity.type(entity.path, followLinks: false) !=
          FileSystemEntityType.file) {
        continue;
      }
      final canonicalFile = await entity.resolveSymbolicLinks();
      if (!p.isWithin(canonicalRoot, canonicalFile)) continue;
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        await entity.delete();
      }
    }
  }

  static Future<bool> _isRealDirectory(String path) async {
    return await FileSystemEntity.type(path, followLinks: false) ==
        FileSystemEntityType.directory;
  }

  static Future<void> _deleteFileBestEffort(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Best-effort cleanup after a failed scratch operation.
    }
  }

  static Future<void> _deleteDirectoryBestEffort(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete();
    } on FileSystemException {
      // Leave non-empty or concurrently used item directories intact.
    }
  }
}
