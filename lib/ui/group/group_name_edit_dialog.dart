import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_common/utils/tox_group_kind.dart';
import 'package:tencent_cloud_chat_intl/tencent_cloud_chat_intl.dart';

import '../../i18n/app_localizations.dart';
import '../../util/app_l10n.dart';
import '../testing/ui_keys.dart';
import '../widgets/safe_dialog_pop.dart';
import 'group_name_limits.dart';

/// The group-profile "Set group name" dialog. It OWNS its
/// [TextEditingController] and disposes it in [dispose] — at unmount, i.e.
/// after the LAST rebuild the framework can run against the field.
///
/// Why this is a widget of its own (2026-09-05, iPad `conference_rename_leave`
/// red on both attempts while the iPhone was green): the previous inline
/// `showDialog(builder: ...).whenComplete(addPostFrameCallback(controller
/// .dispose))` disposed the controller ONE frame after `didPop`, while the
/// dialog's `TextField` stays mounted for the whole ~150 ms dismiss
/// transition. Any rebuild inside that window — the soft keyboard's
/// view-insets animating out re-run the `MediaQuery.viewInsetsOf` dependency
/// below — reached `_AnimatedState.didUpdateWidget` for the `TextField`'s
/// `Listenable.merge([focusNode, controller])` and called `addListener` on the
/// disposed controller. That debug FlutterError is caught by the field's
/// `RawGestureDetector`, which swaps in an ErrorWidget and ORPHANS the old
/// subtree (still active, its InheritedElement registrations intact). When
/// the dialog's overlay entry is then removed, every InheritedElement in it
/// fails `'_dependents.isEmpty'` (framework.dart `debugDeactivated`) during
/// the Overlay's `_Theater.updateChildren`, and the Navigator's Overlay
/// replaces its ENTIRE route stack with an ErrorWidget — no header, no
/// conversation list, no profile. Shared Dart: every shell was exposed; the
/// phone merely never rebuilt inside the window.
///
/// Owning the controller in a State is the Flutter contract: `dispose` runs
/// only once the element is defunct, so no rebuild can ever observe a
/// disposed controller, on any shell.
class GroupNameEditDialog extends StatefulWidget {
  const GroupNameEditDialog({
    super.key,
    required this.initialName,
    required this.groupType,
    required this.onConfirm,
  });

  /// The name pre-filled into the field.
  final String initialName;

  /// The group's type. A legacy conference's title (published to the peers)
  /// may be 128 bytes, an NGC group's name 48 — the same limits as creating
  /// the group.
  final String? groupType;

  /// Called with the trimmed, non-empty new name before the dialog pops. An
  /// empty / whitespace-only name pops without calling this. A name over the
  /// group kind's byte limit neither confirms nor pops: the field says why.
  final ValueChanged<String> onConfirm;

  @override
  State<GroupNameEditDialog> createState() => _GroupNameEditDialogState();
}

class _GroupNameEditDialogState extends State<GroupNameEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  /// Set when confirm was refused for length; cleared as soon as the text
  /// changes. Same byte rule as creating a group: without it a rename could
  /// take a name creation refuses, and a conference title past
  /// TOX_MAX_NAME_LENGTH then failed to publish and silently stayed local.
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: UiKeys.groupProfileEditNameDialog,
      title: Text(tL10n.setGroupName),
      // Dialog already lifts itself above the soft keyboard (it pads by the
      // view insets and zeroes them for its subtree); padding here again — the
      // insets read from THIS context are the real ones — only added a
      // keyboard-sized blank under the field. The scroll view stays so a very
      // long name can't push the buttons off-screen.
      content: SingleChildScrollView(
        child: TextField(
          key: UiKeys.groupProfileEditNameField,
          controller: _controller,
          autofocus: true,
          maxLines: 3,
          minLines: 1,
          decoration: InputDecoration(errorText: _error, errorMaxLines: 2),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => popDialogIfCurrent(context),
          child: Text(tL10n.cancel),
        ),
        TextButton(
          key: UiKeys.groupProfileEditNameConfirmButton,
          onPressed: () {
            final trimmed = _controller.text.trim();
            if (groupNameTooLong(
              trimmed,
              conference: isToxConferenceGroupType(widget.groupType),
            )) {
              final l10n = AppLocalizations.of(context) ?? currentAppL10n();
              setState(() => _error = l10n.groupNameTooLong);
              return;
            }
            if (trimmed.isNotEmpty) widget.onConfirm(trimmed);
            // The confirm can fire twice (flutter_skill: pointer + direct
            // callback); popDialogIfCurrent absorbs the second pop.
            popDialogIfCurrent(context);
          },
          child: Text(tL10n.confirm),
        ),
      ],
    );
  }
}
