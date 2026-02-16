import 'package:flutter_test/flutter_test.dart';
import 'package:rolodojo/core/services/dojo_service.dart';
import 'package:rolodojo/domain/entities/attribute.dart';
import 'package:rolodojo/domain/entities/dojo_uri.dart';
import 'package:rolodojo/domain/entities/record.dart';
import 'package:rolodojo/domain/entities/rolo.dart';
import 'package:rolodojo/domain/repositories/attribute_repository.dart';
import 'package:rolodojo/domain/repositories/record_repository.dart';
import 'package:rolodojo/domain/repositories/rolo_repository.dart';

void main() {
  group('DojoService query responses', () {
    late _InMemoryRoloRepository roloRepository;
    late _InMemoryRecordRepository recordRepository;
    late _InMemoryAttributeRepository attributeRepository;
    late DojoService dojoService;

    setUp(() {
      roloRepository = _InMemoryRoloRepository();
      recordRepository = _InMemoryRecordRepository();
      attributeRepository = _InMemoryAttributeRepository();
      dojoService = DojoService(
        roloRepository: roloRepository,
        recordRepository: recordRepository,
        attributeRepository: attributeRepository,
      );
    });

    test('answers "what is <subject>\'s <attribute>" from stored facts', () async {
      await dojoService.processSummoning("Joe's coffee is Espresso");

      final result = await dojoService.processSummoning("What is Joe's coffee?");

      expect(result.rolo.type, RoloType.request);
      expect(result.message, contains('Espresso'));
      expect(result.message.toLowerCase(), contains('coffee'));
    });

    test('explains missing facts when attribute is unknown', () async {
      await dojoService.processSummoning("Joe's coffee is Espresso");

      final result = await dojoService.processSummoning("What is Joe's birthday?");

      expect(result.rolo.type, RoloType.request);
      expect(result.message, contains('I do not have Birthday for Joe yet.'));
      expect(result.message, contains('Known facts: Coffee.'));
    });

    test('summarizes known attributes for "who is <subject>"', () async {
      await dojoService.processSummoning("Joe's coffee is Espresso");
      await dojoService.processSummoning("Joe's city is Tokyo");

      final result = await dojoService.processSummoning('Who is Joe?');

      expect(result.rolo.type, RoloType.request);
      expect(result.message, contains('Joe'));
      expect(result.message, contains('Coffee: Espresso'));
      expect(result.message, contains('City: Tokyo'));
    });
  });
}

class _InMemoryRoloRepository implements RoloRepository {
  final List<Rolo> _rolos = [];

  @override
  Future<int> count() async => _rolos.length;

  @override
  Future<Rolo> create(Rolo rolo) async {
    _rolos.add(rolo);
    return rolo;
  }

  @override
  Future<Rolo?> getById(String id) async {
    for (final rolo in _rolos) {
      if (rolo.id == id) return rolo;
    }
    return null;
  }

  @override
  Future<List<Rolo>> getByParentId(String parentId) async {
    return _rolos.where((r) => r.parentRoloId == parentId).toList();
  }

  @override
  Future<List<Rolo>> getByTargetUri(String uri) async {
    return _rolos.where((r) => r.targetUri == uri).toList();
  }

  @override
  Future<List<Rolo>> getRecent({int limit = 50, int offset = 0}) async {
    final sorted = [..._rolos]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.skip(offset).take(limit).toList();
  }

  @override
  Future<List<Rolo>> search(String query) async {
    final lowered = query.toLowerCase();
    return _rolos
        .where((r) => r.summoningText.toLowerCase().contains(lowered))
        .toList();
  }

  @override
  Future<void> update(Rolo rolo) async {
    final index = _rolos.indexWhere((r) => r.id == rolo.id);
    if (index >= 0) {
      _rolos[index] = rolo;
    }
  }
}

class _InMemoryRecordRepository implements RecordRepository {
  final Map<String, Record> _records = {};

  @override
  Future<int> count() async => _records.length;

  @override
  Future<int> countByCategory(DojoCategory category) async {
    return _records.values
        .where((r) => r.uri.startsWith('dojo.${category.prefix}.'))
        .length;
  }

  @override
  Future<void> delete(String uri) async {
    _records.remove(uri);
  }

  @override
  Future<bool> exists(String uri) async => _records.containsKey(uri);

  @override
  Future<List<Record>> getAll({int? limit, int? offset}) async {
    final values = _records.values.toList();
    final start = offset ?? 0;
    final max = limit ?? values.length;
    return values.skip(start).take(max).toList();
  }

  @override
  Future<List<Record>> getByCategory(DojoCategory category) async {
    return _records.values
        .where((r) => r.uri.startsWith('dojo.${category.prefix}.'))
        .toList();
  }

  @override
  Future<Record?> getByUri(String uri) async => _records[uri];

  @override
  Future<List<Record>> searchByName(String query) async {
    final lowered = query.toLowerCase();
    return _records.values
        .where((r) => r.displayName.toLowerCase().contains(lowered))
        .toList();
  }

  @override
  Future<Record> upsert(Record record) async {
    _records[record.uri] = record;
    return record;
  }
}

class _InMemoryAttributeRepository implements AttributeRepository {
  final Map<String, Attribute> _attributes = {};

  String _compositeKey(String subjectUri, String key) {
    return '$subjectUri::$key';
  }

  @override
  Future<void> deleteByUri(String subjectUri) async {
    _attributes.removeWhere((key, _) => key.startsWith('$subjectUri::'));
  }

  @override
  Future<Attribute?> get(String subjectUri, String key) async {
    return _attributes[_compositeKey(subjectUri, key)];
  }

  @override
  Future<List<Attribute>> getByKey(String key) async {
    return _attributes.values
        .where((a) => a.key == key && a.value != null)
        .toList();
  }

  @override
  Future<List<Attribute>> getByUri(
    String subjectUri, {
    bool includeDeleted = false,
  }) async {
    final items = _attributes.values.where((a) => a.subjectUri == subjectUri);
    final filtered = includeDeleted ? items : items.where((a) => a.value != null);
    final result = filtered.toList()..sort((a, b) => a.key.compareTo(b.key));
    return result;
  }

  @override
  Future<List<AttributeHistoryEntry>> getHistory(
    String subjectUri,
    String key,
  ) async {
    return [];
  }

  @override
  Future<List<Attribute>> search(String query) async {
    final lowered = query.toLowerCase();
    return _attributes.values.where((a) {
      return a.key.toLowerCase().contains(lowered) ||
          (a.value?.toLowerCase().contains(lowered) ?? false);
    }).toList();
  }

  @override
  Future<Attribute> softDelete(
    String subjectUri,
    String key,
    String deletionRoloId,
  ) async {
    final existing = _attributes[_compositeKey(subjectUri, key)];
    final deleted = (existing ??
            Attribute(
              subjectUri: subjectUri,
              key: key,
              value: null,
              lastRoloId: deletionRoloId,
            ))
        .copyWith(
      value: null,
      lastRoloId: deletionRoloId,
      updatedAt: DateTime.now(),
    );
    _attributes[_compositeKey(subjectUri, key)] = deleted;
    return deleted;
  }

  @override
  Future<Attribute> upsert(Attribute attribute) async {
    _attributes[_compositeKey(attribute.subjectUri, attribute.key)] = attribute;
    return attribute;
  }
}
