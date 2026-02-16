import 'dart:convert';

import '../../domain/entities/journal_entry.dart';

/// Data model for `tbl_journal` rows.
class JournalEntryModel extends JournalEntry {
  const JournalEntryModel({
    required super.id,
    required super.journalDate,
    required super.role,
    required super.entryType,
    required super.content,
    super.sourceRoloId,
    super.metadata,
    required super.createdAt,
  });

  factory JournalEntryModel.fromEntity(JournalEntry entry) {
    return JournalEntryModel(
      id: entry.id,
      journalDate: entry.journalDate,
      role: entry.role,
      entryType: entry.entryType,
      content: entry.content,
      sourceRoloId: entry.sourceRoloId,
      metadata: entry.metadata,
      createdAt: entry.createdAt,
    );
  }

  factory JournalEntryModel.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> payload = const {};
    final metadata = map['metadata'] as String?;
    if (metadata != null && metadata.isNotEmpty) {
      try {
        final decoded = jsonDecode(metadata);
        if (decoded is Map<String, dynamic>) {
          payload = decoded;
        }
      } catch (_) {
        payload = const {};
      }
    }

    return JournalEntryModel(
      id: map['journal_id'] as String,
      journalDate: map['journal_date'] as String,
      role: JournalRole.fromValue(map['role'] as String? ?? 'user'),
      entryType: JournalEntryType.fromValue(
        map['entry_type'] as String? ?? 'partial',
      ),
      content: map['content'] as String? ?? '',
      sourceRoloId: map['source_rolo_id'] as String?,
      metadata: payload,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'journal_id': id,
      'journal_date': journalDate,
      'role': role.value,
      'entry_type': entryType.value,
      'content': content,
      'source_rolo_id': sourceRoloId,
      'metadata': jsonEncode(metadata),
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  JournalEntry toEntity() {
    return JournalEntry(
      id: id,
      journalDate: journalDate,
      role: role,
      entryType: entryType,
      content: content,
      sourceRoloId: sourceRoloId,
      metadata: metadata,
      createdAt: createdAt,
    );
  }
}
