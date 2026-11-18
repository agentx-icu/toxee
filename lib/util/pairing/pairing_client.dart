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
  }) : _materializeProfile = materializeProfile,
       _connectTimeout = connectTimeout,
       _transferTimeout = transferTimeout;

  /// Materialize the decrypted profile and return its Tox ID. The bytes are
  /// borrowed until the returned future settles and are then wiped.
  final Future<String> Function(Uint8List profilePlaintext) _materializeProfile;

  /// Per CEO plan: "Device B detects connection failure within 8s and shows
  /// a clear error". Spec literal — do not change without spec change.
  final Duration _connectTimeout;
  final Duration _transferTimeout;

  Socket? _sock;
  SimpleKeyPair? _ephemeral;
  final _events = StreamController<ClientEvent>.broadcast();
  final _sasConfirmed = Completer<void>();
  bool _started = false;
  bool _completed = false;

  Stream<ClientEvent> get events => _events.stream;

  /// Begin a pairing attempt. [pairingUrl] is the raw text decoded from the
  /// QR or pasted by the user (desktop fallback). All validation errors
  /// (malformed URL, unsupported version, public IP) are emitted as
  /// [ClientFailed] events with a [ClientFailureReason] tagging the cause —
  /// the caller doesn't need a try/catch around [connect].
  Future<void> connect(String pairingUrl) async {
    if (_started) {
      throw StateError('PairingClient.connect() called twice');
    }
    if (_completed) return;
    _started = true;

    final PairingInvite invite;
    try {
      final parsed = PairingUrl.decode(pairingUrl);
      if (parsed == null) {
        _fail(
          ClientFailureReason.invalidUrl,
          'Not a recognizable pairing QR code',
        );
        return;
      }
      invite = parsed;
    } on PairingUrlException catch (e) {
      // The UI localizes by reason; the English message is diagnostics only.
      AppLogger.info('[PairingClient] rejected invite: ${e.message}');
      _fail(switch (e.problem) {
        PairingUrlProblem.unsupportedVersion =>
          ClientFailureReason.unsupportedVersion,
        PairingUrlProblem.nonLanAddress => ClientFailureReason.nonLanAddress,
        PairingUrlProblem.malformed => ClientFailureReason.invalidUrl,
      }, e.detail ?? e.message);
      return;
    } on FormatException catch (e) {
      // Belt and braces: decode keeps its rejections structured, but any
      // other FormatException must still end as a localized failure, never
      // escape connect() with English text.
      AppLogger.info('[PairingClient] rejected invite: ${e.message}');
      _fail(ClientFailureReason.invalidUrl, e.message);
      return;
    }

    Socket? sock;
    try {
      sock = await Socket.connect(
        invite.ipAddress,
        invite.port,
        timeout: _connectTimeout,
      );
    } on SocketException catch (e) {
      _fail(ClientFailureReason.lanUnreachable, _formatLanError(e));
      return;
    } on TimeoutException {
      // Endpoint only; the localized connectTimeout sentence wraps it.
      _fail(
        ClientFailureReason.connectTimeout,
        '${invite.ipAddress}:${invite.port}',
      );
      return;
    }
    if (_completed) {
      sock.destroy();
      return;
    }
    _sock = sock;

    _ephemeral = await PairingCrypto.generateEphemeral();
    final ourPub = Uint8List.fromList(await _extractPublicKey(_ephemeral!));
    if (_completed) return;

    final reader = PairingFrameReader();
    var receivedProfile = false;
    // Observe the socket while waiting for local consent. Keep a complete
    // frame if the host confirms first and closes its end of the socket.
    final pendingCiphertext = reader.frames.first.then<Uint8List?>(
      (bytes) {
        receivedProfile = true;
        return bytes;
      },
      onError: (Object error) {
        if (error is StateError) {
          _fail(
            ClientFailureReason.networkError,
            'The sending device disconnected before the transfer',
          );
        } else {
          _fail(ClientFailureReason.protocolError, '$error');
        }
        return null;
      },
    );
    final dataSub = sock.listen(
      reader.feed,
      onError: (Object e, StackTrace st) {
        if (!receivedProfile) {
          _fail(ClientFailureReason.networkError, 'socket error: $e');
        }
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
      if (_completed) return;
      _events.add(ClientAwaitingSas(keys.sas));

      // 3. Wait for the user to confirm SAS.
      await _sasConfirmed.future;
      if (_completed) return;

      // 4. Read the AEAD blob and decrypt.
      final cipher = await pendingCiphertext.timeout(
        _transferTimeout,
        onTimeout: () => throw TimeoutException(
          'No ciphertext from host within ${_transferTimeout.inSeconds}s',
        ),
      );
      if (cipher == null || _completed) return;
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
        _fail(
          ClientFailureReason.decryptionFailed,
          'Failed to decrypt the received profile: $e',
        );
        return;
      }

      final String toxId;
      try {
        if (_completed) return;
        toxId = await _materializeProfile(plain);
      } finally {
        plain.fillRange(0, plain.length, 0);
      }
      try {
        await sock.close();
      } catch (e) {
        AppLogger.warn('[PairingClient] socket close after success failed: $e');
      }
      _succeed(toxId);
    } on PairingImportCancelled {
      _fail(ClientFailureReason.cancelled, 'Account import cancelled');
    } on TimeoutException catch (e) {
      _fail(ClientFailureReason.timeout, '$e');
    } catch (e, st) {
      if (_completed) return;
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
    _fail(ClientFailureReason.cancelled, reason);
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
    confirmSas();
    try {
      _sock?.destroy();
    } catch (e) {
      AppLogger.warn(
        '[PairingClient] socket destroy during failure handling failed: $e',
      );
    }
    _events.add(ClientFailed(reason, message));
    _events.close();
  }

  /// The OS-level detail only. The actionable sentence around it ("Devices
  /// can't see each other on this network…") is UI copy, localized where
  /// [ClientFailureReason.lanUnreachable] is rendered.
  static String _formatLanError(SocketException e) =>
      e.osError?.message ?? e.message;

  static Future<List<int>> _extractPublicKey(SimpleKeyPair kp) async {
    final pub = await kp.extractPublicKey();
    return pub.bytes;
  }
}

class PairingImportCancelled implements Exception {
  const PairingImportCancelled();
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
  /// Not a pairing code, or a damaged one (message = diagnostic text only).
  invalidUrl,

  /// The invite speaks another protocol version (message = that version).
  unsupportedVersion,

  /// The invite points outside the LAN (message = the advertised IP).
  nonLanAddress,
  cancelled,
  timeout,
  lanUnreachable,

  /// The TCP connect to the host's advertised endpoint did not complete in
  /// time (message = `ip:port`) — distinct from [lanUnreachable], where the OS
  /// refused/failed the connect outright.
  connectTimeout,
  networkError,
  decryptionFailed,
  protocolError,
}
