import '../../domain/entities/rolo.dart';

/// Represents a call log entry.
class CallLogEntry {
  /// Unique ID of the call log entry.
  final String id;

  /// Phone number (E.164 format preferred).
  final String phoneNumber;

  /// Contact name if available.
  final String? contactName;

  /// Type of call.
  final CallType type;

  /// Duration of the call in seconds.
  final int durationSeconds;

  /// Timestamp of the call.
  final DateTime timestamp;

  const CallLogEntry({
    required this.id,
    required this.phoneNumber,
    this.contactName,
    required this.type,
    required this.durationSeconds,
    required this.timestamp,
  });

  /// Creates metadata for a Rolo from this call.
  RoloMetadata toRoloMetadata() {
    return RoloMetadata(
      sourceId: 'call:$id',
      trigger: 'Call_Log',
    );
  }

  /// Returns a formatted duration string.
  String get formattedDuration {
    if (durationSeconds < 60) {
      return '${durationSeconds}s';
    } else if (durationSeconds < 3600) {
      final mins = durationSeconds ~/ 60;
      final secs = durationSeconds % 60;
      return '${mins}m ${secs}s';
    } else {
      final hours = durationSeconds ~/ 3600;
      final mins = (durationSeconds % 3600) ~/ 60;
      return '${hours}h ${mins}m';
    }
  }
}

/// Type of phone call.
enum CallType {
  incoming,
  outgoing,
  missed,
  rejected,
  blocked,
}

/// Represents an SMS message.
class SmsMessage {
  /// Unique ID of the SMS.
  final String id;

  /// Phone number (E.164 format preferred).
  final String phoneNumber;

  /// Contact name if available.
  final String? contactName;

  /// Message body.
  final String body;

  /// Whether this is an incoming or outgoing message.
  final bool isIncoming;

  /// Timestamp of the message.
  final DateTime timestamp;

  const SmsMessage({
    required this.id,
    required this.phoneNumber,
    this.contactName,
    required this.body,
    required this.isIncoming,
    required this.timestamp,
  });

  /// Creates metadata for a Rolo from this SMS.
  RoloMetadata toRoloMetadata() {
    return RoloMetadata(
      sourceId: 'sms:$id',
      trigger: 'SMS_Sync',
    );
  }
}

/// Result of a caller ID lookup.
class CallerIdResult {
  /// The phone number that was looked up.
  final String phoneNumber;

  /// Whether a match was found in the Dojo.
  final bool isKnown;

  /// The matching URI if found.
  final String? matchedUri;

  /// The display name from the matched record.
  final String? displayName;

  /// Confidence score of the match (0.0 - 1.0).
  final double confidence;

  const CallerIdResult({
    required this.phoneNumber,
    required this.isKnown,
    this.matchedUri,
    this.displayName,
    this.confidence = 0.0,
  });
}

/// Telephony integration service for call/SMS monitoring.
///
/// From ROLODOJO_INTEGRATIONS.md:
/// "Call Log: Monitor incoming numbers via system permissions.
/// Spam Defense: Cross-reference caller_id with dojo.con.* URIs.
/// SMS: Parse specific structured texts directly into the Attribute Vault."
///
/// NOTE: Full implementation requires:
/// - Platform-specific permissions (READ_CALL_LOG, READ_SMS)
/// - telephony or call_log package
/// - Background service for monitoring
abstract class TelephonyService {
  /// Whether the service has required permissions.
  Future<bool> hasPermissions();

  /// Requests necessary permissions.
  ///
  /// Returns true if all permissions were granted.
  Future<bool> requestPermissions();

  /// Gets recent call log entries.
  ///
  /// [limit] - Maximum number of entries to return.
  /// [since] - Only return entries after this timestamp.
  Future<List<CallLogEntry>> getCallLog({
    int limit = 50,
    DateTime? since,
  });

  /// Gets recent SMS messages.
  ///
  /// [limit] - Maximum number of messages to return.
  /// [since] - Only return messages after this timestamp.
  Future<List<SmsMessage>> getSmsMessages({
    int limit = 50,
    DateTime? since,
  });

  /// Performs a Caller ID lookup against the Dojo.
  ///
  /// Searches for the phone number in tbl_attributes to find
  /// a matching contact URI.
  Future<CallerIdResult> lookupCallerId(String phoneNumber);

  /// Parses an SMS for structured data.
  ///
  /// Looks for patterns like "Gate code is 1234" that can be
  /// extracted into attributes.
  Future<Map<String, String>?> parseSmsForData(SmsMessage sms);

  /// Starts monitoring for incoming calls/SMS.
  void startMonitoring();

  /// Stops monitoring.
  void stopMonitoring();

  /// Callback for when a call is received.
  void onCallReceived(void Function(CallLogEntry call) callback);

  /// Callback for when an SMS is received.
  void onSmsReceived(void Function(SmsMessage sms) callback);
}

/// Placeholder implementation for development/testing.
///
/// Replace with real implementation when permissions are configured.
class MockTelephonyService implements TelephonyService {
  void Function(CallLogEntry)? _callCallback;
  void Function(SmsMessage)? _smsCallback;

  @override
  Future<bool> hasPermissions() async => false;

  @override
  Future<bool> requestPermissions() async {
    // TODO: Implement with permission_handler
    // Request READ_CALL_LOG, READ_SMS, READ_PHONE_STATE
    return false;
  }

  @override
  Future<List<CallLogEntry>> getCallLog({
    int limit = 50,
    DateTime? since,
  }) async {
    // TODO: Implement with call_log package
    return [];
  }

  @override
  Future<List<SmsMessage>> getSmsMessages({
    int limit = 50,
    DateTime? since,
  }) async {
    // TODO: Implement with telephony package
    return [];
  }

  @override
  Future<CallerIdResult> lookupCallerId(String phoneNumber) async {
    // TODO: Query tbl_attributes for matching phone numbers
    // 1. Normalize phone number to E.164
    // 2. Search for attr_key='phone' with matching value
    // 3. Return matched URI and display name
    return CallerIdResult(
      phoneNumber: phoneNumber,
      isKnown: false,
    );
  }

  @override
  Future<Map<String, String>?> parseSmsForData(SmsMessage sms) async {
    // Common patterns to extract
    final patterns = [
      // "Gate code is 1234" or "Code: 1234"
      RegExp(r'(?:gate\s*)?code[:\s]+(\d{4,6})', caseSensitive: false),
      // "OTP: 123456" or "Verification code: 123456"
      RegExp(r'(?:otp|verification\s*code)[:\s]+(\d{4,6})', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(sms.body);
      if (match != null) {
        return {'code': match.group(1)!};
      }
    }

    return null;
  }

  @override
  void startMonitoring() {
    // TODO: Implement with platform channels or background service
  }

  @override
  void stopMonitoring() {
    // TODO: Cancel monitoring
  }

  @override
  void onCallReceived(void Function(CallLogEntry call) callback) {
    _callCallback = callback;
  }

  @override
  void onSmsReceived(void Function(SmsMessage sms) callback) {
    _smsCallback = callback;
  }
}
