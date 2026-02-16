import '../../domain/entities/sensei_response.dart';
import '../../domain/repositories/sensei_repository.dart';
import '../datasources/local_data_source.dart';
import '../models/sensei_response_model.dart';

/// Implementation of SenseiRepository using local SQLCipher database.
class SenseiRepositoryImpl implements SenseiRepository {
  final LocalDataSource _dataSource;

  SenseiRepositoryImpl(this._dataSource);

  @override
  Future<SenseiResponse> create(SenseiResponse response) async {
    final model = SenseiResponseModel.fromEntity(response);
    await _dataSource.insertSenseiResponse(model);
    return response;
  }

  @override
  Future<List<SenseiResponse>> getByInputRoloId(String inputRoloId) async {
    final models = await _dataSource.getSenseiResponsesByInputRolo(inputRoloId);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<SenseiResponse>> getRecent({int limit = 50, int offset = 0}) async {
    final models = await _dataSource.getRecentSenseiResponses(
      limit: limit,
      offset: offset,
    );
    return models.map((m) => m.toEntity()).toList();
  }
}
