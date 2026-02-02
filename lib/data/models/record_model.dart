import 'dart:convert';
import '../../domain/entities/record.dart';

/// Data model for Record with database serialization.
class RecordModel extends Record {
  const RecordModel({
    required super.uri,
    required super.displayName,
    super.payload,
    super.lastRoloId,
    super.updatedAt,
  });

  /// Creates a RecordModel from a domain Record entity.
  factory RecordModel.fromEntity(Record record) {
    return RecordModel(
      uri: record.uri,
      displayName: record.displayName,
      payload: record.payload,
      lastRoloId: record.lastRoloId,
      updatedAt: record.updatedAt,
    );
  }

  /// Creates a RecordModel from a database row (Map).
  factory RecordModel.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> payload = {};
    if (map['payload'] != null) {
      try {
        payload = jsonDecode(map['payload'] as String) as Map<String, dynamic>;
      } catch (_) {
        // Keep empty payload if parsing fails
      }
    }

    DateTime? updatedAt;
    if (map['updated_at'] != null) {
      try {
        updatedAt = DateTime.parse(map['updated_at'] as String);
      } catch (_) {
        // Keep null if parsing fails
      }
    }

    return RecordModel(
      uri: map['uri'] as String,
      displayName: map['display_name'] as String? ?? '',
      payload: payload,
      lastRoloId: map['last_rolo_id'] as String?,
      updatedAt: updatedAt,
    );
  }

  /// Converts this RecordModel to a database row (Map).
  Map<String, dynamic> toMap() {
    return {
      'uri': uri,
      'display_name': displayName,
      'payload': jsonEncode(payload),
      'last_rolo_id': lastRoloId,
    };
  }

  /// Converts to domain Record entity.
  Record toEntity() {
    return Record(
      uri: uri,
      displayName: displayName,
      payload: payload,
      lastRoloId: lastRoloId,
      updatedAt: updatedAt,
    );
  }
}
