import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../logger.dart';
import 'pairing_crypto.dart';
import 'pairing_url.dart';
import 'pairing_wire.dart';

/// One-shot pairing host (Device A — the device that already has the account).
///
/// Lifecycle:
///   - construct → [start] (returns the QR URL)
///   - emits [HostAwaitingSas] once Device B connects and SAS is derived
///   - user taps "the codes match" → [confirmSas]
///   - emits [HostCompleted] (success) or [HostFailed] (any error)
///
/// The host accepts exactly **one** TCP connection per [start] call and then
/// shuts down — the ephemeral keypair is single-use by construction (per CEO
/// plan: "Fresh ephemeral per QR display; refuses connections from older
/// keys"). To pair again, construct a fresh [PairingHost] (and a fresh QR).
///
/// AEAD wraps the `.tox` blob **unconditionally** regardless of whether the
/// account password is set. The account password is an inner layer only; the
/// transit-security guarantee comes from the X25519+AEAD layer. This is the
/// regression target of `pairing_security_regression_test.dart`.
class PairingHost {
  PairingHost({
    required Future<Uint8List> Function() loadProfileBlob,
    required String bindAddress,
    int port = 0,
    Duration acceptTimeout = const Duration(minutes: 2),
  })  : _loadProfileBlob = loadProfileBlob,
        _bindAddress = bindAddress,
        _requestedPort = port,
        _acceptTimeout = acceptTimeout;

  /// Loader for the `.tox` profile bytes. Injected (not a hard dep on
  /// `AccountExportService`) so unit tests can drive deterministic payloads
  /// without spinning up real Tox state.
  final Future<Uint8List> Function() _loadProfileBlob;

  /// Address to bind the listener on. Typically `0.0.0.0` so any LAN client
  /// can reach us; tests can pass `127.0.0.1` for loopback isolation.
  final String _bindAddress;

  /// Requested TCP port. 0 means "let the OS pick" which is what we want
  /// every time outside tests so we never collide with another listener.
  final int _requestedPort;

  /// If no client connects within this window, [start] auto-cancels. The
  /// user can always restart the flow; this is just a safety valve so an
  /// abandoned QR doesn't keep a listener open forever.
  final Duration _acceptTimeout;

  ServerSocket? _server;
  SimpleKeyPair? _ephemeral;
  Socket? _peer;
  final _events = StreamController<HostEvent>.broadcast();
  final _sasConfirmed = Completer<void>();
  bool _completed = false;
  Timer? _acceptTimer;

  Stream<HostEvent> get events => _events.stream;

  /// Start listening and return the pairing URL ready to render as a QR.
  ///
  /// The URL embeds the LAN address chosen by [advertiseAddress]. If the
  /// caller didn't supply one, the host listens on [_bindAddress] verbatim
  /// — but the QR will then advertise that same address, which is
  /// 0.0.0.0-meaningless to a client. Production callers MUST resolve and
  /// pass an actual LAN IP. The integration tests pass `127.0.0.1` for both
  /// bind and advertise so the loopback round-trip works cleanly.
  Future<String> start({required String advertiseAddress}) async {
    if (_server != null) {
      throw StateError('PairingHost.start() called twice');
    }
    _ephemeral = await PairingCrypto.generateEphemeral();
    final pubKey =
        Uint8List.fromList(await _extractPublicKey(_ephemeral!));
    final nonce = PairingCrypto.generateNonce();

    final server = await ServerSocket.bind(_bindAddress, _requestedPort);
    _server = server;
    final boundPort = server.port;

    final invite = PairingInvite(
      publicKey: pubKey,
      ipAddress: advertiseAddress,
      port: boundPort,
      nonce: nonce,
    );
    final url = PairingUrl.encode(invite);
    AppLogger.log(
        '[PairingHost] listening on $_bindAddress:$boundPort, advertising '
        '$advertiseAddress:$boundPort');

    // Listen for exactly one connection. Future is fire-and-forget; we wire
    // its completion through the _events stream that the caller listens to.
    unawaited(server.first.then(
      (sock) => _handlePeer(sock, nonce, pubKey),
      onError: (Object e, StackTrace st) {
        _fail(HostFailureReason.networkError, '$e');
      },
    ));

    _acceptTimer = Timer(_acceptTimeout, () {
      if (_peer == null && !_completed) {
        _fail(HostFailureReason.timeout,
            'No device connected within ${_acceptTimeout.inSeconds}s');
      }
    });

    _events.add(HostQrReady(url, nonce: nonce, publicKey: pubKey));
    return url;
  }

  /// User has visually compared SAS digits and tapped "the codes match" on
  /// both devices. This unblocks the host's ciphertext send.
  void confirmSas() {
    if (_sasConfirmed.isCompleted) return;
    _sasConfirmed.complete();
  }

  /// Abort cleanly. Idempotent.
  Future<void> cancel({String reason = 'cancelled by user'}) async {
    if (_completed) return;
    _completed = true;
    _acceptTimer?.cancel();
    try {
      await _peer?.close();
    } catch (_) {}
    try {
      await _server?.close();
    } catch (_) {}
    _events.add(HostFailed(HostFailureReason.cancelled, reason));
    await _events.close();
  }

  Future<void> _handlePeer(
      Socket sock, Uint8List nonce, Uint8List ourPub) async {
    if (_completed) {
      // Race: cancelled while we were waiting for `first`. Drop the socket.
      try {
        await sock.close();
      } catch (_) {}
      return;
    }
    _peer = sock;
    _acceptTimer?.cancel();
    AppLogger.log(
        '[PairingHost] peer connected from ${sock.remoteAddress.address}:${sock.remotePort}');

    final reader = PairingFrameReader();
    final dataSub = sock.listen(
      reader.feed,
      onError: (Object e, StackTrace st) {
        _fail(HostFailureReason.networkError, 'socket error: $e');
      },
      onDone: reader.close,
    );

    try {
      // 1. Receive Device B's pubkey.
      final peerPub = await reader.frames.first.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
            'No handshake from peer within 15s'),
      );
      if (peerPub.length != PairingCrypto.publicKeyLength) {
        throw FormatException(
            'Peer public key has wrong length: ${peerPub.length}');
      }

      // 2. ECDH + derive (transit_key, sas).
      final shared = await PairingCrypto.deriveSharedSecret(
        ourKeyPair: _ephemeral!,
        theirPublicKey: peerPub,
      );
      final keys = await PairingCrypto.deriveSessionKeys(
        sharedSecret: shared,
        nonce: nonce,
        ourPublicKey: ourPub,
        theirPublicKey: peerPub,
      );
      _events.add(HostAwaitingSas(keys.sas));

      // 3. Wait for the user to tap "the codes match". The peer is similarly
      // waiting on the user. If the user cancels, [cancel] short-circuits.
      await _sasConfirmed.future;
      if (_completed) return; // cancelled while waiting

      // 4. Load + AEAD-encrypt the .tox blob. AEAD unconditional — see class
      // docstring.
      final plain = await _loadProfileBlob();
      final cipher = await PairingCrypto.aeadEncrypt(
        transitKey: keys.transitKey,
        plaintext: plain,
      );
      sock.add(PairingFrame.encode(cipher));
      await sock.flush();
      AppLogger.log(
          '[PairingHost] sent AEAD blob: ${cipher.length} bytes (plain=${plain.length})');

      // 5. Half-close + done.
      await sock.close();
      _succeed();
    } on TimeoutException catch (e) {
      _fail(HostFailureReason.timeout, '$e');
    } catch (e, st) {
      AppLogger.logError('[PairingHost] handshake error', e, st);
      _fail(HostFailureReason.protocolError, '$e');
    } finally {
      await dataSub.cancel();
      await reader.close();
    }
  }

  void _succeed() {
    if (_completed) return;
    _completed = true;
    _acceptTimer?.cancel();
    try {
      unawaited(_server?.close());
    } catch (_) {}
    _events.add(const HostCompleted());
    unawaited(_events.close());
  }

  void _fail(HostFailureReason reason, String message) {
    if (_completed) return;
    _completed = true;
    _acceptTimer?.cancel();
    try {
      _peer?.destroy();
    } catch (_) {}
    try {
      unawaited(_server?.close());
    } catch (_) {}
    _events.add(HostFailed(reason, message));
    unawaited(_events.close());
  }

  static Future<List<int>> _extractPublicKey(SimpleKeyPair kp) async {
    final pub = await kp.extractPublicKey();
    return pub.bytes;
  }
}

/// Host-side state-machine events. Listeners should treat the first
/// [HostCompleted] or [HostFailed] as terminal and stop reacting after that.
sealed class HostEvent {
  const HostEvent();
}

class HostQrReady extends HostEvent {
  const HostQrReady(this.url, {required this.nonce, required this.publicKey});
  final String url;
  final Uint8List nonce;
  final Uint8List publicKey;
}

class HostAwaitingSas extends HostEvent {
  const HostAwaitingSas(this.sas);
  final String sas;
}

class HostCompleted extends HostEvent {
  const HostCompleted();
}

class HostFailed extends HostEvent {
  const HostFailed(this.reason, this.message);
  final HostFailureReason reason;
  final String message;
}

enum HostFailureReason {
  cancelled,
  timeout,
  networkError,
  protocolError,
}
