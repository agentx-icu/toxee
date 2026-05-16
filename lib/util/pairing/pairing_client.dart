import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../logger.dart';
import 'pairing_crypto.dart';
import 'pairing_url.dart';
import 'pairing_wire.dart';

/// One-shot pairing client (Device B — the device receiving the account).
///
/// Lifecycle mirrors [PairingHost]:
///   - construct → [connect] with the scanned pairing URL
///   - emits [ClientAwaitingSas] once the X25519 ECDH completes
///   - user taps "the codes match" → [confirmSas]
///   - decrypts the AEAD blob, writes plaintext to a callback-provided sink
///   - emits [ClientCompleted(toxId)] or [ClientFailed]
class PairingClient {
  PairingClient({
    required Future<String> Function(Uint8List profilePlaintext)
        materializeProfile,
    Duration connectTimeout = const Duration(seconds: 8),
    Duration transferTimeout = const Duration(seconds: 60),
  })  : _materializeProfile = materializeProfile,
        _connectTimeout = connectTimeout,
        _transferTimeout = transferTimeout;

  /// Materialize the freshly decrypted profile and return its resulting
  /// toxId. The plan calls for writing to a temp file then calling
  /// `AccountExportService.importAccountData(filePath)`; abstracting the
  /// sink here keeps PairingClient testable without disk I/O.
  final Future<String> Function(Uint8List profilePlaintext) _materializeProfile;

  /// Per CEO plan: "Device B detects connection failure within 8s and shows
  /// a clear error". Spec literal — do not change without spec change.
  final Duration _connectTimeout;
  final Duration _transferTimeout;

  Socket? _sock;
  SimpleKeyPair? _ephemeral;
  final _events = StreamController<ClientEvent>.broadcast();
  final _sasConfirmed = Completer<void>();
  bool _completed = false;

  Stream<ClientEvent> get events => _events.stream;

  /// Begin a pairing attempt. [pairingUrl] is the raw text decoded from the
  /// QR or pasted by the user (desktop fallback). All validation errors
  /// (malformed URL, unsupported version, public IP) are emitted as
  /// [ClientFailed] events with a [ClientFailureReason] tagging the cause —
  /// the caller doesn't need a try/catch around [connect].
  Future<void> connect(String pairingUrl) async {
    if (_sock != null) {
      throw StateError('PairingClient.connect() called twice');
    }

    final PairingInvite invite;
    try {
      final parsed = PairingUrl.decode(pairingUrl);
      if (parsed == null) {
        _fail(ClientFailureReason.invalidUrl,
            'Not a recognizable pairing QR code');
        return;
      }
      invite = parsed;
    } on FormatException catch (e) {
      _fail(ClientFailureReason.invalidUrl, e.message);
      return;
    }

    Socket? sock;
    try {
      sock = await Socket.connect(invite.ipAddress, invite.port,
          timeout: _connectTimeout);
    } on SocketException catch (e) {
      _fail(ClientFailureReason.lanUnreachable, _formatLanError(e));
      return;
    } on TimeoutException {
      _fail(ClientFailureReason.lanUnreachable,
          'Connection to ${invite.ipAddress}:${invite.port} timed out');
      return;
    }
    _sock = sock;

    _ephemeral = await PairingCrypto.generateEphemeral();
    final ourPub = Uint8List.fromList(await _extractPublicKey(_ephemeral!));

    final reader = PairingFrameReader();
    final dataSub = sock.listen(
      reader.feed,
      onError: (Object e, StackTrace st) {
        _fail(ClientFailureReason.networkError, 'socket error: $e');
      },
      onDone: reader.close,
    );

    try {
      // 1. Send our pubkey.
      sock.add(PairingFrame.encode(ourPub));
      await sock.flush();

      // 2. ECDH (host's pubkey is already in the QR). Derive keys.
      final shared = await PairingCrypto.deriveSharedSecret(
        ourKeyPair: _ephemeral!,
        theirPublicKey: invite.publicKey,
      );
      final keys = await PairingCrypto.deriveSessionKeys(
        sharedSecret: shared,
        nonce: invite.nonce,
        ourPublicKey: ourPub,
        theirPublicKey: invite.publicKey,
      );
      _events.add(ClientAwaitingSas(keys.sas));

      // 3. Wait for the user to confirm SAS.
      await _sasConfirmed.future;
      if (_completed) return;

      // 4. Read the AEAD blob and decrypt.
      final cipher = await reader.frames.first.timeout(_transferTimeout,
          onTimeout: () => throw TimeoutException(
              'No ciphertext from host within ${_transferTimeout.inSeconds}s'));
      Uint8List plain;
      try {
        plain = await PairingCrypto.aeadDecrypt(
          transitKey: keys.transitKey,
          blob: cipher,
        );
      } catch (e) {
        // AEAD failure means either the wrong key (active MITM somehow
        // bypassed SAS comparison) or a tampered blob. Either way: abort,
        // write nothing.
        _fail(ClientFailureReason.decryptionFailed,
            'Failed to decrypt the received profile: $e');
        return;
      }

      // 5. Hand the plaintext to the caller's materializer. They write to
      // disk + call importAccountData; we just need the resulting toxId for
      // the UI completion event.
      final toxId = await _materializeProfile(plain);
      try {
        await sock.close();
      } catch (_) {}
      _succeed(toxId);
    } on TimeoutException catch (e) {
      _fail(ClientFailureReason.timeout, '$e');
    } catch (e, st) {
      AppLogger.logError('[PairingClient] handshake error', e, st);
      _fail(ClientFailureReason.protocolError, '$e');
    } finally {
      await dataSub.cancel();
      await reader.close();
    }
  }

  /// User has visually compared SAS digits and tapped "the codes match".
  void confirmSas() {
    if (_sasConfirmed.isCompleted) return;
    _sasConfirmed.complete();
  }

  /// Abort cleanly. Idempotent.
  Future<void> cancel({String reason = 'cancelled by user'}) async {
    if (_completed) return;
    _completed = true;
    try {
      _sock?.destroy();
    } catch (_) {}
    _events.add(ClientFailed(ClientFailureReason.cancelled, reason));
    await _events.close();
  }

  void _succeed(String toxId) {
    if (_completed) return;
    _completed = true;
    _events.add(ClientCompleted(toxId));
    _events.close();
  }

  void _fail(ClientFailureReason reason, String message) {
    if (_completed) return;
    _completed = true;
    try {
      _sock?.destroy();
    } catch (_) {}
    _events.add(ClientFailed(reason, message));
    _events.close();
  }

  static String _formatLanError(SocketException e) {
    // The CEO plan literal: "Devices can't see each other on this network.
    // Try a personal hotspot, or use Export → Import via file instead."
    return "Devices can't see each other on this network. Try a personal "
        'hotspot, or use Export → Import via file instead. '
        '(${e.osError?.message ?? e.message})';
  }

  static Future<List<int>> _extractPublicKey(SimpleKeyPair kp) async {
    final pub = await kp.extractPublicKey();
    return pub.bytes;
  }
}

sealed class ClientEvent {
  const ClientEvent();
}

class ClientAwaitingSas extends ClientEvent {
  const ClientAwaitingSas(this.sas);
  final String sas;
}

class ClientCompleted extends ClientEvent {
  const ClientCompleted(this.toxId);
  final String toxId;
}

class ClientFailed extends ClientEvent {
  const ClientFailed(this.reason, this.message);
  final ClientFailureReason reason;
  final String message;
}

enum ClientFailureReason {
  invalidUrl,
  cancelled,
  timeout,
  lanUnreachable,
  networkError,
  decryptionFailed,
  protocolError,
}
