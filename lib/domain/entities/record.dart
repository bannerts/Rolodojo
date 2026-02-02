/// A Record represents the current "State of Truth" for a URI.
///
/// From ROLODOJO_GLOSSARY.md:
/// "The Master Scroll: The tbl_records table. It serves as the central
/// registry for every URI (People, Places, Things)."
///
/// Records are stored in tbl_records and contain the current state
/// of any URI-addressable entity in the Dojo.
class Record {
  /// The URI address (Primary Key) - e.g., dojo.con.joe
  final String uri;

  /// Human-readable display name - e.g., "Joe Smith"
  final String displayName;

  /// JSON payload containing standardized data
  final Map<String, dynamic> payload;

  /// FK to tbl_rolos - The last Rolo that modified this record
  final String? lastRoloId;

  /// Timestamp of last modification
  final DateTime? updatedAt;

  const Record({
    required this.uri,
    required this.displayName,
    this.payload = const {},
    this.lastRoloId,
    this.updatedAt,
  });

  Record copyWith({
    String? uri,
    String? displayName,
    Map<String, dynamic>? payload,
    String? lastRoloId,
    DateTime? updatedAt,
  }) {
    return Record(
      uri: uri ?? this.uri,
      displayName: displayName ?? this.displayName,
      payload: payload ?? this.payload,
      lastRoloId: lastRoloId ?? this.lastRoloId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Record && other.uri == uri;
  }

  @override
  int get hashCode => uri.hashCode;
}
