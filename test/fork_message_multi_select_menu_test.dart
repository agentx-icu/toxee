import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SOURCE GUARD for the message multi-select entry point.
///
/// WHY THIS EXISTS. The four `sweep_msg_select` real-UI cases can only reach
/// select mode through `message_menu_item:multiSelect`, and the fork's menu
/// container strips that item (`_uikit_multi_message`) from TEXT bubbles and
/// from file/image/video/sound bubbles. The CUSTOM bubble is the last type that
/// still carries it, which is why every one of those cases seeds a custom
/// message. If a fork sync ever strips it there too, the entire multi-select
/// surface silently stops being covered.
///
/// The runtime driver now FAILS (rather than SKIPs) in that situation, but that
/// only helps when someone actually launches a device campaign. These tests are
/// the device-free half: they run in the ordinary `flutter test` gate, so a bad
/// fork sync is red before any simulator is booted.
///
/// They are deliberately STRUCTURAL, not a checksum: they assert the *shape* of
/// the gating (which element types are stripped, and that the entry is added at
/// all), so unrelated edits to the menu container do not produce noise.
void main() {
  final root = Directory.current.path;
  final menuContainer = File(
    '$root/third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/'
    'tencent_cloud_chat_message_widgets/menu/'
    'tencent_cloud_chat_message_item_with_menu_container.dart',
  );

  /// Element types the multi-select item is ALLOWED to be stripped for. A
  /// custom message must never appear here — it is the only remaining bubble
  /// that can open select mode.
  const strippableTypes = <String>{
    'V2TIM_ELEM_TYPE_TEXT',
    'V2TIM_ELEM_TYPE_FILE',
    'V2TIM_ELEM_TYPE_IMAGE',
    'V2TIM_ELEM_TYPE_VIDEO',
    'V2TIM_ELEM_TYPE_SOUND',
  };

  test('the fork still OFFERS multiSelect, gated only by enableMessageSelect',
      () async {
    expect(
      menuContainer.existsSync(),
      isTrue,
      reason:
          'the fork submodule is missing; run dart run tool/bootstrap_deps.dart',
    );
    final lines = await menuContainer.readAsLines();
    final addIndex = lines.indexWhere(
      (l) => l.contains('id: "_uikit_multi_message"'),
    );
    expect(
      addIndex,
      isNot(-1),
      reason:
          'the message menu no longer declares a `_uikit_multi_message` option '
          'at all. sweep_msg_select drives that item as '
          '`message_menu_item:multiSelect`; without it the whole select-mode '
          'surface (toolbar, delete dialog, forward picker, select header) is '
          'unreachable and its four cases assert nothing.',
    );
    // The option is emitted from a collection-if. Scan back a few lines for the
    // guard so a config regression (enableMessageSelect defaulted off, or the
    // guard swapped for an unrelated flag) is caught too.
    final guardWindow = lines
        .sublist((addIndex - 6).clamp(0, addIndex), addIndex)
        .join('\n');
    expect(
      guardWindow,
      contains('defaultMessageMenuConfig.enableMessageSelect'),
      reason:
          'the multiSelect menu option is no longer gated by '
          '`enableMessageSelect`. toxee pins that flag on in '
          'lib/ui/home_page_bootstrap.dart; if the gate moved, re-point that '
          'pin (and this guard) at whatever replaced it.',
    );
  });

  test('multiSelect is never stripped for CUSTOM bubbles', () async {
    final source = await menuContainer.readAsString();
    final lines = source.split('\n');

    // Every `removeWhere` block that mentions `_uikit_multi_message`, paired
    // with the `if (...)` condition that guards it. The container writes these
    // as `if (<element-type test>) { mergedList.removeWhere((e) => ... ); }`.
    final strips = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].contains('_uikit_multi_message')) continue;
      if (lines[i].contains('id: "_uikit_multi_message"')) continue; // the add
      // Walk back to the nearest enclosing `if (` and capture the condition.
      var start = -1;
      for (var j = i; j >= 0 && j > i - 30; j--) {
        if (lines[j].trimLeft().startsWith('if (')) {
          start = j;
          break;
        }
      }
      expect(
        start,
        isNot(-1),
        reason:
            'line ${i + 1} of the fork menu container removes '
            '`_uikit_multi_message` with no enclosing `if` guard in the '
            'preceding 30 lines — i.e. it may be stripping it '
            'UNCONDITIONALLY, which would take multi-select away from custom '
            'bubbles and blank out sweep_msg_select.',
      );
      strips.add(lines.sublist(start, i + 1).join('\n'));
    }

    expect(
      strips,
      isNotEmpty,
      reason:
          'no `_uikit_multi_message` strip rule found. That is not necessarily '
          'wrong, but sweep_msg_select and REAL_UI_TWO_PROCESS.md both '
          'document that only CUSTOM bubbles can enter select mode — if the '
          'fork now offers it everywhere, widen those cases instead of '
          'leaving the docs stale.',
    );

    final typePattern = RegExp(r'V2TIM_ELEM_TYPE_[A-Z_]+');
    for (final strip in strips) {
      final types = typePattern
          .allMatches(strip)
          .map((m) => m.group(0)!)
          .toSet();
      expect(
        types,
        isNotEmpty,
        reason:
            'a `_uikit_multi_message` strip rule is guarded by something other '
            'than an element-type test:\n$strip\nsweep_msg_select assumes the '
            'ONLY reason the item disappears is the bubble type.',
      );
      expect(
        types.difference(strippableTypes),
        isEmpty,
        reason:
            'a `_uikit_multi_message` strip rule now covers element types '
            'outside the known text/file/image/video/sound set:\n$strip\nIf '
            'CUSTOM was added, sweep_msg_select has no bubble left that can '
            'open select mode and its four cases must be redesigned (they '
            'seed a custom message on purpose).',
      );
      expect(
        strip,
        isNot(contains('elemType !=')),
        reason:
            'a `_uikit_multi_message` strip rule became a NEGATIVE match '
            '(`elemType != ...`):\n$strip\nA negative guard strips every OTHER '
            'type, custom included, which is exactly the regression '
            'sweep_msg_select would then be unable to observe.',
      );
    }
  });

  test('toxee pins enableMessageSelect on', () async {
    final bootstrap = await File(
      '$root/lib/ui/home_page_bootstrap.dart',
    ).readAsString();
    expect(
      bootstrap.replaceAll(RegExp(r'\s+'), ' '),
      contains('enableMessageSelect: true'),
      reason:
          'toxee no longer turns the multi-select menu entry on, so '
          'sweep_msg_select cannot reach select mode on any bubble.',
    );
  });
}
