import '../entities/journal_entry.dart';

/// Repository interface for persisted journal entries (`tbl_journal`).
abstract class JournalRepository {
  /// Stores a journal row.
  Future<JournalEntry> create(JournalEntry entry);

  /// Returns journal rows for a specific local day key (YYYY-MM-DD).
  Future<List<JournalEntry>> getByDate(
    String journalDate, {
    int limit = 200,
    int offset = 0,
  });

  /// Returns journal rows for an inclusive date range.
  Future<List<JournalEntry>> getByDateRange(
    String startDate,
    String endDate, {
    int limit = 1000,
    int offset = 0,
  });

  /// Returns most recent journal rows.
  Future<List<JournalEntry>> getRecent({int limit = 200, int offset = 0});
}
