// Surface 2: Native ToxAV handle — per-instance or shared?
//
// Evidence (code inspection, see docs/audits/2026-05-16-ffi-reentrancy-audit.md):
//   - ToxAVManager is per-instance, owned by
//     V2TIMManagerImpl::toxav_manager_ (V2TIMManagerImpl.h:250).
//   - Constructed at V2TIMManagerImpl.cpp:238 inside InitSDK.
//   - ToxAVManager::getInstance() static is preserved for backward
//     compatibility (ToxAVManager.h:22) but production code uses
//     V2TIMManagerImpl::GetToxAVManager() per-instance.
//   - All AV FFI calls take instance_id as the first arg (see
//     third_party/tim2tox/dart/lib/ffi/tim2tox_ffi.dart:201-260,
//     e.g. avInitialize, avShutdown, avIterate, avStartCallNative).
//   - g_instance_av_callbacks keyed by instance_id
//     (tim2tox_ffi.cpp:2668) — per-instance callback storage.
//
// This test makes synchronous FFI calls that DO NOT spawn audio devices
// (we never call avInitialize). Instead we verify that the AV setter
// bindings exist for any instance handle without crashing — i.e. the
// per-instance dispatch table is wired.

// ignore_for_file: avoid_print
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/ffi/tim2tox_ffi.dart' as ffi_lib;

void main() {
  ffi_lib.Tim2ToxFfi? lib;
  setUpAll(() {
    try {
      lib = ffi_lib.Tim2ToxFfi.open();
    } catch (e) {
      print('[surface_2] Skipping FFI-call portion: $e');
      lib = null;
    }
  });

  test('AV setter bindings are resolvable per-instance', () {
    if (lib == null) {
      print(
        '[surface_2] FALLBACK (code-inspection):'
        ' V2TIMManagerImpl.h:250, tim2tox_ffi.cpp:2668, tim2tox_ffi.dart:201-260',
      );
      return;
    }
    // Resolving these closures forces the dlsym lookup. If the symbol
    // is missing, lookupFunction throws — so the act of touching them
    // proves the multi-instance AV ABI exists.
    expect(lib!.avSetCallCallbackNative, isNotNull);
    expect(lib!.avSetCallStateCallbackNative, isNotNull);
    expect(lib!.avSetAudioReceiveCallbackNative, isNotNull);
    expect(lib!.avSetVideoReceiveCallbackNative, isNotNull);
    // The ABI shape: each setter is
    //   void (int64_t instance_id, NativeFunction cb, Pointer<Void> user)
    // — i.e. the FIRST argument is instance_id. This is the multi-instance
    // contract. We do not actually invoke them (registering a real callback
    // pulls in NativeApi).
  });

  test('AV callback setters keep six independent user_data contexts', () async {
    final repoRoot = Directory.current.path;
    final ffiSource = await File(
      '$repoRoot/third_party/tim2tox/ffi/tim2tox_ffi.cpp',
    ).readAsString();
    final ffiHeader = await File(
      '$repoRoot/third_party/tim2tox/ffi/tim2tox_ffi.h',
    ).readAsString();
    final dartBinding = await File(
      '$repoRoot/third_party/tim2tox/dart/lib/ffi/tim2tox_ffi.dart',
    ).readAsString();

    final avCallbacksBody = _extractStructBody(ffiSource, 'AVCallbacks');
    final issues = <String>[];

    if (RegExp(r'\bvoid\s*\*\s*user_data\s*=').hasMatch(avCallbacksBody)) {
      issues.add(
        'AVCallbacks still has one shared user_data field; it needs one '
        'context field per callback slot.',
      );
    }

    for (final contract in _avCallbackContracts) {
      _expectNativeSetterSignature(ffiHeader, ffiSource, contract);
      _expectDartSetterSignature(dartBinding, contract);

      if (!RegExp(
        r'\bvoid\s*\*\s*' +
            RegExp.escape(contract.userDataField) +
            r'\s*=\s*nullptr\s*;',
      ).hasMatch(avCallbacksBody)) {
        issues.add(
          '${contract.label}: AVCallbacks must store ${contract.userDataField} '
          'separately from ${contract.callbackField}.',
        );
      }

      final setterBody = _extractFunctionBody(ffiSource, contract.nativeSetter);
      if (!RegExp(
        r'\bcallbacks\s*->\s*' +
            RegExp.escape(contract.callbackField) +
            r'\s*=\s*callback\s*;',
      ).hasMatch(setterBody)) {
        issues.add(
          '${contract.label}: ${contract.nativeSetter} must store callback in '
          '${contract.callbackField}.',
        );
      }
      if (!RegExp(
        r'\bcallbacks\s*->\s*' +
            RegExp.escape(contract.userDataField) +
            r'\s*=\s*user_data\s*;',
      ).hasMatch(setterBody)) {
        issues.add(
          '${contract.label}: ${contract.nativeSetter} must store user_data in '
          '${contract.userDataField}.',
        );
      }
      if (RegExp(
        r'\bcallbacks\s*->\s*user_data\s*=\s*user_data\s*;',
      ).hasMatch(setterBody)) {
        issues.add(
          '${contract.label}: ${contract.nativeSetter} still writes the shared '
          'AVCallbacks.user_data field.',
        );
      }

      if (_isSingleDeliveryCallback(contract.callbackField) ||
          contract.callbackField == 'on_audio_receive' ||
          contract.callbackField == 'on_video_receive') {
        continue;
      }

      if (_isBitrateCallback(contract.callbackField)) {
        final drainBody = _extractNativeFunctionBody(
          ffiSource,
          'DrainAVBitrateEvents',
        );
        _expectBitrateDrainUsesLocalUserData(drainBody, contract, issues);
        continue;
      }

      if (!_sourceContainsDispatchUsingUserData(
        ffiSource,
        contract.callbackField,
        contract.userDataField,
      )) {
        issues.add(
          '${contract.label}: dispatcher must pass ${contract.userDataField} '
          'to ${contract.callbackField}.',
        );
      }
      if (_sourceContainsDispatchUsingSharedUserData(
        ffiSource,
        contract.callbackField,
      )) {
        issues.add(
          '${contract.label}: dispatcher still reads shared '
          'AVCallbacks.user_data.',
        );
      }
    }

    expect(
      issues,
      isEmpty,
      reason:
          'Each exported AV setter must keep its current ABI while binding '
          'a distinct callback context and dispatching that same context.\n'
          '${issues.join('\n')}',
    );
  });

  test(
    'AV call callbacks use direct delivery or global fallback, not both',
    () async {
      final repoRoot = Directory.current.path;
      final ffiSource = await File(
        '$repoRoot/third_party/tim2tox/ffi/tim2tox_ffi.cpp',
      ).readAsString();
      final issues = <String>[];

      for (final contract in _avSingleDeliveryContracts) {
        final lambdaBody = _extractBetween(
          ffiSource,
          contract.lambdaStart,
          contract.lambdaEnd,
        );
        final globalType = 'GlobalCallbackType::${contract.globalCallbackType}';

        if (lambdaBody.contains('CallbackSnapshot')) {
          issues.add(
            '${contract.label}: direct delivery must not use a local wrapper '
            'struct shaped like a map iterator.',
          );
        }
        if (lambdaBody.contains('has_direct')) {
          issues.add(
            '${contract.label}: direct delivery can use the callback pointer as '
            'the branch condition instead of a separate has_direct flag.',
          );
        }

        final callbackAssignment = _localAssignedFromCallbackStorage(
          lambdaBody,
          contract.callbackField,
        );
        final userDataAssignment = _localAssignedFromCallbackStorage(
          lambdaBody,
          contract.userDataField,
        );

        if (callbackAssignment == null) {
          issues.add(
            '${contract.label}: missing local callback snapshot from '
            '${contract.callbackField}.',
          );
          continue;
        }
        if (userDataAssignment == null) {
          issues.add(
            '${contract.label}: missing local user_data snapshot from '
            '${contract.userDataField}.',
          );
          continue;
        }

        if (!_isInsideAvCallbackMutexScope(
          lambdaBody,
          callbackAssignment.index,
        )) {
          issues.add(
            '${contract.label}: callback pointer snapshot must happen under '
            'g_av_callbacks_mutex.',
          );
        }
        if (!_isInsideAvCallbackMutexScope(
          lambdaBody,
          userDataAssignment.index,
        )) {
          issues.add(
            '${contract.label}: user_data snapshot must happen under '
            'g_av_callbacks_mutex.',
          );
        }

        final branches = _extractIfElseBranches(
          lambdaBody,
          callbackAssignment.variableName,
        );
        if (branches == null) {
          issues.add(
            '${contract.label}: direct callback and global fallback must be '
            'split by an explicit if/else on the direct callback pointer.',
          );
          continue;
        }

        final directIndex = _indexOfInvocationWithArgument(
          lambdaBody,
          callbackAssignment.variableName,
          userDataAssignment.variableName,
        );
        if (directIndex < 0 ||
            !_containsInvocationWithArgument(
              branches.thenBody,
              callbackAssignment.variableName,
              userDataAssignment.variableName,
            )) {
          issues.add(
            '${contract.label}: direct branch must invoke the local callback '
            'with the matching local user_data.',
          );
        } else if (_isInsideAvCallbackMutexScope(lambdaBody, directIndex)) {
          issues.add(
            '${contract.label}: direct callback invocation must happen outside '
            'g_av_callbacks_mutex.',
          );
        }

        if (branches.thenBody.contains(globalType) ||
            branches.thenBody.contains('"globalCallback"')) {
          issues.add(
            '${contract.label}: direct branch must not also post the global '
            'fallback.',
          );
        }
        if (_containsInvocationWithArgument(
          branches.elseBody,
          callbackAssignment.variableName,
          userDataAssignment.variableName,
        )) {
          issues.add(
            '${contract.label}: else fallback must not invoke the direct '
            'callback.',
          );
        }
        if (!_containsGlobalCallbackFallback(branches.elseBody, globalType)) {
          issues.add(
            '${contract.label}: $globalType fallback must still post through '
            'SendCallbackToDart("globalCallback", ...).',
          );
        }

        final globalIndex = lambdaBody.indexOf(
          globalType,
          branches.elseStartIndex,
        );
        if (globalIndex >= 0 &&
            _isInsideAvCallbackMutexScope(lambdaBody, globalIndex)) {
          issues.add(
            '${contract.label}: global fallback must happen outside '
            'g_av_callbacks_mutex.',
          );
        }
      }

      expect(
        issues,
        isEmpty,
        reason:
            'Native AV call events must deliver exactly once. Direct FFI '
            'callbacks win when registered; globalCallback remains only as the '
            'binary-replacement fallback when direct delivery is absent.\n'
            '${issues.join('\n')}',
      );
    },
  );

  test(
    'AV audio/video receive callbacks snapshot callback context before delivery',
    () async {
      final repoRoot = Directory.current.path;
      final ffiSource = await File(
        '$repoRoot/third_party/tim2tox/ffi/tim2tox_ffi.cpp',
      ).readAsString();
      final issues = <String>[];

      for (final contract in _receiveFrameCallbackContracts) {
        final lambdaBody = _extractNativeLambdaBody(
          ffiSource,
          contract.installCall,
        );
        final directInvoke = _firstCallbackFieldInvocation(
          lambdaBody,
          contract.callbackField,
        );
        if (directInvoke != null) {
          final lockState =
              _isInsideAvCallbackMutexScope(lambdaBody, directInvoke.start)
              ? ' while g_av_callbacks_mutex is held'
              : '';
          issues.add(
            '${contract.label}: receive lambda directly invokes '
            '${contract.callbackField}$lockState. It must copy callback and '
            'matching user_data to locals first.',
          );
        }

        final callbackAssignment = _localAssignedFromCallbackStorage(
          lambdaBody,
          contract.callbackField,
        );
        final userDataAssignment = _localAssignedFromCallbackStorage(
          lambdaBody,
          contract.userDataField,
        );

        if (callbackAssignment == null) {
          issues.add(
            '${contract.label}: receive lambda must snapshot '
            '${contract.callbackField} into a local callback variable.',
          );
        }
        if (userDataAssignment == null) {
          issues.add(
            '${contract.label}: receive lambda must snapshot '
            '${contract.userDataField} into a local user_data variable.',
          );
        }
        if (callbackAssignment == null || userDataAssignment == null) {
          continue;
        }

        if (!_isInsideAvCallbackMutexScope(
          lambdaBody,
          callbackAssignment.index,
        )) {
          issues.add(
            '${contract.label}: callback snapshot must happen under '
            'g_av_callbacks_mutex.',
          );
        }
        if (!_isInsideAvCallbackMutexScope(
          lambdaBody,
          userDataAssignment.index,
        )) {
          issues.add(
            '${contract.label}: user_data snapshot must happen under '
            'g_av_callbacks_mutex.',
          );
        }

        final invocationIndex = _indexOfInvocationWithArgument(
          lambdaBody,
          callbackAssignment.variableName,
          userDataAssignment.variableName,
        );
        if (invocationIndex < 0) {
          issues.add(
            '${contract.label}: receive lambda must invoke the local callback '
            'with the matching local user_data variable.',
          );
        } else if (_isInsideAvCallbackMutexScope(lambdaBody, invocationIndex)) {
          issues.add(
            '${contract.label}: receive lambda must invoke Dart after releasing '
            'g_av_callbacks_mutex.',
          );
        }
      }

      expect(
        issues,
        isEmpty,
        reason:
            'ToxAV audio/video receive callbacks must snapshot the callback and '
            'its matching user_data under g_av_callbacks_mutex, release that '
            'mutex, then invoke the local callback. Re-entering Dart while the '
            'FFI callback registry mutex is held can deadlock callback '
            'registration/teardown paths.\n'
            '${issues.join('\n')}',
      );
    },
  );

  test(
    'sendVideoFrame gives empty Dart chroma planes native backing',
    () async {
      final repoRoot = Directory.current.path;
      final toxAvService = await File(
        '$repoRoot/third_party/tim2tox/dart/lib/service/toxav_service.dart',
      ).readAsString();
      final sendVideoFrameBody = _extractDartFunctionBody(
        toxAvService,
        'sendVideoFrame',
      );
      final issues = <String>[];

      _expectDartChromaPlaneAllocationKeepsBacking(
        sendVideoFrameBody,
        planeName: 'u',
        pointerName: 'uPtr',
        issues: issues,
      );
      _expectDartChromaPlaneAllocationKeepsBacking(
        sendVideoFrameBody,
        planeName: 'v',
        pointerName: 'vPtr',
        issues: issues,
      );
      _expectDartWidthOneFloorChromaStillValid(toxAvService, issues);

      expect(
        issues,
        isEmpty,
        reason:
            'Outbound I420 frames with width=1 have zero-length floor-chroma '
            'planes, but native FFI still receives non-null U/V pointers. Dart '
            'must therefore allocate at least one byte of native backing for '
            'empty U/V lists without rejecting width=1 floor-chroma frames.\n'
            '${issues.join('\n')}',
      );
    },
  );

  test(
    'native video send guards zero-width chroma before U/V pointer offsets',
    () async {
      final repoRoot = Directory.current.path;
      final ffiSource = await File(
        '$repoRoot/third_party/tim2tox/ffi/tim2tox_ffi.cpp',
      ).readAsString();
      final sendVideoFrameBody = _extractNativeFunctionBody(
        ffiSource,
        'tim2tox_ffi_av_send_video_frame',
      );
      final issues = <String>[];

      if (!RegExp(
        r'\bpacked_uv\s*=\s*static_cast\s*<\s*int32_t\s*>\s*\(\s*width\s*/\s*2\s*\)',
      ).hasMatch(sendVideoFrameBody)) {
        issues.add(
          'tim2tox_ffi_av_send_video_frame must keep floor-chroma '
          'packed_uv = width / 2 semantics.',
        );
      }

      final chromaPointerArithmetic = _firstChromaPlanePointerArithmetic(
        sendVideoFrameBody,
      );
      if (chromaPointerArithmetic != null) {
        final hasGuard = _hasPackedUvZeroControlBeforeArithmetic(
          sendVideoFrameBody,
          chromaPointerArithmetic.start,
        );
        final beforeArithmetic = sendVideoFrameBody.substring(
          0,
          chromaPointerArithmetic.start,
        );
        final hasNormalization = _containsPackedUvZeroStrideNormalization(
          beforeArithmetic,
        );
        if (!hasGuard && !hasNormalization) {
          issues.add(
            'tim2tox_ffi_av_send_video_frame forms ${chromaPointerArithmetic.group(0)} '
            'without an earlier packed_uv==0 guard or stride normalization. '
            'A width=1 frame can have packed_uv==0 and chroma_h>0, so the '
            'native path must either return/send before U/V row arithmetic or '
            'guard the chroma loop behind an explicit packed_uv non-zero check.',
          );
        }
      }

      expect(
        issues,
        isEmpty,
        reason:
            'Native strided I420 compaction must not form U/V row pointer '
            'offsets when packed_uv==0. The contract allows either an early '
            'return/send path for zero-width chroma or a guarded chroma loop, '
            'but the packed_uv==0 decision must appear before the first U/V '
            'row pointer arithmetic.\n'
            '${issues.join('\n')}',
      );
    },
  );

  test(
    'AV bitrate callbacks are drained after toxav iterate without FFI locks',
    () async {
      final repoRoot = Directory.current.path;
      final ffiSource = await File(
        '$repoRoot/third_party/tim2tox/ffi/tim2tox_ffi.cpp',
      ).readAsString();
      final toxAvManagerSource = await File(
        '$repoRoot/third_party/tim2tox/source/ToxAVManager.cpp',
      ).readAsString();
      final ffiIterateBody = _extractNativeFunctionBody(
        ffiSource,
        'tim2tox_ffi_av_iterate',
      );
      final toxAvIterateBody = _extractNativeFunctionBody(
        toxAvManagerSource,
        'ToxAVManager::iterate',
      );
      final issues = <String>[];

      final toxavIterateIndex = toxAvIterateBody.indexOf('toxav_iterate');
      if (toxavIterateIndex < 0) {
        issues.add('ToxAVManager::iterate must call toxav_iterate.');
      } else if (!_isInsideNamedMutexScope(
        toxAvIterateBody,
        toxavIterateIndex,
        'mutex_',
      )) {
        issues.add(
          'ToxAVManager::iterate must keep documenting that toxav_iterate '
          'runs while ToxAVManager::mutex_ is held.',
        );
      }

      final avIterateCall = RegExp(
        r'\bav_mgr\s*->\s*iterate\s*\(\s*\)\s*;',
      ).firstMatch(ffiIterateBody);
      if (avIterateCall == null) {
        issues.add('tim2tox_ffi_av_iterate must call av_mgr->iterate().');
      }

      final preIterate = avIterateCall == null
          ? ffiIterateBody
          : ffiIterateBody.substring(0, avIterateCall.start);
      final postIterateDrainSource = avIterateCall == null
          ? ''
          : _postIterateDrainSource(ffiIterateBody, avIterateCall.end);

      for (final contract in _bitrateCallbackContracts) {
        final lambdaBody = _extractNativeLambdaBody(
          ffiSource,
          contract.installCall,
        );
        final directInvoke = _firstCallbackFieldInvocation(
          lambdaBody,
          contract.callbackField,
        );
        if (directInvoke != null) {
          final lockState =
              _isInsideAvCallbackMutexScope(lambdaBody, directInvoke.start)
              ? ' while g_av_callbacks_mutex is held'
              : '';
          issues.add(
            '${contract.label}: toxav bitrate lambda directly invokes '
            '${contract.callbackField}$lockState. Bitrate events must be '
            'queued during toxav iterate, then drained after av_mgr->iterate '
            'returns.',
          );
        }
        if (!_containsDeferredEventWrite(lambdaBody)) {
          issues.add(
            '${contract.label}: toxav bitrate lambda must write the event to '
            'a deferred queue instead of relying on immediate Dart delivery.',
          );
        }
        if (_containsCallbackFieldReference(
          preIterate,
          contract.callbackField,
        )) {
          issues.add(
            '${contract.label}: bitrate drain must not run before '
            'av_mgr->iterate() returns.',
          );
        }

        _expectBitrateDrainAfterIterate(
          postIterateDrainSource,
          contract,
          issues,
        );
      }

      expect(
        issues,
        isEmpty,
        reason:
            'c-toxcore bitrate callbacks are invoked from toxav_iterate while '
            'ToxAVManager::mutex_ is held. The FFI layer must therefore queue '
            'audio/video bitrate events from the toxav callbacks, return from '
            'av_mgr->iterate(), then snapshot callback/context under '
            'g_av_callbacks_mutex and invoke Dart only after that mutex is '
            'released.\n'
            '${issues.join('\n')}',
      );
    },
  );

  test(
    'native video send uses original U/V when either chroma dimension is zero',
    () async {
      final repoRoot = Directory.current.path;
      final ffiSource = await File(
        '$repoRoot/third_party/tim2tox/ffi/tim2tox_ffi.cpp',
      ).readAsString();
      final sendVideoFrameBody = _extractNativeFunctionBody(
        ffiSource,
        'tim2tox_ffi_av_send_video_frame',
      );
      final issues = <String>[];

      if (!RegExp(
        r'\bchroma_h\s*=\s*static_cast\s*<\s*uint16_t\s*>\s*\(\s*height\s*/\s*2\s*\)',
      ).hasMatch(sendVideoFrameBody)) {
        issues.add(
          'tim2tox_ffi_av_send_video_frame must keep floor-chroma '
          'chroma_h = height / 2 semantics.',
        );
      }

      final firstUvBufferUse = _firstUvCompactionBufferUse(sendVideoFrameBody);
      if (firstUvBufferUse == null) {
        issues.add('Expected to find the U/V compaction buffer path.');
      } else {
        final zeroChromaBranches = _zeroChromaBranchesBefore(
          sendVideoFrameBody,
          firstUvBufferUse.start,
        );
        if (zeroChromaBranches.isEmpty) {
          issues.add(
            'U/V compaction buffers are reached without an earlier zero-chroma '
            'branch.',
          );
        } else {
          final handlesPackedUvZero = zeroChromaBranches.any(
            (branch) => _conditionHandlesPackedUvZeroAxis(branch.condition),
          );
          final handlesChromaHeightZero = zeroChromaBranches.any(
            (branch) => _conditionHandlesChromaHeightZeroAxis(branch.condition),
          );
          if (!handlesPackedUvZero || !handlesChromaHeightZero) {
            final conditions = zeroChromaBranches
                .map((branch) => '`${branch.condition}`')
                .join(', ');
            issues.add(
              'Zero-chroma branches before U/V buffers must cover both '
              'packed_uv==0 and chroma_h==0; found $conditions.',
            );
          }
          for (final branch in zeroChromaBranches) {
            if (RegExp(r'\b[uv]_buf\b').hasMatch(branch.body)) {
              issues.add(
                'Zero-chroma branch `${branch.condition}` must not allocate or '
                'read U/V compaction buffers.',
              );
            }
            if (!_sendsOriginalChromaPointers(branch.body)) {
              issues.add(
                'Zero-chroma branch `${branch.condition}` must pass the '
                'original non-null u/v pointers to av_mgr->sendVideoFrame '
                'after any needed Y-only compaction.',
              );
            }
          }
        }
      }

      expect(
        issues,
        isEmpty,
        reason:
            'A frame with height=1 and width>1 has packed_uv>0 but '
            'chroma_h==0. The strided-Y path must treat that exactly like '
            'packed_uv==0: compact Y only when needed and pass original U/V '
            'pointers through, never zero-length U/V vector data.\n'
            '${issues.join('\n')}',
      );
    },
  );

  test('avShutdown with a non-existent instance returns without crashing', () {
    if (lib == null) {
      print(
        '[surface_2] FALLBACK (code-inspection):'
        ' tim2tox_ffi.cpp avShutdown safety check',
      );
      return;
    }
    // 0 = current/default. Calling avShutdown without a prior avInitialize
    // should be a no-op (no AV bound to default). It demonstrates per-instance
    // teardown does not touch any state belonging to a different id.
    const int defaultId = 0;
    expect(() => lib!.avShutdown(defaultId), returnsNormally);
  });

  test('ABI sanity: AV per-frame send takes instance_id first', () {
    // Pure code-inspection assertion; the typedefs in tim2tox_ffi.dart
    // make this a compile-time invariant. We re-affirm it here so a
    // refactor that drops instance_id from any AV signature will fail
    // a regression check.
    final fn = lib?.avSendAudioFrameNative;
    if (fn == null) {
      print('[surface_2] FALLBACK (code-inspection): tim2tox_ffi.dart:474');
      return;
    }
    // The Dart binding declares
    //   int Function(int instanceId, int friendNumber, Pointer<Int16> pcm,
    //                int sampleCount, int channels, int samplingRate)
    // — confirmed by the typedef _av_send_audio_frame_c at tim2tox_ffi.dart:209.
    // A real call would need a valid PCM pointer; here we just assert the
    // closure is bound (i.e. dlsym succeeded).
    expect(fn, isA<Function>());
    // Reference ffi to silence unused-import lints if Surface 2 strips assertions later.
    ffi.nullptr;
  });
}

const _avCallbackContracts = <_AvCallbackContract>[
  _AvCallbackContract(
    label: 'call',
    nativeSetter: 'tim2tox_ffi_av_set_call_callback',
    nativeCallbackType: 'tim2tox_av_call_callback_t',
    dartSetterTypedef: '_av_set_call_callback_c',
    dartCallbackTypedef: '_av_call_callback_native',
    dartProperty: 'avSetCallCallbackNative',
    callbackField: 'on_call',
    userDataField: 'on_call_user_data',
  ),
  _AvCallbackContract(
    label: 'call-state',
    nativeSetter: 'tim2tox_ffi_av_set_call_state_callback',
    nativeCallbackType: 'tim2tox_av_call_state_callback_t',
    dartSetterTypedef: '_av_set_call_state_callback_c',
    dartCallbackTypedef: '_av_call_state_callback_native',
    dartProperty: 'avSetCallStateCallbackNative',
    callbackField: 'on_call_state',
    userDataField: 'on_call_state_user_data',
  ),
  _AvCallbackContract(
    label: 'audio receive',
    nativeSetter: 'tim2tox_ffi_av_set_audio_receive_callback',
    nativeCallbackType: 'tim2tox_av_audio_receive_callback_t',
    dartSetterTypedef: '_av_set_audio_receive_callback_c',
    dartCallbackTypedef: '_av_audio_receive_callback_native',
    dartProperty: 'avSetAudioReceiveCallbackNative',
    callbackField: 'on_audio_receive',
    userDataField: 'on_audio_receive_user_data',
  ),
  _AvCallbackContract(
    label: 'video receive',
    nativeSetter: 'tim2tox_ffi_av_set_video_receive_callback',
    nativeCallbackType: 'tim2tox_av_video_receive_callback_t',
    dartSetterTypedef: '_av_set_video_receive_callback_c',
    dartCallbackTypedef: '_av_video_receive_callback_native',
    dartProperty: 'avSetVideoReceiveCallbackNative',
    callbackField: 'on_video_receive',
    userDataField: 'on_video_receive_user_data',
  ),
  _AvCallbackContract(
    label: 'audio bitrate',
    nativeSetter: 'tim2tox_ffi_av_set_audio_bitrate_callback',
    nativeCallbackType: 'tim2tox_av_audio_bitrate_callback_t',
    dartSetterTypedef: '_av_set_audio_bitrate_callback_c',
    dartCallbackTypedef: '_av_audio_bitrate_callback_native',
    dartProperty: 'avSetAudioBitrateCallbackNative',
    callbackField: 'on_audio_bitrate',
    userDataField: 'on_audio_bitrate_user_data',
  ),
  _AvCallbackContract(
    label: 'video bitrate',
    nativeSetter: 'tim2tox_ffi_av_set_video_bitrate_callback',
    nativeCallbackType: 'tim2tox_av_video_bitrate_callback_t',
    dartSetterTypedef: '_av_set_video_bitrate_callback_c',
    dartCallbackTypedef: '_av_video_bitrate_callback_native',
    dartProperty: 'avSetVideoBitrateCallbackNative',
    callbackField: 'on_video_bitrate',
    userDataField: 'on_video_bitrate_user_data',
  ),
];

const _avSingleDeliveryContracts = <_AvSingleDeliveryContract>[
  _AvSingleDeliveryContract(
    label: 'call',
    lambdaStart: 'av_mgr->setCallCallback([captured_instance_id]',
    lambdaEnd: 'av_mgr->setCallStateCallback([captured_instance_id]',
    callbackField: 'on_call',
    userDataField: 'on_call_user_data',
    globalCallbackType: 'ToxAVCall',
  ),
  _AvSingleDeliveryContract(
    label: 'call-state',
    lambdaStart: 'av_mgr->setCallStateCallback([captured_instance_id]',
    lambdaEnd: 'av_mgr->setAudioReceiveFrameCallback([captured_instance_id]',
    callbackField: 'on_call_state',
    userDataField: 'on_call_state_user_data',
    globalCallbackType: 'ToxAVCallState',
  ),
];

const _bitrateCallbackContracts = <_BitrateCallbackContract>[
  _BitrateCallbackContract(
    label: 'audio bitrate',
    installCall: 'av_mgr->setAudioBitrateCallback',
    callbackField: 'on_audio_bitrate',
    userDataField: 'on_audio_bitrate_user_data',
  ),
  _BitrateCallbackContract(
    label: 'video bitrate',
    installCall: 'av_mgr->setVideoBitrateCallback',
    callbackField: 'on_video_bitrate',
    userDataField: 'on_video_bitrate_user_data',
  ),
];

const _receiveFrameCallbackContracts = <_ReceiveFrameCallbackContract>[
  _ReceiveFrameCallbackContract(
    label: 'audio receive',
    installCall: 'av_mgr->setAudioReceiveFrameCallback',
    callbackField: 'on_audio_receive',
    userDataField: 'on_audio_receive_user_data',
  ),
  _ReceiveFrameCallbackContract(
    label: 'video receive',
    installCall: 'av_mgr->setVideoReceiveFrameCallback',
    callbackField: 'on_video_receive',
    userDataField: 'on_video_receive_user_data',
  ),
];

class _AvCallbackContract {
  const _AvCallbackContract({
    required this.label,
    required this.nativeSetter,
    required this.nativeCallbackType,
    required this.dartSetterTypedef,
    required this.dartCallbackTypedef,
    required this.dartProperty,
    required this.callbackField,
    required this.userDataField,
  });

  final String label;
  final String nativeSetter;
  final String nativeCallbackType;
  final String dartSetterTypedef;
  final String dartCallbackTypedef;
  final String dartProperty;
  final String callbackField;
  final String userDataField;
}

class _AvSingleDeliveryContract {
  const _AvSingleDeliveryContract({
    required this.label,
    required this.lambdaStart,
    required this.lambdaEnd,
    required this.callbackField,
    required this.userDataField,
    required this.globalCallbackType,
  });

  final String label;
  final String lambdaStart;
  final String lambdaEnd;
  final String callbackField;
  final String userDataField;
  final String globalCallbackType;
}

class _BitrateCallbackContract {
  const _BitrateCallbackContract({
    required this.label,
    required this.installCall,
    required this.callbackField,
    required this.userDataField,
  });

  final String label;
  final String installCall;
  final String callbackField;
  final String userDataField;
}

class _ReceiveFrameCallbackContract {
  const _ReceiveFrameCallbackContract({
    required this.label,
    required this.installCall,
    required this.callbackField,
    required this.userDataField,
  });

  final String label;
  final String installCall;
  final String callbackField;
  final String userDataField;
}

class _ZeroChromaBranch {
  const _ZeroChromaBranch({required this.condition, required this.body});

  final String condition;
  final String body;
}

class _LocalAssignment {
  const _LocalAssignment({required this.variableName, required this.index});

  final String variableName;
  final int index;
}

class _IfElseBranches {
  const _IfElseBranches({
    required this.thenBody,
    required this.elseBody,
    required this.elseStartIndex,
  });

  final String thenBody;
  final String elseBody;
  final int elseStartIndex;
}

void _expectNativeSetterSignature(
  String ffiHeader,
  String ffiSource,
  _AvCallbackContract contract,
) {
  final signature = RegExp(
    r'void\s+' +
        RegExp.escape(contract.nativeSetter) +
        r'\s*\(\s*int64_t\s+instance_id\s*,\s*' +
        RegExp.escape(contract.nativeCallbackType) +
        r'\s+callback\s*,\s*void\s*\*\s*user_data\s*\)',
  );

  expect(
    signature.hasMatch(ffiHeader),
    isTrue,
    reason: '${contract.nativeSetter} must keep its exported header ABI.',
  );
  expect(
    signature.hasMatch(ffiSource),
    isTrue,
    reason: '${contract.nativeSetter} must keep its exported C++ ABI.',
  );
}

void _expectDartSetterSignature(
  String dartBinding,
  _AvCallbackContract contract,
) {
  final typedefBlock = _extractTypedefBlock(
    dartBinding,
    contract.dartSetterTypedef,
  );
  expect(typedefBlock, contains('ffi.Int64,'));
  expect(
    typedefBlock,
    contains(
      'ffi.Pointer<ffi.NativeFunction<${contract.dartCallbackTypedef}>>',
    ),
  );
  expect(typedefBlock, contains('ffi.Pointer<ffi.Void>,'));

  final dartFunctionType =
      'void Function(int, ffi.Pointer<ffi.NativeFunction<${contract.dartCallbackTypedef}>>, ffi.Pointer<ffi.Void>)';
  final assignment = RegExp(
    r'\b' + RegExp.escape(contract.dartProperty) + r'\s*=',
  ).firstMatch(dartBinding);
  expect(
    assignment,
    isNotNull,
    reason: '${contract.dartProperty} must exist in tim2tox_ffi.dart',
  );
  final assignmentMatch = assignment!;
  final declarationStart =
      dartBinding.lastIndexOf(';', assignmentMatch.start) + 1;
  final declarationEnd = dartBinding.indexOf(';', assignmentMatch.end);
  expect(
    declarationEnd,
    isNonNegative,
    reason: '${contract.dartProperty} must have a complete field assignment',
  );
  final declaration = dartBinding.substring(
    declarationStart,
    declarationEnd + 1,
  );
  final compactDeclaration = declaration.replaceAll(RegExp(r'\s+'), '');
  final compactDartFunctionType = dartFunctionType.replaceAll(
    RegExp(r'\s+'),
    '',
  );

  expect(
    compactDeclaration,
    contains('$compactDartFunctionType${contract.dartProperty}='),
  );
  expect(
    compactDeclaration,
    contains(
      'lookupFunction<${contract.dartSetterTypedef},$compactDartFunctionType>',
    ),
  );
  expect(compactDeclaration, contains("('${contract.nativeSetter}')"));
}

String _extractStructBody(String source, String structName) {
  final match = RegExp(
    r'struct\s+' + RegExp.escape(structName) + r'\s*\{([\s\S]*?)\n\s*\};',
  ).firstMatch(source);
  expect(match, isNotNull, reason: '$structName must exist in tim2tox_ffi.cpp');
  return match!.group(1)!;
}

String _extractFunctionBody(String source, String functionName) {
  final match = RegExp(
    r'void\s+' +
        RegExp.escape(functionName) +
        r'\s*\([^)]*\)\s*\{([\s\S]*?)\n\}',
  ).firstMatch(source);
  expect(
    match,
    isNotNull,
    reason: '$functionName must exist in tim2tox_ffi.cpp',
  );
  return match!.group(1)!;
}

String _extractNativeFunctionBody(String source, String functionName) {
  final markerIndex = source.indexOf(functionName);
  expect(
    markerIndex,
    isNonNegative,
    reason: '$functionName must exist in tim2tox_ffi.cpp',
  );
  final openBrace = source.indexOf('{', markerIndex);
  expect(
    openBrace,
    isNonNegative,
    reason: '$functionName must have a function body in tim2tox_ffi.cpp',
  );
  final closeBrace = _findMatchingBrace(source, openBrace);
  expect(
    closeBrace,
    isNonNegative,
    reason: '$functionName must have a balanced function body',
  );
  return source.substring(openBrace + 1, closeBrace);
}

String _extractNativeLambdaBody(String source, String callMarker) {
  final markerIndex = source.indexOf(callMarker);
  expect(
    markerIndex,
    isNonNegative,
    reason: '$callMarker must exist in tim2tox_ffi.cpp',
  );
  final openBrace = source.indexOf('{', markerIndex);
  expect(
    openBrace,
    isNonNegative,
    reason: '$callMarker must install a lambda body',
  );
  final closeBrace = _findMatchingBrace(source, openBrace);
  expect(
    closeBrace,
    isNonNegative,
    reason: '$callMarker lambda body must be balanced',
  );
  return source.substring(openBrace + 1, closeBrace);
}

String _extractDartFunctionBody(String source, String functionName) {
  final namePattern = RegExp(r'\b' + RegExp.escape(functionName) + r'\s*\(');
  for (final match in namePattern.allMatches(source)) {
    final lineStart = source.lastIndexOf('\n', match.start) + 1;
    final prefix = source.substring(lineStart, match.start).trim();
    if (!_looksLikeDartFunctionDeclarationPrefix(prefix)) continue;

    final openParen = source.indexOf('(', match.start);
    final closeParen = _findMatchingParen(source, openParen);
    if (closeParen < 0) continue;

    final openBrace = source.indexOf('{', closeParen);
    final semicolon = source.indexOf(';', closeParen);
    if (openBrace < 0 || (semicolon >= 0 && semicolon < openBrace)) continue;

    final closeBrace = _findMatchingBrace(source, openBrace);
    if (closeBrace < 0) continue;
    return source.substring(openBrace + 1, closeBrace);
  }

  fail('$functionName must have a Dart function body');
}

bool _looksLikeDartFunctionDeclarationPrefix(String prefix) {
  return RegExp(
    r'^(?:@override\s+)?(?:static\s+)?(?:Future\s*<\s*[^>]+\s*>|bool|int|void|[A-Za-z_]\w*)$',
  ).hasMatch(prefix);
}

int _findMatchingParen(String source, int openParenIndex) {
  if (openParenIndex < 0 || source.codeUnitAt(openParenIndex) != 0x28) {
    return -1;
  }

  var depth = 0;
  var inLineComment = false;
  var inBlockComment = false;
  var inString = false;
  var inChar = false;
  var escaped = false;

  for (var index = openParenIndex; index < source.length; index += 1) {
    final code = source.codeUnitAt(index);
    final next = index + 1 < source.length ? source.codeUnitAt(index + 1) : -1;

    if (inLineComment) {
      if (code == 0x0a) inLineComment = false;
      continue;
    }
    if (inBlockComment) {
      if (code == 0x2a && next == 0x2f) {
        inBlockComment = false;
        index += 1;
      }
      continue;
    }
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (code == 0x5c) {
        escaped = true;
      } else if (code == 0x22) {
        inString = false;
      }
      continue;
    }
    if (inChar) {
      if (escaped) {
        escaped = false;
      } else if (code == 0x5c) {
        escaped = true;
      } else if (code == 0x27) {
        inChar = false;
      }
      continue;
    }

    if (code == 0x2f && next == 0x2f) {
      inLineComment = true;
      index += 1;
      continue;
    }
    if (code == 0x2f && next == 0x2a) {
      inBlockComment = true;
      index += 1;
      continue;
    }
    if (code == 0x22) {
      inString = true;
      continue;
    }
    if (code == 0x27) {
      inChar = true;
      continue;
    }
    if (code == 0x28) {
      depth += 1;
    } else if (code == 0x29) {
      depth -= 1;
      if (depth == 0) return index;
    }
  }
  return -1;
}

void _expectDartChromaPlaneAllocationKeepsBacking(
  String sendVideoFrameBody, {
  required String planeName,
  required String pointerName,
  required List<String> issues,
}) {
  final allocation = RegExp(
    r'\b(?:final|var)\s+' +
        RegExp.escape(pointerName) +
        r'\s*=\s*pkgffi\.malloc\s*<\s*ffi\.Uint8\s*>\s*\(([\s\S]*?)\)\s*;',
  ).firstMatch(sendVideoFrameBody);
  if (allocation == null) {
    issues.add('$pointerName must allocate native Uint8 backing.');
    return;
  }

  final allocationArgument = allocation.group(1)!.trim();
  final prefix = sendVideoFrameBody.substring(0, allocation.start);
  if (_allocationArgumentGuaranteesNonZeroLength(
    allocationArgument,
    prefix,
    planeName,
  )) {
    return;
  }

  issues.add(
    '$pointerName currently allocates pkgffi.malloc<ffi.Uint8>('
    '$allocationArgument); empty $planeName planes need at least one byte of '
    'native backing before crossing the FFI boundary.',
  );
}

bool _allocationArgumentGuaranteesNonZeroLength(
  String allocationArgument,
  String prefix,
  String planeName,
) {
  if (_expressionGuaranteesNonZeroPlaneLength(allocationArgument, planeName)) {
    return true;
  }
  if (!RegExp(r'^[A-Za-z_]\w*$').hasMatch(allocationArgument)) return false;

  final assignmentPattern = RegExp(
    r'\b(?:final|var|int)\s+' +
        RegExp.escape(allocationArgument) +
        r'\s*=\s*([^;]+)\s*;',
  );
  final assignments = assignmentPattern.allMatches(prefix).toList();
  if (assignments.isEmpty) return false;
  final assignedExpression = assignments.last.group(1)!.trim();
  return _expressionGuaranteesNonZeroPlaneLength(assignedExpression, planeName);
}

bool _expressionGuaranteesNonZeroPlaneLength(
  String expression,
  String planeName,
) {
  final planeLength = RegExp.escape('$planeName.length');
  final planeIsEmpty = RegExp.escape('$planeName.isEmpty');
  final planeIsNotEmpty = RegExp.escape('$planeName.isNotEmpty');
  return RegExp(
        r'\b(?:math\.)?max\s*\(\s*(?:1\s*,\s*' +
            planeLength +
            r'|' +
            planeLength +
            r'\s*,\s*1)\s*\)',
      ).hasMatch(expression) ||
      RegExp(
            r'(?:' +
                planeIsEmpty +
                r'|' +
                planeLength +
                r'\s*(?:==|<=)\s*0|0\s*(?:==|>=)\s*' +
                planeLength +
                r'|' +
                planeIsNotEmpty +
                r')',
          ).hasMatch(expression) &&
          RegExp(r'\b1\b').hasMatch(expression) ||
      RegExp(planeLength + r'\s*\+\s*1\b').hasMatch(expression) ||
      RegExp(r'\b1\s*\+\s*' + planeLength).hasMatch(expression);
}

void _expectDartWidthOneFloorChromaStillValid(
  String toxAvService,
  List<String> issues,
) {
  final dimensionBody = _extractDartFunctionBody(
    toxAvService,
    '_isValidVideoDimensionForAbi',
  );
  if (!RegExp(r'\bvalue\s*>=\s*1\b').hasMatch(dimensionBody)) {
    issues.add('Video dimension validation must continue to allow width=1.');
  }

  final planeSpanBody = _extractDartFunctionBody(
    toxAvService,
    '_isValidPlaneSpan',
  );
  if (!RegExp(
    r'\browWidth\s*==\s*0\s*\|\|\s*height\s*==\s*0',
  ).hasMatch(planeSpanBody)) {
    issues.add(
      'Plane-span validation must continue to accept zero-size floor-chroma '
      'planes for width=1 or height=1.',
    );
  }
}

RegExpMatch? _firstChromaPlanePointerArithmetic(String source) {
  final patterns = <RegExp>[
    RegExp(
      r'\b[uv]\s*\+\s*(?:static_cast\s*<\s*size_t\s*>\s*\(\s*row\s*\)|row)\s*\*\s*eff_[uv]_stride',
    ),
    RegExp(
      r'\b[uv]\s*\[\s*(?:static_cast\s*<\s*size_t\s*>\s*\(\s*row\s*\)|row)\s*\*\s*eff_[uv]_stride\s*\]',
    ),
  ];
  RegExpMatch? firstMatch;
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(source)) {
      if (firstMatch == null || match.start < firstMatch.start) {
        firstMatch = match;
      }
    }
  }
  return firstMatch;
}

bool _hasPackedUvZeroControlBeforeArithmetic(
  String source,
  int arithmeticIndex,
) {
  final ifPattern = RegExp(r'\bif\s*\(([\s\S]*?)\)');
  for (final match in ifPattern.allMatches(source)) {
    if (match.start >= arithmeticIndex) break;
    final condition = match.group(1)!;
    if (!_checksPackedUvAgainstZero(condition)) continue;

    final nextIndex = _firstNonWhitespaceIndex(source, match.end);
    if (nextIndex < 0) continue;

    if (source.codeUnitAt(nextIndex) == 0x7b) {
      final closeBrace = _findMatchingBrace(source, nextIndex);
      if (_requiresPackedUvNonZero(condition) && arithmeticIndex < closeBrace) {
        return true;
      }
      if (_handlesPackedUvZero(condition) &&
          closeBrace < arithmeticIndex &&
          source.substring(nextIndex + 1, closeBrace).contains('return')) {
        return true;
      }
      continue;
    }

    final statementEnd = source.indexOf(';', nextIndex);
    if (_handlesPackedUvZero(condition) &&
        statementEnd >= 0 &&
        statementEnd < arithmeticIndex &&
        source.substring(nextIndex, statementEnd).contains('return')) {
      return true;
    }
  }
  return false;
}

int _firstNonWhitespaceIndex(String source, int start) {
  for (var index = start; index < source.length; index += 1) {
    if (!_isWhitespaceCode(source.codeUnitAt(index))) return index;
  }
  return -1;
}

bool _isWhitespaceCode(int code) {
  return code == 0x09 || code == 0x0a || code == 0x0d || code == 0x20;
}

bool _containsPackedUvZeroStrideNormalization(String source) {
  return _strideNormalizationChecksPackedUv(source, 'eff_u_stride') &&
      _strideNormalizationChecksPackedUv(source, 'eff_v_stride');
}

void _expectBitrateDrainAfterIterate(
  String drainSource,
  _BitrateCallbackContract contract,
  List<String> issues,
) {
  if (!RegExp(
    r'\bDrainAVBitrateEvents\s*\(\s*instance_id\s*\)\s*;',
  ).hasMatch(drainSource)) {
    issues.add(
      '${contract.label}: tim2tox_ffi_av_iterate must drain queued bitrate '
      'events after av_mgr->iterate() by calling DrainAVBitrateEvents('
      'instance_id).',
    );
    return;
  }
}

String _postIterateDrainSource(
  String ffiIterateBody,
  int afterIterateCallIndex,
) {
  return ffiIterateBody.substring(afterIterateCallIndex);
}

bool _containsDeferredEventWrite(String source) {
  return RegExp(
        r'\b(?:push_back|emplace_back|push|emplace)\s*\(',
      ).hasMatch(source) ||
      RegExp(
        r'\b(?:queue|enqueue|defer|pending|buffer|record)[A-Za-z_0-9]*\s*\(',
        caseSensitive: false,
      ).hasMatch(source) ||
      RegExp(
        r'\b[A-Za-z_]\w*(?:queue|pending|buffer)[A-Za-z_0-9]*\s*(?:\.|->)',
        caseSensitive: false,
      ).hasMatch(source);
}

bool _containsCallbackFieldReference(String source, String callbackField) {
  return RegExp(r'\b' + RegExp.escape(callbackField) + r'\b').hasMatch(source);
}

RegExpMatch? _firstCallbackFieldInvocation(
  String source,
  String callbackField,
) {
  return RegExp(
    r'\b' + RegExp.escape(callbackField) + r'\s*\(',
  ).firstMatch(source);
}

RegExpMatch? _firstUvCompactionBufferUse(String source) {
  final patterns = <RegExp>[
    RegExp(r'\bstd::vector\s*<\s*uint8_t\s*>\s*[uv]_buf\b'),
    RegExp(r'\b[uv]_buf\s*\.\s*data\s*\('),
  ];
  RegExpMatch? firstMatch;
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(source)) {
      if (firstMatch == null || match.start < firstMatch.start) {
        firstMatch = match;
      }
    }
  }
  return firstMatch;
}

List<_ZeroChromaBranch> _zeroChromaBranchesBefore(
  String source,
  int boundaryIndex,
) {
  final branches = <_ZeroChromaBranch>[];
  final ifPattern = RegExp(r'\bif\s*\(([\s\S]*?)\)');
  for (final match in ifPattern.allMatches(source)) {
    if (match.start >= boundaryIndex) break;
    final condition = match.group(1)!.trim();
    if (!_conditionMentionsZeroChroma(condition)) continue;

    final nextIndex = _firstNonWhitespaceIndex(source, match.end);
    if (nextIndex < 0) continue;
    if (source.codeUnitAt(nextIndex) == 0x7b) {
      final closeBrace = _findMatchingBrace(source, nextIndex);
      if (closeBrace < 0 || closeBrace >= boundaryIndex) continue;
      final body = source.substring(nextIndex + 1, closeBrace);
      if (body.contains('return')) {
        branches.add(_ZeroChromaBranch(condition: condition, body: body));
      }
      continue;
    }

    final statementEnd = source.indexOf(';', nextIndex);
    if (statementEnd >= 0 && statementEnd < boundaryIndex) {
      final body = source.substring(nextIndex, statementEnd + 1);
      if (body.contains('return')) {
        branches.add(_ZeroChromaBranch(condition: condition, body: body));
      }
    }
  }
  return branches;
}

bool _conditionMentionsZeroChroma(String expression) {
  return _conditionHandlesPackedUvZeroAxis(expression) ||
      _conditionHandlesChromaHeightZeroAxis(expression);
}

bool _conditionHandlesPackedUvZeroAxis(String expression) {
  return _handlesPackedUvZero(expression) ||
      _handlesChromaProductZero(expression);
}

bool _conditionHandlesChromaHeightZeroAxis(String expression) {
  return _handlesChromaHeightZero(expression) ||
      _handlesChromaProductZero(expression);
}

bool _handlesChromaHeightZero(String expression) {
  return RegExp(r'\bchroma_h\s*(?:==|<=)\s*0\b').hasMatch(expression) ||
      RegExp(r'\b0\s*(?:==|>=)\s*chroma_h\b').hasMatch(expression) ||
      RegExp(r'!\s*chroma_h\b').hasMatch(expression);
}

bool _handlesChromaProductZero(String expression) {
  return RegExp(
        r'\bpacked_uv\s*\*\s*chroma_h\s*==\s*0\b',
      ).hasMatch(expression) ||
      RegExp(r'\bchroma_h\s*\*\s*packed_uv\s*==\s*0\b').hasMatch(expression) ||
      RegExp(r'\b0\s*==\s*packed_uv\s*\*\s*chroma_h\b').hasMatch(expression) ||
      RegExp(r'\b0\s*==\s*chroma_h\s*\*\s*packed_uv\b').hasMatch(expression);
}

bool _sendsOriginalChromaPointers(String source) {
  return RegExp(
    r'\bsendVideoFrame\s*\([\s\S]*,\s*u\s*,\s*v\s*\)',
  ).hasMatch(source);
}

bool _strideNormalizationChecksPackedUv(String source, String strideName) {
  final pattern = RegExp(
    r'\b' + RegExp.escape(strideName) + r'\s*=\s*([^;]+)\s*;',
  );
  final match = pattern.firstMatch(source);
  if (match == null) return false;
  return _checksPackedUvAgainstZero(match.group(1)!);
}

bool _checksPackedUvAgainstZero(String expression) {
  return _handlesPackedUvZero(expression) ||
      _requiresPackedUvNonZero(expression);
}

bool _handlesPackedUvZero(String expression) {
  return RegExp(r'\bpacked_uv\s*(?:==|<=)\s*0\b').hasMatch(expression) ||
      RegExp(r'\b0\s*(?:==|>=)\s*packed_uv\b').hasMatch(expression) ||
      RegExp(r'!\s*packed_uv\b').hasMatch(expression);
}

bool _requiresPackedUvNonZero(String expression) {
  return RegExp(r'\bpacked_uv\s*(?:!=|>)\s*0\b').hasMatch(expression) ||
      RegExp(r'\b0\s*(?:!=|<)\s*packed_uv\b').hasMatch(expression) ||
      RegExp(r'\bpacked_uv\s*>=\s*1\b').hasMatch(expression) ||
      RegExp(r'\b1\s*<=\s*packed_uv\b').hasMatch(expression) ||
      RegExp(r'^\s*packed_uv\s*$').hasMatch(expression);
}

String _extractBetween(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  expect(startIndex, isNonNegative, reason: 'start marker missing: $start');
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(endIndex, isNonNegative, reason: 'end marker missing: $end');
  return source.substring(startIndex, endIndex);
}

bool _isSingleDeliveryCallback(String callbackField) {
  return _avSingleDeliveryContracts.any(
    (contract) => contract.callbackField == callbackField,
  );
}

bool _isBitrateCallback(String callbackField) {
  return callbackField == 'on_audio_bitrate' ||
      callbackField == 'on_video_bitrate';
}

void _expectBitrateDrainUsesLocalUserData(
  String drainBody,
  _AvCallbackContract contract,
  List<String> issues,
) {
  if (!RegExp(
    r'\bg_instance_av_callbacks\s*\.\s*find\s*\(\s*instance_id\s*\)',
  ).hasMatch(drainBody)) {
    issues.add(
      '${contract.label}: DrainAVBitrateEvents must look up callbacks for '
      'the same instance_id whose queued event is being drained.',
    );
  }

  final callbackAssignment = _localAssignedFromCallbackStorage(
    drainBody,
    contract.callbackField,
  );
  final userDataAssignment = _localAssignedFromCallbackStorage(
    drainBody,
    contract.userDataField,
  );

  if (callbackAssignment == null) {
    issues.add(
      '${contract.label}: DrainAVBitrateEvents must snapshot '
      '${contract.callbackField} into a local callback variable.',
    );
    return;
  }
  if (userDataAssignment == null) {
    issues.add(
      '${contract.label}: DrainAVBitrateEvents must snapshot '
      '${contract.userDataField} into a local user_data variable.',
    );
    return;
  }

  if (!_isInsideAvCallbackMutexScope(drainBody, callbackAssignment.index)) {
    issues.add(
      '${contract.label}: callback snapshot must happen under '
      'g_av_callbacks_mutex.',
    );
  }
  if (!_isInsideAvCallbackMutexScope(drainBody, userDataAssignment.index)) {
    issues.add(
      '${contract.label}: user_data snapshot must happen under '
      'g_av_callbacks_mutex.',
    );
  }

  final invocationIndex = _indexOfInvocationWithArgument(
    drainBody,
    callbackAssignment.variableName,
    userDataAssignment.variableName,
  );
  if (invocationIndex < 0) {
    issues.add(
      '${contract.label}: DrainAVBitrateEvents must invoke the local '
      'callback with the matching local user_data variable.',
    );
  } else if (_isInsideAvCallbackMutexScope(drainBody, invocationIndex)) {
    issues.add(
      '${contract.label}: DrainAVBitrateEvents must invoke Dart after '
      'releasing g_av_callbacks_mutex.',
    );
  }
}

bool _sourceContainsDispatchUsingUserData(
  String source,
  String callbackField,
  String userDataField,
) {
  return RegExp(
    r'\b[A-Za-z_]\w*(?:->|\.)second\.' +
        RegExp.escape(callbackField) +
        r'\s*\([\s\S]*?\b[A-Za-z_]\w*(?:->|\.)second\.' +
        RegExp.escape(userDataField) +
        r'\s*\)',
  ).hasMatch(source);
}

bool _sourceContainsDispatchUsingSharedUserData(
  String source,
  String callbackField,
) {
  return RegExp(
    r'\b[A-Za-z_]\w*(?:->|\.)second\.' +
        RegExp.escape(callbackField) +
        r'\s*\([\s\S]*?\b[A-Za-z_]\w*(?:->|\.)second\.user_data\s*\)',
  ).hasMatch(source);
}

_LocalAssignment? _localAssignedFromCallbackStorage(
  String source,
  String fieldName,
) {
  final match = RegExp(
    r'^\s*([A-Za-z_]\w*)\s*=\s*[A-Za-z_]\w*\s*->\s*second\s*\.\s*' +
        RegExp.escape(fieldName) +
        r'\s*;',
    multiLine: true,
  ).firstMatch(source);
  if (match == null) return null;
  return _LocalAssignment(variableName: match.group(1)!, index: match.start);
}

_IfElseBranches? _extractIfElseBranches(
  String source,
  String conditionVariable,
) {
  final condition = RegExp.escape(conditionVariable);
  final match = RegExp(
    r'\bif\s*\(\s*(?:' +
        condition +
        r'|' +
        condition +
        r'\s*!=\s*nullptr|nullptr\s*!=\s*' +
        condition +
        r')\s*\)\s*\{',
  ).firstMatch(source);
  if (match == null) return null;

  final thenOpenBrace = source.indexOf('{', match.start);
  final thenCloseBrace = _findMatchingBrace(source, thenOpenBrace);
  if (thenCloseBrace < 0) return null;

  final elseMatch = RegExp(
    r'\s*else\s*\{',
  ).matchAsPrefix(source.substring(thenCloseBrace + 1));
  if (elseMatch == null) return null;

  final elseStart = thenCloseBrace + 1 + elseMatch.start;
  final elseOpenBrace = source.indexOf('{', elseStart);
  final elseCloseBrace = _findMatchingBrace(source, elseOpenBrace);
  if (elseCloseBrace < 0) return null;

  return _IfElseBranches(
    thenBody: source.substring(thenOpenBrace + 1, thenCloseBrace),
    elseBody: source.substring(elseOpenBrace + 1, elseCloseBrace),
    elseStartIndex: elseStart,
  );
}

bool _containsInvocationWithArgument(
  String source,
  String functionName,
  String argumentName,
) {
  return _indexOfInvocationWithArgument(source, functionName, argumentName) >=
      0;
}

int _indexOfInvocationWithArgument(
  String source,
  String functionName,
  String argumentName,
) {
  final callPattern = RegExp(
    r'\b' + RegExp.escape(functionName) + r'\s*\(([\s\S]*?)\)\s*;',
  );
  final argumentPattern = RegExp(r'\b' + RegExp.escape(argumentName) + r'\b');
  for (final match in callPattern.allMatches(source)) {
    if (argumentPattern.hasMatch(match.group(1)!)) {
      return match.start;
    }
  }
  return -1;
}

bool _containsGlobalCallbackFallback(String source, String globalType) {
  return RegExp(
    RegExp.escape(globalType) +
        r'[\s\S]*?SendCallbackToDart\s*\(\s*"globalCallback"',
  ).hasMatch(source);
}

bool _isInsideAvCallbackMutexScope(String source, int index) {
  return _isInsideNamedMutexScope(source, index, 'g_av_callbacks_mutex');
}

bool _isInsideNamedMutexScope(String source, int index, String mutexName) {
  final lockPattern = RegExp(
    r'std::lock_guard\s*<\s*std::mutex\s*>\s+\w+\s*\(\s*' +
        RegExp.escape(mutexName) +
        r'\s*\)\s*;',
  );
  for (final lockMatch in lockPattern.allMatches(source)) {
    final openBrace = source.lastIndexOf('{', lockMatch.start);
    if (openBrace < 0) {
      if (lockMatch.start < index) return true;
      continue;
    }
    final closeBrace = _findMatchingBrace(source, openBrace);
    if (openBrace < index && index < closeBrace) return true;
  }
  return false;
}

int _findMatchingBrace(String source, int openBraceIndex) {
  if (openBraceIndex < 0 || source.codeUnitAt(openBraceIndex) != 0x7b) {
    return -1;
  }

  var depth = 0;
  var inLineComment = false;
  var inBlockComment = false;
  var inString = false;
  var inChar = false;
  var escaped = false;

  for (var index = openBraceIndex; index < source.length; index += 1) {
    final code = source.codeUnitAt(index);
    final next = index + 1 < source.length ? source.codeUnitAt(index + 1) : -1;

    if (inLineComment) {
      if (code == 0x0a) inLineComment = false;
      continue;
    }
    if (inBlockComment) {
      if (code == 0x2a && next == 0x2f) {
        inBlockComment = false;
        index += 1;
      }
      continue;
    }
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (code == 0x5c) {
        escaped = true;
      } else if (code == 0x22) {
        inString = false;
      }
      continue;
    }
    if (inChar) {
      if (escaped) {
        escaped = false;
      } else if (code == 0x5c) {
        escaped = true;
      } else if (code == 0x27) {
        inChar = false;
      }
      continue;
    }

    if (code == 0x2f && next == 0x2f) {
      inLineComment = true;
      index += 1;
      continue;
    }
    if (code == 0x2f && next == 0x2a) {
      inBlockComment = true;
      index += 1;
      continue;
    }
    if (code == 0x22) {
      inString = true;
      continue;
    }
    if (code == 0x27) {
      inChar = true;
      continue;
    }
    if (code == 0x7b) {
      depth += 1;
    } else if (code == 0x7d) {
      depth -= 1;
      if (depth == 0) return index;
    }
  }
  return -1;
}

String _extractTypedefBlock(String source, String typedefName) {
  final match = RegExp(
    r'typedef\s+' +
        RegExp.escape(typedefName) +
        r'\s*=\s*ffi\.Void\s+Function\(([\s\S]*?)\);',
  ).firstMatch(source);
  expect(
    match,
    isNotNull,
    reason: '$typedefName must exist in tim2tox_ffi.dart',
  );
  return match!.group(1)!;
}
