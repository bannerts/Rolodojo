import '../../domain/entities/rolo.dart';
import '../../domain/repositories/rolo_repository.dart';
import '../datasources/local_data_source.dart';
import '../models/rolo_model.dart';

/// Implementation of RoloRepository using local SQLCipher database.
class RoloRepositoryImpl implements RoloRepository {
  final LocalDataSource _dataSource;

  RoloRepositoryImpl(this._dataSource);

  @override
  Future<Rolo> create(Rolo rolo) async {
    final model = RoloModel.fromEntity(rolo);
    await _dataSource.insertRolo(model);
    return rolo;
  }

  @override
  Future<Rolo?> getById(String id) async {
    final model = await _dataSource.getRoloById(id);
    return model?.toEntity();
  }

  @override
  Future<List<Rolo>> getByTargetUri(String uri) async {
    final models = await _dataSource.getRolosByTargetUri(uri);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<Rolo>> getByParentId(String parentId) async {
    final models = await _dataSource.getRolosByParentId(parentId);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<Rolo>> getRecent({int limit = 50, int offset = 0}) async {
    final models = await _dataSource.getRecentRolos(limit: limit, offset: offset);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<Rolo>> search(String query) async {
    final models = await _dataSource.searchRolos(query);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<int> count() async {
    return _dataSource.countRolos();
  }
}
