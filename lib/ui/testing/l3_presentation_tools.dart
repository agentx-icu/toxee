// L3 presentation seams for the product-screenshot pipeline
// (tool/screenshots/): orientation, capture-device override, seed avatars.
//
// These exist because a seeded, offline, Simulator-hosted app differs from a
// real phone in ways that have nothing to do with the product and everything
// to do with the capture environment: the Simulator has no camera (so the
// video-call affordances hide), the iPad boots portrait (the product page
// frames it landscape), and seeded peers have no avatar. Each tool drives the
// SAME product seam a real device/user would (SystemChrome orientation, the
// capability override the unit tests use, the friend avatar path Prefs
// already resolves) — nothing here paints a fake widget.
//
// Registered from l3_debug_tools.dart behind its kDebugMode + TOXEE_L3_TEST
// gate; every MUTATING tool additionally requires the test/seed account.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show DeviceOrientation, SystemChrome;
import 'package:mcp_toolkit/mcp_toolkit.dart';
import 'package:path/path.dart' as p;

import '../../call/call_media_capabilities.dart';
import '../../util/app_paths.dart';
import '../../util/logger.dart';
import '../../util/prefs.dart';

/// Adds the presentation tools to the MCP registry. [isTestAccount] is the
/// caller's account gate (l3_debug_tools' `_activeAccountIsTest`).
void registerL3PresentationTools({
  required Future<bool> Function() isTestAccount,
}) {
  addMcpTool(_l3SetOrientationEntry(isTestAccount));
  addMcpTool(_l3SetCaptureDeviceEntry(isTestAccount));
}

MCPCallEntry _l3SetOrientationEntry(
  Future<bool> Function() isTestAccount,
) => MCPCallEntry.tool(
  handler: (request) async {
    if (!await isTestAccount()) {
      return MCPCallResult(
        message: 'l3_set_orientation: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final want = (request['orientation'] ?? 'clear')
        .toString()
        .trim()
        .toLowerCase();
    final List<DeviceOrientation> orientations;
    switch (want) {
      case 'landscape':
        orientations = const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
      case 'portrait':
        orientations = const [DeviceOrientation.portraitUp];
      case 'clear':
      case '':
        orientations = const [];
      default:
        return MCPCallResult(
          message:
              'l3_set_orientation: unknown orientation "$want" '
              '(portrait|landscape|clear)',
          parameters: {'ok': false, 'error': 'bad_orientation'},
        );
    }
    if (!(Platform.isIOS || Platform.isAndroid)) {
      // Desktop windows have no device orientation; report that honestly
      // instead of pretending the call took.
      return MCPCallResult(
        message: 'l3_set_orientation: not a mobile platform — no-op',
        parameters: {'ok': true, 'applied': false},
      );
    }
    await SystemChrome.setPreferredOrientations(orientations);
    AppLogger.info('[L3] l3_set_orientation: $want');
    return MCPCallResult(
      message: 'orientation preference set',
      parameters: {'ok': true, 'applied': true, 'orientation': want},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_set_orientation',
    description:
        'L3 TEST ONLY (test/seed account, mobile): pin the app\'s preferred '
        'device orientation via SystemChrome.setPreferredOrientations so a '
        'Simulator/emulator capture can be taken landscape or portrait '
        'deterministically. orientation=portrait|landscape|clear (clear '
        'restores the unrestricted default). No-op on desktop.',
    inputSchema: ObjectSchema(
      properties: {
        'orientation': StringSchema(
          description: 'portrait | landscape | clear (default clear).',
        ),
      },
    ),
  ),
);

MCPCallEntry _l3SetCaptureDeviceEntry(
  Future<bool> Function() isTestAccount,
) => MCPCallEntry.tool(
  handler: (request) async {
    if (!await isTestAccount()) {
      return MCPCallResult(
        message: 'l3_set_capture_device: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    final raw = (request['hasCamera'] ?? 'clear')
        .toString()
        .trim()
        .toLowerCase();
    final bool? override = switch (raw) {
      'true' => true,
      'false' => false,
      'clear' || '' => null,
      _ => throw ArgumentError('hasCamera must be true|false|clear'),
    };
    // Same seam the unit tests use; SessionRuntimeCoordinator listens on
    // CallMediaCapabilities.changes and re-pushes the video-call flag, so the
    // header/menu affordances follow without a session restart.
    CallMediaCapabilities.setDeviceHasCameraOverride(override);
    AppLogger.info('[L3] l3_set_capture_device: hasCamera=$raw');
    return MCPCallResult(
      message: 'capture-device override set',
      parameters: {
        'ok': true,
        'hasCamera': raw,
        'videoCaptureSupported': CallMediaCapabilities.supportsVideoCapture(),
      },
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_set_capture_device',
    description:
        'L3 TEST ONLY (test/seed account): override the has-camera answer '
        'CallMediaCapabilities.supportsVideoCapture() gives (hasCamera=true|'
        'false|clear). Lets a camera-less Simulator render the same video-call '
        'affordances a phone does for product screenshots, or force the '
        'camera-less path on a device that has one. The session runtime '
        're-evaluates the video-call entry points on change.',
    inputSchema: ObjectSchema(
      properties: {
        'hasCamera': StringSchema(
          description: 'true | false | clear (default clear).',
        ),
      },
    ),
  ),
);

/// Decode a base64 PNG into the current account's avatars directory and
/// return its absolute path, or null when [base64Png] is empty/invalid. Used
/// by l3_seed_friend / l3_create_group so seeded peers and groups carry an
/// avatar through the SAME Prefs-backed path the real avatar sync writes
/// (`Prefs.setFriendAvatarPath` / `Prefs.setGroupAvatar`); the UIKit avatar
/// widget then renders it exactly as it would a received one.
Future<String?> writeSeedAvatarPng({
  required String fileStem,
  required String base64Png,
}) async {
  final trimmed = base64Png.trim();
  if (trimmed.isEmpty) return null;
  final List<int> bytes;
  try {
    bytes = base64Decode(trimmed);
  } on FormatException {
    return null;
  }
  final toxId = await Prefs.getCurrentAccountToxId();
  if (toxId == null || toxId.isEmpty) return null;
  final dir = await AppPaths.getAccountAvatarsPath(toxId);
  final safeStem = fileStem.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  final file = File(p.join(dir, 'seed_$safeStem.png'));
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
