import 'package:geolocator/geolocator.dart';

import '../util/platform_utils.dart';

/// One position fix.
class LocationFix {
  const LocationFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.at,
  });
  final double latitude;
  final double longitude;
  final double accuracyM;
  final DateTime at;
}

enum LocationPermissionState {
  granted,
  denied,
  deniedForever,

  /// The OS location service itself is off.
  serviceDisabled,

  /// The platform cannot tell (no provider, plugin error).
  unavailable,
}

/// The device-location seam. Everything above it (settings switch, location
/// message, nearby) talks to this interface, so tests inject a fake and no
/// test ever touches the OS.
abstract class LocationSource {
  Future<LocationPermissionState> permissionState();

  /// Asks the OS (shows the system prompt where applicable). Prompts on every
  /// platform toxee ships, desktop included: macOS has CoreLocation, Linux
  /// GeoClue, Windows the Location API.
  Future<LocationPermissionState> requestPermission();

  Future<LocationFix?> currentFix({Duration timeout = const Duration(seconds: 15)});

  /// Opens the OS page where the user can grant the permission.
  Future<bool> openSettings();
}

class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  @override
  Future<LocationPermissionState> permissionState() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationPermissionState.serviceDisabled;
      }
      return _map(await Geolocator.checkPermission());
    } catch (_) {
      return LocationPermissionState.unavailable;
    }
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationPermissionState.serviceDisabled;
      }
      final current = await Geolocator.checkPermission();
      if (current == LocationPermission.deniedForever) {
        return LocationPermissionState.deniedForever;
      }
      if (current == LocationPermission.always ||
          current == LocationPermission.whileInUse) {
        return LocationPermissionState.granted;
      }
      return _map(await Geolocator.requestPermission());
    } catch (_) {
      return LocationPermissionState.unavailable;
    }
  }

  @override
  Future<LocationFix?> currentFix(
      {Duration timeout = const Duration(seconds: 15)}) async {
    try {
      final settings = PlatformUtils.isAndroid
          // No Play Services: the framework LocationManager works on every
          // Android build toxee targets, GMS or not.
          ? AndroidSettings(
              accuracy: LocationAccuracy.medium,
              forceLocationManager: true,
              timeLimit: timeout,
            )
          : LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: timeout);
      final p = await Geolocator.getCurrentPosition(locationSettings: settings);
      return LocationFix(
        latitude: p.latitude,
        longitude: p.longitude,
        accuracyM: p.accuracy,
        at: p.timestamp,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> openSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  static LocationPermissionState _map(LocationPermission p) {
    switch (p) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return LocationPermissionState.granted;
      case LocationPermission.denied:
        return LocationPermissionState.denied;
      case LocationPermission.deniedForever:
        return LocationPermissionState.deniedForever;
      case LocationPermission.unableToDetermine:
        return LocationPermissionState.unavailable;
    }
  }
}
