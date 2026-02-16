import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum LocationAccessStatus {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
  unavailable,
}

/// Captures device GPS coordinates for ledger metadata.
class LocationService {
  /// Checks and (optionally) requests foreground location permission.
  ///
  /// Returns a status describing whether location capture can proceed.
  Future<LocationAccessStatus> ensureLocationAccess({
    bool requestPermission = true,
  }) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (requestPermission && permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        return LocationAccessStatus.denied;
      }
      if (permission == LocationPermission.deniedForever) {
        return LocationAccessStatus.deniedForever;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationAccessStatus.serviceDisabled;
      }

      return LocationAccessStatus.granted;
    } catch (e) {
      debugPrint('[LocationService] Location access check failed: $e');
      return LocationAccessStatus.unavailable;
    }
  }

  /// Returns coordinates as "lat,lon" in decimal degrees, or null when unavailable.
  Future<String?> getCurrentCoordinates() async {
    try {
      final access = await ensureLocationAccess(requestPermission: true);
      if (access != LocationAccessStatus.granted) {
        return null;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ).timeout(const Duration(seconds: 6));
      } catch (_) {
        // Fallback to last-known coordinates if a fresh GPS lock is slow/unavailable.
        position = await Geolocator.getLastKnownPosition();
      }

      if (position == null) {
        return null;
      }

      return '${position.latitude.toStringAsFixed(6)},'
          '${position.longitude.toStringAsFixed(6)}';
    } catch (e) {
      debugPrint('[LocationService] Unable to capture coordinates: $e');
      return null;
    }
  }
}
