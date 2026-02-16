/// Who authored a journal row.
enum JournalRole {
  user('user'),
  sensei('sensei');

  final String value;
  const JournalRole(this.value);

  static JournalRole fromValue(String value) {
    final normalized = value.trim().toLowerCase();
    for (final role in JournalRole.values) {
      if (role.value == normalized) {
        return role;
      }
    }
    return JournalRole.user;
  }
}

/// Purpose of a journal row.
enum JournalEntryType {
  partial('partial'),
  followUp('follow_up'),
  answer('answer'),
  recall('recall'),
  dailySummary('daily_summary'),
  weeklySummary('weekly_summary');

  final String value;
  const JournalEntryType(this.value);

  static JournalEntryType fromValue(String value) {
    final normalized = value.trim().toLowerCase();
    for (final type in JournalEntryType.values) {
      if (type.value == normalized) {
        return type;
      }
    }
    return JournalEntryType.partial;
  }
}

/// Journal ledger row persisted in `tbl_journal`.
///
/// Journal rows store both user entries and Sensei responses, including
/// partial/day updates plus explicit summary blocks.
class JournalEntry {
  /// Primary key UUID.
  final String id;

  /// Local day key (YYYY-MM-DD) used for daily grouping.
  final String journalDate;

  /// Author of this row.
  final JournalRole role;

  /// Row purpose (partial/follow-up/answer/summary).
  final JournalEntryType entryType;

  /// Entry text body.
  final String content;

  /// Optional source rolo id for audit linkage.
  final String? sourceRoloId;

  /// Optional metadata payload.
  final Map<String, dynamic> metadata;

  /// Creation timestamp (UTC).
  final DateTime createdAt;

  const JournalEntry({
    required this.id,
    required this.journalDate,
    required this.role,
    required this.entryType,
    required this.content,
    this.sourceRoloId,
    this.metadata = const {},
    required this.createdAt,
  });

  JournalEntry copyWith({
    String? id,
    String? journalDate,
    JournalRole? role,
    JournalEntryType? entryType,
    String? content,
    Object? sourceRoloId = _sentinel,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
  }) {
    return JournalEntry(
      id: id ?? this.id,
      journalDate: journalDate ?? this.journalDate,
      role: role ?? this.role,
      entryType: entryType ?? this.entryType,
      content: content ?? this.content,
      sourceRoloId: sourceRoloId == _sentinel
          ? this.sourceRoloId
          : sourceRoloId as String?,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static const Object _sentinel = Object();
}
