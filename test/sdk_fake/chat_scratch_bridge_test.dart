import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:toxee/sdk_fake/fake_msg_provider.dart';
import 'package:toxee/util/account_scratch_storage.dart';
import 'package:toxee/util/prefs.dart';

const _accountA =
    '0123456789ABCDEF111111111111111111111111111111111111111111111111111111111111';
const _accountB =
    '0123456789ABCDEF222222222222222222222222222222222222222222222222222222222222';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late AccountScratchStorage storage;
  late List<FakeChatMessageProvider> providers;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('toxee_scratch_bridge_');
    storage = AccountScratchStorage(
      accountToxId: _accountA,
      accountDataRoot: p.join(sandbox.path, 'account_data', _accountA),
    );
    providers = <FakeChatMessageProvider>[];
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.initialize(await SharedPreferences.getInstance());
  });

  tearDown(() async {
    for (final provider in providers) {
      provider.dispose();
    }
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  FakeChatScratchOwner ownerFor({
    String accountToxId = _accountA,
    void Function()? onWrite,
    void Function()? onDelete,
  }) {
    return FakeChatScratchOwner(
      accountToxId: accountToxId,
      writeBytes:
          ({required category, required suggestedFileName, required bytes}) {
            onWrite?.call();
            return storage.writeBytesToScratch(
              bytes,
              category: category,
              suggestedFileName: suggestedFileName,
            );
          },
      deleteFile: (path) {
        onDelete?.call();
        return storage.deleteScratchFile(path);
      },
    );
  }

  FakeChatMessageProvider providerFor({
    String? activeToxId = _accountA,
    FakeChatScratchOwner? owner,
  }) {
    final provider = FakeChatMessageProvider(
      scratchAccountToxIdLoader: () async => activeToxId,
      scratchOwnerLoader: () => owner,
    );
    providers.add(provider);
    return provider;
  }

  test(
    'implements UIKit scratch provider and delegates write/delete',
    () async {
      var writes = 0;
      var deletes = 0;
      final provider = providerFor(
        owner: ownerFor(onWrite: () => writes++, onDelete: () => deletes++),
      );
      expect(provider, isA<ChatScratchFileProvider>());

      final path = await provider.writeScratchBytes(
        category: 'clipboard_images',
        suggestedFileName: 'paste.png',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );

      expect(writes, 1);
      expect(p.isWithin(storage.scratchRoot, path), isTrue);
      expect(await File(path).readAsBytes(), <int>[1, 2, 3]);

      await provider.deleteScratchFile(path);
      expect(deletes, 1);
      expect(await File(path).exists(), isFalse);
    },
  );

  test('rejects absent, short, or mismatched full account owners', () async {
    var writes = 0;
    final owner = ownerFor(onWrite: () => writes++);
    final missingSession = providerFor(activeToxId: null, owner: owner);
    final shortSession = providerFor(
      activeToxId: _accountA.substring(0, 64),
      owner: owner,
    );
    final mismatchedSession = providerFor(activeToxId: _accountB, owner: owner);
    final missingOwner = providerFor(activeToxId: _accountA);

    for (final provider in <FakeChatMessageProvider>[
      missingSession,
      shortSession,
      mismatchedSession,
      missingOwner,
    ]) {
      await expectLater(
        provider.writeScratchBytes(
          category: 'clipboard_images',
          suggestedFileName: 'paste.png',
          bytes: Uint8List(0),
        ),
        throwsA(isA<StateError>()),
      );
    }
    expect(writes, 0);
  });

  test(
    'registration bootstrap owner fails closed before account discovery',
    () {
      final unavailable = AccountScratchStorage.unavailableUntilAccountKnown();
      expect(
        () => unavailable.writeBytesToScratch(
          Uint8List(0),
          category: 'clipboard_images',
          suggestedFileName: 'paste.png',
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}
