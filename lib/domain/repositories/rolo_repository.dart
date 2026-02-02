import '../entities/rolo.dart';

/// Repository interface for Rolo (The Ledger) operations.
///
/// The Rolo repository manages the immutable ledger of all interactions.
/// Records in tbl_rolos are never modified or deleted as they serve
/// as the permanent "black box" for the Dojo.
abstract class RoloRepository {
  /// Creates a new Rolo in the ledger.
  ///
  /// Returns the created Rolo with its assigned ID.
  Future<Rolo> create(Rolo rolo);

  /// Retrieves a Rolo by its ID.
  ///
  /// Returns null if no Rolo exists with the given ID.
  Future<Rolo?> getById(String id);

  /// Retrieves all Rolos targeting a specific URI.
  ///
  /// Returns Rolos in reverse chronological order (newest first).
  Future<List<Rolo>> getByTargetUri(String uri);

  /// Retrieves child Rolos of a parent (for threading).
  Future<List<Rolo>> getByParentId(String parentId);

  /// Retrieves the most recent Rolos.
  ///
  /// [limit] - Maximum number of Rolos to return (default: 50)
  /// [offset] - Number of Rolos to skip (for pagination)
  Future<List<Rolo>> getRecent({int limit = 50, int offset = 0});

  /// Searches Rolos by summoning text.
  ///
  /// Returns Rolos where the summoning_text contains [query].
  Future<List<Rolo>> search(String query);

  /// Returns the total count of Rolos in the ledger.
  Future<int> count();
}
