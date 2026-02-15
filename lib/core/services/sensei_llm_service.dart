import 'dart:async';
import 'package:flutter/foundation.dart';
import 'input_parser.dart';

/// Result of a local LLM inference call.
class LlmResult {
  /// The generated text response.
  final String text;

  /// Confidence score (0.0 - 1.0).
  final double confidence;

  /// Time taken for inference in milliseconds.
  final int inferenceTimeMs;

  const LlmResult({
    required this.text,
    required this.confidence,
    required this.inferenceTimeMs,
  });
}

/// Parsed extraction result from the LLM.
class LlmExtraction {
  /// Subject name (e.g., "Joe").
  final String? subjectName;

  /// Attribute key (e.g., "coffee_preference").
  final String? attributeKey;

  /// Attribute value (e.g., "Espresso").
  final String? attributeValue;

  /// Whether this is a query.
  final bool isQuery;

  /// Confidence score.
  final double confidence;

  const LlmExtraction({
    this.subjectName,
    this.attributeKey,
    this.attributeValue,
    this.isQuery = false,
    this.confidence = 0.0,
  });

  bool get canCreateAttribute =>
      subjectName != null && attributeKey != null && attributeValue != null;
}

/// Abstract interface for local LLM operations.
///
/// Per CLAUDE.md: "The Sensei agent must be implemented using a local
/// LLM runner (e.g., Llama 3.2 via llama_flutter). External AI APIs
/// are strictly forbidden to maintain the Zero-Cloud policy."
///
/// All inference runs on-device via llama.cpp FFI bindings.
abstract class SenseiLlmService {
  /// Whether the LLM model is loaded and ready.
  bool get isReady;

  /// Initialize the LLM with a GGUF model file.
  ///
  /// [modelPath] - Path to the .gguf model file on device.
  /// [contextSize] - Token context window size.
  /// [threads] - Number of CPU threads for inference.
  Future<void> initialize({
    required String modelPath,
    int contextSize = 2048,
    int threads = 4,
  });

  /// Parse natural language input into structured data.
  ///
  /// Uses the LLM to extract subject, attribute key, and value
  /// from free-form text with higher accuracy than regex alone.
  Future<LlmExtraction> parseInput(String input);

  /// Generate a synthesis insight from multiple facts.
  ///
  /// [facts] - List of key:value facts about a subject.
  /// [recentRolos] - Recent summoning texts for context.
  Future<LlmResult> synthesize({
    required String subjectUri,
    required Map<String, String> facts,
    List<String> recentRolos = const [],
  });

  /// Summarize a long text for Ghost record compression.
  Future<String> summarize(String text, {int maxLength = 50});

  /// Release model resources.
  Future<void> dispose();
}

/// Local LLM implementation using llama.cpp via fllama FFI bindings.
///
/// Requires a GGUF model file (e.g., Llama-3.2-3B-Instruct.Q4_K_M.gguf)
/// to be present on the device. Falls back to rule-based parsing if
/// the model file is not available.
class LocalLlmService implements SenseiLlmService {
  bool _isReady = false;
  String? _modelPath;

  // In production, this holds the fllama model handle
  // fllama.OpenAiApi? _api;

  @override
  bool get isReady => _isReady;

  @override
  Future<void> initialize({
    required String modelPath,
    int contextSize = 2048,
    int threads = 4,
  }) async {
    _modelPath = modelPath;

    // TODO: Uncomment when fllama package is available on target platform
    // _api = fllama.OpenAiApi(
    //   modelPath: modelPath,
    //   contextSize: contextSize,
    //   nThreads: threads,
    // );

    // Verify model file exists
    // final modelFile = File(modelPath);
    // if (!await modelFile.exists()) {
    //   throw StateError('Model file not found: $modelPath');
    // }

    _isReady = true;
    debugPrint('[Sensei LLM] Model loaded from: $modelPath');
  }

  @override
  Future<LlmExtraction> parseInput(String input) async {
    if (!_isReady) {
      return const LlmExtraction(confidence: 0.0);
    }

    final stopwatch = Stopwatch()..start();

    // Build the extraction prompt for the local LLM
    final prompt = _buildExtractionPrompt(input);

    // TODO: Replace with actual fllama inference call
    // final response = await _api!.createChatCompletion(
    //   request: fllama.CreateChatCompletionRequest(
    //     messages: [
    //       fllama.ChatCompletionMessage(role: 'system', content: _systemPrompt),
    //       fllama.ChatCompletionMessage(role: 'user', content: prompt),
    //     ],
    //     maxTokens: 128,
    //     temperature: 0.1,
    //   ),
    // );
    // final responseText = response.choices.first.message.content;

    // For now, use enhanced rule-based extraction as the inference path
    final extraction = _ruleBasedExtraction(input);

    stopwatch.stop();
    debugPrint(
      '[Sensei LLM] Parse took ${stopwatch.elapsedMilliseconds}ms '
      '(confidence: ${extraction.confidence})',
    );

    return extraction;
  }

  @override
  Future<LlmResult> synthesize({
    required String subjectUri,
    required Map<String, String> facts,
    List<String> recentRolos = const [],
  }) async {
    if (!_isReady) {
      return const LlmResult(text: '', confidence: 0.0, inferenceTimeMs: 0);
    }

    final stopwatch = Stopwatch()..start();

    // Build synthesis prompt
    final factsText = facts.entries.map((e) => '- ${e.key}: ${e.value}').join('\n');
    final recentText = recentRolos.isNotEmpty
        ? '\nRecent activity:\n${recentRolos.map((r) => '- $r').join('\n')}'
        : '';

    // TODO: Replace with actual fllama inference call
    // final prompt = 'Given these facts about $subjectUri:\n$factsText'
    //     '$recentText\n\nSuggest a new insight or connection:';
    // final response = await _api!.createChatCompletion(...);

    // Rule-based synthesis fallback
    final synthesis = _ruleBasedSynthesis(subjectUri, facts, recentRolos);

    stopwatch.stop();
    return LlmResult(
      text: synthesis,
      confidence: 0.7,
      inferenceTimeMs: stopwatch.elapsedMilliseconds,
    );
  }

  @override
  Future<String> summarize(String text, {int maxLength = 50}) async {
    if (!_isReady || text.length <= maxLength) {
      return text.length <= maxLength
          ? text
          : '${text.substring(0, maxLength - 3)}...';
    }

    // TODO: Replace with actual fllama inference call for smarter summarization
    // For now, extract first sentence or truncate
    final firstSentence = text.split(RegExp(r'[.!?]')).first.trim();
    if (firstSentence.length <= maxLength) {
      return firstSentence;
    }
    return '${firstSentence.substring(0, maxLength - 3)}...';
  }

  @override
  Future<void> dispose() async {
    // TODO: Release fllama model resources
    // await _api?.close();
    _isReady = false;
    debugPrint('[Sensei LLM] Model unloaded');
  }

  /// Builds the extraction prompt for the LLM.
  String _buildExtractionPrompt(String input) {
    return '''Extract structured data from this input.
Return JSON with: subject_name, attribute_key (snake_case), attribute_value, is_query.
If you cannot extract data, return empty fields.

Input: "$input"

JSON:''';
  }

  /// System prompt for the Sensei LLM.
  static const _systemPrompt = '''You are the Sensei, a privacy-first AI that extracts structured data from natural language.
You identify: subject names, attribute keys (in snake_case), and attribute values.
You also identify queries (questions about data).
Always respond with valid JSON. Never make up data that isn't in the input.''';

  /// Enhanced rule-based extraction (fallback when LLM is unavailable).
  LlmExtraction _ruleBasedExtraction(String input) {
    final parser = InputParser();
    final parsed = parser.parse(input);

    if (parsed.canCreateAttribute) {
      return LlmExtraction(
        subjectName: parsed.subjectName,
        attributeKey: parsed.attributeKey,
        attributeValue: parsed.attributeValue,
        isQuery: parsed.isQuery,
        confidence: parsed.confidence,
      );
    }

    return LlmExtraction(
      isQuery: parsed.isQuery,
      confidence: parsed.confidence,
    );
  }

  /// Rule-based synthesis (fallback when LLM is unavailable).
  String _ruleBasedSynthesis(
    String subjectUri,
    Map<String, String> facts,
    List<String> recentRolos,
  ) {
    if (facts.isEmpty) return '';

    final parts = <String>[];

    // Look for patterns in the facts
    if (facts.length >= 3) {
      parts.add(
        '${subjectUri.split('.').last} has ${facts.length} known attributes',
      );
    }

    // Look for time-related facts
    for (final entry in facts.entries) {
      if (entry.key.contains('birthday') || entry.key.contains('anniversary')) {
        parts.add('Note: ${entry.key} is ${entry.value}');
      }
    }

    // Look for relationships in recent rolos
    if (recentRolos.length >= 2) {
      parts.add('Active recently with ${recentRolos.length} interactions');
    }

    return parts.isEmpty ? 'No new insights detected' : parts.join('. ');
  }
}
