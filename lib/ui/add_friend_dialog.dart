import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../util/ffi_chat_service_account_key.dart';
import '../../i18n/app_localizations.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';
import '../../util/responsive_layout.dart';
import '../../util/tox_utils.dart';
import 'widgets/app_dialog.dart';
import 'testing/ui_keys.dart';

// TOX_MAX_FRIEND_REQUEST_LENGTH — used for both inline counter and validation.
const int _kMaxFriendRequestLength = 921;

// Per-form-factor dialog widths. The wider tablet/desktop caps let the long
// Tox ID and the multi-line request message breathe instead of wrapping into
// a tall, narrow column.
const double _kMobileMaxDialogWidth = 480;
const double _kTabletMaxDialogWidth = 640;
const double _kDesktopMaxDialogWidth = 720;

double _dialogMaxWidth(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  if (ResponsiveLayout.isDesktop(context)) {
    return (w - 64).clamp(280.0, _kDesktopMaxDialogWidth);
  }
  if (ResponsiveLayout.isTabletLandscape(context)) {
    return (w - 48).clamp(280.0, _kDesktopMaxDialogWidth);
  }
  if (ResponsiveLayout.isTablet(context)) {
    return (w - 48).clamp(280.0, _kTabletMaxDialogWidth);
  }
  return (w - 32).clamp(280.0, _kMobileMaxDialogWidth);
}

class AddFriendDialog extends StatefulWidget {
  const AddFriendDialog({
    super.key,
    required this.service,
    this.onFriendAdded,
    this.onShowSnackBar,
  });

  final FfiChatService service;
  final Future<void> Function(String friendId)? onFriendAdded;
  final void Function(String message)? onShowSnackBar;

  @override
  State<AddFriendDialog> createState() => _AddFriendDialogState();
}

class _AddFriendDialogState extends State<AddFriendDialog> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  late final TextEditingController _messageController;
  final FocusNode _submitFocusNode = FocusNode();
  bool _isSubmitting = false;
  bool _isConnected = true;
  StreamSubscription<bool>? _connSub;
  // Friend IDs we have already sent a request to in this dialog session.
  // Tox itself rejects duplicate adds (TOX_ERR_FRIEND_ADD_ALREADY_SENT) but
  // surfaces the error generically; tracking locally lets us give a
  // clearer message before the FFI roundtrip.
  final Set<String> _attemptedThisSession = <String>{};

  bool get _canSubmit {
    if (_isSubmitting) return false;
    return _idController.text.trim().isNotEmpty &&
        _messageController.text.trim().isNotEmpty;
  }

  void _rebuildOnControllerChange() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    // Default request message is locale-dependent, so initialize empty here
    // and fill in didChangeDependencies once we have a BuildContext.
    _messageController = TextEditingController();
    // Submit button's `onPressed` is gated by `_canSubmit`, which reads from
    // both controllers. TextField only rebuilds its own subtree on keystroke,
    // so without these listeners the parent's `build()` never re-runs and the
    // button stays disabled even after the user types a valid Tox ID.
    _idController.addListener(_rebuildOnControllerChange);
    _messageController.addListener(_rebuildOnControllerChange);
    _isConnected = widget.service.isConnected;
    _connSub = widget.service.connectionStatusStream.listen((connected) {
      if (!mounted) return;
      setState(() => _isConnected = connected);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messageController.text.isEmpty) {
      _messageController.text = AppLocalizations.of(
        context,
      )!.defaultFriendRequestMessage;
    }
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _submitFocusNode.dispose();
    _idController.removeListener(_rebuildOnControllerChange);
    _messageController.removeListener(_rebuildOnControllerChange);
    _idController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_formKey.currentState!.validate()) return;
    final rawId = _idController.text.trim();
    final message = _messageController.text.trim();

    if (message.isEmpty) {
      _notify(
        _localeText(
          context,
          'enterMessage',
          fallback: 'Please enter a message',
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final defaultMessage = AppLocalizations.of(
      context,
    )!.defaultFriendRequestMessage;
    final successText = _localeText(
      context,
      'requestSent',
      fallback: 'Friend request sent',
    );
    final queuedText = _localeText(
      context,
      'requestQueued',
      fallback: 'Offline — request queued and will be sent when you reconnect',
    );
    final failurePrefix = _localeText(
      context,
      'requestFailed',
      fallback: 'Failed',
    );

    // A1: client-side self-add check. C++ also rejects (TOX_ERR_FRIEND_ADD_OWN_KEY)
    // but surfaces a generic error; reject earlier with a clear message.
    // Use `accountKey` (real Tox address) — `selfId` returns the V2TIM login
    // placeholder, which would never match a user-pasted 76-char Tox ID and
    // silently disabled the self-add guard.
    final selfId = widget.service.accountKey;
    if (selfId.isNotEmpty && compareToxIds(rawId, selfId)) {
      _notifyVia(
        messenger,
        _localeText(
          context,
          'cannotAddSelf',
          fallback: 'You cannot add yourself as a friend',
        ),
      );
      return;
    }

    // A2: dedup vs existing friends and against requests already sent during
    // this dialog session. Tox layer would reject anyway with
    // TOX_ERR_FRIEND_ADD_ALREADY_SENT, but the generic "addFriend failed"
    // surfaced before this change confused users.
    final normalizedRaw = normalizeToxId(rawId);
    // Capture localized strings before any await so we can use them past
    // the async gap without re-touching BuildContext.
    final alreadySentText = _localeText(
      context,
      'requestAlreadySent',
      fallback: 'A friend request was already sent in this session',
    );
    final alreadyFriendText = _localeText(
      context,
      'alreadyFriend',
      fallback: 'This user is already in your friend list',
    );
    if (_attemptedThisSession.contains(normalizedRaw)) {
      _notifyVia(messenger, alreadySentText);
      return;
    }

    // A3: the validator already enforces "exactly 76 hex chars", which is the
    // Tox protocol contract for AddFriend (pubkey + nospam + checksum).
    // Anything else is rejected before this point, so no special pre-flight
    // is needed here — the unified validator + async result callback
    // together cover all failure modes that used to be silent.

    // Flip _isSubmitting BEFORE the first await so a double-tap during the
    // friend-list read can't slip past the early-return guard on line 110
    // and race two concurrent addFriend() calls.
    setState(() => _isSubmitting = true);
    try {
      try {
        final friends = await widget.service.getFriendList();
        final alreadyFriend = friends.any(
          (f) => normalizeToxId(f.userId) == normalizedRaw,
        );
        if (alreadyFriend) {
          _notifyVia(messenger, alreadyFriendText);
          return;
        }
      } catch (_) {
        // If we can't read the friend list (rare), fall through and let the
        // FFI layer handle dedup. Don't block the user on a transient read.
      }

      // `addFriend()` resolves with an [AddFriendResult] that carries the
      // V2TIMFriendOperationResult.resultCode the C++ layer surfaces via the
      // `friendAddResult` callback. Non-zero codes (e.g. 6770 "Friend add
      // requires full Tox address") are real failures even though dispatch
      // succeeded — only `result.isSuccess` should pop the dialog. On
      // failure, keep the dialog mounted so the user can edit and retry.
      final result = await widget.service.addFriend(
        rawId,
        requestMessage: message,
      );
      if (!result.isSuccess) {
        await HapticFeedback.lightImpact();
        final detail = result.resultInfo.isNotEmpty
            ? result.resultInfo
            : 'result_code=${result.resultCode}';
        _notifyVia(messenger, '$failurePrefix: $detail');
        return;
      }
      _attemptedThisSession.add(normalizedRaw);
      await widget.onFriendAdded?.call(rawId);
      await HapticFeedback.lightImpact();
      // A5: differentiate "sent immediately" from "queued while offline".
      // Tox queues outgoing requests when our DHT connection is down and
      // sends them on reconnect, so the request isn't lost — but the user
      // should know it's not delivered yet.
      _notifyVia(messenger, _isConnected ? successText : queuedText);
      _idController.clear();
      _messageController.text = defaultMessage;
      if (mounted) {
        await navigator.maybePop();
      }
    } catch (e) {
      await HapticFeedback.lightImpact();
      _notifyVia(messenger, '$failurePrefix: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // Tox protocol: AddFriend requires the full 76-char Tox address
  // (32-byte pubkey + 4-byte nospam + 2-byte checksum, all hex-encoded).
  // A bare 64-char public key is rejected by the C++ layer with
  // ERR_INVALID_PARAMETERS (6770) and used to fail silently in the UI.
  // Enforcing exactly 76 here keeps the validator, submit handler, and hint
  // text in agreement so any invalid input is rejected with one clear
  // error before the async round-trip.
  static final RegExp _kToxAddressRegex = RegExp(r'^[0-9a-fA-F]{76}$');

  String? _validateToxId(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return _localeText(context, 'enterId', fallback: 'Please enter a Tox ID');
    }
    if (!_kToxAddressRegex.hasMatch(trimmed)) {
      return AppLocalizations.of(context)!.addFriendInvalidToxIdHint;
    }
    return null;
  }

  String? _validateMessage(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return _localeText(
        context,
        'enterMessage',
        fallback: 'Please enter a message',
      );
    }
    if (trimmed.length > _kMaxFriendRequestLength) {
      return AppLocalizations.of(context)!.friendRequestMessageTooLong;
    }
    return null;
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (!mounted) return;
    if (data?.text != null) {
      setState(() {
        _idController.text = data!.text!.trim();
      });
    }
  }

  // QR scan is only useful (and the mobile_scanner plugin only ships a
  // camera-backed implementation) on iOS/Android. Desktop users have the
  // Paste button and a full-size keyboard, so we don't surface this there.
  bool get _supportsCameraScan =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _scanQr() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => const _ScanToxIdPage(),
      ),
    );
    if (!mounted) return;
    if (scanned == null || scanned.isEmpty) return;
    // The QR card we generate on the profile page is a self-contained PNG
    // whose payload is exactly the Tox ID hex string — no URL prefix, no
    // JSON. Just trim and drop it in; the existing validator will reject
    // anything else.
    setState(() {
      _idController.text = scanned.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        // D1: Esc closes the dialog, Cmd/Ctrl+Enter submits. Plain Enter
        // would conflict with multi-line message field, so we require the
        // modifier when focus is in a text field.
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (_isSubmitting) return;
              Navigator.of(context).maybePop();
            },
            const SingleActivator(LogicalKeyboardKey.enter, meta: true): () {
              if (!_isSubmitting) _submit();
            },
            const SingleActivator(LogicalKeyboardKey.enter, control: true): () {
              if (!_isSubmitting) _submit();
            },
          },
          child: Focus(
            autofocus: true,
            child: AppDialog(
              title: _localeText(
                context,
                'addContact',
                fallback: 'Add Contact',
              ),
              maxWidth: _dialogMaxWidth(context),
              // SingleChildScrollView lets the form scroll when the keyboard
              // pushes content up on small screens — without it, the bottom
              // (counter, action row) would be clipped on iPhone SE-class
              // viewports. Adding viewInsets.bottom to the bottom padding keeps
              // Submit + counter reachable when the keyboard is up.
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _localeText(
                          context,
                          'addContactHint',
                          fallback:
                              'Enter the friend\'s 76-character hex Tox address.',
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (!_isConnected) ...[
                        AppSpacing.verticalMd,
                        _OfflineBanner(
                          message: _localeText(
                            context,
                            'offlineBanner',
                            fallback:
                                'Offline — your friend request will be queued and sent automatically when you reconnect.',
                          ),
                        ),
                      ],
                      AppSpacing.verticalLg,
                      TextFormField(
                        key: UiKeys.addFriendIdInput,
                        controller: _idController,
                        textAlignVertical: TextAlignVertical.center,
                        autofocus: true,
                        // Tox addresses are 76-char hex strings — iOS would
                        // otherwise try to autocorrect/capitalize them.
                        keyboardType: TextInputType.visiblePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        textCapitalization: TextCapitalization.none,
                        decoration: InputDecoration(
                          labelText: _localeText(
                            context,
                            'friendUserID',
                            fallback: 'Friend Tox ID',
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.input),
                          ),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_supportsCameraScan)
                                IconButton(
                                  icon: const Icon(
                                    Icons.qr_code_scanner_rounded,
                                  ),
                                  tooltip: _localeText(
                                    context,
                                    'scanQr',
                                    fallback: 'Scan QR',
                                  ),
                                  onPressed: _scanQr,
                                ),
                              IconButton(
                                key: UiKeys.addFriendPasteButton,
                                icon: const Icon(Icons.paste),
                                tooltip: _localeText(
                                  context,
                                  'paste',
                                  fallback: 'Paste',
                                ),
                                onPressed: _pasteFromClipboard,
                              ),
                            ],
                          ),
                        ),
                        validator: _validateToxId,
                        minLines: 1,
                        maxLines: 3,
                      ),
                      AppSpacing.verticalLg,
                      TextFormField(
                        key: UiKeys.addFriendMessageInput,
                        controller: _messageController,
                        textAlignVertical: TextAlignVertical.center,
                        // Free-form prose: keep autocorrect on, but
                        // sentence-case for normal English-style writing.
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          labelText: _localeText(
                            context,
                            'requestMessage',
                            fallback: 'Request Message',
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.input),
                          ),
                          helperText:
                              '${_messageController.text.length}/$_kMaxFriendRequestLength',
                        ),
                        validator: _validateMessage,
                        minLines: 1,
                        maxLines: 4,
                        onChanged: (value) {
                          setState(() {}); // refresh inline counter
                        },
                      ),
                      AppSpacing.verticalXl,
                      _buildActions(context, scheme),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActions(BuildContext context, ColorScheme scheme) {
    final cancelLabel = MaterialLocalizations.of(context).cancelButtonLabel;
    final submitLabel = _localeText(
      context,
      'addContact',
      fallback: 'Add Contact',
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          key: UiKeys.addFriendCancelButton,
          onPressed: _isSubmitting
              ? null
              : () => Navigator.of(context).maybePop(),
          child: Text(cancelLabel),
        ),
        AppSpacing.horizontalSm,
        Tooltip(
          message: _isSubmitting
              ? _localeText(context, 'sending', fallback: 'Sending...')
              : '',
          child: FilledButton.icon(
            key: UiKeys.addFriendSubmitButton,
            focusNode: _submitFocusNode,
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.button),
              ),
            ),
            icon: _isSubmitting
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        scheme.onPrimary,
                      ),
                    ),
                  )
                : const Icon(Icons.person_add_alt_1),
            label: Text(submitLabel),
            onPressed: _canSubmit ? _submit : null,
          ),
        ),
      ],
    );
  }

  String _localeText(
    BuildContext context,
    String key, {
    required String fallback,
  }) {
    final t = TencentCloudChatLocalizations.of(context);
    final appL10n = AppLocalizations.of(context)!;
    switch (key) {
      case 'addContact':
        return t?.addContact ?? fallback;
      case 'friendUserID':
        return t?.userID ?? fallback;
      case 'requestSent':
        return t?.requestSent ?? fallback;
      case 'requestFailed':
        return appL10n.addFailed;
      case 'enterId':
        return appL10n.enterId;
      case 'invalidLength':
        return appL10n.invalidLength;
      case 'invalidHex':
        return appL10n.invalidCharacters;
      case 'paste':
        return appL10n.paste;
      case 'addContactHint':
        return appL10n.addContactHint;
      case 'requestMessage':
        return appL10n.verificationMessage;
      case 'enterMessage':
        return appL10n.enterMessage;
      case 'sending':
        return fallback;
    }
    return fallback;
  }

  void _notify(String message) {
    _notifyVia(ScaffoldMessenger.maybeOf(context), message);
  }

  void _notifyVia(ScaffoldMessengerState? messenger, String message) {
    if (widget.onShowSnackBar != null) {
      widget.onShowSnackBar!(message);
    } else {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

/// Full-screen camera scanner that returns the first decoded QR payload via
/// `Navigator.pop(context, payload)`. Used by the Add Contact dialog on
/// mobile to capture another user's Tox ID without manual entry.
class _ScanToxIdPage extends StatefulWidget {
  const _ScanToxIdPage();

  @override
  State<_ScanToxIdPage> createState() => _ScanToxIdPageState();
}

class _ScanToxIdPageState extends State<_ScanToxIdPage> {
  late final MobileScannerController _controller;
  // Guard against the detection callback firing twice between the time we
  // decide to pop and the time the page actually unmounts (`onDetect`
  // can deliver a follow-up frame in the same tick).
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.normal,
    );
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (raw == null) return;
    _handled = true;
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    // No ARB key yet for 'Scan QR' on this widget — fall back to a hardcoded
    // English string. Add a real localization later if/when we ship a
    // translated label set.
    const title = 'Scan QR';
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(AppSpacing.xxl),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white70, width: 2),
                  borderRadius: BorderRadius.circular(AppRadii.card),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadii.input),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: scheme.onErrorContainer),
          AppSpacing.horizontalSm,
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
