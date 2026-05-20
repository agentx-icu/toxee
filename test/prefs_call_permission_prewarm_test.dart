import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
  });

  test('call permission prewarm flag defaults false and round-trips', () async {
    expect(await Prefs.getCallPermissionsPrewarmed(), isFalse);

    await Prefs.setCallPermissionsPrewarmed(true);
    expect(await Prefs.getCallPermissionsPrewarmed(), isTrue);
  });
}
