import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/util/bootstrap_node_probe.dart';

/// `BootstrapNodeProbe.verdictFor` is the one place a probe window becomes a
/// verdict. The cases below pin the split that the macOS real-UI case
/// `settings_bootstrap_manual_add_node` caught live (2026-08-22): a
/// UDP-capable device probing an unresolvable host was told "this device is
/// running TCP-only".
void main() {
  group('BootstrapNodeProbe.verdictFor', () {
    test('any answer is reachable, whatever else happened', () {
      expect(
        BootstrapNodeProbe.verdictFor(
          answered: true,
          sendCount: 1,
          sendErrors: {DhtSendNodesRequestError.fail},
        ),
        BootstrapProbeVerdict.reachable,
      );
    });

    test('requests left and nothing answered is unreachable', () {
      expect(
        BootstrapNodeProbe.verdictFor(
          answered: false,
          sendCount: 3,
          sendErrors: const {},
        ),
        BootstrapProbeVerdict.unreachable,
      );
    });

    test('an unresolvable host is the node\'s problem, not this device\'s', () {
      expect(
        BootstrapNodeProbe.verdictFor(
          answered: false,
          sendCount: 0,
          sendErrors: {DhtSendNodesRequestError.badIp},
        ),
        BootstrapProbeVerdict.unreachable,
      );
      expect(
        BootstrapNodeProbe.verdictFor(
          answered: false,
          sendCount: 0,
          sendErrors: {
            DhtSendNodesRequestError.badIp,
            DhtSendNodesRequestError.badPort,
          },
        ),
        BootstrapProbeVerdict.unreachable,
      );
    });

    test('UDP disabled on this device stays the local constraint', () {
      expect(
        BootstrapNodeProbe.verdictFor(
          answered: false,
          sendCount: 0,
          sendErrors: {DhtSendNodesRequestError.udpDisabled},
        ),
        BootstrapProbeVerdict.udpUnavailable,
      );
    });

    test('a local failure mixed with a descriptor refusal is not held against '
        'the node', () {
      expect(
        BootstrapNodeProbe.verdictFor(
          answered: false,
          sendCount: 0,
          sendErrors: {
            DhtSendNodesRequestError.badIp,
            DhtSendNodesRequestError.fail,
          },
        ),
        BootstrapProbeVerdict.udpUnavailable,
      );
    });

    test('no sends and no recorded reason is the local constraint', () {
      // Only reachable when every send threw before toxcore answered; nothing
      // was asked of the node, so it must not be blamed.
      expect(
        BootstrapNodeProbe.verdictFor(
          answered: false,
          sendCount: 0,
          sendErrors: const {},
        ),
        BootstrapProbeVerdict.udpUnavailable,
      );
    });
  });

  group('DhtSendNodesRequestError.fromNative', () {
    test('decodes the tim2tox_ffi_dht_send_nodes_request contract', () {
      expect(DhtSendNodesRequestError.fromNative(1), isNull);
      expect(
        DhtSendNodesRequestError.fromNative(0),
        DhtSendNodesRequestError.notReady,
      );
      expect(
        DhtSendNodesRequestError.fromNative(-1),
        DhtSendNodesRequestError.udpDisabled,
      );
      expect(
        DhtSendNodesRequestError.fromNative(-2),
        DhtSendNodesRequestError.nullArgument,
      );
      expect(
        DhtSendNodesRequestError.fromNative(-3),
        DhtSendNodesRequestError.badPort,
      );
      expect(
        DhtSendNodesRequestError.fromNative(-4),
        DhtSendNodesRequestError.badIp,
      );
      expect(
        DhtSendNodesRequestError.fromNative(-5),
        DhtSendNodesRequestError.fail,
      );
      expect(
        DhtSendNodesRequestError.fromNative(-99),
        DhtSendNodesRequestError.fail,
      );
    });
  });
}
