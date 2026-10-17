// Pure Prefs: the two location switches are account-scoped and default OFF
// (doc/plans/LOCATION_AND_NEARBY_PLAN.md §4.5).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/util/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final a = 'A' * 64;
  final b = 'B' * 64;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults are off for every account', () async {
    expect(await LocationPrefs.getLocationEnabled(a), isFalse);
    expect(await LocationPrefs.getNearbyVisible(a), isFalse);
  });

  test('switches are scoped to the account', () async {
    await LocationPrefs.setLocationEnabled(true, a);
    await LocationPrefs.setNearbyVisible(true, a);
    expect(await LocationPrefs.getLocationEnabled(a), isTrue);
    expect(await LocationPrefs.getNearbyVisible(a), isTrue);
    expect(await LocationPrefs.getLocationEnabled(b), isFalse);
    expect(await LocationPrefs.getNearbyVisible(b), isFalse);
    await LocationPrefs.setLocationEnabled(false, a);
    expect(await LocationPrefs.getLocationEnabled(a), isFalse);
  });

  test('without a current account nothing is stored or read as on', () async {
    await LocationPrefs.setLocationEnabled(true);
    expect(await LocationPrefs.getLocationEnabled(), isFalse);
  });

  test('the privacy notice is remembered per account', () async {
    final a = 'A' * 76, b = 'B' * 76;
    expect(await LocationPrefs.getNearbyPrivacyShown(a), isFalse);
    await LocationPrefs.setNearbyPrivacyShown(true, a);
    expect(await LocationPrefs.getNearbyPrivacyShown(a), isTrue);
    expect(await LocationPrefs.getNearbyPrivacyShown(b), isFalse);
  });
}
