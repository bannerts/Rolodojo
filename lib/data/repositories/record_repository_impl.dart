import '../../domain/entities/dojo_uri.dart';
import '../../domain/entities/record.dart';
import '../../domain/repositories/record_repository.dart';
import '../datasources/local_data_source.dart';
import '../models/record_model.dart';

/// Implementation of RecordRepository using local SQLCipher database.
class RecordRepositoryImpl implements RecordRepository {
  final LocalDataSource _dataSource;

  RecordRepositoryImpl(this._dataSource);

  @override
  Future<Record> upsert(Record record) async {
    final model = RecordModel.fromEntity(record);
    await _dataSource.upsertRecord(model);
    return record;
  }

  @override
  Future<Record?> getByUri(String uri) async {
    final model = await _dataSource.getRecordByUri(uri);
    return model?.toEntity();
  }

  @override
  Future<List<Record>> getByCategory(DojoCategory category) async {
    final models = await _dataSource.getRecordsByCategory(category.prefix);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<Record>> searchByName(String query) async {
    final models = await _dataSource.searchRecordsByName(query);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<Record>> getAll({int? limit, int? offset}) async {
    final models = await _dataSource.getAllRecords(limit: limit, offset: offset);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<void> delete(String uri) async {
    await _dataSource.deleteRecord(uri);
  }

  @override
  Future<bool> exists(String uri) async {
    return _dataSource.recordExists(uri);
  }

  @override
  Future<int> count() async {
    return _dataSource.countRecords();
  }

  @override
  Future<int> countByCategory(DojoCategory category) async {
    return _dataSource.countRecordsByCategory(category.prefix);
  }
}
