part of '../prefs.dart';

/// Location + People-nearby switches (doc/plans/LOCATION_AND_NEARBY_PLAN.md
/// §4.5). Account-scoped like the auto-accept switches, default OFF: no code
/// path reads the OS position while `location_enabled` is false, and nearby
/// visibility additionally needs `nearby_visible`.
extension LocationPrefs on Prefs {
  static const _kLocationEnabled = 'acct_location_enabled';
  static const _kNearbyVisible = 'acct_nearby_visible';
  static const _kNearbyPrivacyShown = 'acct_nearby_privacy_shown';

  static Future<bool> _getScopedBool(String baseKey, String? toxId) async {
    final p = await Prefs._getPrefs();
    var effectiveToxId = toxId;
    if (effectiveToxId == null || effectiveToxId.isEmpty) {
      effectiveToxId = await Prefs.getCurrentAccountToxId();
    }
    if (effectiveToxId == null || effectiveToxId.isEmpty) return false;
    return p.getBool(Prefs._scopedKey(baseKey, effectiveToxId)) ?? false;
  }

  static Future<void> _setScopedBool(
      String baseKey, bool value, String? toxId) async {
    final p = await Prefs._getPrefs();
    var effectiveToxId = toxId;
    if (effectiveToxId == null || effectiveToxId.isEmpty) {
      effectiveToxId = await Prefs.getCurrentAccountToxId();
    }
    if (effectiveToxId == null || effectiveToxId.isEmpty) return;
    await p.setBool(Prefs._scopedKey(baseKey, effectiveToxId), value);
  }

  /// Master switch: may toxee read this device's position at all.
  static Future<bool> getLocationEnabled([String? toxId]) =>
      _getScopedBool(_kLocationEnabled, toxId);
  static Future<void> setLocationEnabled(bool value, [String? toxId]) =>
      _setScopedBool(_kLocationEnabled, value, toxId);

  /// Visible to people nearby (only meaningful while the master is on).
  static Future<bool> getNearbyVisible([String? toxId]) =>
      _getScopedBool(_kNearbyVisible, toxId);
  static Future<void> setNearbyVisible(bool value, [String? toxId]) =>
      _setScopedBool(_kNearbyVisible, value, toxId);

  /// The nearby privacy notice was accepted once for this account (plan
  /// §4.5: shown once, not on every off → on).
  static Future<bool> getNearbyPrivacyShown([String? toxId]) =>
      _getScopedBool(_kNearbyPrivacyShown, toxId);
  static Future<void> setNearbyPrivacyShown(bool value, [String? toxId]) =>
      _setScopedBool(_kNearbyPrivacyShown, value, toxId);
}
