import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';

import '../../i18n/app_localizations.dart';
import '../../navigation/app_navigation.dart';
import '../../notifications/notification_service.dart';
import '../../util/app_l10n.dart';
import '../../util/logger.dart';
import '../../util/prefs.dart';

/// Surfaces group invites that are waiting for the user's answer.
///
/// With "auto-accept group invites" off — the default — an invite used to be
/// stored natively and never shown anywhere: no row, no badge, no
/// notification, nothing to accept. This asks the user, one invite at a time,
/// on every platform and in both shells (it is a plain dialog on the root
/// navigator), and raises a notification while the app is not in front.
///
/// A join the group refuses hands its invite back; `GroupJoinFailureNotifier`
/// owns that invite (explanation + password retry) while its dialog is up —
/// see [holdForJoinFailure] / [releaseFromJoinFailure].
///
/// Attached from the HomePage bootstrap for the account's service; attaching
/// again (account switch) drops the previous account's subscription.
class GroupInvitePrompter {
  GroupInvitePrompter._();
  static final GroupInvitePrompter instance = GroupInvitePrompter._();

  FfiChatService? _service;
  StreamSubscription<void>? _subscription;
  bool _autoAccept = false;
  bool _showing = false;

  /// Bumped by every attach to a different service. A drain that is still
  /// suspended on a dialog for the PREVIOUS account (account switch mid-prompt)
  /// must neither act on the new service nor clear its `_showing` flag.
  int _generation = 0;

  /// Answered "Later", with the `receivedAt` of the invite that was put off:
  /// not asked again until the inviter sends it again (native keeps a re-sent
  /// invite under the same id and refreshes its `receivedAt`, which makes it a
  /// new question) or auto-accept is switched on. An invite native hands back
  /// after a refused join keeps its original `receivedAt`, so that one stays
  /// put off.
  final Map<String, int> _deferred = <String, int>{};

  /// Invites to skip until something changes: an accept that FAILED
  /// (typically "the inviter went offline", which leaves the invite listed
  /// natively) and a prompt the user DISMISSED with system back / Escape
  /// instead of answering it.
  ///
  /// Deliberately NOT [_deferred]: that is keyed by `receivedAt` and only
  /// reopens when the inviter re-sends, which made both cases unreachable for
  /// the rest of the session. Cleared by the next invite-list change, by the
  /// auto-accept toggle, and when the app returns to the foreground — never
  /// re-asked while nothing changes, so this is neither a loop nor a dead end.
  final Set<String> _suppressedUntilChange = <String>{};

  /// Clears [_suppressedUntilChange] when the app is resumed, so an invite
  /// whose accept failed (or whose prompt was dismissed) is asked again on
  /// the next foreground instead of waiting for the inviter to re-send.
  AppLifecycleListener? _lifecycle;

  /// Same keying as [_deferred]: one notification per invite that was sent.
  final Map<String, int> _notified = <String, int>{};

  /// Accepted this session — by auto-accept, by "Join", or by the password
  /// retry of `GroupJoinFailureNotifier`. Never auto-accepted again: when the
  /// group refuses the join (wrong/missing password, full), native hands the
  /// invite back as unanswered, and accepting it again with no password would
  /// be refused again — forever, one "Join failed" dialog per round.
  final Set<String> _accepted = <String>{};

  /// Accepted, and the join not refused-and-explained yet. A refused join's
  /// invite comes back BEFORE the refusal reaches `GroupJoinFailureNotifier`;
  /// it belongs to that notifier's dialog (which offers the password route),
  /// not to a second prompt underneath it. [releaseFromJoinFailure] hands it
  /// back to this prompter, which then asks once.
  ///
  /// Keyed by the `receivedAt` the invite had when it was accepted: a join
  /// that SUCCEEDS never hands its invite back, so the entry would otherwise
  /// sit here forever and silently swallow a genuinely new invite the inviter
  /// sends later under the same id.
  final Map<String, int> _awaitingOutcome = <String, int>{};

  /// Held by `GroupJoinFailureNotifier` while its dialog is up. Separate from
  /// [_awaitingOutcome] because the notifier only knows the invite id, not the
  /// `receivedAt`, and its hold ends explicitly.
  final Set<String> _heldByNotifier = <String>{};

  void attach(FfiChatService service, {required bool autoAccept}) {
    _autoAccept = autoAccept;
    if (identical(_service, service)) {
      unawaited(_drain());
      return;
    }
    unawaited(_subscription?.cancel());
    _service = service;
    _generation++;
    _showing = false;
    _deferred.clear();
    _suppressedUntilChange.clear();
    _notified.clear();
    _accepted.clear();
    _awaitingOutcome.clear();
    _heldByNotifier.clear();
    _lifecycle ??= AppLifecycleListener(onResume: () {
      _suppressedUntilChange.clear();
      unawaited(_drain());
    });
    _subscription = service.pendingGroupInvitesChanged.listen((_) {
      // Something about the invite list changed: an accept that failed
      // earlier (offline inviter) gets another chance, without this ever
      // becoming a retry loop — nothing re-asks while nothing changes.
      _suppressedUntilChange.clear();
      unawaited(_drain());
    });
    unawaited(_drain());
  }

  /// The setting was toggled while running. Switching it ON also covers the
  /// invites that are already waiting — the ones put off and the ones whose
  /// accept failed — which is what the setting says it does.
  set autoAccept(bool value) {
    _autoAccept = value;
    if (!value) return;
    _deferred.clear();
    _suppressedUntilChange.clear();
    unawaited(_drain());
  }

  /// `GroupJoinFailureNotifier` is explaining why the group behind [inviteId]
  /// refused the join. Until [releaseFromJoinFailure], the invite native
  /// handed back is that dialog's to redeem, not something to prompt for.
  void holdForJoinFailure(FfiChatService service, String inviteId) {
    if (inviteId.isEmpty || !identical(_service, service)) return;
    _heldByNotifier.add(inviteId);
  }

  /// The join-failure dialog for [inviteId] is done. [redeemed]: the user
  /// accepted it again with a password, so its outcome is pending again (a
  /// renewed refusal comes back through the notifier). Otherwise the invite is
  /// still waiting natively and becomes the user's to answer again: asked once
  /// — never auto-accepted — so it can be declined, put off, or joined (which
  /// leads back to the password route) instead of lingering unreachable.
  void releaseFromJoinFailure(FfiChatService service, String inviteId,
      {required bool redeemed, bool retryFailed = false}) {
    if (inviteId.isEmpty || !identical(_service, service)) return;
    _heldByNotifier.remove(inviteId);
    if (redeemed) {
      _accepted.add(inviteId);
      _markAwaitingOutcome(inviteId);
      return;
    }
    // The outcome of the accept that led here is now known (refused, and
    // explained), so the invite is answerable again.
    _awaitingOutcome.remove(inviteId);
    if (retryFailed) {
      // The password retry itself failed (the notifier already said so).
      // Asking again in the same breath would stack a second dialog on that
      // message; the invite stays eligible for the next change event.
      _suppressedUntilChange.add(inviteId);
      return;
    }
    unawaited(_drain());
  }

  /// [inviteId] is accepted and waiting for its outcome, recorded against the
  /// `receivedAt` it currently has.
  void _markAwaitingOutcome(String inviteId, {int? fallbackReceivedMs}) {
    final service = _service;
    if (service == null) return;
    for (final invite in _pending(service)) {
      if (invite.id == inviteId) {
        _awaitingOutcome[inviteId] = invite.receivedAt.millisecondsSinceEpoch;
        return;
      }
    }
    if (fallbackReceivedMs != null) {
      // The accept consumed the listing: record what it had, which is what
      // native hands back if the group refuses the join. A genuinely re-sent
      // invite carries a NEWER value and is a new question.
      _awaitingOutcome[inviteId] = fallbackReceivedMs;
      return;
    }
    // Native no longer lists it (the accept consumed it): the id alone is
    // enough to keep a hand-back from prompting underneath the notifier.
    _awaitingOutcome[inviteId] = 0;
  }

  /// Whether [invite] is one we accepted and whose outcome is still open.
  /// A re-sent invite (refreshed `receivedAt`) is a new question, not the old
  /// one still pending.
  bool _isAwaitingOutcome(PendingGroupInvite invite) {
    if (_heldByNotifier.contains(invite.id)) return true;
    final at = _awaitingOutcome[invite.id];
    if (at == null) return false;
    if (at == 0 || at == invite.receivedAt.millisecondsSinceEpoch) return true;
    _awaitingOutcome.remove(invite.id);
    return false;
  }

  bool _isDeferred(PendingGroupInvite invite) {
    final at = _deferred[invite.id];
    if (at == null) return false;
    if (at == invite.receivedAt.millisecondsSinceEpoch) return true;
    _deferred.remove(invite.id); // sent again: a new question
    return false;
  }

  void _defer(PendingGroupInvite invite) =>
      _deferred[invite.id] = invite.receivedAt.millisecondsSinceEpoch;

  Future<void> _drain() async {
    final service = _service;
    if (service == null || _showing) return;
    final generation = _generation;
    _showing = true;
    try {
      while (identical(_service, service) && generation == _generation) {
        PendingGroupInvite? next;
        for (final invite in _pending(service)) {
          if (!_isAwaitingOutcome(invite) &&
              !_isDeferred(invite) &&
              !_suppressedUntilChange.contains(invite.id)) {
            next = invite;
            break;
          }
        }
        if (next == null) return;

        if (_autoAccept && !_accepted.contains(next.id)) {
          // An invite that arrived before the persisted setting reached the
          // native gate (it is applied from the HomePage bootstrap, after
          // polling has started) lands here as "pending": honor the setting.
          // Once only: an invite back from a refused join is asked about.
          if (!await _accept(service, next)) _suppressedUntilChange.add(next.id);
          continue;
        }

        final inviter = await _inviterName(next.inviterUserId);
        if (!identical(_service, service) || generation != _generation) return;
        // Accepted (password retry) or taken over by the join-failure dialog
        // while the name was being looked up.
        if (_isAwaitingOutcome(next)) continue;
        _notifyIfBackgrounded(next, inviter);

        final context = appNavigatorKey.currentContext;
        if (context == null || !context.mounted) {
          // No navigator yet (very early start): the next change event, or the
          // next attach, asks again.
          return;
        }
        final answer = await _ask(context, next, inviter);
        if (!identical(_service, service)) return;
        switch (answer) {
          case _Answer.join:
            if (!await _accept(service, next)) {
              // Not [_defer]: a failed accept is not "answer me later",
              // and the inviter coming back does not refresh `receivedAt`.
              _suppressedUntilChange.add(next.id);
              final failContext = appNavigatorKey.currentContext;
              if (failContext == null || !failContext.mounted) break;
              if (await _showAcceptFailed(failContext) &&
                  identical(_service, service) &&
                  generation == _generation) {
                if (await _accept(service, next)) break;
                final againContext = appNavigatorKey.currentContext;
                if (againContext != null && againContext.mounted) {
                  // No Retry this time: its result is not acted on, and a
                  // button that does nothing is worse than no button.
                  await _showAcceptFailed(againContext, canRetry: false);
                }
              }
            }
          case _Answer.decline:
            service.rejectGroupInvite(next.id);
          case _Answer.later:
            _defer(next);
          case _Answer.dismissed:
            _suppressedUntilChange.add(next.id);
        }
      }
    } finally {
      if (generation == _generation) _showing = false;
    }
  }

  /// Never lets a native hiccup (library not loaded yet, older native lib)
  /// escape into the HomePage bootstrap that attached us.
  List<PendingGroupInvite> _pending(FfiChatService service) {
    try {
      return service.getPendingGroupInvites();
    } catch (e, st) {
      AppLogger.logError('[GroupInvite] listing pending invites failed', e, st);
      return const [];
    }
  }

  Future<bool> _accept(FfiChatService service, PendingGroupInvite invite) async {
    try {
      await service.acceptGroupInvite(invite.id);
      // A refusal hands the invite back only after a network round trip, so
      // recording it now is in time. Not for a service we were detached from.
      if (identical(_service, service)) {
        _accepted.add(invite.id);
        _suppressedUntilChange.remove(invite.id);
        // Against the `receivedAt` native holds NOW, not the one this object
        // was read with: the inviter may have re-sent while the dialog was
        // open, which refreshes it under the same id. Recording the stale
        // value made the hand-back of a refused join look like a new
        // question and prompted underneath the failure dialog.
        _markAwaitingOutcome(invite.id,
            fallbackReceivedMs: invite.receivedAt.millisecondsSinceEpoch);
      }
      return true;
    } catch (e, st) {
      AppLogger.logError(
          '[GroupInvite] accept failed for ${invite.id}', e, st);
      return false;
    }
  }

  Future<String> _inviterName(String inviterUserId) async {
    final remark = await Prefs.getFriendRemark(inviterUserId);
    if (remark != null && remark.isNotEmpty) return remark;
    final nick = await Prefs.getFriendNickname(inviterUserId);
    if (nick != null && nick.isNotEmpty) return nick;
    return inviterUserId.length > 12
        ? '${inviterUserId.substring(0, 12)}…'
        : inviterUserId;
  }

  String _body(AppLocalizations l10n, PendingGroupInvite invite, String who) =>
      invite.groupName.isEmpty
          ? l10n.groupInviteBodyUnnamed(who)
          : l10n.groupInviteBody(who, invite.groupName);

  void _notifyIfBackgrounded(PendingGroupInvite invite, String inviter) {
    final sentAt = invite.receivedAt.millisecondsSinceEpoch;
    if (_notified[invite.id] == sentAt) return;
    _notified[invite.id] = sentAt;
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return;
    final l10n = currentAppL10n();
    unawaited(NotificationService.instance.showGroupInviteNotification(
      inviteId: invite.id,
      title: l10n.groupInviteTitle,
      body: _body(l10n, invite, inviter),
    ));
  }

  Future<_Answer> _ask(
      BuildContext context, PendingGroupInvite invite, String inviter) async {
    final answer = await showDialog<_Answer>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        return AlertDialog(
          key: const ValueKey('group_invite_dialog'),
          title: Text(l10n.groupInviteTitle),
          content: Text(_body(l10n, invite, inviter)),
          actions: [
            TextButton(
              key: const ValueKey('group_invite_decline_button'),
              onPressed: () => Navigator.of(dialogContext).pop(_Answer.decline),
              child: Text(l10n.groupInviteDecline),
            ),
            TextButton(
              key: const ValueKey('group_invite_later_button'),
              onPressed: () => Navigator.of(dialogContext).pop(_Answer.later),
              child: Text(l10n.groupInviteLater),
            ),
            FilledButton(
              key: const ValueKey('group_invite_join_button'),
              onPressed: () => Navigator.of(dialogContext).pop(_Answer.join),
              child: Text(l10n.join),
            ),
          ],
        );
      },
    );
    // Dismissed rather than answered (system back, Escape, a route change on
    // logout). NOT "Later": that is keyed by `receivedAt` and would hide the
    // invite until the inviter re-sent it.
    return answer ?? _Answer.dismissed;
  }

  /// True when the user asked to try the accept again. The invite is still
  /// listed natively (the usual cause is an offline inviter), so a retry is
  /// the difference between "try once more now" and waiting for the next
  /// invite-list change.
  Future<bool> _showAcceptFailed(BuildContext context,
          {bool canRetry = true}) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final l10n = AppLocalizations.of(dialogContext)!;
          return AlertDialog(
            key: const ValueKey('group_invite_accept_failed_dialog'),
            title: Text(l10n.joinFailed),
            content: Text(l10n.groupInviteAcceptFailed),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
              ),
              if (canRetry)
                FilledButton(
                  key: const ValueKey('group_invite_accept_retry_button'),
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: Text(l10n.retry),
                ),
            ],
          );
        },
      ) ??
      false;
}

enum _Answer { join, decline, later, dismissed }
