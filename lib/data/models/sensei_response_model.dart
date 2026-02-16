import '../../domain/entities/sensei_response.dart';

/// Data model for `tbl_sensei` rows.
class SenseiResponseModel extends SenseiResponse {
  const SenseiResponseModel({
    required super.id,
    required super.inputRoloId,
    super.targetUri,
    required super.responseText,
    super.provider,
    super.model,
    super.confidenceScore,
    required super.createdAt,
  });

  factory SenseiResponseModel.fromEntity(SenseiResponse response) {
    return SenseiResponseModel(
      id: response.id,
      inputRoloId: response.inputRoloId,
      targetUri: response.targetUri,
      responseText: response.responseText,
      provider: response.provider,
      model: response.model,
      confidenceScore: response.confidenceScore,
      createdAt: response.createdAt,
    );
  }

  factory SenseiResponseModel.fromMap(Map<String, dynamic> map) {
    return SenseiResponseModel(
      id: map['sensei_id'] as String,
      inputRoloId: map['input_rolo_id'] as String,
      targetUri: map['target_uri'] as String?,
      responseText: map['response_text'] as String? ?? '',
      provider: map['provider'] as String?,
      model: map['model'] as String?,
      confidenceScore: (map['confidence_score'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sensei_id': id,
      'input_rolo_id': inputRoloId,
      'target_uri': targetUri,
      'response_text': responseText,
      'provider': provider,
      'model': model,
      'confidence_score': confidenceScore,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }

  SenseiResponse toEntity() {
    return SenseiResponse(
      id: id,
      inputRoloId: inputRoloId,
      targetUri: targetUri,
      responseText: responseText,
      provider: provider,
      model: model,
      confidenceScore: confidenceScore,
      createdAt: createdAt,
    );
  }
}
