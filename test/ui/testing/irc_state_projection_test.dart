import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/ui/testing/l3_debug_tools.dart';

void main() {
  test(
    'projectIrcState exposes deterministic IRC prefs and channel mappings',
    () {
      final out = projectIrcState(
        installed: true,
        channels: const ['#toxee', '#l3'],
        server: '.invalid',
        port: 6667,
        useSasl: false,
        channelGroups: const {'#toxee': 'l3_irc_toxee'},
      );

      expect(out['ircInstalled'], isTrue);
      expect(out['ircChannels'], ['#toxee', '#l3']);
      expect(out['ircServer'], '.invalid');
      expect(out['ircPort'], 6667);
      expect(out['ircUseSasl'], isFalse);
      expect(out['ircChannelGroups'], {'#toxee': 'l3_irc_toxee'});
    },
  );

  test('projectIrcState preserves both IRC channel sigils', () {
    final out = projectIrcState(
      installed: true,
      channels: const ['#public', '&local'],
      server: '.invalid',
      port: 6667,
      useSasl: false,
      channelGroups: const {'&local': 'l3_irc_local'},
    );

    expect(out['ircChannels'], ['#public', '&local']);
    expect(out['ircChannelGroups'], {'&local': 'l3_irc_local'});
  });
}
