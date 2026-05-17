import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tencent_cloud_chat_common/base/tencent_cloud_chat_theme_widget.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import '../../i18n/app_localizations.dart';
import '../../util/app_spacing.dart';
import '../../util/app_theme_config.dart';

// TOX_MAX_FRIEND_REQUEST_LENGTH — used for both inline counter and validation.
const int _kMaxFriendRequestLength = 921;

/// Desktop / wide-window max dialog width. Mobile dialogs use the system width
/// minus 32px gutter (see [_dialogMaxWidth]).
const double _kDesktopMaxDialogWidth = 480;

double _dialogMaxWidth(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  // On narrow viewports, hug the screen with a 32-px gutter. On wide viewports,
  // cap to the desktop dialog width so the dialog doesn't sprawl.
  return (w - 32).clamp(280.0, _kDesktopMaxDialogWidth);
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
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Default request message is locale-dependent, so initialize empty here
    // and fill in didChangeDependencies once we have a BuildContext.
    _messageController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messageController.text.isEmpty) {
      _messageController.text =
          AppLocalizations.of(context)!.defaultFriendRequestMessage;
    }
  }

  @override
  void dispose() {
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
      _notify(_localeText(context, 'enterMessage',
          fallback: 'Please enter a message'));
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final defaultMessage =
        AppLocalizations.of(context)!.defaultFriendRequestMessage;
    final successText = _localeText(context, 'requestSent',
        fallback: 'Friend request sent');
    final failurePrefix =
        _localeText(context, 'requestFailed', fallback: 'Failed');

    setState(() => _isSubmitting = true);
    try {
      await widget.service.addFriend(rawId, requestMessage: message);
      await widget.onFriendAdded?.call(rawId);
      await HapticFeedback.lightImpact();
      _notifyVia(messenger, successText);
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

  String? _validateToxId(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return _localeText(context, 'enterId',
          fallback: 'Please enter a Tox ID');
    }
    // Accept 64 (public key) or 76 (full address). Keep 76 as-is - Tox friend
    // request spam mechanism relies on nospam+checksum in the full address.
    if (trimmed.length < 64) {
      return _localeText(context, 'invalidLength',
          fallback: 'ID must be at least 64 hex characters');
    }
    final hexRegex = RegExp(r'^[0-9A-Fa-f]+$');
    if (!hexRegex.hasMatch(trimmed)) {
      return _localeText(context, 'invalidHex',
          fallback: 'Only hexadecimal characters are allowed');
    }
    return null;
  }

  String? _validateMessage(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      return _localeText(context, 'enterMessage',
          fallback: 'Please enter a message');
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

  @override
  Widget build(BuildContext context) {
    return TencentCloudChatThemeWidget(
      build: (context, colorTheme, textStyle) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: _dialogMaxWidth(context)),
          child: Material(
            color: Colors.transparent,
            child: Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: scheme.outlineVariant),
                borderRadius: BorderRadius.circular(AppRadii.dialog),
              ),
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _localeText(context, 'addContact',
                            fallback: 'Add Contact'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                      ),
                      AppSpacing.verticalSm,
                      Text(
                        _localeText(
                          context,
                          'addContactHint',
                          fallback:
                              'Enter the peer Tox ID (at least 64 hex characters, or 76 for full address).',
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      AppSpacing.verticalLg,
                      TextFormField(
                        controller: _idController,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          labelText: _localeText(context, 'friendUserID',
                              fallback: 'Friend Tox ID'),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadii.input),
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.paste),
                            tooltip: _localeText(context, 'paste',
                                fallback: 'Paste'),
                            onPressed: _pasteFromClipboard,
                          ),
                        ),
                        validator: _validateToxId,
                        minLines: 1,
                        maxLines: 3,
                      ),
                      AppSpacing.verticalLg,
                      TextFormField(
                        controller: _messageController,
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          labelText: _localeText(context, 'requestMessage',
                              fallback: 'Request Message'),
                          border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadii.input),
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
    final submitLabel =
        _localeText(context, 'addContact', fallback: 'Add Contact');
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed:
              _isSubmitting ? null : () => Navigator.of(context).maybePop(),
          child: Text(cancelLabel),
        ),
        AppSpacing.horizontalSm,
        Tooltip(
          message: _isSubmitting
              ? _localeText(context, 'sending', fallback: 'Sending...')
              : '',
          child: FilledButton.icon(
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
                      valueColor:
                          AlwaysStoppedAnimation<Color>(scheme.onPrimary),
                    ),
                  )
                : const Icon(Icons.person_add_alt_1),
            label: Text(submitLabel),
            onPressed: _isSubmitting ? null : _submit,
          ),
        ),
      ],
    );
  }

  String _localeText(BuildContext context, String key,
      {required String fallback}) {
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
