/// An Attribute represents a key-value fact in the Vault.
///
/// From ROLODOJO_GLOSSARY.md:
/// "The Vault: The tbl_attributes table. This is where 'soft data'
/// (specific details like gate codes or coffee orders) lives."
///
/// Attributes follow the audit requirement: every change must link
/// to a last_rolo_id explaining where the fact came from.
class Attribute {
  /// The URI this attribute belongs to (FK to tbl_records)
  final String subjectUri;

  /// The attribute key (snake_case) - e.g., "coffee_order"
  final String key;

  /// The attribute value (NULL if soft-deleted)
  final String? value;

  /// FK to tbl_rolos - The "Audit Receipt" for this fact
  final String lastRoloId;

  /// Whether this attribute contains encrypted/sensitive data
  final bool isEncrypted;

  /// Timestamp of last modification
  final DateTime? updatedAt;

  const Attribute({
    required this.subjectUri,
    required this.key,
    this.value,
    required this.lastRoloId,
    this.isEncrypted = false,
    this.updatedAt,
  });

  /// Returns true if this attribute has been soft-deleted.
  bool get isDeleted => value == null;

  Attribute copyWith({
    String? subjectUri,
    String? key,
    String? value,
    String? lastRoloId,
    bool? isEncrypted,
    DateTime? updatedAt,
  }) {
    return Attribute(
      subjectUri: subjectUri ?? this.subjectUri,
      key: key ?? this.key,
      value: value ?? this.value,
      lastRoloId: lastRoloId ?? this.lastRoloId,
      isEncrypted: isEncrypted ?? this.isEncrypted,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Creates a soft-deleted version of this attribute.
  ///
  /// Sets value to NULL while preserving the key and updating
  /// the last_rolo_id to maintain the audit trail.
  Attribute softDelete(String deletionRoloId) {
    return Attribute(
      subjectUri: subjectUri,
      key: key,
      value: null,
      lastRoloId: deletionRoloId,
      isEncrypted: isEncrypted,
      updatedAt: DateTime.now(),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Attribute &&
        other.subjectUri == subjectUri &&
        other.key == key;
  }

  @override
  int get hashCode => Object.hash(subjectUri, key);
}
