import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/attribute.dart';
import '../../domain/entities/dojo_uri.dart';
import '../../domain/entities/journal_entry.dart';
import '../../domain/entities/record.dart';
import '../../domain/entities/rolo.dart';
import '../../domain/entities/sensei_response.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/attribute_repository.dart';
import '../../domain/repositories/journal_repository.dart';
import '../../domain/repositories/record_repository.dart';
import '../../domain/repositories/rolo_repository.dart';
import '../../domain/repositories/sensei_repository.dart';
import '../../domain/repositories/user_repository.dart';
import 'input_parser.dart';
import 'location_service.dart';
import 'sensei_llm_service.dart';
import '../utils/uri_utils.dart';

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

/// Result of processing a journal-mode input.
class JournalProcessingResult {
  /// User-authored journal row.
  final JournalEntry userEntry;

  /// Sensei-authored journal row.
  final JournalEntry senseiEntry;

  /// Audit rolo created for this journal input.
  final Rolo rolo;

  /// Final Sensei message for UI display.
  final String message;

  const JournalProcessingResult({
    required this.userEntry,
    required this.senseiEntry,
    required this.rolo,
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
  final JournalRepository? _journalRepository;
  final InputParser _inputParser;
  final SenseiLlmService? _senseiLlm;
  final SenseiRepository? _senseiRepository;
  final UserRepository? _userRepository;
  final LocationService _locationService;
  final Uuid _uuid;

  DojoService({
    required RoloRepository roloRepository,
    required RecordRepository recordRepository,
    required AttributeRepository attributeRepository,
    JournalRepository? journalRepository,
    InputParser? inputParser,
    SenseiLlmService? senseiLlm,
    SenseiRepository? senseiRepository,
    UserRepository? userRepository,
    LocationService? locationService,
  })  : _roloRepository = roloRepository,
        _recordRepository = recordRepository,
        _attributeRepository = attributeRepository,
        _journalRepository = journalRepository,
        _inputParser = inputParser ?? InputParser(),
        _senseiLlm = senseiLlm,
        _senseiRepository = senseiRepository,
        _userRepository = userRepository,
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
    bool persistSenseiResponse = true,
    String? fallbackTargetUri,
    UserProfile? primaryUser,
  }) async {
    // Every user summoning should capture the device coordinates when possible.
    final enrichedMetadata = await _enrichMetadataWithLocation(metadata);
    final resolvedPrimaryUser = primaryUser ?? await _getPrimaryUserProfile();

    // Parse every input through Sensei (LLM-first with vault context).
    final parserFallback = _inputParser.parse(input);
    var parsed = parserFallback;
    var parsedFromLlm = false;

    if (_senseiLlm != null) {
      final parsingContext = await _buildLlmParsingContext(
        input: input,
        parserFallback: parserFallback,
        primaryUser: resolvedPrimaryUser,
      );
      final llmExtraction = await _senseiLlm!.parseInput(
        input,
        context: parsingContext,
      );
      parsed = _parsedInputFromExtraction(
        input: input,
        fallback: parserFallback,
        extraction: llmExtraction,
      );
      parsedFromLlm = _senseiLlm!.healthStatus.value.isHealthy;
    }

    if (parsed.canCreateAttribute && parsed.subjectName != null) {
      final preferredCategory = parsed.subjectUri != null
          ? UriUtils.getCategoryFromString(parsed.subjectUri!.toString())
          : null;
      final matchedRecord = await _findExistingRecordByName(
        parsed.subjectName!,
        preferredCategory: preferredCategory,
      );
      if (matchedRecord != null &&
          matchedRecord.uri != parsed.subjectUri?.toString()) {
        final matchedUri = DojoUri.tryParse(matchedRecord.uri);
        if (matchedUri != null) {
          parsed = ParsedInput(
            subjectName: matchedRecord.displayName,
            subjectUri: matchedUri,
            attributeKey: parsed.attributeKey,
            attributeValue: parsed.attributeValue,
            isQuery: parsed.isQuery,
            confidence: parsed.confidence,
            originalText: parsed.originalText,
          );
        }
      }
    }

    // Create the Rolo
    final roloId = _uuid.v4();
    final rolo = Rolo(
      id: roloId,
      type: parsed.isQuery ? RoloType.request : RoloType.input,
      summoningText: input,
      targetUri: parsed.subjectUri?.toString() ?? fallbackTargetUri,
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
      final subjectUri = parsed.subjectUri!.toString();
      final now = DateTime.now();
      final subjectLabel = parsed.subjectName ?? subjectUri;

      // Check if record exists
      final existingRecord = await _recordRepository.getByUri(subjectUri);
      final existingAttribute = await _attributeRepository.get(
        subjectUri,
        parsed.attributeKey!,
      );
      final sameValueAlreadyStored = existingAttribute?.value != null &&
          _valuesEquivalent(existingAttribute!.value!, parsed.attributeValue);
      final hasConflictingValue = existingAttribute?.value != null &&
          !_valuesEquivalent(existingAttribute!.value!, parsed.attributeValue);
      final shouldProtectExistingValue = parsedFromLlm &&
          !parserFallback.canCreateAttribute &&
          hasConflictingValue &&
          !_isExplicitUpdateInput(input);

      if (sameValueAlreadyStored) {
        record = existingRecord;
        attribute = existingAttribute;
        message = 'No change made. $subjectLabel already has '
            '${_formatKey(parsed.attributeKey!)} set to '
            '"${existingAttribute!.value}".';
      } else if (shouldProtectExistingValue) {
        record = existingRecord;
        attribute = existingAttribute;
        message = 'Existing ${_formatKey(parsed.attributeKey!)} for '
            '$subjectLabel is "${existingAttribute!.value}". '
            'I did not overwrite it automatically. '
            'Use an explicit update command or edit it in The Vault.';
      } else {
        if (existingRecord == null) {
          // Create new record
          record = Record(
            uri: subjectUri,
            displayName: parsed.subjectName!,
            lastRoloId: roloId,
            updatedAt: now,
          );
          await _recordRepository.upsert(record);
          createdNewRecord = true;
        } else {
          // Update existing record's last_rolo_id
          record = existingRecord.copyWith(
            lastRoloId: roloId,
            updatedAt: now,
          );
          await _recordRepository.upsert(record);
        }

        // Create/update the attribute
        attribute = Attribute(
          subjectUri: subjectUri,
          key: parsed.attributeKey!,
          value: parsed.attributeValue,
          lastRoloId: roloId,
          updatedAt: now,
        );
        await _attributeRepository.upsert(attribute);

        message = createdNewRecord
            ? 'Created $subjectLabel with ${_formatKey(parsed.attributeKey!)}: ${parsed.attributeValue}'
            : 'Updated $subjectLabel\'s ${_formatKey(parsed.attributeKey!)} to ${parsed.attributeValue}';
      }
    } else if (parsed.isQuery) {
      message = await _answerQueryFromVault(
        query: input,
        parsed: parsed,
        primaryUser: resolvedPrimaryUser,
      );
    } else {
      message = 'Input recorded. Unable to extract structured data.';
    }

    if (persistSenseiResponse) {
      await _persistSenseiResponse(
        inputRoloId: roloId,
        targetUri: rolo.targetUri,
        responseText: message,
        confidenceScore: parsed.confidence,
      );
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
    final auditRolo = await _createAuditRolo(
      summoningText: 'Delete $key from $subjectUri',
      targetUri: subjectUri,
      trigger: 'Manual_Delete',
    );

    // Soft-delete the attribute
    return _attributeRepository.softDelete(subjectUri, key, auditRolo.id);
  }

  /// Manually updates an attribute value with an explicit audit Rolo.
  Future<Attribute> updateAttributeValue({
    required String subjectUri,
    required String key,
    required String value,
  }) async {
    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      throw ArgumentError('Attribute value cannot be empty.');
    }

    final existing = await _attributeRepository.get(subjectUri, key);
    if (existing == null) {
      throw StateError('Attribute "$key" does not exist for $subjectUri.');
    }

    final normalizedExisting = existing.value?.trim() ?? '';
    if (_valuesEquivalent(normalizedExisting, trimmedValue)) {
      return existing;
    }

    final now = DateTime.now();
    final auditRolo = await _createAuditRolo(
      summoningText:
          'Manual edit: $key for $subjectUri from "${existing.value ?? '(empty)'}" '
          'to "$trimmedValue"',
      targetUri: subjectUri,
    );

    final updated = existing.copyWith(
      value: trimmedValue,
      lastRoloId: auditRolo.id,
      updatedAt: now,
    );
    await _attributeRepository.upsert(updated);
    return updated;
  }

  /// Manually renames a record display name with an audit Rolo.
  Future<Record> updateRecordDisplayName({
    required String uri,
    required String displayName,
  }) async {
    final trimmedName = displayName.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Display name cannot be empty.');
    }

    final existing = await _recordRepository.getByUri(uri);
    if (existing == null) {
      throw StateError('Record not found for uri "$uri".');
    }
    if (_valuesEquivalent(existing.displayName, trimmedName)) {
      return existing;
    }

    final now = DateTime.now();
    final auditRolo = await _createAuditRolo(
      summoningText:
          'Manual edit: rename "$uri" from "${existing.displayName}" to "$trimmedName"',
      targetUri: uri,
    );

    final updated = existing.copyWith(
      displayName: trimmedName,
      lastRoloId: auditRolo.id,
      updatedAt: now,
    );
    await _recordRepository.upsert(updated);
    return updated;
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

  /// Retrieves the primary user profile from `tbl_user`.
  Future<UserProfile?> getPrimaryUserProfile() async {
    return _userRepository?.getPrimary();
  }

  /// Creates or updates the primary user profile in `tbl_user`.
  Future<UserProfile> upsertPrimaryUserProfile({
    required String displayName,
    String? preferredName,
    Map<String, dynamic> profile = const {},
  }) async {
    final now = DateTime.now().toUtc();
    final existing = _userRepository != null
        ? await _userRepository!.getPrimary()
        : null;
    final userProfile = (existing ??
            UserProfile(
              userId: UserProfile.primaryUserId,
              displayName: displayName,
              preferredName: preferredName,
              profile: profile,
              createdAt: now,
              updatedAt: now,
            ))
        .copyWith(
          displayName: displayName,
          preferredName: preferredName,
          profile: profile,
          updatedAt: now,
        );

    if (_userRepository == null) {
      return userProfile;
    }

    return _userRepository!.upsert(userProfile);
  }

  /// Retrieves recent Sensei responses from `tbl_sensei`.
  Future<List<SenseiResponse>> getRecentSenseiResponses({int limit = 50}) async {
    if (_senseiRepository == null) {
      return const [];
    }
    return _senseiRepository!.getRecent(limit: limit);
  }

  /// Retrieves Sensei responses linked to a specific input rolo.
  Future<List<SenseiResponse>> getSenseiResponsesForInput(String roloId) async {
    if (_senseiRepository == null) {
      return const [];
    }
    return _senseiRepository!.getByInputRoloId(roloId);
  }

  /// Processes a Journal Mode input and stores both user + Sensei rows.
  ///
  /// The journal flow focuses on reflective prompts (mood, people, places),
  /// supports "what happened today" recall queries, and can produce
  /// day/week summary blocks.
  Future<JournalProcessingResult> processJournalEntry(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Journal input cannot be empty.');
    }

    final primaryUser = await _getPrimaryUserProfile();
    final vaultSummoning = await processSummoning(
      trimmed,
      metadata: const RoloMetadata(trigger: 'Journal_Entry'),
      persistSenseiResponse: false,
      fallbackTargetUri: _journalTargetUri(DateTime.now()),
      primaryUser: primaryUser,
    );
    final rolo = vaultSummoning.rolo;
    final dayKey = _journalDayKey(rolo.timestamp);
    final userEntryMetadata = <String, dynamic>{
      ..._journalMetadataFromRolo(rolo.metadata),
      if (vaultSummoning.record != null)
        'vault_record_uri': vaultSummoning.record!.uri,
      if (vaultSummoning.attribute != null)
        'vault_attribute_key': vaultSummoning.attribute!.key,
      if (vaultSummoning.attribute != null)
        'vault_attribute_value': vaultSummoning.attribute!.value,
      'vault_augmented': vaultSummoning.attribute != null,
    };

    final userEntry = JournalEntry(
      id: _uuid.v4(),
      journalDate: dayKey,
      role: JournalRole.user,
      entryType: JournalEntryType.partial,
      content: trimmed,
      sourceRoloId: rolo.id,
      metadata: userEntryMetadata,
      createdAt: rolo.timestamp,
    );
    if (_journalRepository != null) {
      await _journalRepository!.create(userEntry);
    }

    final dayEntries = await getJournalEntriesForDate(rolo.timestamp, limit: 500);
    final sourceEntries = dayEntries.isEmpty
        ? <JournalEntry>[userEntry]
        : dayEntries;

    final responseType = _resolveJournalResponseType(trimmed);
    late final String responseText;
    if (responseType == JournalEntryType.dailySummary) {
      responseText = await _buildDailySummaryBlock(
        rolo.timestamp,
        requestPrompt: trimmed,
        primaryUser: primaryUser,
      );
    } else if (responseType == JournalEntryType.weeklySummary) {
      responseText = await _buildWeeklySummaryBlock(
        rolo.timestamp,
        requestPrompt: trimmed,
        primaryUser: primaryUser,
      );
    } else if (responseType == JournalEntryType.recall) {
      responseText = await _buildJournalRecallResponse(
        trimmed,
        sourceEntries,
        primaryUser: primaryUser,
      );
    } else {
      responseText = await _buildJournalFollowUpResponse(
        trimmed,
        sourceEntries,
        primaryUser: primaryUser,
      );
    }

    final senseiEntry = JournalEntry(
      id: _uuid.v4(),
      journalDate: dayKey,
      role: JournalRole.sensei,
      entryType: responseType,
      content: responseText,
      sourceRoloId: rolo.id,
      metadata: {
        'mode': 'journal',
        'response_type': responseType.value,
      },
      createdAt: DateTime.now().toUtc(),
    );
    if (_journalRepository != null) {
      await _journalRepository!.create(senseiEntry);
    }

    await _persistSenseiResponse(
      inputRoloId: rolo.id,
      targetUri: rolo.targetUri,
      responseText: responseText,
      confidenceScore: 0.88,
    );

    return JournalProcessingResult(
      userEntry: userEntry,
      senseiEntry: senseiEntry,
      rolo: rolo,
      message: responseText,
    );
  }

  /// Returns journal rows for a specific day.
  Future<List<JournalEntry>> getJournalEntriesForDate(
    DateTime day, {
    int limit = 300,
  }) async {
    if (_journalRepository == null) {
      return const [];
    }
    return _journalRepository!.getByDate(_journalDayKey(day), limit: limit);
  }

  /// Returns journal rows across the week containing [anchorDay].
  Future<List<JournalEntry>> getJournalEntriesForWeek(
    DateTime anchorDay, {
    int limit = 1500,
  }) async {
    if (_journalRepository == null) {
      return const [];
    }
    final weekStart = _startOfWeek(anchorDay);
    final weekEnd = weekStart.add(const Duration(days: 6));
    return _journalRepository!.getByDateRange(
      _journalDayKey(weekStart),
      _journalDayKey(weekEnd),
      limit: limit,
    );
  }

  /// Returns recent journal rows (across days).
  Future<List<JournalEntry>> getRecentJournalEntries({int limit = 200}) async {
    if (_journalRepository == null) {
      return const [];
    }
    return _journalRepository!.getRecent(limit: limit);
  }

  /// Generates and persists a clean day summary block for Journal Mode.
  Future<JournalEntry?> generateDailyJournalSummary({DateTime? day}) async {
    if (_journalRepository == null) {
      return null;
    }
    final targetDay = day ?? DateTime.now();
    final primaryUser = await _getPrimaryUserProfile();
    final summaryText = await _buildDailySummaryBlock(
      targetDay,
      primaryUser: primaryUser,
    );
    final entry = JournalEntry(
      id: _uuid.v4(),
      journalDate: _journalDayKey(targetDay),
      role: JournalRole.sensei,
      entryType: JournalEntryType.dailySummary,
      content: summaryText,
      metadata: const {
        'mode': 'journal',
        'generated': 'manual_daily_summary',
      },
      createdAt: DateTime.now().toUtc(),
    );
    await _journalRepository!.create(entry);
    return entry;
  }

  /// Generates and persists a weekly journal summary block.
  Future<JournalEntry?> generateWeeklyJournalSummary({DateTime? anchorDay}) async {
    if (_journalRepository == null) {
      return null;
    }
    final anchor = anchorDay ?? DateTime.now();
    final weekStart = _startOfWeek(anchor);
    final primaryUser = await _getPrimaryUserProfile();
    final summaryText = await _buildWeeklySummaryBlock(
      anchor,
      primaryUser: primaryUser,
    );
    final entry = JournalEntry(
      id: _uuid.v4(),
      journalDate: _journalDayKey(weekStart),
      role: JournalRole.sensei,
      entryType: JournalEntryType.weeklySummary,
      content: summaryText,
      metadata: {
        'mode': 'journal',
        'generated': 'manual_weekly_summary',
        'week_start': _journalDayKey(weekStart),
        'week_end': _journalDayKey(weekStart.add(const Duration(days: 6))),
      },
      createdAt: DateTime.now().toUtc(),
    );
    await _journalRepository!.create(entry);
    return entry;
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

  Future<LlmParsingContext> _buildLlmParsingContext({
    required String input,
    required ParsedInput parserFallback,
    required UserProfile? primaryUser,
  }) async {
    final recentRolos = await _roloRepository.getRecent(limit: 8);
    final recentTargetUris = recentRolos
        .where((r) => r.targetUri != null)
        .map((r) => r.targetUri!)
        .toSet()
        .take(6)
        .toList(growable: false);

    final hintAttributeKeys = <String>{};
    final knownRecordSummaries = <String>[];
    final knownFactSummaries = <String>[];
    final seenRecordUris = <String>{};
    final seenFactKeys = <String>{};

    void addRecordSummary(Record record) {
      if (!seenRecordUris.add(record.uri)) {
        return;
      }
      knownRecordSummaries.add('${record.displayName} (${record.uri})');
    }

    void addFactSummary(Attribute attribute) {
      final factId = '${attribute.subjectUri}.${attribute.key}';
      if (!seenFactKeys.add(factId)) {
        return;
      }
      hintAttributeKeys.add(attribute.key);
      knownFactSummaries.add(
        '$factId = ${_truncateForPrompt(attribute.value ?? '(deleted)', 90)}',
      );
    }

    final fallbackUri = parserFallback.subjectUri?.toString();
    if (fallbackUri != null) {
      final directRecord = await _recordRepository.getByUri(fallbackUri);
      if (directRecord != null) {
        addRecordSummary(directRecord);
      }
      final directAttributes = await _attributeRepository.getByUri(fallbackUri);
      for (final attribute in directAttributes.take(10)) {
        addFactSummary(attribute);
      }
    }

    final subjectName = parserFallback.subjectName?.trim();
    if (subjectName != null && subjectName.isNotEmpty) {
      final byName = await _recordRepository.searchByName(subjectName);
      for (final record in byName.take(6)) {
        addRecordSummary(record);
        final attrs = await _attributeRepository.getByUri(record.uri);
        for (final attr in attrs.take(6)) {
          addFactSummary(attr);
        }
        if (knownFactSummaries.length >= 16) {
          break;
        }
      }
    }

    final normalizedQuery = _normalizeQueryForVaultSearch(input);
    if (normalizedQuery.isNotEmpty) {
      final attrsBySearch = await _attributeRepository.search(normalizedQuery);
      for (final attr in attrsBySearch.take(12)) {
        addFactSummary(attr);
      }
    }

    return LlmParsingContext(
      userProfileSummary: _buildUserProfileSummary(primaryUser),
      parserSubjectUriHint: parserFallback.subjectUri?.toString(),
      recentSummonings: recentRolos
          .map((r) => _truncateForPrompt(r.summoningText, 140))
          .toList(growable: false),
      recentTargetUris: recentTargetUris,
      hintAttributes: hintAttributeKeys.take(12).toList(growable: false),
      knownRecordSummaries: knownRecordSummaries.take(8).toList(growable: false),
      knownFactSummaries: knownFactSummaries.take(16).toList(growable: false),
    );
  }

  ParsedInput _parsedInputFromExtraction({
    required String input,
    required ParsedInput fallback,
    required LlmExtraction extraction,
  }) {
    if (!extraction.canCreateAttribute && !extraction.isQuery) {
      return fallback;
    }

    final subjectName = extraction.subjectName;
    final inferredSubjectUri = subjectName == null
        ? null
        : _inputParser.parse("$subjectName's x is y").subjectUri;

    return ParsedInput(
      subjectName: subjectName,
      subjectUri: inferredSubjectUri,
      attributeKey: extraction.attributeKey,
      attributeValue: extraction.attributeValue,
      isQuery: extraction.isQuery,
      confidence: extraction.confidence > 0 ? extraction.confidence : fallback.confidence,
      originalText: input,
    );
  }

  Future<Record?> _findExistingRecordByName(
    String displayName, {
    DojoCategory? preferredCategory,
  }) async {
    final query = displayName.trim();
    if (query.isEmpty) {
      return null;
    }

    final candidates = await _recordRepository.searchByName(query);
    if (candidates.isEmpty) {
      return null;
    }

    final normalizedQuery = _normalizeDisplayName(query);
    Record? fallbackMatch;
    for (final candidate in candidates) {
      final normalizedCandidate = _normalizeDisplayName(candidate.displayName);
      if (normalizedCandidate != normalizedQuery) {
        continue;
      }

      final category = UriUtils.getCategoryFromString(candidate.uri);
      if (preferredCategory == null || category == preferredCategory) {
        return candidate;
      }
      fallbackMatch ??= candidate;
    }
    return fallbackMatch;
  }

  Future<String> _answerQueryFromVault({
    required String query,
    required ParsedInput parsed,
    required UserProfile? primaryUser,
  }) async {
    final bundle = await _buildVaultContextBundle(
      query: query,
      parsed: parsed,
      primaryUser: primaryUser,
    );
    final journalBundle = await _buildJournalQueryContext(query);
    final combinedContext = journalBundle.hasFacts
        ? '${bundle.context}\n\nJournal context:\n${journalBundle.context}'
        : bundle.context;
    final combinedSources = _mergeSources(
      bundle.sourcesUsed,
      journalBundle.sourcesUsed,
    );

    if (bundle.directAnswer != null) {
      return '${bundle.directAnswer}\n\n'
          '${_buildSourcesUsedSection(combinedSources)}';
    }

    if (_senseiLlm != null) {
      try {
        final llmAnswer = await _senseiLlm!.answerWithVault(
          question: query,
          vaultContext: combinedContext,
          userProfileSummary: _buildUserProfileSummary(primaryUser),
        );
        final normalized = llmAnswer.trim();
        if (normalized.isNotEmpty) {
          return '$normalized\n\n${_buildSourcesUsedSection(combinedSources)}';
        }
      } catch (e) {
        debugPrint('[DojoService] Query answer via LLM failed: $e');
      }
    }

    if (!bundle.hasFacts && !journalBundle.hasFacts) {
      return 'I searched your vault but could not find enough related facts '
          'for that question yet.\n\n'
          '${_buildSourcesUsedSection(combinedSources)}';
    }

    final previewSections = <String>[
      if (bundle.factsPreview.trim().isNotEmpty)
        'Vault:\n${bundle.factsPreview.trim()}',
      if (journalBundle.factsPreview.trim().isNotEmpty)
        'Journal:\n${journalBundle.factsPreview.trim()}',
    ];
    return 'I found related vault facts, but could not produce a complete '
        'answer right now. Relevant entries:\n'
        '${previewSections.join('\n\n')}\n\n'
        '${_buildSourcesUsedSection(combinedSources)}';
  }

  Future<_VaultContextBundle> _buildVaultContextBundle({
    required String query,
    required ParsedInput parsed,
    required UserProfile? primaryUser,
  }) async {
    final normalizedQuery = _normalizeQueryForVaultSearch(query);
    final searchTerms = _extractVaultSearchTerms(normalizedQuery);
    final contextLines = <String>[];
    final factLines = <String>[];
    final sourceMap = <String, Set<String>>{};
    final recordCache = <String, Record>{};
    final attributeCache = <String, Attribute>{};
    final roloCache = <String, Rolo>{};

    void addSource(String uri, String key) {
      sourceMap.putIfAbsent(uri, () => <String>{}).add(key);
    }

    void addRecordCandidate(Record record) {
      recordCache.putIfAbsent(record.uri, () => record);
    }

    void addAttributeCandidate(Attribute attribute) {
      final cacheKey = '${attribute.subjectUri}::${attribute.key}';
      attributeCache.putIfAbsent(cacheKey, () => attribute);
    }

    void addRoloCandidate(Rolo rolo) {
      roloCache.putIfAbsent(rolo.id, () => rolo);
    }

    Future<void> collectBySearchTerm(String term) async {
      final cleaned = term.trim();
      if (cleaned.isEmpty) {
        return;
      }

      final records = await _recordRepository.searchByName(cleaned);
      for (final record in records.take(10)) {
        addRecordCandidate(record);
      }

      final attrs = await _attributeRepository.search(cleaned);
      for (final attr in attrs.take(16)) {
        addAttributeCandidate(attr);
      }

      final rolos = await _roloRepository.search(cleaned);
      for (final rolo in rolos.take(12)) {
        addRoloCandidate(rolo);
      }
    }

    if (searchTerms.isEmpty) {
      await collectBySearchTerm(normalizedQuery);
    } else {
      for (final term in searchTerms.take(6)) {
        await collectBySearchTerm(term);
      }
    }

    Record? directRecord;
    List<Attribute> directAttributes = const [];
    List<Rolo> directRolos = const [];
    if (parsed.subjectUri != null) {
      final subjectUri = parsed.subjectUri!.toString();
      directRecord = await _recordRepository.getByUri(subjectUri);
      directAttributes = await _attributeRepository.getByUri(subjectUri);
      directRolos = await _roloRepository.getByTargetUri(subjectUri);
      if (directRecord != null) {
        addRecordCandidate(directRecord);
      }
      for (final attr in directAttributes) {
        addAttributeCandidate(attr);
      }
      for (final rolo in directRolos) {
        addRoloCandidate(rolo);
      }
    }

    final asksAboutSelf = RegExp(r'\bmy\b', caseSensitive: false).hasMatch(query);
    final ownerRecords = <Record>[];
    final ownerAttributes = <Attribute>[];
    if (asksAboutSelf && primaryUser != null) {
      final ownerHints = <String>{
        primaryUser.displayName.trim(),
        if ((primaryUser.preferredName?.trim().isNotEmpty ?? false))
          primaryUser.preferredName!.trim(),
      };
      final seenOwnerUris = <String>{};
      for (final hint in ownerHints) {
        if (hint.isEmpty) continue;
        final candidates = await _recordRepository.searchByName(hint);
        for (final candidate in candidates) {
          if (_normalizeDisplayName(candidate.displayName) !=
              _normalizeDisplayName(hint)) {
            continue;
          }
          if (!seenOwnerUris.add(candidate.uri)) {
            continue;
          }
          ownerRecords.add(candidate);
          addRecordCandidate(candidate);
          final attrs = await _attributeRepository.getByUri(candidate.uri);
          for (final attr in attrs) {
            ownerAttributes.add(attr);
            addAttributeCandidate(attr);
          }
          final rolos = await _roloRepository.getByTargetUri(candidate.uri);
          for (final rolo in rolos.take(8)) {
            addRoloCandidate(rolo);
          }
          if (ownerRecords.length >= 2) {
            break;
          }
        }
        if (ownerRecords.length >= 2) {
          break;
        }
      }
    }

    if (directRecord != null) {
      final line = '- Direct record: ${directRecord.displayName} '
          '(${directRecord.uri})';
      contextLines.add(line);
      factLines.add(line);
      addSource(directRecord.uri, 'display_name');
    }

    if (asksAboutSelf && ownerRecords.isNotEmpty) {
      for (final ownerRecord in ownerRecords.take(2)) {
        final line = '- Owner record: ${ownerRecord.displayName} (${ownerRecord.uri})';
        contextLines.add(line);
        factLines.add(line);
        addSource(ownerRecord.uri, 'display_name');
      }
    }

    if (directAttributes.isNotEmpty) {
      for (final attr in directAttributes.take(10)) {
        final line = '- Fact: ${attr.subjectUri}.${attr.key} = '
            '${_truncateForPrompt(attr.value ?? '(deleted)', 120)}';
        contextLines.add(line);
        factLines.add(line);
        addSource(attr.subjectUri, attr.key);
      }
    }

    final relationshipAttrs = attributeCache.values
        .where((attr) => attr.key == 'relationship_to_user')
        .toList(growable: false);
    for (final rel in relationshipAttrs.take(10)) {
      final relatedRecord = recordCache[rel.subjectUri] ??
          await _recordRepository.getByUri(rel.subjectUri);
      if (relatedRecord != null) {
        addRecordCandidate(relatedRecord);
      }
    }

    final recordsByName = recordCache.values.toList(growable: false);
    if (recordsByName.isNotEmpty) {
      for (final record in recordsByName.take(10)) {
        final line = '- Record match: ${record.displayName} (${record.uri})';
        contextLines.add(line);
        addSource(record.uri, 'display_name');
      }
    }

    final attrsBySearch = attributeCache.values.toList(growable: false);
    if (attrsBySearch.isNotEmpty) {
      final seen = <String>{};
      for (final attr in attrsBySearch.take(24)) {
        final key = '${attr.subjectUri}::${attr.key}';
        if (seen.contains(key)) continue;
        seen.add(key);
        final line = '- Vault fact: ${attr.subjectUri}.${attr.key} = '
            '${_truncateForPrompt(attr.value ?? '(deleted)', 120)}';
        contextLines.add(line);
        factLines.add(line);
        addSource(attr.subjectUri, attr.key);
        if (seen.length >= 20) break;
      }
    }

    final rolosBySearch = roloCache.values.toList(growable: false)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (directRolos.isNotEmpty || rolosBySearch.isNotEmpty) {
      final candidateRolos = <Rolo>[
        ...directRolos.take(4),
        ...rolosBySearch.take(10),
      ];
      final seenRoloIds = <String>{};
      var count = 0;
      for (final rolo in candidateRolos) {
        if (seenRoloIds.contains(rolo.id)) continue;
        seenRoloIds.add(rolo.id);
        final line = '- Ledger note: ${_truncateForPrompt(rolo.summoningText, 140)} '
            '(${_formatRoloTime(rolo.timestamp)})';
        contextLines.add(line);
        if (++count >= 8) break;
      }
    }

    String? directAnswer;
    if (asksAboutSelf &&
        (normalizedQuery.contains('address') || normalizedQuery == 'address')) {
      Attribute? ownerAddress;
      for (final attr in ownerAttributes) {
        if (attr.key == 'address' &&
            (attr.value?.trim().isNotEmpty ?? false)) {
          ownerAddress = attr;
          break;
        }
      }
      if (ownerAddress == null) {
        for (final attr in attrsBySearch) {
          if (attr.key == 'address' &&
              (attr.value?.trim().isNotEmpty ?? false)) {
            ownerAddress = attr;
            break;
          }
        }
      }

      if (ownerAddress != null && ownerAddress.value != null) {
        directAnswer = 'Your address is ${ownerAddress.value}.';
        addSource(ownerAddress.subjectUri, ownerAddress.key);
      }
    }

    if (directAnswer == null) {
      final relationshipTerm = _extractRelationshipTerm(normalizedQuery);
      final asksForName = normalizedQuery.contains('name') ||
          normalizedQuery.startsWith('who') ||
          RegExp(r'\bwho\b').hasMatch(normalizedQuery);
      if (relationshipTerm != null && asksForName) {
        var relationshipFacts = attrsBySearch
            .where((a) => a.key == 'relationship_to_user')
            .toList(growable: false);
        if (relationshipFacts.isEmpty) {
          relationshipFacts =
              await _attributeRepository.getByKey('relationship_to_user');
        }
        for (final rel in relationshipFacts) {
          final value = (rel.value ?? '').toLowerCase();
          if (!value.contains(relationshipTerm)) {
            continue;
          }
          final relatedRecord = recordCache[rel.subjectUri] ??
              await _recordRepository.getByUri(rel.subjectUri);
          if (relatedRecord != null) {
            addRecordCandidate(relatedRecord);
          }
          final relationshipLabel = relationshipTerm == 'fiancee'
              ? 'fiancee'
              : relationshipTerm;
          directAnswer = relatedRecord != null
              ? 'Your $relationshipLabel is ${relatedRecord.displayName}.'
              : 'Your $relationshipLabel is ${rel.subjectUri}.';
          addSource(rel.subjectUri, rel.key);
          if (relatedRecord != null) {
            addSource(relatedRecord.uri, 'display_name');
          }
          break;
        }
      }
    }

    if (contextLines.isEmpty) {
      contextLines.add('- No matching vault facts were found.');
    }

    final sourcesUsed = _formatSourcesFromMap(sourceMap);
    final preview = factLines.take(4).join('\n');
    return _VaultContextBundle(
      context: contextLines.join('\n'),
      hasFacts: factLines.isNotEmpty,
      factsPreview: preview,
      sourcesUsed: sourcesUsed,
      directAnswer: directAnswer,
    );
  }

  List<String> _formatSourcesFromMap(Map<String, Set<String>> sourceMap) {
    if (sourceMap.isEmpty) {
      return const [];
    }

    final uris = sourceMap.keys.toList(growable: false)..sort();
    final lines = <String>[];
    for (final uri in uris) {
      final keys = sourceMap[uri]!.toList(growable: false)..sort();
      lines.add('$uri -> ${keys.join(', ')}');
    }
    return lines;
  }

  List<String> _mergeSources(List<String> primary, List<String> secondary) {
    final merged = <String>[];
    final seen = <String>{};
    for (final source in [...primary, ...secondary]) {
      final normalized = source.trim();
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      merged.add(normalized);
    }
    return merged;
  }

  String _buildSourcesUsedSection(List<String> sources) {
    if (sources.isEmpty) {
      return 'Sources used:\n- none';
    }

    final limited = sources.take(8).toList(growable: false);
    final buffer = StringBuffer('Sources used:\n');
    for (final line in limited) {
      buffer.writeln('- $line');
    }
    final remaining = sources.length - limited.length;
    if (remaining > 0) {
      buffer.writeln('- ...and $remaining more');
    }
    return buffer.toString().trimRight();
  }

  Future<_JournalQueryContext> _buildJournalQueryContext(String query) async {
    final entries = await getRecentJournalEntries(limit: 700);
    if (entries.isEmpty) {
      return const _JournalQueryContext();
    }

    final normalizedQuery = _normalizeQueryForVaultSearch(query);
    final terms = _extractVaultSearchTerms(normalizedQuery)
        .where((term) => term.trim().isNotEmpty)
        .take(10)
        .toList(growable: false);

    final scored = <({JournalEntry entry, int score})>[];
    for (final entry in entries) {
      final content = entry.content.trim();
      if (content.isEmpty) {
        continue;
      }
      final lower = content.toLowerCase();
      var score = 0;
      for (final term in terms) {
        if (term.isEmpty) continue;
        if (lower.contains(term)) {
          score += term.length;
        }
      }
      if (score == 0 && terms.isNotEmpty) {
        continue;
      }
      if (entry.role == JournalRole.user) {
        score += 3;
      }
      if (entry.entryType == JournalEntryType.partial ||
          entry.entryType == JournalEntryType.followUp) {
        score += 1;
      }
      scored.add((entry: entry, score: score));
    }

    if (scored.isEmpty) {
      return const _JournalQueryContext();
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return b.entry.createdAt.compareTo(a.entry.createdAt);
    });

    final selected = scored.take(16).map((row) => row.entry).toList(growable: false)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (selected.isEmpty) {
      return const _JournalQueryContext();
    }

    final contextLines = <String>[];
    final factLines = <String>[];
    final sources = <String>[];
    for (final entry in selected) {
      final role = entry.role == JournalRole.user ? 'user' : 'sensei';
      final line = '- ${entry.journalDate} ${_formatRoloTime(entry.createdAt)} '
          '[$role/${entry.entryType.value}]: '
          '${_truncateForPrompt(entry.content, 140)}';
      contextLines.add(line);
      factLines.add(line);
      sources.add('journal:${entry.journalDate}#${entry.id.substring(0, 8)}');
    }

    return _JournalQueryContext(
      context: contextLines.join('\n'),
      hasFacts: factLines.isNotEmpty,
      factsPreview: factLines.take(4).join('\n'),
      sourcesUsed: sources,
    );
  }

  String _truncateForPrompt(String text, int maxLength) {
    if (text.length <= maxLength) {
      return text;
    }
    return '${text.substring(0, maxLength - 3)}...';
  }

  String _normalizeQueryForVaultSearch(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return query;
    }

    var normalized = trimmed
        .replaceAll(RegExp(r"[’']s\b"), '')
        .replaceAll(RegExp(r'^(what|who|where|when|why|how)\s+'), '')
        .replaceAll(RegExp(r'^(is|are|was|were|do|does|did|can|could)\s+'), '')
        .replaceAll(RegExp(r'^(tell me|show me|find|lookup|look up)\s+'), '')
        .replaceAll(RegExp(r'\b(my|mine|me|please)\b'), ' ')
        .replaceAll(RegExp(r'\babout\b'), '')
        .replaceAll(RegExp(r'[^a-z0-9\s._-]'), ' ')
        .replaceAll(RegExp(r'\bs\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) {
      normalized = query
          .replaceAll(RegExp(r'[^A-Za-z0-9\s._-]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }
    return normalized.isEmpty ? query.trim() : normalized;
  }

  List<String> _extractVaultSearchTerms(String normalizedQuery) {
    final cleaned = normalizedQuery.trim().toLowerCase();
    if (cleaned.isEmpty) {
      return const [];
    }

    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .where((token) => !_vaultQueryStopWords.contains(token))
        .toList(growable: false);

    final ordered = <String>[];
    final seen = <String>{};

    void addTerm(String term) {
      final value = term.trim();
      if (value.isEmpty || !seen.add(value)) {
        return;
      }
      ordered.add(value);
    }

    // Keep full normalized phrase first.
    addTerm(cleaned);

    for (final token in tokens) {
      if (token.length >= 3 || token == 'ai' || token == 'id') {
        addTerm(token);
      }
    }

    if (tokens.length >= 2) {
      for (var i = 0; i < tokens.length - 1; i++) {
        final pair = '${tokens[i]} ${tokens[i + 1]}'.trim();
        if (pair.length >= 5) {
          addTerm(pair);
        }
      }
    }

    return ordered;
  }

  String? _extractRelationshipTerm(String normalizedQuery) {
    for (final term in _relationshipTerms) {
      if (RegExp('\\b$term\\b').hasMatch(normalizedQuery)) {
        return term;
      }
    }
    return null;
  }

  String _formatRoloTime(DateTime timestamp) {
    final local = timestamp.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }

  JournalEntryType _resolveJournalResponseType(String input) {
    if (_isJournalWeeklySummaryRequest(input)) {
      return JournalEntryType.weeklySummary;
    }
    if (_isJournalDailySummaryRequest(input)) {
      return JournalEntryType.dailySummary;
    }
    if (_isJournalRecallRequest(input)) {
      return JournalEntryType.recall;
    }
    return JournalEntryType.followUp;
  }

  Future<String> _buildJournalFollowUpResponse(
    String input,
    List<JournalEntry> dayEntries, {
    required UserProfile? primaryUser,
  }) async {
    final contextEntries = await _buildJournalFollowUpContextEntries(dayEntries);
    final recentQuestions = _extractRecentSenseiQuestions(contextEntries);
    final supplementalContext = await _buildJournalFollowUpSupplementalContext(
      latestInput: input,
      dayEntries: dayEntries,
      contextEntries: contextEntries,
      recentQuestions: recentQuestions,
    );

    final llmResponse = await _tryLlmJournalResponse(
      prompt:
          'New journal entry: "$input"\nGenerate one high-value follow-up '
          'question that helps the user journal better today.',
      contextEntries: contextEntries,
      primaryUser: primaryUser,
      systemInstruction: _journalFollowUpSystemInstruction,
      maxTokens: 220,
      temperature: 0.55,
      extraContext: supplementalContext,
    );
    final normalizedQuestion = _normalizeJournalQuestion(llmResponse);
    if (normalizedQuestion != null &&
        !_isQuestionRepetitive(normalizedQuestion, recentQuestions)) {
      return normalizedQuestion;
    }

    if (recentQuestions.isNotEmpty) {
      final retryResponse = await _tryLlmJournalResponse(
        prompt:
            'The previous question was too similar to prior follow-ups. '
            'Ask one different follow-up question that explores a new angle.\n'
            'Avoid these prior questions:\n'
            '${recentQuestions.take(8).map((q) => '- $q').join('\n')}',
        contextEntries: contextEntries,
        primaryUser: primaryUser,
        systemInstruction: _journalFollowUpSystemInstruction,
        maxTokens: 220,
        temperature: 0.65,
        extraContext: supplementalContext,
      );
      final retryQuestion = _normalizeJournalQuestion(retryResponse);
      if (retryQuestion != null &&
          !_isQuestionRepetitive(retryQuestion, recentQuestions)) {
        return retryQuestion;
      }
    }

    return _buildJournalFollowUpFallback(
      input: input,
      contextEntries: contextEntries,
      recentQuestions: recentQuestions,
    );
  }

  Future<String> _buildJournalRecallResponse(
    String input,
    List<JournalEntry> dayEntries, {
    required UserProfile? primaryUser,
  }) async {
    final llmResponse = await _tryLlmJournalResponse(
      prompt: 'User question about today\'s journal: "$input"',
      contextEntries: dayEntries,
      primaryUser: primaryUser,
      systemInstruction: _journalRecallSystemInstruction,
      maxTokens: 260,
      temperature: 0.15,
    );
    if (llmResponse != null) {
      return llmResponse;
    }

    final lower = input.toLowerCase();
    final insights = _extractJournalInsights(dayEntries);
    if (!insights.hasAnyData) {
      return 'I do not have enough journal detail yet for recall. '
          'Add mood, people, and places as your day unfolds.';
    }

    if ((lower.contains('who') && lower.contains('met')) ||
        lower.contains('people')) {
      return 'People mentioned today: '
          '${insights.people.isEmpty ? 'none logged yet' : insights.people.join(', ')}.';
    }

    if (lower.contains('where') ||
        lower.contains('place') ||
        lower.contains('went')) {
      return 'Places logged today: '
          '${insights.places.isEmpty ? 'none logged yet' : insights.places.join(', ')}.';
    }

    if (lower.contains('mood') ||
        lower.contains('feel') ||
        lower.contains('emotion')) {
      return 'Mood signals today: '
          '${insights.moods.isEmpty ? 'not clearly logged yet' : insights.moods.join(', ')}.';
    }

    final highlights = insights.highlights.take(4).toList(growable: false);
    final summaryLines = highlights.isEmpty
        ? '- Journal data exists, but no clear highlight lines were detected yet.'
        : highlights.map((h) => '- $h').join('\n');
    return 'So far today, here is what you logged:\n$summaryLines';
  }

  Future<String> _buildDailySummaryBlock(
    DateTime day, {
    String? requestPrompt,
    UserProfile? primaryUser,
  }) async {
    final entries = await getJournalEntriesForDate(day, limit: 800);
    final llmSummary = await _tryLlmJournalResponse(
      prompt: requestPrompt?.trim().isNotEmpty == true
          ? requestPrompt!.trim()
          : 'Generate a clean end-of-day journal summary block.',
      contextEntries: entries,
      primaryUser: primaryUser,
      systemInstruction:
          '${_journalSummarySystemInstruction}\nSummary date: ${_journalDayKey(day)}',
      maxTokens: 520,
      temperature: 0.2,
    );
    if (llmSummary != null) {
      return llmSummary;
    }

    final insights = _extractJournalInsights(entries);
    final userCount = entries.where((e) => e.role == JournalRole.user).length;
    final senseiCount = entries.where((e) => e.role == JournalRole.sensei).length;

    var llmNarrative = '';
    final narrativeSource = _buildJournalNarrative(entries);
    if (narrativeSource.isNotEmpty && _senseiLlm != null && _senseiLlm!.isReady) {
      try {
        llmNarrative = await _senseiLlm!.summarize(
          narrativeSource,
          maxLength: 720,
        );
      } catch (_) {
        llmNarrative = '';
      }
    }

    final highlights = insights.highlights.take(5).toList(growable: false);
    final buffer = StringBuffer()
      ..writeln('=== JOURNAL SUMMARY (${_journalDayKey(day)}) ===')
      ..writeln(
        'Mood: ${insights.moods.isEmpty ? 'Not specified' : insights.moods.join(', ')}',
      )
      ..writeln(
        'People: ${insights.people.isEmpty ? 'Not specified' : insights.people.join(', ')}',
      )
      ..writeln(
        'Places: ${insights.places.isEmpty ? 'Not specified' : insights.places.join(', ')}',
      )
      ..writeln('Entries captured: $userCount user / $senseiCount Sensei')
      ..writeln('Highlights:');

    if (highlights.isEmpty) {
      buffer.writeln('- No detailed highlights captured yet.');
    } else {
      for (final highlight in highlights) {
        buffer.writeln('- $highlight');
      }
    }

    if (llmNarrative.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Condensed narrative:')
        ..writeln(llmNarrative.trim());
    }

    buffer
      ..writeln()
      ..writeln('Reflection prompt:')
      ..writeln(
        insights.hasMood && insights.hasPeople && insights.hasPlaces
            ? 'What should tomorrow-you repeat or improve based on today?'
            : 'Add missing mood/people/place details to strengthen this day log.',
      );

    return buffer.toString().trimRight();
  }

  Future<String> _buildWeeklySummaryBlock(
    DateTime anchorDay, {
    String? requestPrompt,
    UserProfile? primaryUser,
  }) async {
    final weekStart = _startOfWeek(anchorDay);
    final weekEnd = weekStart.add(const Duration(days: 6));
    final weekEntries = await getJournalEntriesForWeek(anchorDay, limit: 1600);

    final llmSummary = await _tryLlmJournalResponse(
      prompt: requestPrompt?.trim().isNotEmpty == true
          ? requestPrompt!.trim()
          : 'Generate a weekly journal summary across the provided entries.',
      contextEntries: weekEntries,
      primaryUser: primaryUser,
      systemInstruction:
          '${_journalWeeklySystemInstruction}\nWeek range: '
          '${_journalDayKey(weekStart)} to ${_journalDayKey(weekEnd)}',
      maxTokens: 620,
      temperature: 0.2,
    );
    if (llmSummary != null) {
      return llmSummary;
    }

    final byDate = <String, List<JournalEntry>>{};
    for (final entry in weekEntries) {
      byDate.putIfAbsent(entry.journalDate, () => <JournalEntry>[]).add(entry);
    }

    final aggregateMood = <String>{};
    final aggregatePeople = <String>{};
    final aggregatePlaces = <String>{};
    final dailyLines = <String>[];
    var daysLogged = 0;

    for (var i = 0; i < 7; i++) {
      final day = weekStart.add(Duration(days: i));
      final dayKey = _journalDayKey(day);
      final dayRows = byDate[dayKey] ?? const <JournalEntry>[];
      if (dayRows.isEmpty) {
        continue;
      }

      daysLogged++;
      final dayInsights = _extractJournalInsights(dayRows);
      aggregateMood.addAll(dayInsights.moods);
      aggregatePeople.addAll(dayInsights.people);
      aggregatePlaces.addAll(dayInsights.places);

      final lead = dayInsights.highlights.isNotEmpty
          ? dayInsights.highlights.first
          : 'Journal activity logged.';
      dailyLines.add('- ${_weekdayLabel(day)} ($dayKey): $lead');
    }

    final buffer = StringBuffer()
      ..writeln(
        '=== WEEKLY JOURNAL SUMMARY '
        '(${_journalDayKey(weekStart)} to ${_journalDayKey(weekEnd)}) ===',
      )
      ..writeln('Days logged: $daysLogged/7')
      ..writeln(
        'Mood trends: ${aggregateMood.isEmpty ? 'Not enough data' : aggregateMood.join(', ')}',
      )
      ..writeln(
        'People mentioned: ${aggregatePeople.isEmpty ? 'Not enough data' : aggregatePeople.join(', ')}',
      )
      ..writeln(
        'Places visited: ${aggregatePlaces.isEmpty ? 'Not enough data' : aggregatePlaces.join(', ')}',
      )
      ..writeln('Daily breakdown:');

    if (dailyLines.isEmpty) {
      buffer.writeln('- No journal entries found for this week.');
    } else {
      for (final line in dailyLines) {
        buffer.writeln(line);
      }
    }

    buffer
      ..writeln()
      ..writeln('Next-week focus:')
      ..writeln(
        'Keep logging mood shifts, people interactions, and locations each day for richer patterns.',
      );

    return buffer.toString().trimRight();
  }

  Future<String?> _tryLlmJournalResponse({
    required String prompt,
    required List<JournalEntry> contextEntries,
    required UserProfile? primaryUser,
    required String systemInstruction,
    int maxTokens = 280,
    double temperature = 0.2,
    String? extraContext,
  }) async {
    final llm = _senseiLlm;
    if (llm == null) {
      return null;
    }

    final entriesContext = _buildJournalContextBlock(contextEntries);
    if (entriesContext.isEmpty) {
      return null;
    }
    final contextSections = <String>[
      entriesContext,
    ];
    final userProfile = _buildUserProfileSummary(primaryUser);
    if (userProfile != null) {
      contextSections.insert(0, '- User profile: $userProfile');
    }
    final supplemental = extraContext?.trim();
    if (supplemental != null && supplemental.isNotEmpty) {
      contextSections.add(supplemental);
    }
    final contextBlock = contextSections.join('\n');

    try {
      final response = await llm.answerWithContext(
        prompt: prompt,
        context: contextBlock,
        systemInstruction: systemInstruction,
        maxTokens: maxTokens,
        temperature: temperature,
      );
      final normalized = response.trim();
      return normalized.isEmpty ? null : normalized;
    } catch (e) {
      debugPrint('[DojoService] Journal LLM response failed: $e');
      return null;
    }
  }

  String _buildJournalContextBlock(List<JournalEntry> entries) {
    if (entries.isEmpty) {
      return '';
    }

    final normalizedEntries = [...entries]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final lines = <String>[];
    var added = 0;
    for (final entry in normalizedEntries) {
      if (entry.entryType == JournalEntryType.weeklySummary ||
          entry.entryType == JournalEntryType.dailySummary) {
        continue;
      }
      final content = entry.content.trim();
      if (content.isEmpty) {
        continue;
      }
      final author = entry.role == JournalRole.user ? 'User' : 'Sensei';
      lines.add(
        '- ${entry.journalDate} ${_formatRoloTime(entry.createdAt)} '
        '[$author/${entry.entryType.value}]: '
        '${_truncateForPrompt(content, 220)}',
      );
      if (++added >= 40) {
        break;
      }
    }

    return lines.join('\n');
  }

  Future<List<JournalEntry>> _buildJournalFollowUpContextEntries(
    List<JournalEntry> dayEntries,
  ) async {
    final recentEntries = await getRecentJournalEntries(limit: 800);
    final mergedById = <String, JournalEntry>{};
    for (final entry in recentEntries) {
      mergedById[entry.id] = entry;
    }
    for (final entry in dayEntries) {
      mergedById[entry.id] = entry;
    }

    final merged = mergedById.values.toList(growable: false)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (merged.length <= 48) {
      return merged;
    }
    return merged.sublist(merged.length - 48);
  }

  Future<String> _buildJournalFollowUpSupplementalContext({
    required String latestInput,
    required List<JournalEntry> dayEntries,
    required List<JournalEntry> contextEntries,
    required List<String> recentQuestions,
  }) async {
    final nowKey = _journalDayKey(DateTime.now());
    final recentRolos = await _roloRepository.getRecent(limit: 320);
    final todayRoloLines = <String>[];
    final historicalRoloLines = <String>[];
    final seenRoloSummonings = <String>{};
    for (final rolo in recentRolos) {
      final text = rolo.summoningText.trim();
      if (text.isEmpty) {
        continue;
      }
      final normalized = _normalizeQuestionForComparison(text);
      if (normalized.isNotEmpty && !seenRoloSummonings.add(normalized)) {
        continue;
      }

      final line = '- ${_journalDayKey(rolo.timestamp)} '
          '${_formatRoloTime(rolo.timestamp)}: ${_truncateForPrompt(text, 130)}';
      if (_journalDayKey(rolo.timestamp) == nowKey) {
        if (todayRoloLines.length < 18) {
          todayRoloLines.add(line);
        }
      } else if (historicalRoloLines.length < 8) {
        historicalRoloLines.add(line);
      }

      if (todayRoloLines.length >= 18 && historicalRoloLines.length >= 8) {
        break;
      }
    }

    final query = _normalizeQueryForVaultSearch(latestInput);
    final relatedVaultFacts = <String>[];
    if (query.trim().isNotEmpty) {
      final attrs = await _attributeRepository.search(query);
      for (final attr in attrs.take(8)) {
        relatedVaultFacts.add(
          '- ${attr.subjectUri}.${attr.key} = '
          '${_truncateForPrompt(attr.value ?? '(deleted)', 90)}',
        );
      }
    }

    final insights = _extractJournalInsights(dayEntries);
    final coverageSignals = <String>[
      if (insights.moods.isNotEmpty) 'moods: ${insights.moods.join(', ')}',
      if (insights.people.isNotEmpty) 'people: ${insights.people.join(', ')}',
      if (insights.places.isNotEmpty) 'places: ${insights.places.join(', ')}',
      if (insights.highlights.isNotEmpty)
        'highlights: ${insights.highlights.take(3).map((h) => _truncateForPrompt(h, 70)).join(' | ')}',
      if (!insights.hasMood) 'missing mood depth',
      if (!insights.hasPeople) 'missing people interactions',
      if (!insights.hasPlaces) 'missing place details',
    ];

    final journalLinesAnalyzed = contextEntries
        .where((entry) => entry.content.trim().isNotEmpty)
        .length;
    final buffer = StringBuffer()
      ..writeln('Journal coaching reference (expanded context):')
      ..writeln('- Latest input: ${_truncateForPrompt(latestInput, 180)}')
      ..writeln('- Journal lines analyzed: $journalLinesAnalyzed')
      ..writeln('- Coverage signals: ${coverageSignals.join('; ')}')
      ..writeln(
        '- Recently asked Sensei questions to avoid repeating: '
        '${recentQuestions.isEmpty ? 'none' : recentQuestions.take(8).join(' | ')}',
      )
      ..writeln('Web-inspired journal quality criteria:')
      ..writeln(_journalWebInspiredQualityCriteria.map((q) => '- $q').join('\n'))
      ..writeln('Web-inspired prompt angles (adapt to user context, do not copy verbatim):')
      ..writeln(_journalWebInspiredPromptAngles.map((q) => '- $q').join('\n'))
      ..writeln('Today text capture (from ledger rolos):')
      ..writeln(
        todayRoloLines.isEmpty
            ? '- No additional same-day rolos captured.'
            : todayRoloLines.join('\n'),
      )
      ..writeln('Relevant historical text (for continuity):')
      ..writeln(
        historicalRoloLines.isEmpty
            ? '- No historical rolo snippets selected.'
            : historicalRoloLines.join('\n'),
      )
      ..writeln('Related vault facts:')
      ..writeln(
        relatedVaultFacts.isEmpty
            ? '- No directly related vault facts found.'
            : relatedVaultFacts.join('\n'),
      );
    return buffer.toString().trimRight();
  }

  List<String> _extractRecentSenseiQuestions(
    List<JournalEntry> entries, {
    int limit = 12,
  }) {
    final sorted = [...entries]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final questions = <String>[];
    final seen = <String>{};
    for (final entry in sorted) {
      if (entry.role != JournalRole.sensei) {
        continue;
      }
      final extracted = _extractQuestionCandidates(entry.content);
      for (final question in extracted) {
        final normalized = _normalizeQuestionForComparison(question);
        if (normalized.isEmpty || !seen.add(normalized)) {
          continue;
        }
        questions.add(question.trim());
        if (questions.length >= limit) {
          return questions;
        }
      }
    }
    return questions;
  }

  List<String> _extractQuestionCandidates(String text) {
    final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) {
      return const [];
    }
    final matches = RegExp(r'[^?]{8,}\?').allMatches(compact);
    if (matches.isNotEmpty) {
      return matches
          .map((m) => m.group(0)!.trim())
          .where((line) => line.length >= 8)
          .toList(growable: false);
    }
    if (compact.endsWith('?') && compact.length >= 8) {
      return <String>[compact];
    }
    return const [];
  }

  String? _normalizeJournalQuestion(String? raw) {
    if (raw == null) {
      return null;
    }
    var text = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) {
      return null;
    }

    text = text.replaceAll(RegExp(r'^(question|follow-up)\s*:\s*', caseSensitive: false), '');
    final questionMatches = RegExp(r'[^?]{8,}\?').allMatches(text).toList();
    if (questionMatches.isNotEmpty) {
      text = questionMatches.first.group(0)!.trim();
    } else if (!text.endsWith('?')) {
      text = '$text?';
    }

    return text.trim();
  }

  bool _isQuestionRepetitive(String candidate, List<String> previousQuestions) {
    final candidateNormalized = _normalizeQuestionForComparison(candidate);
    if (candidateNormalized.isEmpty) {
      return false;
    }
    final candidateTokens = _questionContentTokens(candidateNormalized);
    for (final previous in previousQuestions) {
      final previousNormalized = _normalizeQuestionForComparison(previous);
      if (candidateNormalized == previousNormalized) {
        return true;
      }
      final previousTokens = _questionContentTokens(previousNormalized);
      if (candidateTokens.isEmpty || previousTokens.isEmpty) {
        continue;
      }
      final overlap = candidateTokens.intersection(previousTokens).length;
      final union = candidateTokens.union(previousTokens).length;
      if (union > 0 && (overlap / union) >= 0.72) {
        return true;
      }
    }
    return false;
  }

  Set<String> _questionContentTokens(String normalized) {
    return normalized
        .split(' ')
        .where((token) => token.isNotEmpty && !_journalQuestionStopWords.contains(token))
        .toSet();
  }

  String _normalizeQuestionForComparison(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _buildJournalFollowUpFallback({
    required String input,
    required List<JournalEntry> contextEntries,
    required List<String> recentQuestions,
  }) {
    final insights = _extractJournalInsights(contextEntries);
    final highlights = insights.highlights.take(4).toList(growable: false);
    final candidateQuestions = <String>[
      if (highlights.isNotEmpty)
        'You mentioned "${_truncateForPrompt(highlights.first, 75)}". '
            'What detail from that moment feels most important to remember?',
      if (!insights.hasMood)
        'What emotion stayed with you the longest today, and what triggered it?',
      if (!insights.hasPeople)
        'Who shaped your energy the most today, and what happened in that interaction?',
      if (!insights.hasPlaces)
        'Which place influenced your day the most, and what stood out there?',
      ..._journalWebInspiredPromptAngles,
    ];

    if (candidateQuestions.isEmpty) {
      return 'What feels most important for future-you to remember from today?';
    }

    final seed = input.codeUnits.fold<int>(0, (sum, unit) => sum + unit) +
        DateTime.now().millisecondsSinceEpoch ~/ 60000;
    final start = seed % candidateQuestions.length;
    for (var i = 0; i < candidateQuestions.length; i++) {
      final question = candidateQuestions[(start + i) % candidateQuestions.length];
      if (!_isQuestionRepetitive(question, recentQuestions)) {
        return question;
      }
    }
    return candidateQuestions[start];
  }

  static const String _journalFollowUpSystemInstruction =
      'You are Sensei in Journal Mode. Generate exactly one short follow-up '
      'question tailored to the user\'s latest entry and the full supplied '
      'context. Avoid repeating any previously asked question. Use evidence '
      'from context to choose the highest-value next prompt. Blend practical '
      'journaling quality principles from public best-practice guidance '
      '(specific event detail, emotional depth, reflection, meaning, '
      'relationships, body signals, gratitude, and next-step clarity). '
      'Ask only one question. Return the question text only.';

  static const List<String> _journalWebInspiredQualityCriteria = <String>[
    'Capture concrete events (who, where, what happened), not only labels.',
    'Include emotional texture and body sensation where possible.',
    'Record why moments mattered, not just what happened.',
    'Note relationships and conversations that changed your state.',
    'Extract one lesson or pattern from the day.',
    'End with a clear next action or intention for tomorrow.',
    'Balance challenge notes with gratitude or wins.',
  ];

  static const List<String> _journalWebInspiredPromptAngles = <String>[
    'What happened right before your mood shifted most today?',
    'What conversation or interaction changed your energy, and why?',
    'What did your body signal (tension, fatigue, calm) during your key moment?',
    'What detail would be missing if you reread this entry six months from now?',
    'What felt unresolved today, and what is one next step you can take tomorrow?',
    'What small win are you most grateful for today, and what enabled it?',
    'What assumption did today challenge, and what did you learn from that?',
    'What boundary or decision mattered most today, and how did it affect you?',
    'What pattern keeps repeating lately that showed up again today?',
    'What is one thing future-you will thank you for documenting tonight?',
  ];

  static const Set<String> _journalQuestionStopWords = <String>{
    'a',
    'an',
    'and',
    'are',
    'as',
    'at',
    'be',
    'did',
    'do',
    'for',
    'from',
    'how',
    'i',
    'in',
    'is',
    'it',
    'me',
    'my',
    'of',
    'on',
    'or',
    'that',
    'the',
    'to',
    'today',
    'was',
    'what',
    'where',
    'which',
    'who',
    'with',
    'you',
    'your',
  };

  static const Set<String> _vaultQueryStopWords = <String>{
    'a',
    'an',
    'and',
    'are',
    'at',
    'be',
    'can',
    'did',
    'do',
    'does',
    'for',
    'from',
    'how',
    'i',
    'in',
    'is',
    'it',
    'me',
    'mine',
    'my',
    'of',
    'on',
    'please',
    'show',
    'tell',
    'the',
    'to',
    'was',
    'what',
    'where',
    'who',
    'why',
    'with',
  };

  static const List<String> _relationshipTerms = <String>[
    'girlfriend',
    'boyfriend',
    'wife',
    'husband',
    'partner',
    'fiancee',
  ];

  static const String _journalRecallSystemInstruction =
      'You are Sensei answering recall questions from journal context only. '
      'Do not invent facts. If missing, explicitly say the journal does not '
      'contain that detail yet.';

  static const String _journalSummarySystemInstruction =
      'Create a clean daily journal summary block. Include sections:\n'
      '1) Mood through the day\n'
      '2) People and interactions\n'
      '3) Places visited\n'
      '4) Key events/highlights\n'
      '5) One reflection prompt for tomorrow.\n'
      'Stay grounded strictly in provided context.';

  static const String _journalWeeklySystemInstruction =
      'Create a weekly journal summary from context only. Include:\n'
      '1) Overall mood trends\n'
      '2) Most frequent people interactions\n'
      '3) Places/patterns across the week\n'
      '4) Daily bullets where available\n'
      '5) Recommended focus for next week.';

  _JournalInsights _extractJournalInsights(List<JournalEntry> entries) {
    final moods = <String>{};
    final people = <String>{};
    final places = <String>{};
    final highlights = <String>[];
    final moodWords = <String, String>{
      'happy': 'Happy',
      'excited': 'Excited',
      'grateful': 'Grateful',
      'calm': 'Calm',
      'content': 'Content',
      'tired': 'Tired',
      'stressed': 'Stressed',
      'anxious': 'Anxious',
      'frustrated': 'Frustrated',
      'sad': 'Sad',
      'angry': 'Angry',
      'overwhelmed': 'Overwhelmed',
      'good': 'Good',
      'bad': 'Bad',
    };
    final peopleKeywords = <String>[
      'mom',
      'dad',
      'wife',
      'husband',
      'partner',
      'friend',
      'boss',
      'client',
      'coworker',
      'colleague',
      'team',
    ];
    final placeKeywords = <String>[
      'home',
      'office',
      'work',
      'gym',
      'school',
      'hospital',
      'restaurant',
      'cafe',
      'park',
      'store',
      'airport',
    ];
    final peoplePattern = RegExp(
      r'\b(?:met|with|called|texted|spoke with|talked to|saw|visited)\s+'
      r'([A-Z][A-Za-z]+(?:\s+[A-Z][A-Za-z]+){0,2})',
    );
    final placePattern = RegExp(
      r'\b(?:at|to|in|visited|went to|drove to|walked to)\s+'
      r"([A-Za-z][A-Za-z0-9'\-\s]{1,40})",
      caseSensitive: false,
    );

    for (final entry in entries) {
      if (entry.role != JournalRole.user) {
        continue;
      }
      final raw = entry.content.trim();
      if (raw.isEmpty) {
        continue;
      }
      if (_isJournalDailySummaryRequest(raw) ||
          _isJournalWeeklySummaryRequest(raw) ||
          _isJournalRecallRequest(raw)) {
        continue;
      }

      final lower = raw.toLowerCase();
      for (final moodEntry in moodWords.entries) {
        if (lower.contains(moodEntry.key)) {
          moods.add(moodEntry.value);
        }
      }

      final feltMatches = RegExp(
        r'\b(?:felt|feeling|mood(?:\s+was|\s+is)?)\s+([a-z]+)',
      ).allMatches(lower);
      for (final match in feltMatches) {
        final token = match.group(1);
        if (token != null && token.isNotEmpty) {
          moods.add(_toTitleCase(token));
        }
      }

      for (final keyword in peopleKeywords) {
        if (lower.contains(keyword)) {
          people.add(_toTitleCase(keyword));
        }
      }
      for (final match in peoplePattern.allMatches(raw)) {
        final token = match.group(1)?.trim();
        if (token != null && token.isNotEmpty) {
          people.add(token);
        }
      }

      for (final keyword in placeKeywords) {
        if (lower.contains(keyword)) {
          places.add(_toTitleCase(keyword));
        }
      }
      for (final match in placePattern.allMatches(raw)) {
        final candidate = match.group(1)?.trim();
        if (candidate == null || candidate.isEmpty) {
          continue;
        }
        final firstClause = candidate.split(RegExp(r'[,.!?;]')).first.trim();
        if (firstClause.isEmpty) {
          continue;
        }
        final compact = firstClause
            .split(RegExp(r'\s+'))
            .where((token) => token.isNotEmpty)
            .take(4)
            .join(' ');
        if (compact.isNotEmpty) {
          places.add(_toTitleCase(compact));
        }
      }

      final fragments = raw
          .split(RegExp(r'[\n.!?]'))
          .map((part) => part.trim())
          .where((part) => part.length >= 14);
      for (final fragment in fragments.take(2)) {
        if (!highlights.contains(fragment)) {
          highlights.add(fragment);
        }
      }
    }

    return _JournalInsights(
      moods: moods,
      people: people,
      places: places,
      highlights: highlights,
    );
  }

  String _buildJournalNarrative(List<JournalEntry> entries) {
    final lines = <String>[];
    for (final entry in entries) {
      if (entry.entryType == JournalEntryType.dailySummary ||
          entry.entryType == JournalEntryType.weeklySummary) {
        continue;
      }
      final text = entry.content.trim();
      if (text.isEmpty) {
        continue;
      }
      final author = entry.role == JournalRole.user ? 'User' : 'Sensei';
      lines.add('$author: $text');
    }
    return lines.join('\n');
  }

  Map<String, dynamic> _journalMetadataFromRolo(RoloMetadata metadata) {
    return <String, dynamic>{
      if (metadata.location != null) 'location': metadata.location,
      if (metadata.weather != null) 'weather': metadata.weather,
      if (metadata.sourceId != null) 'source_id': metadata.sourceId,
      if (metadata.sourceDevice != null) 'source_device': metadata.sourceDevice,
      if (metadata.trigger != null) 'trigger': metadata.trigger,
      if (metadata.confidenceScore != null)
        'confidence_score': metadata.confidenceScore,
    };
  }

  bool _isJournalDailySummaryRequest(String input) {
    final lower = input.toLowerCase();
    return lower.contains('summarize today') ||
        lower.contains('summary for today') ||
        lower.contains('journal summary') ||
        lower.contains('end journal') ||
        lower.contains('end of day') ||
        lower.contains('done for today') ||
        lower.contains('wrap up today');
  }

  bool _isJournalWeeklySummaryRequest(String input) {
    final lower = input.toLowerCase();
    return lower.contains('weekly summary') ||
        lower.contains('summarize week') ||
        lower.contains('week summary') ||
        (lower.contains('summary') && lower.contains('this week'));
  }

  bool _isJournalRecallRequest(String input) {
    final lower = input.toLowerCase();
    return lower.contains('who did i') ||
        lower.contains('where did i') ||
        lower.contains('what happened today') ||
        lower.contains('so far today') ||
        lower.contains('what was my mood') ||
        lower.contains('how was my mood') ||
        lower.contains('recall') ||
        lower.contains('remind me');
  }

  String _journalDayKey(DateTime moment) {
    final local = moment.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  DateTime _startOfWeek(DateTime anchor) {
    final localDay = DateTime(anchor.year, anchor.month, anchor.day);
    final delta = localDay.weekday - DateTime.monday;
    return localDay.subtract(Duration(days: delta));
  }

  String _weekdayLabel(DateTime day) {
    const labels = <String>[
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    final index = day.weekday - 1;
    final safeIndex = index.clamp(0, labels.length - 1).toInt();
    return labels[safeIndex];
  }

  String _journalTargetUri(DateTime moment) {
    final dateKey = _journalDayKey(moment).replaceAll('-', '');
    return 'dojo.sys.journal_$dateKey';
  }

  String _toTitleCase(String value) {
    final words = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) {
      return value;
    }
    return words
        .map((word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }

  String _formatKey(String key) {
    return key
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  bool _isExplicitUpdateInput(String input) {
    final normalized = input.toLowerCase();
    return normalized.contains(' set ') ||
        normalized.startsWith('set ') ||
        normalized.contains(' update ') ||
        normalized.startsWith('update ') ||
        normalized.contains(' change ') ||
        normalized.startsWith('change ') ||
        normalized.contains(' correct ') ||
        normalized.startsWith('correct ') ||
        normalized.contains(' replace ') ||
        normalized.startsWith('replace ');
  }

  bool _valuesEquivalent(String? left, String? right) {
    final normalizedLeft = (left ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    final normalizedRight = (right ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
    return normalizedLeft == normalizedRight;
  }

  String _normalizeDisplayName(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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

  Future<void> _persistSenseiResponse({
    required String inputRoloId,
    required String? targetUri,
    required String responseText,
    required double confidenceScore,
  }) async {
    if (_senseiRepository == null) {
      return;
    }

    final provider = _senseiLlm?.currentProvider.id;
    final model = _senseiLlm?.activeModelName;

    final response = SenseiResponse(
      id: _uuid.v4(),
      inputRoloId: inputRoloId,
      targetUri: targetUri,
      responseText: responseText,
      provider: provider,
      model: model,
      confidenceScore: confidenceScore,
      createdAt: DateTime.now().toUtc(),
    );
    try {
      await _senseiRepository!.create(response);
    } catch (e) {
      debugPrint('[DojoService] Failed to persist Sensei response: $e');
    }
  }

  String? _buildUserProfileSummary(UserProfile? profile) {
    if (profile == null) return null;
    final parts = <String>[
      'name: ${profile.senseiNameHint}',
    ];
    final timezone = profile.profile['timezone']?.toString();
    if (timezone != null && timezone.isNotEmpty) {
      parts.add('timezone: $timezone');
    }
    final locale = profile.profile['locale']?.toString();
    if (locale != null && locale.isNotEmpty) {
      parts.add('locale: $locale');
    }
    return parts.join(', ');
  }

  Future<UserProfile?> _getPrimaryUserProfile() async {
    if (_userRepository == null) {
      return null;
    }
    return _userRepository!.getPrimary();
  }

  Future<Rolo> _createAuditRolo({
    required String summoningText,
    required String targetUri,
    String trigger = 'Manual_Edit',
  }) async {
    final location = await _locationService.getCurrentCoordinates();
    final rolo = Rolo(
      id: _uuid.v4(),
      type: RoloType.input,
      summoningText: summoningText,
      targetUri: targetUri,
      metadata: RoloMetadata(
        trigger: trigger,
        location: location,
      ),
      timestamp: DateTime.now().toUtc(),
    );
    await _roloRepository.create(rolo);
    return rolo;
  }
}

class _JournalInsights {
  final Set<String> moods;
  final Set<String> people;
  final Set<String> places;
  final List<String> highlights;

  const _JournalInsights({
    required this.moods,
    required this.people,
    required this.places,
    required this.highlights,
  });

  bool get hasMood => moods.isNotEmpty;
  bool get hasPeople => people.isNotEmpty;
  bool get hasPlaces => places.isNotEmpty;
  bool get hasAnyData =>
      moods.isNotEmpty || people.isNotEmpty || places.isNotEmpty || highlights.isNotEmpty;
}

class _VaultContextBundle {
  final String context;
  final bool hasFacts;
  final String factsPreview;
  final List<String> sourcesUsed;
  final String? directAnswer;

  const _VaultContextBundle({
    required this.context,
    required this.hasFacts,
    required this.factsPreview,
    required this.sourcesUsed,
    this.directAnswer,
  });
}

class _JournalQueryContext {
  final String context;
  final bool hasFacts;
  final String factsPreview;
  final List<String> sourcesUsed;

  const _JournalQueryContext({
    this.context = '',
    this.hasFacts = false,
    this.factsPreview = '',
    this.sourcesUsed = const [],
  });
}
