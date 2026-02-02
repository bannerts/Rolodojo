import '../entities/dojo_uri.dart';
import '../entities/record.dart';

/// Repository interface for Record (The Master Scroll) operations.
///
/// The Record repository manages the central registry for every
/// URI-addressable entity in the Dojo.
abstract class RecordRepository {
  /// Creates or updates a Record.
  ///
  /// If a Record with the same URI exists, it will be updated.
  /// Returns the created/updated Record.
  Future<Record> upsert(Record record);

  /// Retrieves a Record by its URI.
  ///
  /// Returns null if no Record exists with the given URI.
  Future<Record?> getByUri(String uri);

  /// Retrieves all Records in a specific category.
  ///
  /// [category] - The DojoCategory to filter by (con, ent, med, sys)
  Future<List<Record>> getByCategory(DojoCategory category);

  /// Searches Records by display name.
  ///
  /// Returns Records where the display_name contains [query].
  Future<List<Record>> searchByName(String query);

  /// Retrieves all Records.
  ///
  /// [limit] - Maximum number of Records to return
  /// [offset] - Number of Records to skip (for pagination)
  Future<List<Record>> getAll({int? limit, int? offset});

  /// Deletes a Record by its URI.
  ///
  /// Note: This is a hard delete. Consider soft-deleting attributes instead.
  Future<void> delete(String uri);

  /// Checks if a Record exists with the given URI.
  Future<bool> exists(String uri);

  /// Returns the total count of Records.
  Future<int> count();

  /// Returns the count of Records in a specific category.
  Future<int> countByCategory(DojoCategory category);
}
