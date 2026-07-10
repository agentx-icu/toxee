// Honest add-channel outcome mapping, shared by the Applications page and the
// chats-tab "+" → join-IRC flow (home_page). Guards the classification the two
// entry points use to decide "success" vs "added-but-not-connected" vs
// "failed" — a home-page regression here previously slipped through because
// only the Applications-page path was covered.
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/irc_app_manager.dart';

void main() {
  group('classifyIrcAddChannelResult', () {
    test('added + connected + groupId → addedConnected', () {
      expect(
        classifyIrcAddChannelResult(
          const IrcAddChannelResult(
            added: true,
            connected: true,
            groupId: 'g1',
          ),
        ),
        IrcAddChannelUiOutcome.addedConnected,
      );
    });

    test('added + NOT connected → addedNotConnected (honest, not success)', () {
      expect(
        classifyIrcAddChannelResult(
          const IrcAddChannelResult(
            added: true,
            connected: false,
            groupId: 'g1',
          ),
        ),
        IrcAddChannelUiOutcome.addedNotConnected,
      );
    });

    test('not added → failed', () {
      expect(
        classifyIrcAddChannelResult(
          const IrcAddChannelResult(added: false, connected: false),
        ),
        IrcAddChannelUiOutcome.failed,
      );
    });

    test('added but null groupId → failed (cannot open the group)', () {
      expect(
        classifyIrcAddChannelResult(
          const IrcAddChannelResult(added: true, connected: true),
        ),
        IrcAddChannelUiOutcome.failed,
      );
    });
  });
}
