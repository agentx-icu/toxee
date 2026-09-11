import 'package:flutter/material.dart';
import 'package:tencent_cloud_chat_intl/tencent_cloud_chat_intl.dart';

import '../testing/ui_keys.dart';
import '../widgets/safe_dialog_pop.dart';

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
    required this.onConfirm,
  });

  /// The name pre-filled into the field.
  final String initialName;

  /// Called with the trimmed, non-empty new name before the dialog pops. An
  /// empty / whitespace-only name pops without calling this.
  final ValueChanged<String> onConfirm;

  @override
  State<GroupNameEditDialog> createState() => _GroupNameEditDialogState();
}

class _GroupNameEditDialogState extends State<GroupNameEditDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

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
