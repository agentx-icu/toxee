import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/util/pairing/pairing_client.dart';
import 'package:toxee/util/pairing/pairing_host.dart';

void main() {
  group('Pairing handshake (loopback integration)', () {
    test('successful end-to-end transfer', () async {
      // Fake .tox blob — what matters is that the receiving side ends up with
      // the same bytes. The real AccountExportService is not in the loop here
      // (that's by design; this test is about the pairing transport).
      final fakeProfile =
          Uint8List.fromList(List<int>.generate(4096, (i) => (i * 13) & 0xff));
      const expectedToxId = 'TEST_TOXID_FROM_HANDSHAKE';

      final host = PairingHost(
        loadProfileBlob: () async => fakeProfile,
        bindAddress: '127.0.0.1',
      );

      Uint8List? received;
      final client = PairingClient(
        materializeProfile: (plaintext) async {
          received = plaintext;
          return expectedToxId;
        },
      );

      final hostEvents = <HostEvent>[];
      final clientEvents = <ClientEvent>[];
      final hostDone = Completer<void>();
      final clientDone = Completer<void>();

      host.events.listen((e) {
        hostEvents.add(e);
        if (e is HostCompleted || e is HostFailed) {
          if (!hostDone.isCompleted) hostDone.complete();
        }
      });
      client.events.listen((e) {
        clientEvents.add(e);
        if (e is ClientCompleted || e is ClientFailed) {
          if (!clientDone.isCompleted) clientDone.complete();
        }
      });

      final url = await host.start(advertiseAddress: '127.0.0.1');
      final connectFut = client.connect(url);

      // Wait until both sides emit awaitingSas, then "user taps match" on
      // both. This mirrors the real UX exactly.
      String? hostSas;
      String? clientSas;
      while (hostSas == null || clientSas == null) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        for (final e in hostEvents) {
          if (e is HostAwaitingSas) hostSas = e.sas;
        }
        for (final e in clientEvents) {
          if (e is ClientAwaitingSas) clientSas = e.sas;
        }
      }
      expect(hostSas, equals(clientSas),
          reason: 'SAS must match on both sides — that is the user-visible '
              'authentication check.');

      host.confirmSas();
      client.confirmSas();

      await connectFut;
      await hostDone.future.timeout(const Duration(seconds: 10));
      await clientDone.future.timeout(const Duration(seconds: 10));

      expect(hostEvents.last, isA<HostCompleted>());
      expect(clientEvents.last, isA<ClientCompleted>());
      expect((clientEvents.last as ClientCompleted).toxId, expectedToxId);
      expect(received, isNotNull);
      expect(received, equals(fakeProfile),
          reason: 'Receiver must see the same plaintext the host sent.');
    });

    test('SAS-mismatch aborts cleanly (no plaintext written)', () async {
      // We simulate the "user said codes don't match" outcome by simply
      // cancelling on Device B. The host should never send ciphertext, the
      // client materializer should never be invoked, and both sides should
      // report failure.
      final fakeProfile = Uint8List(2048);
      bool materializerCalled = false;

      final host = PairingHost(
        loadProfileBlob: () async => fakeProfile,
        bindAddress: '127.0.0.1',
      );
      final client = PairingClient(
        materializeProfile: (_) async {
          materializerCalled = true;
          return 'should-not-happen';
        },
      );

      final hostEvents = <HostEvent>[];
      final clientEvents = <ClientEvent>[];
      final hostDone = Completer<void>();
      final clientDone = Completer<void>();
      host.events.listen((e) {
        hostEvents.add(e);
        if (e is HostCompleted || e is HostFailed) {
          if (!hostDone.isCompleted) hostDone.complete();
        }
      });
      client.events.listen((e) {
        clientEvents.add(e);
        if (e is ClientCompleted || e is ClientFailed) {
          if (!clientDone.isCompleted) clientDone.complete();
        }
      });

      final url = await host.start(advertiseAddress: '127.0.0.1');
      unawaited(client.connect(url));

      // Wait for both sides to reach awaitingSas.
      while (!clientEvents.any((e) => e is ClientAwaitingSas) ||
          !hostEvents.any((e) => e is HostAwaitingSas)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      // "User says: nope, codes don't match."
      await client.cancel(reason: 'SAS mismatch (simulated)');
      await host.cancel(reason: 'SAS mismatch (simulated)');

      await hostDone.future.timeout(const Duration(seconds: 5));
      await clientDone.future.timeout(const Duration(seconds: 5));

      expect(materializerCalled, isFalse,
          reason: 'No plaintext should be materialized when SAS mismatch '
              'aborts the session.');
      expect(hostEvents.whereType<HostCompleted>(), isEmpty);
      expect(clientEvents.whereType<ClientCompleted>(), isEmpty);
    });

    test('invalid pairing URL fails fast with ClientFailureReason.invalidUrl',
        () async {
      final client = PairingClient(
        materializeProfile: (_) async => 'unreachable',
      );
      final events = <ClientEvent>[];
      final done = Completer<void>();
      client.events.listen((e) {
        events.add(e);
        if (e is ClientCompleted || e is ClientFailed) {
          if (!done.isCompleted) done.complete();
        }
      });

      await client.connect('not a pairing url');
      await done.future.timeout(const Duration(seconds: 5));

      expect(events.last, isA<ClientFailed>());
      expect((events.last as ClientFailed).reason,
          ClientFailureReason.invalidUrl);
    });
  });
}
