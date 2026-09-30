import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/bootstrap/single_session_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('toxee/session_owner');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<String> calls;

  void answerClaim(Object? Function() claim) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'claim') return claim();
      return null;
    });
  }

  setUp(() => calls = <String>[]);
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('the first engine claims the session and starts', () async {
    answerClaim(() => true);
    expect(await SingleSessionGuard.claimOrYield(isAndroid: true), isTrue);
    expect(calls, ['claim']);
  });

  test('a second engine yields to the owner and does not start', () async {
    answerClaim(() => false);
    expect(await SingleSessionGuard.claimOrYield(isAndroid: true), isFalse);
    expect(calls, ['claim', 'yieldToOwner']);
  });

  test('other platforms never ask', () async {
    answerClaim(() => false);
    expect(await SingleSessionGuard.claimOrYield(isAndroid: false), isTrue);
    expect(calls, isEmpty);
  });

  test('a missing or failing guard never blocks startup', () async {
    expect(await SingleSessionGuard.claimOrYield(isAndroid: true), isTrue);
    answerClaim(() => throw PlatformException(code: 'boom'));
    expect(await SingleSessionGuard.claimOrYield(isAndroid: true), isTrue);
  });

  test('a known non-owner never starts, even if yielding fails', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'claim') return false;
      throw PlatformException(code: 'yield-failed');
    });
    expect(await SingleSessionGuard.claimOrYield(isAndroid: true), isFalse);
    expect(calls, ['claim', 'yieldToOwner']);
  });
}
