import 'package:uuid/uuid.dart';
import '../../domain/entities/attribute.dart';
import '../../domain/entities/dojo_uri.dart';
import '../../domain/entities/record.dart';
import '../../domain/entities/rolo.dart';
import '../../domain/repositories/attribute_repository.dart';
import '../../domain/repositories/record_repository.dart';
import '../../domain/repositories/rolo_repository.dart';
import '../utils/uri_utils.dart';
import 'input_parser.dart';
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
  final Uuid _uuid;

  DojoService({
    required RoloRepository roloRepository,
    required RecordRepository recordRepository,
    required AttributeRepository attributeRepository,
    InputParser? inputParser,
    SenseiLlmService? senseiLlm,
  })  : _roloRepository = roloRepository,
        _recordRepository = recordRepository,
        _attributeRepository = attributeRepository,
        _inputParser = inputParser ?? InputParser(),
        _senseiLlm = senseiLlm,
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
    // Parse the input — use local LLM if available, fall back to regex
    var parsed = _inputParser.parse(input);

    if (!parsed.canCreateAttribute && _senseiLlm != null && _senseiLlm!.isReady) {
      // LLM may extract structure that regex missed
      final llmResult = await _senseiLlm!.parseInput(input);
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

    final queryIntent = parsed.isQuery
        ? _extractQueryIntent(parsed.originalText)
        : const _QueryIntent();
    final queryTargetUri = queryIntent.subjectName != null
        ? _inferSubjectUri(queryIntent.subjectName!)
        : null;

    // Create the Rolo
    final roloId = _uuid.v4();
    final rolo = Rolo(
      id: roloId,
      type: parsed.isQuery ? RoloType.request : RoloType.input,
      summoningText: input,
      targetUri: parsed.subjectUri?.toString() ?? queryTargetUri,
      metadata: RoloMetadata(
        trigger: 'Manual_Entry',
        confidenceScore: parsed.confidence,
        location: metadata.location,
        weather: metadata.weather,
        sourceDevice: metadata.sourceDevice,
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
      message = await _answerQuery(queryIntent);
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
    // Create a deletion Rolo
    final roloId = _uuid.v4();
    final rolo = Rolo(
      id: roloId,
      type: RoloType.input,
      summoningText: 'Delete $key from $subjectUri',
      targetUri: subjectUri,
      metadata: const RoloMetadata(trigger: 'Manual_Delete'),
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

  _QueryIntent _extractQueryIntent(String rawInput) {
    final normalizedInput = rawInput.trim().replaceAll(RegExp(r'\s+'), ' ');
    final inputWithoutPunctuation = normalizedInput
        .replaceAll(RegExp(r'[?.!]+$'), '')
        .trim();
    final lowered = inputWithoutPunctuation.toLowerCase();

    final possessivePattern = RegExp(
      r"^what(?:\s+is|['’]s)\s+(.+?)['’]s\s+(.+)$",
      caseSensitive: false,
    );
    final possessiveMatch = possessivePattern.firstMatch(inputWithoutPunctuation);
    if (possessiveMatch != null) {
      return _QueryIntent(
        subjectName: _cleanSubjectName(possessiveMatch.group(1)!),
        attributeKey: _cleanAttributeKey(possessiveMatch.group(2)!),
      );
    }

    final forPattern = RegExp(
      r"^what(?:\s+is|['’]s)\s+(.+?)\s+for\s+(.+)$",
      caseSensitive: false,
    );
    final forMatch = forPattern.firstMatch(inputWithoutPunctuation);
    if (forMatch != null) {
      return _QueryIntent(
        subjectName: _cleanSubjectName(forMatch.group(2)!),
        attributeKey: _cleanAttributeKey(forMatch.group(1)!),
      );
    }

    final profilePatterns = <RegExp>[
      RegExp(r'^who\s+is\s+(.+)$', caseSensitive: false),
      RegExp(r'^where\s+is\s+(.+)$', caseSensitive: false),
      RegExp(r'^tell\s+me\s+about\s+(.+)$', caseSensitive: false),
      RegExp(r'^what\s+do\s+you\s+know\s+about\s+(.+)$', caseSensitive: false),
    ];
    for (final pattern in profilePatterns) {
      final match = pattern.firstMatch(inputWithoutPunctuation);
      if (match != null) {
        return _QueryIntent(subjectName: _cleanSubjectName(match.group(1)!));
      }
    }

    if (lowered.startsWith('what is ') || lowered.startsWith("what's ")) {
      final prefix = lowered.startsWith("what's ") ? "what's " : 'what is ';
      final rawAttribute = inputWithoutPunctuation.substring(prefix.length);
      return _QueryIntent(attributeKey: _cleanAttributeKey(rawAttribute));
    }

    return const _QueryIntent();
  }

  Future<String> _answerQuery(_QueryIntent queryIntent) async {
    if (queryIntent.subjectName != null) {
      final subject = await _resolveSubject(queryIntent.subjectName!);
      if (subject == null) {
        return 'I could not find "${queryIntent.subjectName}" in the Vault yet.';
      }

      if (queryIntent.attributeKey != null) {
        return _answerAttributeQuery(subject, queryIntent.attributeKey!);
      }

      return _answerSubjectSummary(subject);
    }

    if (queryIntent.attributeKey != null) {
      return _answerGlobalAttributeQuery(queryIntent.attributeKey!);
    }

    return 'I heard your question, but need a format like "What is Joe\'s coffee?"';
  }

  Future<String> _answerAttributeQuery(
    _ResolvedSubject subject,
    String rawAttributeKey,
  ) async {
    final attributeKey = UriUtils.nameToIdentifier(rawAttributeKey);
    if (attributeKey.isEmpty) {
      return 'I could not determine which attribute you asked for.';
    }

    final directHit = await _attributeRepository.get(subject.uri, attributeKey);
    if (directHit != null && directHit.value != null) {
      return "${subject.displayName}'s ${_formatKey(directHit.key)} is ${directHit.value}.";
    }

    final attributes = await _attributeRepository.getByUri(subject.uri);
    Attribute? fuzzyMatch;
    for (final attribute in attributes) {
      if (attribute.key.contains(attributeKey) ||
          attributeKey.contains(attribute.key)) {
        fuzzyMatch = attribute;
        break;
      }
    }

    if (fuzzyMatch != null) {
      return "${subject.displayName}'s ${_formatKey(fuzzyMatch.key)} is ${fuzzyMatch.value}.";
    }

    if (attributes.isEmpty) {
      return 'I found ${subject.displayName}, but there are no stored facts yet.';
    }

    final knownKeys = attributes.take(4).map((a) => _formatKey(a.key)).join(', ');
    return 'I do not have ${_formatKey(attributeKey)} for ${subject.displayName} yet. '
        'Known facts: $knownKeys.';
  }

  Future<String> _answerSubjectSummary(_ResolvedSubject subject) async {
    final attributes = await _attributeRepository.getByUri(subject.uri);
    if (attributes.isEmpty) {
      return 'I found ${subject.displayName}, but there are no stored facts yet.';
    }

    final preview = attributes
        .take(3)
        .map((a) => '${_formatKey(a.key)}: ${a.value}')
        .join('; ');
    final remainder = attributes.length > 3
        ? ' (+${attributes.length - 3} more)'
        : '';
    return '${subject.displayName} — $preview$remainder';
  }

  Future<String> _answerGlobalAttributeQuery(String rawAttributeKey) async {
    final attributeKey = UriUtils.nameToIdentifier(rawAttributeKey);
    if (attributeKey.isEmpty) {
      return 'I could not determine which attribute you asked for.';
    }

    final attributes = await _attributeRepository.getByKey(attributeKey);
    if (attributes.isEmpty) {
      return 'I do not have any stored ${_formatKey(attributeKey)} values yet.';
    }

    if (attributes.length == 1) {
      final single = attributes.first;
      final displayName = await _displayNameForUri(single.subjectUri);
      return "$displayName's ${_formatKey(attributeKey)} is ${single.value}.";
    }

    final samples = <String>[];
    for (final attribute in attributes.take(3)) {
      final displayName = await _displayNameForUri(attribute.subjectUri);
      samples.add('$displayName: ${attribute.value}');
    }
    final remainder = attributes.length > 3
        ? ' (+${attributes.length - 3} more)'
        : '';
    return '${_formatKey(attributeKey)} entries: ${samples.join('; ')}$remainder';
  }

  Future<_ResolvedSubject?> _resolveSubject(String subjectName) async {
    final cleanedName = _cleanSubjectName(subjectName);
    if (cleanedName.isEmpty) return null;

    final matches = await _recordRepository.searchByName(cleanedName);
    if (matches.isNotEmpty) {
      final exact = matches.firstWhere(
        (r) => r.displayName.toLowerCase() == cleanedName.toLowerCase(),
        orElse: () => matches.first,
      );
      return _ResolvedSubject(uri: exact.uri, displayName: exact.displayName);
    }

    final inferredUri = _inferSubjectUri(cleanedName);
    if (inferredUri == null) return null;

    final inferredRecord = await _recordRepository.getByUri(inferredUri);
    if (inferredRecord != null) {
      return _ResolvedSubject(
        uri: inferredRecord.uri,
        displayName: inferredRecord.displayName,
      );
    }

    final attributes = await _attributeRepository.getByUri(inferredUri);
    if (attributes.isNotEmpty) {
      return _ResolvedSubject(uri: inferredUri, displayName: cleanedName);
    }

    return null;
  }

  String? _inferSubjectUri(String subjectName) {
    if (subjectName.trim().isEmpty) return null;
    final parsed = _inputParser.parse("$subjectName's profile is known");
    return parsed.subjectUri?.toString();
  }

  Future<String> _displayNameForUri(String uri) async {
    final record = await _recordRepository.getByUri(uri);
    if (record != null) return record.displayName;

    final segments = uri.split('.');
    if (segments.length >= 3) {
      return _formatKey(segments[2]);
    }
    return uri;
  }

  String _cleanSubjectName(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'^(the|a|an)\s+', caseSensitive: false), '')
        .replaceAll(RegExp(r'[?.!]+$'), '')
        .trim();
  }

  String _cleanAttributeKey(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'^(the|a|an)\s+', caseSensitive: false), '')
        .replaceAll(RegExp(r'[?.!]+$'), '')
        .trim();
  }

  String _formatKey(String key) {
    return key
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}

class _QueryIntent {
  final String? subjectName;
  final String? attributeKey;

  const _QueryIntent({
    this.subjectName,
    this.attributeKey,
  });
}

class _ResolvedSubject {
  final String uri;
  final String displayName;

  const _ResolvedSubject({
    required this.uri,
    required this.displayName,
  });
}
