import '../../domain/entities/journal_entry.dart';
import '../../domain/repositories/journal_repository.dart';
import '../datasources/local_data_source.dart';
import '../models/journal_entry_model.dart';

/// Implementation of JournalRepository using local SQLCipher storage.
class JournalRepositoryImpl implements JournalRepository {
  final LocalDataSource _dataSource;

  JournalRepositoryImpl(this._dataSource);

  @override
  Future<JournalEntry> create(JournalEntry entry) async {
    final model = JournalEntryModel.fromEntity(entry);
    await _dataSource.insertJournalEntry(model);
    return entry;
  }

  @override
  Future<List<JournalEntry>> getByDate(
    String journalDate, {
    int limit = 200,
    int offset = 0,
  }) async {
    final models = await _dataSource.getJournalEntriesByDate(
      journalDate,
      limit: limit,
      offset: offset,
    );
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<JournalEntry>> getByDateRange(
    String startDate,
    String endDate, {
    int limit = 1000,
    int offset = 0,
  }) async {
    final models = await _dataSource.getJournalEntriesByDateRange(
      startDate,
      endDate,
      limit: limit,
      offset: offset,
    );
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<JournalEntry>> getRecent({int limit = 200, int offset = 0}) async {
    final models = await _dataSource.getRecentJournalEntries(
      limit: limit,
      offset: offset,
    );
    return models.map((m) => m.toEntity()).toList();
  }
}
