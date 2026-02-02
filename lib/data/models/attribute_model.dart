import '../../domain/entities/attribute.dart';

/// Data model for Attribute with database serialization.
class AttributeModel extends Attribute {
  const AttributeModel({
    required super.subjectUri,
    required super.key,
    super.value,
    required super.lastRoloId,
    super.isEncrypted,
    super.updatedAt,
  });

  /// Creates an AttributeModel from a domain Attribute entity.
  factory AttributeModel.fromEntity(Attribute attribute) {
    return AttributeModel(
      subjectUri: attribute.subjectUri,
      key: attribute.key,
      value: attribute.value,
      lastRoloId: attribute.lastRoloId,
      isEncrypted: attribute.isEncrypted,
      updatedAt: attribute.updatedAt,
    );
  }

  /// Creates an AttributeModel from a database row (Map).
  factory AttributeModel.fromMap(Map<String, dynamic> map) {
    DateTime? updatedAt;
    if (map['updated_at'] != null) {
      try {
        updatedAt = DateTime.parse(map['updated_at'] as String);
      } catch (_) {
        // Keep null if parsing fails
      }
    }

    return AttributeModel(
      subjectUri: map['subject_uri'] as String,
      key: map['attr_key'] as String,
      value: map['attr_value'] as String?,
      lastRoloId: map['last_rolo_id'] as String,
      isEncrypted: (map['is_encrypted'] as int?) == 1,
      updatedAt: updatedAt,
    );
  }

  /// Converts this AttributeModel to a database row (Map).
  Map<String, dynamic> toMap() {
    return {
      'subject_uri': subjectUri,
      'attr_key': key,
      'attr_value': value,
      'last_rolo_id': lastRoloId,
      'is_encrypted': isEncrypted ? 1 : 0,
    };
  }

  /// Converts to domain Attribute entity.
  Attribute toEntity() {
    return Attribute(
      subjectUri: subjectUri,
      key: key,
      value: value,
      lastRoloId: lastRoloId,
      isEncrypted: isEncrypted,
      updatedAt: updatedAt,
    );
  }
}
