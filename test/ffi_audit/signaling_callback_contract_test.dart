import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _dartCompatSignalingPath =
    'third_party/tim2tox/ffi/dart_compat_signaling.cpp';
const _tim2toxFfiPath = 'third_party/tim2tox/ffi/tim2tox_ffi.cpp';
const _signalingManagerImplPath =
    'third_party/tim2tox/source/V2TIMSignalingManagerImpl.cpp';
const _messageManagerImplPath =
    'third_party/tim2tox/source/V2TIMMessageManagerImpl.cpp';
const _managerImplHeaderPath = 'third_party/tim2tox/source/V2TIMManagerImpl.h';

void main() {
  late final String dartCompatSignalingSource;
  late final String tim2toxFfiSource;
  late final String signalingManagerImplSource;
  late final String messageManagerImplSource;
  late final String managerImplHeaderSource;

  setUpAll(() {
    dartCompatSignalingSource = _readSource(_dartCompatSignalingPath);
    tim2toxFfiSource = _readSource(_tim2toxFfiPath);
    signalingManagerImplSource = _readSource(_signalingManagerImplPath);
    messageManagerImplSource = _readSource(_messageManagerImplPath);
    managerImplHeaderSource = _readSource(_managerImplHeaderPath);
  });

  test('binary-replacement signaling ABI and invite-id JSON stay stable', () {
    for (final signature in _stableDartSignalingSignatures) {
      expect(
        dartCompatSignalingSource,
        contains(signature),
        reason: 'binary replacement depends on the exact C ABI: $signature',
      );
    }

    final inviteBody = _cFunctionBody(dartCompatSignalingSource, 'DartInvite');
    final groupInviteBody = _cFunctionBody(
      dartCompatSignalingSource,
      'DartInviteInGroup',
    );
    for (final body in [inviteBody, groupInviteBody]) {
      expect(
        body,
        contains('"{\\"invite_id\\":\\""'),
        reason: 'Dart apiCallback payloads must keep the invite_id JSON key',
      );
      expect(
        body,
        isNot(contains('"{\\"inviteID\\":\\""')),
        reason: 'do not drift to the V2TIM object field name on the C ABI',
      );
    }
  });

  test(
    'binary-replacement invite IDs use thread-local return storage, not an unbounded global map',
    () {
      final preExtern = dartCompatSignalingSource.substring(
        0,
        dartCompatSignalingSource.indexOf('extern "C"'),
      );
      expect(
        preExtern,
        isNot(
          contains(
            'static std::map<std::string, std::string> g_invite_id_storage',
          ),
        ),
        reason:
            'returned const char* invite IDs must not accumulate in process-global storage',
      );
      expect(
        preExtern,
        isNot(contains('static std::mutex g_invite_id_storage_mutex')),
        reason:
            'thread-local return storage does not need a global invite-id map mutex',
      );
      expect(
        dartCompatSignalingSource,
        contains(
          RegExp(
            r'thread_local\s+std::string\s+\w*invite\w*',
            caseSensitive: false,
          ),
        ),
        reason:
            'the returned pointer should be C-owned storage valid until the next same-thread invite return',
      );

      for (final functionName in ['DartInvite', 'DartInviteInGroup']) {
        final body = _cFunctionBody(dartCompatSignalingSource, functionName);
        expect(
          body,
          isNot(contains('storage_key')),
          reason:
              '$functionName should not synthesize global storage keys for returned invite IDs',
        );
        expect(
          body,
          isNot(contains('g_invite_id_storage')),
          reason:
              '$functionName should return same-thread storage, not a global map entry',
        );
        expect(
          body,
          isNot(contains('time(nullptr)')),
          reason:
              '$functionName return ownership must not depend on timestamp-keyed global state',
        );
      }
    },
  );

  test('RunOnEventThread-delayed invite callback uses self ownership', () {
    final inviteImplBody = _cppMethodBody(
      signalingManagerImplSource,
      'V2TIMSignalingManagerImpl::Invite',
    );
    expect(
      inviteImplBody,
      contains('RunOnEventThread<V2TIMString>'),
      reason:
          'DartInvite must be treated as event-thread-delayed for callback ownership',
    );

    final dartBody = _cFunctionBody(dartCompatSignalingSource, 'DartInvite');
    _expectDelayedCallbackOwnership(
      dartBody: dartBody,
      callbackClassName: 'DartInviteCallback',
      dartFunctionName: 'DartInvite',
    );
  });

  test('DartInviteCallback synchronizes delayed success state', () {
    final inviteImplBody = _cppMethodBody(
      signalingManagerImplSource,
      'V2TIMSignalingManagerImpl::Invite',
    );
    _expectInviteIsRunOnEventThreadDelayed(inviteImplBody);

    final dartBody = _cFunctionBody(dartCompatSignalingSource, 'DartInvite');
    final callbackClassBody = _classBody(dartBody, 'DartInviteCallback');
    _expectSuccessStateSynchronized(
      callbackClassBody: callbackClassBody,
      callbackName: 'DartInviteCallback',
    );
  });

  test('platform signaling invite owns its callback across delayed Invite', () {
    final inviteImplBody = _cppMethodBody(
      signalingManagerImplSource,
      'V2TIMSignalingManagerImpl::Invite',
    );
    _expectInviteIsRunOnEventThreadDelayed(inviteImplBody);

    final ffiBody = _cFunctionBody(
      tim2toxFfiSource,
      'tim2tox_ffi_signaling_invite',
    );
    expect(
      ffiBody,
      isNot(contains(RegExp(r'Invite\s*\([^;]*&callback'))),
      reason:
          'tim2tox_ffi_signaling_invite must not pass a stack callback into delayed Invite',
    );
    expect(
      ffiBody,
      isNot(contains(RegExp(r'new\s+\w*Callback\w*'))),
      reason:
          'tim2tox_ffi_signaling_invite must not replace the UAF with a raw heap leak',
    );
    expect(
      ffiBody,
      isNot(contains('.release()')),
      reason:
          'tim2tox_ffi_signaling_invite must not release smart ownership into a raw callback pointer',
    );
    expect(
      ffiBody,
      isNot(contains('delete this')),
      reason:
          'tim2tox_ffi_signaling_invite must not use callback self-delete lifetime management',
    );
    expect(
      ffiBody,
      contains('RunOnEventThread'),
      reason:
          'tim2tox_ffi_signaling_invite needs an outer event-thread handoff that holds callback ownership through late execution',
    );
    expect(
      ffiBody,
      contains(RegExp(r'std::(?:make_)?shared_ptr|std::make_shared')),
      reason:
          'tim2tox_ffi_signaling_invite delayed callback ownership should be shared with queued work',
    );
    expect(
      ffiBody,
      contains(RegExp(r'\[[^\]]*callback[^\]]*\]')),
      reason:
          'the event-thread lambda should capture the callback owner, not a borrowed stack address',
    );
  });

  test('platform signaling invite synchronizes callback terminal state', () {
    final inviteImplBody = _cppMethodBody(
      signalingManagerImplSource,
      'V2TIMSignalingManagerImpl::Invite',
    );
    _expectInviteIsRunOnEventThreadDelayed(inviteImplBody);

    final ffiBody = _cFunctionBody(
      tim2toxFfiSource,
      'tim2tox_ffi_signaling_invite',
    );
    final callbackClassBody = _firstLocalCallbackClassBody(
      ffiBody,
      'V2TIMCallback',
    );
    _expectSuccessStateSynchronized(
      callbackClassBody: callbackClassBody,
      callbackName: 'tim2tox_ffi_signaling_invite callback',
    );
    expect(
      _containsAny(callbackClassBody, [
        'TerminalCallbackGate',
        'std::once_flag',
        'std::atomic',
        'std::mutex',
      ]),
      isTrue,
      reason:
          'tim2tox_ffi_signaling_invite callback terminal state crosses the event-thread boundary and must be synchronized',
    );
  });

  test(
    'RunOnEventThread timeout cannot report failure before side-effecting task settles',
    () {
      final runOnEventThreadBody = _runOnEventThreadBody(
        managerImplHeaderSource,
      );

      _expectRunOnEventThreadUsesAtomicTimeoutStateMachine(
        runOnEventThreadBody,
      );
    },
  );

  test('platform signaling invite logs omit identifiers and payloads', () {
    final ffiBody = _cFunctionBody(
      tim2toxFfiSource,
      'tim2tox_ffi_signaling_invite',
    );
    final logStatements = _v2timLogStatements(ffiBody).join('\n');
    expect(
      logStatements,
      isNot(contains(RegExp(r'\binvitee\b'))),
      reason: 'platform invite logs must not include invitee identifiers',
    );
    expect(
      logStatements,
      isNot(contains(RegExp(r'\bdata\b'))),
      reason: 'platform invite logs must not include signaling payload data',
    );
    expect(
      logStatements,
      isNot(contains(RegExp(r'\binvite_?id\b'))),
      reason: 'platform invite logs must not include generated invite IDs',
    );
    expect(
      logStatements,
      isNot(contains('out_invite_id')),
      reason: 'platform invite logs should stay type/status-only',
    );
  });

  test(
    'truly synchronous signaling wrappers use caller-owned one-shot callbacks',
    () {
      for (final contract in _synchronousCallbackContracts) {
        final dartBody = _cFunctionBody(
          dartCompatSignalingSource,
          contract.dartFunction,
        );
        final cxxBody = _cppMethodBody(
          signalingManagerImplSource,
          contract.cxxMethod,
        );
        expect(
          cxxBody,
          isNot(contains('RunOnEventThread')),
          reason:
              '${contract.dartFunction} is only classified as caller-owned because its C++ method is synchronous',
        );
        _expectSynchronousCallbackOwnership(
          dartBody: dartBody,
          callbackClassName: contract.callbackClass,
          dartFunctionName: contract.dartFunction,
        );
      }
    },
  );

  test('DartGetSignalingInfo treats synchronous FindMessages as caller-owned', () {
    final findMessagesBody = _cppMethodBody(
      messageManagerImplSource,
      'V2TIMMessageManagerImpl::FindMessages',
    );
    _expectFindMessagesIsSynchronous(findMessagesBody);

    final dartBody = _cFunctionBody(
      dartCompatSignalingSource,
      'DartGetSignalingInfo',
    );
    expect(
      dartBody,
      isNot(contains('std::shared_ptr<DartGetSignalingInfoCallback>')),
      reason:
          'DartGetSignalingInfo must not self-own when FindMessages terminal-calls inline',
    );
    expect(
      dartBody,
      isNot(contains('self_')),
      reason:
          'DartGetSignalingInfo must not create a callback self-cycle for synchronous FindMessages',
    );
    expect(
      dartBody,
      isNot(contains('callback.get()')),
      reason:
          'DartGetSignalingInfo must not pass a raw pointer borrowed from shared ownership',
    );
    _expectSynchronousCallbackOwnership(
      dartBody: dartBody,
      callbackClassName: 'DartGetSignalingInfoCallback',
      dartFunctionName: 'DartGetSignalingInfo',
    );
  });

  test(
    'DartGetSignalingInfo fails closed if FindMessages gives no terminal callback',
    () {
      final findMessagesBody = _cppMethodBody(
        messageManagerImplSource,
        'V2TIMMessageManagerImpl::FindMessages',
      );
      _expectFindMessagesIsSynchronous(findMessagesBody);

      final dartBody = _cFunctionBody(
        dartCompatSignalingSource,
        'DartGetSignalingInfo',
      );
      expect(
        dartBody,
        contains(RegExp(r'callback\.terminal_attempt_count\(\)\s*==\s*0')),
        reason:
            'DartGetSignalingInfo should detect a synchronous FindMessages return without OnSuccess/OnError',
      );
      expect(
        dartBody,
        contains(
          'SendNoTerminalCallbackFailure(user_data, "DartGetSignalingInfo")',
        ),
        reason:
            'DartGetSignalingInfo should fail closed instead of leaving Dart completers pending',
      );
    },
  );
}

const _stableDartSignalingSignatures = [
  'const char* DartInvite(const char* invitee, const char* data, bool online_user_only, const char* json_offline_push_info, int timeout, const char* invite_id_buffer, void* user_data)',
  'const char* DartInviteInGroup(const char* group_id, const char* json_invitee_array, const char* data, bool online_user_only, int timeout, const char* invite_id_buffer, void* user_data)',
  'int DartCancel(const char* invite_id, const char* data, void* user_data)',
  'int DartAccept(const char* invite_id, const char* data, void* user_data)',
  'int DartReject(const char* invite_id, const char* data, void* user_data)',
  'int DartGetSignalingInfo(const char* json_msg, void* user_data)',
  'int DartModifyInvitation(const char* invite_id, const char* data, void* user_data)',
];

const _synchronousCallbackContracts = [
  _CallbackContract(
    dartFunction: 'DartInviteInGroup',
    cxxMethod: 'V2TIMSignalingManagerImpl::InviteInGroup',
    callbackClass: 'DartInviteInGroupCallback',
  ),
  _CallbackContract(
    dartFunction: 'DartCancel',
    cxxMethod: 'V2TIMSignalingManagerImpl::Cancel',
    callbackClass: 'DartCancelCallback',
  ),
  _CallbackContract(
    dartFunction: 'DartAccept',
    cxxMethod: 'V2TIMSignalingManagerImpl::Accept',
    callbackClass: 'DartAcceptCallback',
  ),
  _CallbackContract(
    dartFunction: 'DartReject',
    cxxMethod: 'V2TIMSignalingManagerImpl::Reject',
    callbackClass: 'DartRejectCallback',
  ),
  _CallbackContract(
    dartFunction: 'DartModifyInvitation',
    cxxMethod: 'V2TIMSignalingManagerImpl::ModifyInvitation',
    callbackClass: 'DartModifyInvitationCallback',
  ),
];

String _readSource(String relativePath) {
  final file = File(relativePath);
  expect(file.existsSync(), isTrue, reason: '$relativePath must exist');
  return file.readAsStringSync();
}

String _cFunctionBody(String source, String functionName) {
  final declaration = RegExp(
    r'(?:const\s+char\s*\*|int)\s+'
    '$functionName'
    r'\s*\(',
  ).firstMatch(source);
  if (declaration == null) {
    fail('could not find C function $functionName');
  }
  final openBrace = source.indexOf('{', declaration.start);
  if (openBrace == -1) {
    fail('could not find body for C function $functionName');
  }
  return _bracedBlock(source, openBrace);
}

String _cppMethodBody(String source, String qualifiedMethodName) {
  final start = source.indexOf('$qualifiedMethodName(');
  if (start == -1) {
    fail('could not find C++ method $qualifiedMethodName');
  }
  final openBrace = source.indexOf('{', start);
  if (openBrace == -1) {
    fail('could not find body for C++ method $qualifiedMethodName');
  }
  return _bracedBlock(source, openBrace);
}

String _runOnEventThreadBody(String source) {
  final declaration = RegExp(
    r'RunOnEventThread\s*\(\s*std::function<R\(\)>\s+f\s*\)',
  ).firstMatch(source);
  if (declaration == null) {
    fail('could not find V2TIMManagerImpl::RunOnEventThread');
  }
  final openBrace = source.indexOf('{', declaration.start);
  if (openBrace == -1) {
    fail('could not find body for V2TIMManagerImpl::RunOnEventThread');
  }
  return _bracedBlock(source, openBrace);
}

String _classBody(String source, String className) {
  final start = source.indexOf('class $className');
  if (start == -1) {
    fail('could not find callback class $className');
  }
  final openBrace = source.indexOf('{', start);
  if (openBrace == -1) {
    fail('could not find body for callback class $className');
  }
  return _bracedBlock(source, openBrace);
}

String _bracedBlock(String source, int openBrace) {
  var depth = 0;
  var inLineComment = false;
  var inBlockComment = false;
  var inString = false;
  var inChar = false;
  var escaped = false;

  for (var index = openBrace; index < source.length; index++) {
    final codeUnit = source.codeUnitAt(index);
    final next = index + 1 < source.length ? source.codeUnitAt(index + 1) : -1;

    if (inLineComment) {
      if (codeUnit == _lineFeed) inLineComment = false;
      continue;
    }
    if (inBlockComment) {
      if (codeUnit == _asterisk && next == _slash) {
        inBlockComment = false;
        index++;
      }
      continue;
    }
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (codeUnit == _backslash) {
        escaped = true;
      } else if (codeUnit == _doubleQuote) {
        inString = false;
      }
      continue;
    }
    if (inChar) {
      if (escaped) {
        escaped = false;
      } else if (codeUnit == _backslash) {
        escaped = true;
      } else if (codeUnit == _singleQuote) {
        inChar = false;
      }
      continue;
    }

    if (codeUnit == _slash && next == _slash) {
      inLineComment = true;
      index++;
      continue;
    }
    if (codeUnit == _slash && next == _asterisk) {
      inBlockComment = true;
      index++;
      continue;
    }
    if (codeUnit == _doubleQuote) {
      inString = true;
      continue;
    }
    if (codeUnit == _singleQuote) {
      inChar = true;
      continue;
    }
    if (codeUnit == _openBrace) {
      depth++;
      continue;
    }
    if (codeUnit == _closeBrace) {
      depth--;
      if (depth == 0) return source.substring(openBrace + 1, index);
    }
  }

  fail('unterminated braced block');
}

void _expectSynchronousCallbackOwnership({
  required String dartBody,
  required String callbackClassName,
  required String dartFunctionName,
}) {
  expect(
    dartBody,
    isNot(contains('$callbackClassName* callback = new $callbackClassName')),
    reason:
        '$dartFunctionName is synchronous and must not leak a raw heap callback',
  );
  expect(
    dartBody,
    contains(RegExp('$callbackClassName\\s+callback\\s*\\(')),
    reason:
        '$dartFunctionName should keep its synchronous callback caller-owned',
  );
  expect(
    dartBody,
    contains('&callback'),
    reason:
        '$dartFunctionName should pass a borrowed callback only for this synchronous call',
  );
  expect(
    dartBody,
    isNot(contains('.release()')),
    reason:
        '$dartFunctionName must not smuggle raw callback ownership out of a smart owner',
  );
  expect(
    dartBody,
    isNot(contains('delete this')),
    reason:
        '$dartFunctionName must not use callback self-delete lifetime management',
  );

  final classBody = _classBody(dartBody, callbackClassName);
  expect(
    _containsAny(classBody, [
      'TerminalCallbackGate',
      'std::once_flag',
      'std::atomic',
    ]),
    isTrue,
    reason:
        '$dartFunctionName callback should gate success/error as a one-shot terminal result',
  );
  expect(
    _containsAny(classBody, ['TryComplete()', 'call_once', 'exchange(']),
    isTrue,
    reason:
        '$dartFunctionName callback should suppress duplicate terminal callbacks structurally',
  );
}

void _expectDelayedCallbackOwnership({
  required String dartBody,
  required String callbackClassName,
  required String dartFunctionName,
}) {
  expect(
    dartBody,
    isNot(contains('$callbackClassName* callback = new $callbackClassName')),
    reason:
        '$dartFunctionName must not leak a raw heap callback while waiting on the event thread',
  );
  expect(
    dartBody,
    isNot(contains(RegExp('$callbackClassName\\s+callback\\s*\\('))),
    reason:
        '$dartFunctionName cannot use a stack callback because RunOnEventThread may time out before the queued task drains',
  );
  expect(
    dartBody,
    isNot(contains('&callback')),
    reason:
        '$dartFunctionName delayed ownership must not pass a borrowed stack callback',
  );
  expect(
    dartBody,
    isNot(contains('.release()')),
    reason:
        '$dartFunctionName must not trade the leak for a raw released callback',
  );
  expect(
    dartBody,
    isNot(contains('delete this')),
    reason:
        '$dartFunctionName must not use callback self-delete lifetime management',
  );

  final classBody = _classBody(dartBody, callbackClassName);
  expect(
    _containsAny('$dartBody\n$classBody', [
      'std::shared_ptr',
      'shared_from_this',
      'self_',
      'SelfOwned',
      'KeepAlive',
    ]),
    isTrue,
    reason:
        '$dartFunctionName needs event-thread-safe self ownership that outlives a bounded RunOnEventThread timeout',
  );
  expect(
    _containsAny(classBody, [
      'TerminalCallbackGate',
      'std::once_flag',
      'std::atomic',
    ]),
    isTrue,
    reason:
        '$dartFunctionName delayed callback should still gate success/error as one-shot',
  );
  expect(
    _containsAny(classBody, ['TryComplete()', 'call_once', 'exchange(']),
    isTrue,
    reason:
        '$dartFunctionName delayed callback should suppress duplicate terminal callbacks structurally',
  );
}

void _expectInviteIsRunOnEventThreadDelayed(String inviteImplBody) {
  expect(
    inviteImplBody,
    contains('RunOnEventThread<V2TIMString>'),
    reason: 'Invite is delayed through V2TIMManagerImpl::RunOnEventThread',
  );
  expect(
    inviteImplBody,
    contains(RegExp(r'\[[^\]]*callback[^\]]*\]')),
    reason:
        'Invite captures the callback pointer into event-thread work, so callers must keep it alive through late execution',
  );
}

void _expectSuccessStateSynchronized({
  required String callbackClassBody,
  required String callbackName,
}) {
  expect(
    callbackClassBody,
    isNot(contains(RegExp(r'\bbool\s+\w*success\w*\b'))),
    reason:
        '$callbackName must not store cross-thread success state in a plain bool',
  );
  expect(
    _containsAny(callbackClassBody, [
      'std::atomic_bool',
      'std::atomic<bool>',
      'std::mutex',
      'std::lock_guard',
      'std::scoped_lock',
    ]),
    isTrue,
    reason: '$callbackName success state must be atomic or protected by a lock',
  );
}

void _expectRunOnEventThreadUsesAtomicTimeoutStateMachine(
  String runOnEventThreadBody,
) {
  final lowerBody = runOnEventThreadBody.toLowerCase();
  for (final state in ['pending', 'running', 'completed', 'cancelled']) {
    expect(
      lowerBody,
      contains(state),
      reason: 'RunOnEventThread queued work must explicitly model $state state',
    );
  }

  expect(
    runOnEventThreadBody,
    contains(RegExp(r'std::atomic\s*<|std::atomic_\w+')),
    reason:
        'RunOnEventThread task state crosses caller and event threads and must be atomic',
  );

  final pendingToRunningClaim = RegExp(
    r'compare_exchange_(?:strong|weak)\s*\([^;]*pending[\s\S]*running',
    caseSensitive: false,
  ).firstMatch(runOnEventThreadBody);
  expect(
    pendingToRunningClaim,
    isNotNull,
    reason:
        'queued work must atomically claim pending->running before invoking f',
  );
  final firstInvocation = runOnEventThreadBody.indexOf('f()');
  expect(
    firstInvocation,
    isNot(-1),
    reason: 'RunOnEventThread must still invoke the caller-provided function',
  );
  expect(
    pendingToRunningClaim!.start,
    lessThan(firstInvocation),
    reason: 'pending->running claim must happen before invoking f',
  );

  final timeoutPendingToCancelled = RegExp(
    r'wait_for[\s\S]*compare_exchange_(?:strong|weak)\s*\([^;]*pending[\s\S]*cancelled',
    caseSensitive: false,
  ).firstMatch(runOnEventThreadBody);
  expect(
    timeoutPendingToCancelled,
    isNotNull,
    reason:
        'timeout may only convert pending->cancelled atomically before returning a default result',
  );
  final defaultReturnAfterCancellation = RegExp(
    r'compare_exchange_(?:strong|weak)\s*\([^;]*pending[\s\S]*cancelled[\s\S]*return\s+(?:R\s*\{\s*\}|R\s*\(\s*\)|\{\s*\})\s*;',
    caseSensitive: false,
  ).firstMatch(runOnEventThreadBody);
  expect(
    defaultReturnAfterCancellation,
    isNotNull,
    reason:
        'default return is allowed only after successfully cancelling still-pending work',
  );

  expect(
    runOnEventThreadBody,
    contains(
      RegExp(
        r'compare_exchange_(?:strong|weak)\s*\([^;]*pending[\s\S]*cancelled[\s\S]*return\s+(?:R\s*\{\s*\}|R\s*\(\s*\)|\{\s*\})\s*;[\s\S]*(?:future\.get\(\)|future\.wait\(\))',
        caseSensitive: false,
      ),
    ),
    reason:
        'if timeout sees running/completed instead of cancellable pending work, caller must wait for the real future result',
  );
}

String _firstLocalCallbackClassBody(String source, String baseClassName) {
  final match = RegExp(
    r'class\s+(\w+)\s*:\s*public\s+' + RegExp.escape(baseClassName),
  ).firstMatch(source);
  if (match == null) {
    fail('could not find local callback class extending $baseClassName');
  }
  return _classBody(source, match.group(1)!);
}

Iterable<String> _v2timLogStatements(String source) {
  final statements = <String>[];
  var searchStart = 0;
  while (true) {
    final start = source.indexOf('V2TIM_LOG', searchStart);
    if (start == -1) return statements;
    final end = source.indexOf(';', start);
    if (end == -1) fail('unterminated V2TIM_LOG statement');
    statements.add(source.substring(start, end + 1));
    searchStart = end + 1;
  }
}

void _expectFindMessagesIsSynchronous(String findMessagesBody) {
  expect(
    findMessagesBody,
    isNot(contains('RunOnEventThread')),
    reason:
        'DartGetSignalingInfo can only borrow its callback while FindMessages stays synchronous',
  );
  expect(
    findMessagesBody,
    contains('callback->OnSuccess(result);'),
    reason:
        'FindMessages currently completes success inline after constructing the local result',
  );
  expect(
    findMessagesBody,
    contains('callback->OnError(ERR_INVALID_PARAMETERS'),
    reason:
        'FindMessages currently reports invalid input inline before returning',
  );
}

bool _containsAny(String source, Iterable<String> needles) {
  return needles.any(source.contains);
}

class _CallbackContract {
  const _CallbackContract({
    required this.dartFunction,
    required this.cxxMethod,
    required this.callbackClass,
  });

  final String dartFunction;
  final String cxxMethod;
  final String callbackClass;
}

const _lineFeed = 0x0a;
const _doubleQuote = 0x22;
const _singleQuote = 0x27;
const _asterisk = 0x2a;
const _slash = 0x2f;
const _backslash = 0x5c;
const _openBrace = 0x7b;
const _closeBrace = 0x7d;
