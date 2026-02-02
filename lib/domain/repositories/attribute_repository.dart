import '../entities/attribute.dart';

/// Repository interface for Attribute (The Vault) operations.
///
/// The Attribute repository manages flexible key-value storage for
/// "soft data" like gate codes or coffee orders. Every change must
/// link to a last_rolo_id for audit purposes.
abstract class AttributeRepository {
  /// Creates or updates an Attribute.
  ///
  /// If an Attribute with the same (subject_uri, key) exists, it will
  /// be updated. The last_rolo_id must be provided for audit trail.
  Future<Attribute> upsert(Attribute attribute);

  /// Retrieves an Attribute by its composite key.
  ///
  /// Returns null if no Attribute exists with the given URI and key.
  Future<Attribute?> get(String subjectUri, String key);

  /// Retrieves all Attributes for a given URI.
  ///
  /// [includeDeleted] - If true, includes soft-deleted attributes (value=NULL)
  Future<List<Attribute>> getByUri(String subjectUri, {bool includeDeleted = false});

  /// Soft-deletes an Attribute.
  ///
  /// Sets the value to NULL while preserving the key and updating
  /// the last_rolo_id to the deletion Rolo for audit trail.
  ///
  /// [deletionRoloId] - The ID of the Rolo that requested the deletion
  Future<Attribute> softDelete(String subjectUri, String key, String deletionRoloId);

  /// Retrieves the history of an Attribute by querying related Rolos.
  ///
  /// Returns a list of (value, rolo_id, timestamp) tuples showing
  /// how the attribute changed over time.
  Future<List<AttributeHistoryEntry>> getHistory(String subjectUri, String key);

  /// Searches Attributes by key or value.
  ///
  /// Returns Attributes where the key or value contains [query].
  Future<List<Attribute>> search(String query);

  /// Retrieves all Attributes with a specific key across all URIs.
  ///
  /// Example: Get all "coffee_order" attributes for comparison.
  Future<List<Attribute>> getByKey(String key);

  /// Hard-deletes all Attributes for a given URI.
  ///
  /// Note: This breaks the audit trail. Use softDelete instead.
  Future<void> deleteByUri(String subjectUri);
}

/// Represents a historical entry for an Attribute.
class AttributeHistoryEntry {
  /// The value at this point in time (NULL if deleted)
  final String? value;

  /// The Rolo ID that caused this change
  final String roloId;

  /// When this change occurred
  final DateTime timestamp;

  /// The summoning text from the source Rolo
  final String? summoningText;

  const AttributeHistoryEntry({
    this.value,
    required this.roloId,
    required this.timestamp,
    this.summoningText,
  });
}
