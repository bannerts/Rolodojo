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
  }) async {
    // Every user summoning should capture the device coordinates when possible.
    final enrichedMetadata = await _enrichMetadataWithLocation(metadata);
    final primaryUser = _userRepository != null
        ? await _userRepository!.getPrimary()
        : null;

    // Parse the input — use active LLM provider if available, fall back to regex
    var parsed = _inputParser.parse(input);
    var parsedFromLlm = false;

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
          userProfileSummary: _buildUserProfileSummary(primaryUser),
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
        parsedFromLlm = true;
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
      final subjectUri = parsed.subjectUri!.toString();
      final now = DateTime.now();

      // Check if record exists
      final existingRecord = await _recordRepository.getByUri(subjectUri);
      final existingAttribute = await _attributeRepository.get(
        subjectUri,
        parsed.attributeKey!,
      );
      final hasConflictingValue = existingAttribute?.value != null &&
          !_valuesEquivalent(existingAttribute!.value!, parsed.attributeValue);
      final shouldProtectExistingValue = parsedFromLlm &&
          hasConflictingValue &&
          !_isExplicitUpdateInput(input);

      if (shouldProtectExistingValue) {
        record = existingRecord;
        attribute = existingAttribute;
        message = 'Existing ${_formatKey(parsed.attributeKey!)} for '
            '${parsed.subjectName ?? subjectUri} is "${existingAttribute!.value}". '
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
            ? 'Created ${parsed.subjectName} with ${_formatKey(parsed.attributeKey!)}: ${parsed.attributeValue}'
            : 'Updated ${parsed.subjectName}\'s ${_formatKey(parsed.attributeKey!)} to ${parsed.attributeValue}';
      }
    } else if (parsed.isQuery) {
      message = await _answerQueryFromVault(
        query: input,
        parsed: parsed,
        primaryUser: primaryUser,
      );
    } else {
      message = 'Input recorded. Unable to extract structured data.';
    }

    await _persistSenseiResponse(
      inputRoloId: roloId,
      targetUri: parsed.subjectUri?.toString(),
      responseText: message,
      confidenceScore: parsed.confidence,
    );

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

    final editLocation = await _locationService.getCurrentCoordinates();
    final now = DateTime.now();
    final roloId = _uuid.v4();
    final rolo = Rolo(
      id: roloId,
      type: RoloType.input,
      summoningText:
          'Manual edit: $key for $subjectUri from "${existing.value ?? '(empty)'}" '
          'to "$trimmedValue"',
      targetUri: subjectUri,
      metadata: RoloMetadata(
        trigger: 'Manual_Edit',
        location: editLocation,
      ),
      timestamp: now.toUtc(),
    );
    await _roloRepository.create(rolo);

    final updated = existing.copyWith(
      value: trimmedValue,
      lastRoloId: roloId,
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

    final editLocation = await _locationService.getCurrentCoordinates();
    final now = DateTime.now();
    final roloId = _uuid.v4();
    final rolo = Rolo(
      id: roloId,
      type: RoloType.input,
      summoningText:
          'Manual edit: rename "$uri" from "${existing.displayName}" to "$trimmedName"',
      targetUri: uri,
      metadata: RoloMetadata(
        trigger: 'Manual_Edit',
        location: editLocation,
      ),
      timestamp: now.toUtc(),
    );
    await _roloRepository.create(rolo);

    final updated = existing.copyWith(
      displayName: trimmedName,
      lastRoloId: roloId,
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

    final now = DateTime.now();
    final dayKey = _journalDayKey(now);
    final enrichedMetadata = await _enrichMetadataWithLocation(
      const RoloMetadata(trigger: 'Journal_Entry'),
    );

    final roloId = _uuid.v4();
    final rolo = Rolo(
      id: roloId,
      type: RoloType.input,
      summoningText: trimmed,
      targetUri: _journalTargetUri(now),
      metadata: RoloMetadata(
        trigger: enrichedMetadata.trigger ?? 'Journal_Entry',
        confidenceScore: 0.92,
        location: enrichedMetadata.location,
        weather: enrichedMetadata.weather,
        sourceId: enrichedMetadata.sourceId,
        sourceDevice: enrichedMetadata.sourceDevice,
      ),
      timestamp: now.toUtc(),
    );
    await _roloRepository.create(rolo);

    final userEntry = JournalEntry(
      id: _uuid.v4(),
      journalDate: dayKey,
      role: JournalRole.user,
      entryType: JournalEntryType.partial,
      content: trimmed,
      sourceRoloId: roloId,
      metadata: _journalMetadataFromRolo(enrichedMetadata),
      createdAt: now.toUtc(),
    );
    if (_journalRepository != null) {
      await _journalRepository!.create(userEntry);
    }

    final dayEntries = await getJournalEntriesForDate(now, limit: 500);
    final sourceEntries = dayEntries.isEmpty
        ? <JournalEntry>[userEntry]
        : dayEntries;

    final responseType = _resolveJournalResponseType(trimmed);
    late final String responseText;
    if (responseType == JournalEntryType.dailySummary) {
      responseText = await _buildDailySummaryBlock(
        now,
        requestPrompt: trimmed,
        primaryUser: primaryUser,
      );
    } else if (responseType == JournalEntryType.weeklySummary) {
      responseText = await _buildWeeklySummaryBlock(
        now,
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
      sourceRoloId: roloId,
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
      inputRoloId: roloId,
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
    final primaryUser = _userRepository != null
        ? await _userRepository!.getPrimary()
        : null;
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
    final primaryUser = _userRepository != null
        ? await _userRepository!.getPrimary()
        : null;
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

  Future<String> _answerQueryFromVault({
    required String query,
    required ParsedInput parsed,
    required UserProfile? primaryUser,
  }) async {
    final bundle = await _buildVaultContextBundle(
      query: query,
      parsed: parsed,
    );

    if (_senseiLlm != null) {
      try {
        final llmAnswer = await _senseiLlm!.answerWithVault(
          question: query,
          vaultContext: bundle.context,
          userProfileSummary: _buildUserProfileSummary(primaryUser),
        );
        final normalized = llmAnswer.trim();
        if (normalized.isNotEmpty) {
          return normalized;
        }
      } catch (e) {
        debugPrint('[DojoService] Query answer via LLM failed: $e');
      }
    }

    if (!bundle.hasFacts) {
      return 'I searched your vault but could not find enough related facts '
          'for that question yet.';
    }

    return 'I found related vault facts, but could not produce a complete '
        'answer right now. Relevant entries:\n${bundle.factsPreview}';
  }

  Future<_VaultContextBundle> _buildVaultContextBundle({
    required String query,
    required ParsedInput parsed,
  }) async {
    final normalizedQuery = _normalizeQueryForVaultSearch(query);
    final contextLines = <String>[];
    final factLines = <String>[];

    final recordsByName = await _recordRepository.searchByName(normalizedQuery);
    final attrsBySearch = await _attributeRepository.search(normalizedQuery);
    final rolosBySearch = await _roloRepository.search(normalizedQuery);

    Record? directRecord;
    List<Attribute> directAttributes = const [];
    List<Rolo> directRolos = const [];
    if (parsed.subjectUri != null) {
      final subjectUri = parsed.subjectUri!.toString();
      directRecord = await _recordRepository.getByUri(subjectUri);
      directAttributes = await _attributeRepository.getByUri(subjectUri);
      directRolos = await _roloRepository.getByTargetUri(subjectUri);
    }

    if (directRecord != null) {
      final line = '- Direct record: ${directRecord.displayName} '
          '(${directRecord.uri})';
      contextLines.add(line);
      factLines.add(line);
    }

    if (directAttributes.isNotEmpty) {
      for (final attr in directAttributes.take(10)) {
        final line = '- Fact: ${attr.subjectUri}.${attr.key} = '
            '${_truncateForPrompt(attr.value ?? '(deleted)', 120)}';
        contextLines.add(line);
        factLines.add(line);
      }
    }

    if (recordsByName.isNotEmpty) {
      for (final record in recordsByName.take(6)) {
        final line = '- Record match: ${record.displayName} (${record.uri})';
        contextLines.add(line);
      }
    }

    if (attrsBySearch.isNotEmpty) {
      final seen = <String>{};
      for (final attr in attrsBySearch) {
        final key = '${attr.subjectUri}::${attr.key}';
        if (seen.contains(key)) continue;
        seen.add(key);
        final line = '- Vault fact: ${attr.subjectUri}.${attr.key} = '
            '${_truncateForPrompt(attr.value ?? '(deleted)', 120)}';
        contextLines.add(line);
        factLines.add(line);
        if (seen.length >= 12) break;
      }
    }

    if (directRolos.isNotEmpty || rolosBySearch.isNotEmpty) {
      final candidateRolos = <Rolo>[
        ...directRolos.take(4),
        ...rolosBySearch.take(6),
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

    if (contextLines.isEmpty) {
      contextLines.add('- No matching vault facts were found.');
    }

    final preview = factLines.take(4).join('\n');
    return _VaultContextBundle(
      context: contextLines.join('\n'),
      hasFacts: factLines.isNotEmpty,
      factsPreview: preview,
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
        .replaceAll(RegExp(r'^(what|who|where|when|why|how)\s+'), '')
        .replaceAll(RegExp(r'^(is|are|was|were|do|does|did|can|could)\s+'), '')
        .replaceAll(RegExp(r'^(tell me|show me|find|lookup|look up)\s+'), '')
        .replaceAll(RegExp(r'\babout\b'), '')
        .replaceAll(RegExp(r'[^a-z0-9\s._-]'), ' ')
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
    final llmResponse = await _tryLlmJournalResponse(
      prompt:
          'New journal entry: "$input"\nRespond as Sensei with one useful '
          'follow-up that improves day journaling quality.',
      contextEntries: dayEntries,
      primaryUser: primaryUser,
      systemInstruction: _journalFollowUpSystemInstruction,
      maxTokens: 240,
      temperature: 0.25,
    );
    if (llmResponse != null) {
      return llmResponse;
    }

    final insights = _extractJournalInsights(dayEntries);
    final followUps = <String>[];
    if (!insights.hasMood) {
      followUps.add('How did your mood shift throughout the day?');
    }
    if (!insights.hasPeople) {
      followUps.add('Who did you spend time with or communicate with today?');
    }
    if (!insights.hasPlaces) {
      followUps.add('What places did you go today?');
    }

    if (followUps.isNotEmpty) {
      final promptLines = followUps
          .take(2)
          .map((q) => '- $q')
          .join('\n');
      return 'Journal entry captured. Keep layering details so your day-end '
          'summary stays useful.\n\n$promptLines';
    }

    final highlights = insights.highlights.take(3).toList(growable: false);
    final highlightBlock = highlights.isEmpty
        ? ''
        : '\n\nRecent notes I can already use:\n'
            '${highlights.map((h) => '- $h').join('\n')}';
    return 'Great detail so far. What felt most important today, and what do '
        'you want future-you to remember?$highlightBlock';
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
  }) async {
    final llm = _senseiLlm;
    if (llm == null) {
      return null;
    }

    final entriesContext = _buildJournalContextBlock(contextEntries);
    if (entriesContext.isEmpty) {
      return null;
    }
    final userProfile = _buildUserProfileSummary(primaryUser);
    final contextBlock = userProfile == null
        ? entriesContext
        : '- User profile: $userProfile\n$entriesContext';

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

  static const String _journalFollowUpSystemInstruction =
      'You are Sensei in Journal Mode. Coach the user to capture high-value '
      'day details. Prioritize missing: mood shifts, people interactions, '
      'places visited, and key events. Keep response short and practical.';

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

  const _VaultContextBundle({
    required this.context,
    required this.hasFacts,
    required this.factsPreview,
  });
}
