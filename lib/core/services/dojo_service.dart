import 'package:uuid/uuid.dart';
import '../../domain/entities/attribute.dart';
import '../../domain/entities/dojo_uri.dart';
import '../../domain/entities/record.dart';
import '../../domain/entities/rolo.dart';
import '../../domain/repositories/attribute_repository.dart';
import '../../domain/repositories/record_repository.dart';
import '../../domain/repositories/rolo_repository.dart';
import 'input_parser.dart';
import 'location_service.dart';
import 'sensei_llm_service.dart';

/// Result of processing a summoning (user input).
class SummoningResult {
  /// The created Rolo.
  final Rolo rolo;

  /// The parsed input data.
  final ParsedInput parsed;

  /// The affected record (if any).
  final Record? record;

  /// The affected attribute (if any).
  final Attribute? attribute;

  /// Whether the input created a new record.
  final bool createdNewRecord;

  /// Human-readable response message.
  final String message;

  const SummoningResult({
    required this.rolo,
    required this.parsed,
    this.record,
    this.attribute,
    this.createdNewRecord = false,
    required this.message,
  });
}

/// The Dojo Service orchestrates all Sensei operations.
///
/// This is the main coordinator that processes user input, creates Rolos,
/// updates attributes, and manages the data flow between all components.
class DojoService {
  final RoloRepository _roloRepository;
  final RecordRepository _recordRepository;
  final AttributeRepository _attributeRepository;
  final InputParser _inputParser;
  final SenseiLlmService? _senseiLlm;
  final LocationService _locationService;
  final Uuid _uuid;

  DojoService({
    required RoloRepository roloRepository,
    required RecordRepository recordRepository,
    required AttributeRepository attributeRepository,
    InputParser? inputParser,
    SenseiLlmService? senseiLlm,
    LocationService? locationService,
  })  : _roloRepository = roloRepository,
        _recordRepository = recordRepository,
        _attributeRepository = attributeRepository,
        _inputParser = inputParser ?? InputParser(),
        _senseiLlm = senseiLlm,
        _locationService = locationService ?? LocationService(),
        _uuid = const Uuid();

  /// Processes a user summoning (text input) and creates appropriate records.
  ///
  /// This is the main entry point for user interactions. It:
  /// 1. Creates an INPUT Rolo in the ledger
  /// 2. Parses the input for structured data
  /// 3. Creates/updates the target Record if applicable
  /// 4. Creates/updates the Attribute in the Vault if applicable
  Future<SummoningResult> processSummoning(
    String input, {
    RoloMetadata metadata = RoloMetadata.empty,
  }) async {
    // Every user summoning should capture the device coordinates when possible.
    final enrichedMetadata = await _enrichMetadataWithLocation(metadata);

    // Parse the input — use active LLM provider if available, fall back to regex
    var parsed = _inputParser.parse(input);

    if (!parsed.canCreateAttribute && _senseiLlm != null && _senseiLlm!.isReady) {
      // LLM may extract structure that regex missed
      final recentRolos = await _roloRepository.getRecent(limit: 5);
      final recentTargetUris = recentRolos
          .where((r) => r.targetUri != null)
          .map((r) => r.targetUri!)
          .toSet()
          .take(5)
          .toList(growable: false);

      var hintAttributes = <String>[];
      if (parsed.subjectUri != null) {
        final knownAttributes =
            await _attributeRepository.getByUri(parsed.subjectUri!.toString());
        hintAttributes = knownAttributes
            .map((a) => a.key)
            .take(8)
            .toList(growable: false);
      }

      final llmResult = await _senseiLlm!.parseInput(
        input,
        context: LlmParsingContext(
          parserSubjectUriHint: parsed.subjectUri?.toString(),
          recentSummonings: recentRolos
              .map((r) => r.summoningText)
              .toList(growable: false),
          recentTargetUris: recentTargetUris,
          hintAttributes: hintAttributes,
        ),
      );
      if (llmResult.canCreateAttribute && llmResult.confidence > parsed.confidence) {
        parsed = ParsedInput(
          subjectName: llmResult.subjectName,
          subjectUri: llmResult.subjectName != null
              ? _inputParser.parse("${llmResult.subjectName}'s x is y").subjectUri
              : null,
          attributeKey: llmResult.attributeKey,
          attributeValue: llmResult.attributeValue,
          isQuery: llmResult.isQuery,
          confidence: llmResult.confidence,
          originalText: input,
        );
      }
    }

    // Create the Rolo
    final roloId = _uuid.v4();
    final rolo = Rolo(
      id: roloId,
      type: parsed.isQuery ? RoloType.request : RoloType.input,
      summoningText: input,
      targetUri: parsed.subjectUri?.toString(),
      metadata: RoloMetadata(
        trigger: enrichedMetadata.trigger ?? 'Manual_Entry',
        confidenceScore: parsed.confidence,
        location: enrichedMetadata.location,
        weather: enrichedMetadata.weather,
        sourceId: enrichedMetadata.sourceId,
        sourceDevice: enrichedMetadata.sourceDevice,
      ),
      timestamp: DateTime.now().toUtc(),
    );

    // Save the Rolo
    await _roloRepository.create(rolo);

    // If we have structured data, update the record and attribute
    Record? record;
    Attribute? attribute;
    bool createdNewRecord = false;
    String message;

    if (parsed.canCreateAttribute) {
      // Check if record exists
      final existingRecord = await _recordRepository.getByUri(
        parsed.subjectUri!.toString(),
      );

      if (existingRecord == null) {
        // Create new record
        record = Record(
          uri: parsed.subjectUri!.toString(),
          displayName: parsed.subjectName!,
          lastRoloId: roloId,
          updatedAt: DateTime.now(),
        );
        await _recordRepository.upsert(record);
        createdNewRecord = true;
      } else {
        // Update existing record's last_rolo_id
        record = existingRecord.copyWith(
          lastRoloId: roloId,
          updatedAt: DateTime.now(),
        );
        await _recordRepository.upsert(record);
      }

      // Create/update the attribute
      attribute = Attribute(
        subjectUri: parsed.subjectUri!.toString(),
        key: parsed.attributeKey!,
        value: parsed.attributeValue,
        lastRoloId: roloId,
        updatedAt: DateTime.now(),
      );
      await _attributeRepository.upsert(attribute);

      message = createdNewRecord
          ? 'Created ${parsed.subjectName} with ${_formatKey(parsed.attributeKey!)}: ${parsed.attributeValue}'
          : 'Updated ${parsed.subjectName}\'s ${_formatKey(parsed.attributeKey!)} to ${parsed.attributeValue}';
    } else if (parsed.isQuery) {
      message = 'Query received. Searching the Vault...';
    } else {
      message = 'Input recorded. Unable to extract structured data.';
    }

    return SummoningResult(
      rolo: rolo,
      parsed: parsed,
      record: record,
      attribute: attribute,
      createdNewRecord: createdNewRecord,
      message: message,
    );
  }

  /// Soft-deletes an attribute with audit trail.
  Future<Attribute> deleteAttribute(
    String subjectUri,
    String key,
  ) async {
    final deletionLocation = await _locationService.getCurrentCoordinates();

    // Create a deletion Rolo
    final roloId = _uuid.v4();
    final rolo = Rolo(
      id: roloId,
      type: RoloType.input,
      summoningText: 'Delete $key from $subjectUri',
      targetUri: subjectUri,
      metadata: RoloMetadata(
        trigger: 'Manual_Delete',
        location: deletionLocation,
      ),
      timestamp: DateTime.now().toUtc(),
    );
    await _roloRepository.create(rolo);

    // Soft-delete the attribute
    return _attributeRepository.softDelete(subjectUri, key, roloId);
  }

  /// Retrieves all attributes for a URI with their audit information.
  Future<List<Attribute>> getAttributes(String uri) async {
    return _attributeRepository.getByUri(uri);
  }

  /// Retrieves the history of an attribute.
  Future<List<AttributeHistoryEntry>> getAttributeHistory(
    String uri,
    String key,
  ) async {
    return _attributeRepository.getHistory(uri, key);
  }

  /// Retrieves recent Rolos for the stream.
  Future<List<Rolo>> getRecentRolos({int limit = 50}) async {
    return _roloRepository.getRecent(limit: limit);
  }

  /// Retrieves a Rolo by its ID.
  Future<Rolo?> getRolo(String id) async {
    return _roloRepository.getById(id);
  }

  /// Retrieves all records in a category.
  Future<List<Record>> getRecordsByCategory(DojoCategory category) async {
    return _recordRepository.getByCategory(category);
  }

  /// Searches records by name.
  Future<List<Record>> searchRecords(String query) async {
    return _recordRepository.searchByName(query);
  }

  String _formatKey(String key) {
    return key
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  Future<RoloMetadata> _enrichMetadataWithLocation(RoloMetadata metadata) async {
    final existingLocation = metadata.location?.trim();
    if (existingLocation != null && existingLocation.isNotEmpty) {
      return metadata;
    }

    final capturedLocation = await _locationService.getCurrentCoordinates();
    return RoloMetadata(
      location: capturedLocation,
      weather: metadata.weather,
      sourceId: metadata.sourceId,
      trigger: metadata.trigger,
      sourceDevice: metadata.sourceDevice,
      confidenceScore: metadata.confidenceScore,
    );
  }
}
