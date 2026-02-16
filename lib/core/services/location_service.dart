import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Captures device GPS coordinates for ledger metadata.
class LocationService {
  /// Returns coordinates as "lat,lon" in decimal degrees, or null when unavailable.
  Future<String?> getCurrentCoordinates() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
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
