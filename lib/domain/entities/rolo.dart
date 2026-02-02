/// The type of a Rolo entry.
///
/// From ROLODOJO_CONTEXT.md:
/// - [input]: User-provided data (text, voice, or image)
/// - [request]: A query or command from the user
/// - [synthesis]: AI-generated insight connecting existing facts
enum RoloType {
  input('INPUT'),
  request('REQUEST'),
  synthesis('SYNTHESIS');

  final String value;
  const RoloType(this.value);

  static RoloType fromString(String value) {
    return RoloType.values.firstWhere(
      (e) => e.value == value.toUpperCase(),
      orElse: () => RoloType.input,
    );
  }
}

/// Metadata associated with a Rolo.
class RoloMetadata {
  /// GPS coordinates (decimal degrees)
  final String? location;

  /// Weather conditions at time of entry
  final String? weather;

  /// Source identifier (e.g., Gmail message ID, Call Log ID)
  final String? sourceId;

  /// Trigger type (Manual_Entry, Gmail_Sync, Call_Log, etc.)
  final String? trigger;

  /// Device identifier
  final String? sourceDevice;

  /// Confidence score for AI-generated content (0.0 - 1.0)
  final double? confidenceScore;

  const RoloMetadata({
    this.location,
    this.weather,
    this.sourceId,
    this.trigger,
    this.sourceDevice,
    this.confidenceScore,
  });

  Map<String, dynamic> toJson() {
    return {
      if (location != null) 'location': location,
      if (weather != null) 'weather': weather,
      if (sourceId != null) 'source_id': sourceId,
      if (trigger != null) 'trigger': trigger,
      if (sourceDevice != null) 'source_device': sourceDevice,
      if (confidenceScore != null) 'confidence_score': confidenceScore,
    };
  }

  factory RoloMetadata.fromJson(Map<String, dynamic> json) {
    return RoloMetadata(
      location: json['location'] as String?,
      weather: json['weather'] as String?,
      sourceId: json['source_id'] as String?,
      trigger: json['trigger'] as String?,
      sourceDevice: json['source_device'] as String?,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
    );
  }

  static const empty = RoloMetadata();
}

/// A Rolo is the atomic unit of the Rolodojo system.
///
/// Every interaction—whether a user input, an AI response, or a background
/// system update—is recorded as a Rolo in the immutable ledger (tbl_rolos).
///
/// From ROLODOJO_GLOSSARY.md:
/// "Rolo: The atomic unit of the system. Every interaction is a Rolo."
class Rolo {
  /// Unique identifier (UUID)
  final String id;

  /// Type of Rolo (INPUT, REQUEST, SYNTHESIS)
  final RoloType type;

  /// The raw input text or AI output
  final String summoningText;

  /// The URI this Rolo interacts with (e.g., dojo.con.joe)
  final String? targetUri;

  /// Parent Rolo ID for threading conversations
  final String? parentRoloId;

  /// Additional context (GPS, weather, source_id)
  final RoloMetadata metadata;

  /// Timestamp in ISO 8601 format (UTC)
  final DateTime timestamp;

  const Rolo({
    required this.id,
    required this.type,
    required this.summoningText,
    this.targetUri,
    this.parentRoloId,
    this.metadata = RoloMetadata.empty,
    required this.timestamp,
  });

  Rolo copyWith({
    String? id,
    RoloType? type,
    String? summoningText,
    String? targetUri,
    String? parentRoloId,
    RoloMetadata? metadata,
    DateTime? timestamp,
  }) {
    return Rolo(
      id: id ?? this.id,
      type: type ?? this.type,
      summoningText: summoningText ?? this.summoningText,
      targetUri: targetUri ?? this.targetUri,
      parentRoloId: parentRoloId ?? this.parentRoloId,
      metadata: metadata ?? this.metadata,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Rolo && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
