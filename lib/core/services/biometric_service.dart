import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// Result of a biometric authentication attempt.
enum BiometricResult {
  /// Authentication successful
  success,

  /// User cancelled authentication
  cancelled,

  /// Biometrics not available on device
  notAvailable,

  /// Biometrics not enrolled (no fingerprint/face set up)
  notEnrolled,

  /// Authentication failed (wrong fingerprint/face)
  failed,

  /// Platform error
  error,
}

/// Service for handling biometric authentication.
///
/// From ROLODOJO_SECURITY.md:
/// "Biometric Authentication (FaceID/Fingerprint) is required to unlock
/// the Secure Storage and provide the decryption key to the database.
/// No biometrics = No database access."
class BiometricService {
  final LocalAuthentication _auth;

  BiometricService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  /// Checks if biometric authentication is available on the device.
  Future<bool> isAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } on PlatformException {
      return false;
    }
  }

  /// Gets the list of available biometric types.
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } on PlatformException {
      return [];
    }
  }

  /// Checks if any biometric is enrolled on the device.
  Future<bool> hasEnrolledBiometrics() async {
    final biometrics = await getAvailableBiometrics();
    return biometrics.isNotEmpty;
  }

  /// Authenticates the user using biometrics.
  ///
  /// [reason] - The message shown to the user explaining why authentication
  /// is needed. Defaults to the Dojo's standard message.
  ///
  /// Returns a [BiometricResult] indicating the outcome.
  Future<BiometricResult> authenticate({
    String reason = 'Authenticate to enter the Dojo',
  }) async {
    try {
      // Check availability first
      if (!await isAvailable()) {
        return BiometricResult.notAvailable;
      }

      // Check if biometrics are enrolled
      if (!await hasEnrolledBiometrics()) {
        return BiometricResult.notEnrolled;
      }

      // Attempt authentication
      final authenticated = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false, // Allow PIN/password fallback
        ),
      );

      return authenticated ? BiometricResult.success : BiometricResult.failed;
    } on PlatformException catch (e) {
      if (e.code == 'NotAvailable') {
        return BiometricResult.notAvailable;
      } else if (e.code == 'NotEnrolled') {
        return BiometricResult.notEnrolled;
      } else if (e.code == 'LockedOut' || e.code == 'PermanentlyLockedOut') {
        return BiometricResult.failed;
      }
      return BiometricResult.error;
    }
  }

  /// Returns a human-readable message for a biometric result.
  String getResultMessage(BiometricResult result) {
    switch (result) {
      case BiometricResult.success:
        return 'Welcome to the Dojo';
      case BiometricResult.cancelled:
        return 'Authentication cancelled';
      case BiometricResult.notAvailable:
        return 'Biometric authentication not available on this device';
      case BiometricResult.notEnrolled:
        return 'No biometrics enrolled. Please set up Face ID or Fingerprint in device settings';
      case BiometricResult.failed:
        return 'Authentication failed. Please try again';
      case BiometricResult.error:
        return 'An error occurred during authentication';
    }
  }

  /// Returns an appropriate icon for the available biometric type.
  String getBiometricIcon() {
    // This would be used to show the appropriate icon in the UI
    return '🔐';
  }
}
