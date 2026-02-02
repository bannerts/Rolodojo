import '../../domain/entities/attribute.dart';
import '../../domain/repositories/attribute_repository.dart';
import '../datasources/local_data_source.dart';
import '../models/attribute_model.dart';

/// Implementation of AttributeRepository using local SQLCipher database.
class AttributeRepositoryImpl implements AttributeRepository {
  final LocalDataSource _dataSource;

  AttributeRepositoryImpl(this._dataSource);

  @override
  Future<Attribute> upsert(Attribute attribute) async {
    final model = AttributeModel.fromEntity(attribute);
    await _dataSource.upsertAttribute(model);
    return attribute;
  }

  @override
  Future<Attribute?> get(String subjectUri, String key) async {
    final model = await _dataSource.getAttribute(subjectUri, key);
    return model?.toEntity();
  }

  @override
  Future<List<Attribute>> getByUri(
    String subjectUri, {
    bool includeDeleted = false,
  }) async {
    final models = await _dataSource.getAttributesByUri(
      subjectUri,
      includeDeleted: includeDeleted,
    );
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<Attribute> softDelete(
    String subjectUri,
    String key,
    String deletionRoloId,
  ) async {
    await _dataSource.softDeleteAttribute(subjectUri, key, deletionRoloId);

    // Return the soft-deleted attribute
    return Attribute(
      subjectUri: subjectUri,
      key: key,
      value: null,
      lastRoloId: deletionRoloId,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<List<AttributeHistoryEntry>> getHistory(
    String subjectUri,
    String key,
  ) async {
    final historyMaps = await _dataSource.getAttributeHistory(subjectUri, key);

    return historyMaps.map((map) {
      return AttributeHistoryEntry(
        roloId: map['rolo_id'] as String,
        summoningText: map['summoning_text'] as String?,
        timestamp: DateTime.parse(map['timestamp'] as String),
      );
    }).toList();
  }

  @override
  Future<List<Attribute>> search(String query) async {
    final models = await _dataSource.searchAttributes(query);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<List<Attribute>> getByKey(String key) async {
    final models = await _dataSource.getAttributesByKey(key);
    return models.map((m) => m.toEntity()).toList();
  }

  @override
  Future<void> deleteByUri(String subjectUri) async {
    await _dataSource.deleteAttributesByUri(subjectUri);
  }
}
