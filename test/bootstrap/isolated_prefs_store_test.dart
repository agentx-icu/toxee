import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/types.dart';
import 'package:toxee/bootstrap/isolated_prefs_store.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('isolated_prefs');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test(
    'round-trips values through its own JSON file and survives a reload',
    () async {
      final file = File('${dir.path}/shared_preferences.json');
      final store = IsolatedPrefsStore(file);
      await store.setValue('String', 'toxee_a.nick', 'Alice');
      await store.setValue('StringList', 'toxee_a.seed', <String>['1', '2']);
      await store.setValue('Bool', 'toxee_a.flag', true);
      expect(await file.exists(), isTrue);

      final reloaded = IsolatedPrefsStore(file);
      final all = await reloaded.getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: 'toxee_a.')),
      );
      expect(all['toxee_a.nick'], 'Alice');
      expect(all['toxee_a.seed'], ['1', '2']);
      expect(all['toxee_a.flag'], true);
    },
  );

  test('two stores on different files do not clobber each other', () async {
    final a = IsolatedPrefsStore(File('${dir.path}/a/shared_preferences.json'));
    final b = IsolatedPrefsStore(File('${dir.path}/b/shared_preferences.json'));
    await a.setValue('String', 'toxee_a.k', 'A');
    await b.setValue('String', 'toxee_b.k', 'B');
    final everything = GetAllParameters(filter: PreferencesFilter(prefix: ''));
    expect(await IsolatedPrefsStore(a.file).getAllWithParameters(everything), {
      'toxee_a.k': 'A',
    });
    expect(await IsolatedPrefsStore(b.file).getAllWithParameters(everything), {
      'toxee_b.k': 'B',
    });
  });

  test('getAll/clear are scoped to the legacy flutter. prefix', () async {
    final store = IsolatedPrefsStore(File('${dir.path}/legacy.json'));
    await store.setValue('String', 'flutter.a', '1');
    await store.setValue('String', 'toxee_a.b', '2');
    expect(await store.getAll(), {'flutter.a': '1'});
    await store.clear();
    expect(
      await store.getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: '')),
      ),
      {'toxee_a.b': '2'},
    );
  });

  test('overlapping writes are serialized and all land', () async {
    final store = IsolatedPrefsStore(File('${dir.path}/race.json'));
    await Future.wait([
      for (var i = 0; i < 25; i++) store.setValue('Int', 'flutter.k$i', i),
    ]);
    final all = await IsolatedPrefsStore(store.file).getAll();
    expect(all.length, 25);
    expect(all['flutter.k24'], 24);
  });

  test('a failed first load is not retained', () async {
    if (Platform.isWindows) return; // chmod-based; POSIX only
    // An unreadable existing file makes readAsString throw FileSystemException.
    final file = File('${dir.path}/blocked.json');
    await file.writeAsString('{"flutter.ok":"yes"}');
    await Process.run('chmod', ['000', file.path]);
    final store = IsolatedPrefsStore(file);
    await expectLater(store.getAll(), throwsA(isA<FileSystemException>()));
    await Process.run('chmod', ['644', file.path]);
    expect(await store.getAll(), {'flutter.ok': 'yes'}); // recovered
  });

  test('remove, prefix filter and clear', () async {
    final store = IsolatedPrefsStore(File('${dir.path}/p.json'));
    await store.setValue('String', 'toxee_a.x', '1');
    await store.setValue('String', 'toxee_b.x', '2');
    final filtered = await store.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'toxee_a.')),
    );
    expect(filtered.keys, ['toxee_a.x']);
    await store.remove('toxee_a.x');
    final rest = await store.getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: '')),
    );
    expect(rest.keys, ['toxee_b.x']);
    await store.clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'toxee_')),
    );
    expect(
      await store.getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: '')),
      ),
      isEmpty,
    );
  });
}
