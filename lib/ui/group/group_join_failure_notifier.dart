import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../../i18n/app_localizations.dart';
import '../../navigation/app_navigation.dart';
import '../../util/logger.dart';
import 'group_invite_prompter.dart';

/// Tells the user when a group refused to let them in, and why.
///
/// Tox reports a refused join (wrong or missing password, group full)
/// asynchronously, after the join call already returned. It used to be
/// dropped, so the group sat in the list as "joined" with no members and no
/// explanation. The service now drops such a group and reports it on
/// [FfiChatService.groupJoinFailures]; this shows that as a dialog on the root
/// navigator (every platform, both shells), and for a password problem offers
/// to join again with a password.
/// Outcome of the join-failure dialog flow for one refused invite.
enum _RetryOutcome {
  /// The user did not go through the password route (OK / dismissed): the
  /// invite goes back to the prompter, which asks once.
  notRetried,

  /// Accepted again with a password; its outcome is pending again.
  redeemed,

  /// The retry itself failed and was reported here.
  failed,
}

class GroupJoinFailureNotifier {
  GroupJoinFailureNotifier._();
  static final GroupJoinFailureNotifier instance = GroupJoinFailureNotifier._();

  /// Tox group passwords are limited to 32 bytes (TOX_GROUP_MAX_PASSWORD_SIZE).
  static const int maxPasswordBytes = 32;

  static bool isValidPassword(String password) =>
      utf8.encode(password).length <= maxPasswordBytes;

  FfiChatService? _service;
  StreamSubscription<GroupJoinFailure>? _subscription;

  void attach(FfiChatService service) {
    if (identical(_service, service)) return;
    unawaited(_subscription?.cancel());
    _service = service;
    _subscription = service.groupJoinFailures
        .listen((failure) => unawaited(_show(service, failure)));
  }

  /// A refused invite-join is this notifier's to retry: native has already
  /// handed the invite back as unanswered, and [GroupInvitePrompter] leaves it
  /// alone (no auto-accept loop, no second prompt under this dialog) until the
  /// dialog is done — then it asks once if the invite was not redeemed here.
  Future<void> _show(FfiChatService service, GroupJoinFailure failure) async {
    final prompter = GroupInvitePrompter.instance;
    prompter.holdForJoinFailure(service, failure.inviteId);
    var outcome = _RetryOutcome.notRetried;
    try {
      outcome = await _explainAndRetry(service, failure);
    } finally {
      prompter.releaseFromJoinFailure(service, failure.inviteId,
          redeemed: outcome == _RetryOutcome.redeemed,
          retryFailed: outcome == _RetryOutcome.failed);
    }
  }

  /// What the dialog flow did with the invite.
  Future<_RetryOutcome> _explainAndRetry(
      FfiChatService service, GroupJoinFailure failure) async {
    final context = appNavigatorKey.currentContext;
    if (context == null || !context.mounted) return _RetryOutcome.notRetried;
    // A group we still hold is re-joined by its id; a join that was undone
    // needs the chat id to start over.
    // An invite is redeemed through acceptGroupInvite: joinGroup would record
    // the invite's temporary id as a group of its own.
    final viaInvite = !failure.established && failure.inviteId.isNotEmpty;
    final retryTarget = failure.established
        ? failure.groupId
        : viaInvite
            ? failure.inviteId
            : (failure.chatId.length == 64 ? failure.chatId : null);
    final canRetry = failure.reason == GroupJoinFailureReason.invalidPassword &&
        retryTarget != null;
    final retry = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          key: const ValueKey('group_join_failure_dialog'),
          title: Text(l10n.joinFailed),
          content: Text(switch (failure.reason) {
            GroupJoinFailureReason.invalidPassword =>
              l10n.groupJoinRefusedPassword,
            GroupJoinFailureReason.groupFull => l10n.groupJoinRefusedFull,
            GroupJoinFailureReason.unknown => l10n.groupJoinRefusedUnknown,
          }),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
            ),
            if (canRetry)
              FilledButton(
                key: const ValueKey('group_join_failure_password_button'),
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.groupJoinEnterPassword),
              ),
          ],
        );
      },
    );
    if (retry != true || !identical(_service, service)) {
      return _RetryOutcome.notRetried;
    }
    final passwordContext = appNavigatorKey.currentContext;
    if (passwordContext == null || !passwordContext.mounted) {
      return _RetryOutcome.notRetried;
    }
    final password = await _askPassword(passwordContext);
    if (password == null || !identical(_service, service)) {
      return _RetryOutcome.notRetried;
    }
    String? problem;
    try {
      if (viaInvite) {
        await service.acceptGroupInvite(retryTarget!, password: password);
      } else {
        await service.joinGroup(retryTarget!, password: password);
      }
    } on GroupAlreadyJoinedException {
      problem = 'already';
    } catch (e, st) {
      AppLogger.logError(
          '[GroupJoin] retry with password failed for $retryTarget', e, st);
      problem = 'failed';
    }
    // Accepted locally; a renewed refusal comes back as a new failure.
    if (problem == null) {
      return viaInvite ? _RetryOutcome.redeemed : _RetryOutcome.notRetried;
    }
    final resultContext = appNavigatorKey.currentContext;
    if (resultContext == null || !resultContext.mounted) {
      return _RetryOutcome.failed;
    }
    final l10n = AppLocalizations.of(resultContext)!;
    ScaffoldMessenger.maybeOf(resultContext)?.showSnackBar(SnackBar(
      content: Text(problem == 'already' ? l10n.alreadyInGroup : l10n.joinFailed),
    ));
    // The user has just been told the retry failed; the prompter must not
    // stack a fresh Join/Decline/Later dialog on that same message.
    return _RetryOutcome.failed;
  }

  Future<String?> _askPassword(BuildContext context) => showDialog<String>(
        context: context,
        builder: (_) => const _GroupPasswordDialog(),
      );
}

/// Owns its text controller, so it is disposed with the dialog's element —
/// not when the dialog future completes, which is before the exit animation
/// has let go of the field.
class _GroupPasswordDialog extends StatefulWidget {
  const _GroupPasswordDialog();

  @override
  State<_GroupPasswordDialog> createState() => _GroupPasswordDialogState();
}

class _GroupPasswordDialogState extends State<_GroupPasswordDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.groupJoinEnterPassword),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: const ValueKey('group_join_password_input'),
          controller: _controller,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(labelText: l10n.groupPassword),
          // Empty would re-send "no password" and be refused again.
          validator: (value) => (value ?? '').isEmpty
              ? l10n.groupPasswordRequired
              : GroupJoinFailureNotifier.isValidPassword(value!)
                  ? null
                  : l10n.groupPasswordTooLong,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.join)),
      ],
    );
  }
}
