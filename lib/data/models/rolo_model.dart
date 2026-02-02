import 'dart:convert';
import '../../domain/entities/rolo.dart';

/// Data model for Rolo with database serialization.
class RoloModel extends Rolo {
  const RoloModel({
    required super.id,
    required super.type,
    required super.summoningText,
    super.targetUri,
    super.parentRoloId,
    super.metadata,
    required super.timestamp,
  });

  /// Creates a RoloModel from a domain Rolo entity.
  factory RoloModel.fromEntity(Rolo rolo) {
    return RoloModel(
      id: rolo.id,
      type: rolo.type,
      summoningText: rolo.summoningText,
      targetUri: rolo.targetUri,
      parentRoloId: rolo.parentRoloId,
      metadata: rolo.metadata,
      timestamp: rolo.timestamp,
    );
  }

  /// Creates a RoloModel from a database row (Map).
  factory RoloModel.fromMap(Map<String, dynamic> map) {
    RoloMetadata metadata = RoloMetadata.empty;
    if (map['metadata'] != null) {
      try {
        final metadataJson = jsonDecode(map['metadata'] as String);
        metadata = RoloMetadata.fromJson(metadataJson as Map<String, dynamic>);
      } catch (_) {
        // Keep empty metadata if parsing fails
      }
    }

    return RoloModel(
      id: map['rolo_id'] as String,
      type: RoloType.fromString(map['type'] as String? ?? 'INPUT'),
      summoningText: map['summoning_text'] as String? ?? '',
      targetUri: map['target_uri'] as String?,
      parentRoloId: map['parent_rolo_id'] as String?,
      metadata: metadata,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  /// Converts this RoloModel to a database row (Map).
  Map<String, dynamic> toMap() {
    return {
      'rolo_id': id,
      'type': type.value,
      'summoning_text': summoningText,
      'target_uri': targetUri,
      'parent_rolo_id': parentRoloId,
      'metadata': jsonEncode(metadata.toJson()),
      'timestamp': timestamp.toUtc().toIso8601String(),
    };
  }

  /// Converts to domain Rolo entity.
  Rolo toEntity() {
    return Rolo(
      id: id,
      type: type,
      summoningText: summoningText,
      targetUri: targetUri,
      parentRoloId: parentRoloId,
      metadata: metadata,
      timestamp: timestamp,
    );
  }
}
