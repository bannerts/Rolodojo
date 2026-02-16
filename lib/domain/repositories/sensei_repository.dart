import '../entities/sensei_response.dart';

/// Repository interface for persisted Sensei responses (`tbl_sensei`).
abstract class SenseiRepository {
  /// Stores a Sensei response linked to an input rolo.
  Future<SenseiResponse> create(SenseiResponse response);

  /// Retrieves all responses produced for a given input rolo.
  Future<List<SenseiResponse>> getByInputRoloId(String inputRoloId);

  /// Retrieves recent Sensei responses in reverse chronological order.
  Future<List<SenseiResponse>> getRecent({int limit = 50, int offset = 0});
}
