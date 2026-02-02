import '../../domain/entities/rolo.dart';

/// Represents an email message from Gmail.
class GmailMessage {
  /// Gmail message ID (used to prevent duplicates).
  final String messageId;

  /// Email sender.
  final String from;

  /// Email subject.
  final String subject;

  /// Email body snippet.
  final String snippet;

  /// Full email body (if fetched).
  final String? body;

  /// Timestamp of the email.
  final DateTime timestamp;

  /// Labels applied to the email.
  final List<String> labels;

  const GmailMessage({
    required this.messageId,
    required this.from,
    required this.subject,
    required this.snippet,
    this.body,
    required this.timestamp,
    this.labels = const [],
  });

  /// Creates metadata for a Rolo from this email.
  RoloMetadata toRoloMetadata() {
    return RoloMetadata(
      sourceId: 'gmail:$messageId',
      trigger: 'Gmail_Sync',
    );
  }
}

/// Status of the Gmail sync service.
enum GmailSyncStatus {
  /// Not connected to Gmail.
  disconnected,

  /// Connected and ready.
  connected,

  /// Currently syncing messages.
  syncing,

  /// Sync error occurred.
  error,
}

/// Gmail integration service for syncing emails to the Dojo.
///
/// From ROLODOJO_INTEGRATIONS.md:
/// "Gmail API via OAuth2 (Local authentication).
/// Poll for messages with the 'Dojo' label or specific keywords.
/// Convert email body into an 'Input Rolo.' Store message_id in Rolo
/// metadata to prevent duplicates."
///
/// NOTE: Full implementation requires:
/// - Google Cloud Console project setup
/// - OAuth2 client credentials
/// - googleapis package
abstract class GmailService {
  /// Current sync status.
  GmailSyncStatus get status;

  /// Whether the user is authenticated with Gmail.
  Future<bool> isAuthenticated();

  /// Initiates OAuth2 authentication flow.
  ///
  /// Returns true if authentication was successful.
  Future<bool> authenticate();

  /// Signs out of Gmail.
  Future<void> signOut();

  /// Fetches messages with the "Dojo" label.
  ///
  /// [since] - Only fetch messages after this timestamp.
  /// [limit] - Maximum number of messages to fetch.
  Future<List<GmailMessage>> fetchDojoMessages({
    DateTime? since,
    int limit = 50,
  });

  /// Fetches messages matching specific keywords.
  Future<List<GmailMessage>> searchMessages(String query);

  /// Marks a message as processed (prevents re-sync).
  Future<void> markAsProcessed(String messageId);

  /// Checks if a message has already been processed.
  Future<bool> isProcessed(String messageId);

  /// Starts periodic background sync.
  ///
  /// [interval] - How often to check for new messages.
  void startBackgroundSync({Duration interval = const Duration(minutes: 15)});

  /// Stops background sync.
  void stopBackgroundSync();
}

/// Placeholder implementation for development/testing.
///
/// Replace with real implementation when OAuth2 is configured.
class MockGmailService implements GmailService {
  GmailSyncStatus _status = GmailSyncStatus.disconnected;
  final Set<String> _processedIds = {};

  @override
  GmailSyncStatus get status => _status;

  @override
  Future<bool> isAuthenticated() async => false;

  @override
  Future<bool> authenticate() async {
    // TODO: Implement OAuth2 flow
    // 1. Launch browser/webview with Google OAuth URL
    // 2. Handle redirect with auth code
    // 3. Exchange code for access/refresh tokens
    // 4. Store tokens securely
    _status = GmailSyncStatus.error;
    return false;
  }

  @override
  Future<void> signOut() async {
    _status = GmailSyncStatus.disconnected;
  }

  @override
  Future<List<GmailMessage>> fetchDojoMessages({
    DateTime? since,
    int limit = 50,
  }) async {
    // TODO: Implement with Gmail API
    // 1. Query for messages with label:Dojo
    // 2. Filter by date if 'since' is provided
    // 3. Return parsed messages
    return [];
  }

  @override
  Future<List<GmailMessage>> searchMessages(String query) async {
    return [];
  }

  @override
  Future<void> markAsProcessed(String messageId) async {
    _processedIds.add(messageId);
  }

  @override
  Future<bool> isProcessed(String messageId) async {
    return _processedIds.contains(messageId);
  }

  @override
  void startBackgroundSync({Duration interval = const Duration(minutes: 15)}) {
    // TODO: Implement with WorkManager or background_fetch
  }

  @override
  void stopBackgroundSync() {
    // TODO: Cancel background tasks
  }
}
