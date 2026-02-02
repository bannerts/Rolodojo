import '../../domain/entities/attribute.dart';
import '../../domain/entities/dojo_uri.dart';
import '../../domain/entities/record.dart';
import '../../domain/entities/rolo.dart';
import '../../domain/repositories/attribute_repository.dart';
import '../../domain/repositories/record_repository.dart';
import '../../domain/repositories/rolo_repository.dart';
import 'input_parser.dart';

/// A suggested attribute synthesized from Rolo patterns.
class SynthesisSuggestion {
  /// The target URI for the suggestion.
  final String targetUri;

  /// The suggested attribute key.
  final String attributeKey;

  /// The suggested attribute value.
  final String attributeValue;

  /// Confidence score (0.0 - 1.0).
  final double confidence;

  /// The source Rolos that contributed to this suggestion.
  final List<String> sourceRoloIds;

  /// Human-readable explanation of why this was suggested.
  final String reasoning;

  /// Whether this suggestion has been reviewed by the user.
  bool isReviewed;

  /// Whether the user accepted or rejected this suggestion.
  bool? isAccepted;

  SynthesisSuggestion({
    required this.targetUri,
    required this.attributeKey,
    required this.attributeValue,
    required this.confidence,
    required this.sourceRoloIds,
    required this.reasoning,
    this.isReviewed = false,
    this.isAccepted,
  });
}

/// Pattern types that the Sensei can detect.
enum PatternType {
  /// Repeated mentions of the same attribute
  repetition,

  /// Similar attributes across related URIs
  similarity,

  /// Temporal patterns (e.g., weekly meetings)
  temporal,

  /// Co-occurrence patterns (attributes that appear together)
  cooccurrence,
}

/// A detected pattern in Rolo history.
class DetectedPattern {
  /// Type of pattern.
  final PatternType type;

  /// URIs involved in the pattern.
  final List<String> uris;

  /// Attribute keys involved.
  final List<String> attributeKeys;

  /// Frequency of the pattern (times detected).
  final int frequency;

  /// Confidence score.
  final double confidence;

  /// Sample Rolo IDs exhibiting this pattern.
  final List<String> sampleRoloIds;

  const DetectedPattern({
    required this.type,
    required this.uris,
    required this.attributeKeys,
    required this.frequency,
    required this.confidence,
    required this.sampleRoloIds,
  });
}

/// The Synthesis Service analyzes Rolo patterns to suggest new attributes.
///
/// From ROLODOJO_GLOSSARY.md:
/// "Synthesis: An AI-generated Rolo created when the Sensei connects
/// multiple existing facts to form a new insight."
///
/// This service implements local pattern detection without requiring
/// external AI APIs, following the Zero-Cloud policy.
class SynthesisService {
  final RoloRepository _roloRepository;
  final RecordRepository _recordRepository;
  final AttributeRepository _attributeRepository;
  final InputParser _inputParser;

  SynthesisService({
    required RoloRepository roloRepository,
    required RecordRepository recordRepository,
    required AttributeRepository attributeRepository,
    InputParser? inputParser,
  })  : _roloRepository = roloRepository,
        _recordRepository = recordRepository,
        _attributeRepository = attributeRepository,
        _inputParser = inputParser ?? InputParser();

  /// Analyzes recent Rolos and generates synthesis suggestions.
  ///
  /// [limit] - Maximum number of Rolos to analyze.
  /// [minConfidence] - Minimum confidence threshold for suggestions.
  Future<List<SynthesisSuggestion>> generateSuggestions({
    int limit = 100,
    double minConfidence = 0.6,
  }) async {
    final suggestions = <SynthesisSuggestion>[];

    // Get recent Rolos for analysis
    final rolos = await _roloRepository.getRecent(limit: limit);
    if (rolos.isEmpty) return suggestions;

    // Detect patterns
    final patterns = await _detectPatterns(rolos);

    // Generate suggestions from patterns
    for (final pattern in patterns) {
      final suggestion = await _patternToSuggestion(pattern);
      if (suggestion != null && suggestion.confidence >= minConfidence) {
        suggestions.add(suggestion);
      }
    }

    // Analyze unparsed Rolos for potential extractions
    final extractionSuggestions = await _analyzeUnparsedRolos(rolos);
    suggestions.addAll(
      extractionSuggestions.where((s) => s.confidence >= minConfidence),
    );

    // Sort by confidence (highest first)
    suggestions.sort((a, b) => b.confidence.compareTo(a.confidence));

    return suggestions;
  }

  /// Detects patterns in Rolo history.
  Future<List<DetectedPattern>> _detectPatterns(List<Rolo> rolos) async {
    final patterns = <DetectedPattern>[];

    // Group Rolos by target URI
    final rolosByUri = <String, List<Rolo>>{};
    for (final rolo in rolos) {
      if (rolo.targetUri != null) {
        rolosByUri.putIfAbsent(rolo.targetUri!, () => []).add(rolo);
      }
    }

    // Detect repetition patterns (same URI mentioned multiple times)
    for (final entry in rolosByUri.entries) {
      if (entry.value.length >= 3) {
        patterns.add(DetectedPattern(
          type: PatternType.repetition,
          uris: [entry.key],
          attributeKeys: [],
          frequency: entry.value.length,
          confidence: _calculateRepetitionConfidence(entry.value.length),
          sampleRoloIds: entry.value.take(3).map((r) => r.id).toList(),
        ));
      }
    }

    // Detect co-occurrence patterns (URIs mentioned together)
    final cooccurrences = _detectCooccurrences(rolos);
    patterns.addAll(cooccurrences);

    return patterns;
  }

  /// Detects URIs that are frequently mentioned together.
  List<DetectedPattern> _detectCooccurrences(List<Rolo> rolos) {
    final patterns = <DetectedPattern>[];
    final uriPairs = <String, int>{};

    // Group rolos by time windows (1 hour)
    final windows = <int, List<Rolo>>{};
    for (final rolo in rolos) {
      final windowKey = rolo.timestamp.millisecondsSinceEpoch ~/ 3600000;
      windows.putIfAbsent(windowKey, () => []).add(rolo);
    }

    // Find URIs that appear in the same window
    for (final windowRolos in windows.values) {
      final uris = windowRolos
          .where((r) => r.targetUri != null)
          .map((r) => r.targetUri!)
          .toSet()
          .toList();

      for (var i = 0; i < uris.length; i++) {
        for (var j = i + 1; j < uris.length; j++) {
          final key = '${uris[i]}|${uris[j]}';
          uriPairs[key] = (uriPairs[key] ?? 0) + 1;
        }
      }
    }

    // Create patterns for frequent co-occurrences
    for (final entry in uriPairs.entries) {
      if (entry.value >= 2) {
        final uris = entry.key.split('|');
        patterns.add(DetectedPattern(
          type: PatternType.cooccurrence,
          uris: uris,
          attributeKeys: [],
          frequency: entry.value,
          confidence: _calculateCooccurrenceConfidence(entry.value),
          sampleRoloIds: [],
        ));
      }
    }

    return patterns;
  }

  /// Converts a detected pattern into a synthesis suggestion.
  Future<SynthesisSuggestion?> _patternToSuggestion(
    DetectedPattern pattern,
  ) async {
    switch (pattern.type) {
      case PatternType.repetition:
        // Suggest adding a "frequently_mentioned" flag or similar
        return SynthesisSuggestion(
          targetUri: pattern.uris.first,
          attributeKey: 'importance',
          attributeValue: 'high',
          confidence: pattern.confidence,
          sourceRoloIds: pattern.sampleRoloIds,
          reasoning:
              'This contact was mentioned ${pattern.frequency} times recently',
        );

      case PatternType.cooccurrence:
        // Suggest a relationship attribute
        if (pattern.uris.length >= 2) {
          return SynthesisSuggestion(
            targetUri: pattern.uris.first,
            attributeKey: 'related_to',
            attributeValue: pattern.uris[1],
            confidence: pattern.confidence * 0.8,
            sourceRoloIds: pattern.sampleRoloIds,
            reasoning:
                'These two are frequently mentioned together (${pattern.frequency} times)',
          );
        }
        return null;

      default:
        return null;
    }
  }

  /// Analyzes Rolos that weren't fully parsed to extract potential data.
  Future<List<SynthesisSuggestion>> _analyzeUnparsedRolos(
    List<Rolo> rolos,
  ) async {
    final suggestions = <SynthesisSuggestion>[];

    for (final rolo in rolos) {
      // Try to extract key-value pairs from summoning text
      final pairs = _inputParser.extractKeyValuePairs(rolo.summoningText);

      for (final pair in pairs) {
        // Check if this attribute already exists
        if (rolo.targetUri != null) {
          final existing = await _attributeRepository.get(
            rolo.targetUri!,
            pair.key,
          );

          if (existing == null) {
            suggestions.add(SynthesisSuggestion(
              targetUri: rolo.targetUri!,
              attributeKey: pair.key,
              attributeValue: pair.value,
              confidence: 0.5, // Lower confidence for extracted data
              sourceRoloIds: [rolo.id],
              reasoning: 'Extracted from: "${rolo.summoningText}"',
            ));
          }
        }
      }
    }

    return suggestions;
  }

  double _calculateRepetitionConfidence(int frequency) {
    // More mentions = higher confidence, caps at 0.9
    return (frequency / 10).clamp(0.5, 0.9);
  }

  double _calculateCooccurrenceConfidence(int frequency) {
    // More co-occurrences = higher confidence, caps at 0.8
    return (frequency / 5).clamp(0.4, 0.8);
  }

  /// Gets suggestions for a specific URI.
  Future<List<SynthesisSuggestion>> getSuggestionsForUri(String uri) async {
    final allSuggestions = await generateSuggestions();
    return allSuggestions.where((s) => s.targetUri == uri).toList();
  }

  /// Analyzes a single Rolo and returns immediate suggestions.
  Future<List<SynthesisSuggestion>> analyzeRolo(Rolo rolo) async {
    final suggestions = <SynthesisSuggestion>[];

    if (rolo.targetUri == null) return suggestions;

    // Get existing attributes for this URI
    final existingAttrs = await _attributeRepository.getByUri(rolo.targetUri!);
    final existingKeys = existingAttrs.map((a) => a.key).toSet();

    // Try to extract new attributes from the summoning text
    final pairs = _inputParser.extractKeyValuePairs(rolo.summoningText);

    for (final pair in pairs) {
      if (!existingKeys.contains(pair.key)) {
        suggestions.add(SynthesisSuggestion(
          targetUri: rolo.targetUri!,
          attributeKey: pair.key,
          attributeValue: pair.value,
          confidence: 0.7,
          sourceRoloIds: [rolo.id],
          reasoning: 'New attribute detected in your input',
        ));
      }
    }

    return suggestions;
  }
}
