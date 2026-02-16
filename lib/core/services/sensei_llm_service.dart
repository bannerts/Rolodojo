import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/uri_utils.dart';
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

/// Connection state for the local Llama server.
class LlmHealthStatus {
  /// Whether the local HTTP endpoint is reachable.
  final bool serverReachable;

  /// Whether the requested model is available on the server.
  final bool modelAvailable;

  /// Configured OpenAI-compatible endpoint (e.g. http://localhost:11434/v1).
  final String endpoint;

  /// The model requested by app configuration.
  final String configuredModel;

  /// The model currently used for requests (may be a fallback).
  final String? activeModel;

  /// Discovered model IDs from `/v1/models`.
  final List<String> availableModels;

  /// Human-readable status message suitable for UI display.
  final String message;

  /// Timestamp of the last health check.
  final DateTime? checkedAt;

  const LlmHealthStatus({
    this.serverReachable = false,
    this.modelAvailable = false,
    this.endpoint = '',
    this.configuredModel = '',
    this.activeModel,
    this.availableModels = const [],
    this.message = 'Local LLM health has not been checked yet.',
    this.checkedAt,
  });

  /// True only when endpoint and model are both available.
  bool get isHealthy => serverReachable && modelAvailable;
}

/// Abstract interface for local LLM operations.
///
/// Per CLAUDE.md: "The Sensei agent must be implemented using a local
/// LLM runner (e.g., Llama 3.2 via llama_flutter). External AI APIs
/// are strictly forbidden to maintain the Zero-Cloud policy."
///
/// All inference runs against a local server endpoint (no cloud calls).
abstract class SenseiLlmService {
  /// Whether the LLM model is loaded and ready.
  bool get isReady;

  /// OpenAI-compatible base URL for the local server.
  String get baseUrl;

  /// Preferred model name from app configuration.
  String get configuredModelName;

  /// Active model name currently being used.
  String get activeModelName;

  /// Live health status for UI subscriptions.
  ValueListenable<LlmHealthStatus> get healthStatus;

  /// Initialize the local LLM service.
  ///
  /// [modelPath] - Compatibility marker for existing call sites.
  /// [contextSize] - Token context window size.
  /// [threads] - Number of CPU threads for inference.
  Future<void> initialize({
    required String modelPath,
    int contextSize = 2048,
    int threads = 4,
  });

  /// Checks local endpoint and model availability.
  Future<LlmHealthStatus> checkHealth({bool force = false});

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

/// Uses an OpenAI-compatible local endpoint (e.g. Ollama's `/v1` API).
/// Falls back to rule-based parsing when the server/model is unavailable.
class LocalLlmService implements SenseiLlmService {
  LocalLlmService({
    String baseUrl = 'http://localhost:11434/v1',
    String modelName = 'llama3.3',
    List<String> fallbackModels = const ['openchat-3.6'],
    Duration requestTimeout = const Duration(seconds: 12),
    Duration healthPollInterval = const Duration(seconds: 30),
  })  : _baseUri = _normalizeBaseUri(baseUrl),
        _configuredModelName = modelName.trim().isEmpty ? 'llama3.3' : modelName.trim(),
        _fallbackModels = fallbackModels
            .map((m) => m.trim())
            .where((m) => m.isNotEmpty)
            .toList(growable: false),
        _requestTimeout = requestTimeout,
        _healthPollInterval = healthPollInterval {
    _httpClient.connectionTimeout = requestTimeout;
  }

  bool _isReady = false;
  String? _activeModelName;
  DateTime? _lastHealthCheck;
  Timer? _healthPoller;

  final Uri _baseUri;
  final String _configuredModelName;
  final List<String> _fallbackModels;
  final Duration _requestTimeout;
  final Duration _healthPollInterval;
  final HttpClient _httpClient = HttpClient();
  final ValueNotifier<LlmHealthStatus> _healthStatusNotifier =
      ValueNotifier(const LlmHealthStatus());

  @override
  bool get isReady => _isReady;

  @override
  String get baseUrl => _baseUri.toString();

  @override
  String get configuredModelName => _configuredModelName;

  @override
  String get activeModelName => _activeModelName ?? _configuredModelName;

  @override
  ValueListenable<LlmHealthStatus> get healthStatus => _healthStatusNotifier;

  @override
  Future<void> initialize({
    required String modelPath,
    int contextSize = 2048,
    int threads = 4,
  }) async {
    // modelPath/context/thread values are retained for interface compatibility.
    debugPrint(
      '[Sensei LLM] Initializing local endpoint=$baseUrl '
      'configuredModel=$_configuredModelName marker=$modelPath',
    );
    await checkHealth(force: true);
    _startHealthMonitor();
  }

  @override
  Future<LlmHealthStatus> checkHealth({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastHealthCheck != null &&
        now.difference(_lastHealthCheck!) < const Duration(seconds: 5)) {
      return _healthStatusNotifier.value;
    }
    _lastHealthCheck = now;

    try {
      final response = await _getJson(_endpoint('models'));
      final availableModels = _parseModelIds(response);
      final resolvedModel = _resolveModelName(availableModels);
      final modelAvailable = resolvedModel != null;
      _activeModelName = resolvedModel;
      _isReady = modelAvailable;

      final status = LlmHealthStatus(
        serverReachable: true,
        modelAvailable: modelAvailable,
        endpoint: baseUrl,
        configuredModel: _configuredModelName,
        activeModel: resolvedModel,
        availableModels: availableModels,
        message: _buildHealthMessage(
          modelAvailable: modelAvailable,
          resolvedModel: resolvedModel,
          availableModels: availableModels,
        ),
        checkedAt: now,
      );

      _healthStatusNotifier.value = status;
      return status;
    } catch (e) {
      _isReady = false;
      final status = LlmHealthStatus(
        serverReachable: false,
        modelAvailable: false,
        endpoint: baseUrl,
        configuredModel: _configuredModelName,
        activeModel: null,
        availableModels: const [],
        message:
            'Local Llama server is offline at $baseUrl. Start it and retry.',
        checkedAt: now,
      );
      _healthStatusNotifier.value = status;
      debugPrint('[Sensei LLM] Health check failed: $e');
      return status;
    }
  }

  @override
  Future<LlmExtraction> parseInput(String input) async {
    final fallback = _ruleBasedExtraction(input);
    if (input.trim().isEmpty) {
      return fallback;
    }
    final health = await checkHealth();
    if (!health.isHealthy) {
      return fallback;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final responseText = await _createChatCompletion(
        systemPrompt: _systemPrompt,
        userPrompt: _buildExtractionPrompt(input),
        maxTokens: 180,
        temperature: 0.1,
      );
      final llmExtraction = _parseExtractionResponse(responseText);
      return _pickBestExtraction(fallback, llmExtraction);
    } catch (e) {
      await _onRequestFailure(e);
      return fallback;
    } finally {
      stopwatch.stop();
      debugPrint(
        '[Sensei LLM] Parse took ${stopwatch.elapsedMilliseconds}ms '
        '(ready=$_isReady model=$activeModelName)',
      );
    }
  }

  @override
  Future<LlmResult> synthesize({
    required String subjectUri,
    required Map<String, String> facts,
    List<String> recentRolos = const [],
  }) async {
    final health = await checkHealth();
    if (!health.isHealthy) {
      return const LlmResult(text: '', confidence: 0.0, inferenceTimeMs: 0);
    }

    final stopwatch = Stopwatch()..start();

    try {
      final llmText = await _createChatCompletion(
        systemPrompt: _synthesisSystemPrompt,
        userPrompt: _buildSynthesisPrompt(subjectUri, facts, recentRolos),
        maxTokens: 180,
        temperature: 0.3,
      );
      stopwatch.stop();
      final normalized = llmText.trim();
      if (normalized.isEmpty) {
        final fallback = _ruleBasedSynthesis(subjectUri, facts, recentRolos);
        return LlmResult(
          text: fallback,
          confidence: 0.65,
          inferenceTimeMs: stopwatch.elapsedMilliseconds,
        );
      }
      return LlmResult(
        text: normalized,
        confidence: 0.82,
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      await _onRequestFailure(e);
      final fallback = _ruleBasedSynthesis(subjectUri, facts, recentRolos);
      stopwatch.stop();
      return LlmResult(
        text: fallback,
        confidence: 0.65,
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  @override
  Future<String> summarize(String text, {int maxLength = 50}) async {
    if (text.length <= maxLength) {
      return text.length <= maxLength
          ? text
          : '${text.substring(0, maxLength - 3)}...';
    }

    final health = await checkHealth();
    if (!health.isHealthy) {
      return _ruleBasedSummary(text, maxLength);
    }

    try {
      final summary = await _createChatCompletion(
        systemPrompt: _summarySystemPrompt,
        userPrompt:
            'Summarize this in at most $maxLength characters:\n\n$text',
        maxTokens: 80,
        temperature: 0.2,
      );
      final normalized = summary.trim();
      if (normalized.isEmpty) {
        return _ruleBasedSummary(text, maxLength);
      }
      return normalized.length <= maxLength
          ? normalized
          : '${normalized.substring(0, maxLength - 3)}...';
    } catch (e) {
      await _onRequestFailure(e);
      return _ruleBasedSummary(text, maxLength);
    }
  }

  @override
  Future<void> dispose() async {
    _healthPoller?.cancel();
    _healthPoller = null;
    _httpClient.close(force: true);
    _isReady = false;
    _healthStatusNotifier.dispose();
    debugPrint('[Sensei LLM] Local client disposed');
  }

  /// Builds the extraction prompt for the LLM.
  String _buildExtractionPrompt(String input) {
    return '''Extract structured data from this input.
Return ONLY valid JSON with keys:
- subject_name (string or null)
- attribute_key (snake_case string or null)
- attribute_value (string or null)
- is_query (boolean)
- confidence (number 0..1)

Input: "$input"''';
  }

  /// System prompt for the Sensei LLM.
  static const _systemPrompt = '''You are the Sensei, a privacy-first AI that extracts structured data from natural language.
You identify: subject names, attribute keys (in snake_case), and attribute values.
You also identify queries (questions about data).
Always respond with valid JSON only. Never make up data that isn't in the input.''';

  static const _synthesisSystemPrompt =
      'You are a local assistant generating concise relationship insights '
      'from structured personal-ledger facts.';

  static const _summarySystemPrompt =
      'You produce short summaries without adding any extra details.';

  Future<String> _createChatCompletion({
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
    double temperature = 0.1,
  }) async {
    final response = await _postJson(
      _endpoint('chat/completions'),
      <String, dynamic>{
        'model': activeModelName,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'temperature': temperature,
        'max_tokens': maxTokens,
        'stream': false,
      },
    );

    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('No completion choices returned.');
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      throw const FormatException('Invalid completion choice format.');
    }
    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      throw const FormatException('Missing completion message.');
    }
    final content = _extractMessageContent(message['content']);
    if (content.isEmpty) {
      throw const FormatException('Empty completion content.');
    }
    return content;
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final request = await _httpClient.getUrl(uri).timeout(_requestTimeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(_requestTimeout);
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'GET ${uri.path} failed (${response.statusCode}): $body',
        uri: uri,
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object response.');
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, dynamic> payload,
  ) async {
    final request = await _httpClient.postUrl(uri).timeout(_requestTimeout);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.add(utf8.encode(jsonEncode(payload)));

    final response = await request.close().timeout(_requestTimeout);
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'POST ${uri.path} failed (${response.statusCode}): $body',
        uri: uri,
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object response.');
    }
    return decoded;
  }

  List<String> _parseModelIds(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! List) {
      return const [];
    }
    final ids = <String>[];
    for (final entry in data) {
      if (entry is Map<String, dynamic>) {
        final id = entry['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          ids.add(id);
        }
      }
    }
    return ids;
  }

  String _buildHealthMessage({
    required bool modelAvailable,
    required String? resolvedModel,
    required List<String> availableModels,
  }) {
    if (!modelAvailable) {
      final list = availableModels.isEmpty
          ? 'none'
          : availableModels.take(5).join(', ');
      return 'Connected to local server, but model "$_configuredModelName" '
          'is unavailable. Found: $list';
    }

    if (resolvedModel != null && !_isModelMatch(_configuredModelName, resolvedModel)) {
      return 'Connected to local server. Configured "$_configuredModelName" '
          'not found; using "$resolvedModel".';
    }

    return 'Connected to local server at $baseUrl using "$resolvedModel".';
  }

  String? _resolveModelName(List<String> availableModels) {
    final configured = _findModel(_configuredModelName, availableModels);
    if (configured != null) {
      return configured;
    }

    for (final fallback in _fallbackModels) {
      final candidate = _findModel(fallback, availableModels);
      if (candidate != null) {
        return candidate;
      }
    }

    return null;
  }

  String? _findModel(String desired, List<String> availableModels) {
    final wanted = desired.toLowerCase();
    for (final model in availableModels) {
      final normalized = model.toLowerCase();
      if (_isModelMatch(wanted, normalized)) {
        return model;
      }
    }
    return null;
  }

  bool _isModelMatch(String desiredModel, String availableModelId) {
    final desired = desiredModel.toLowerCase();
    final available = availableModelId.toLowerCase();
    return available == desired || available.startsWith('$desired:');
  }

  Uri _endpoint(String suffix) {
    final basePath = _baseUri.path.endsWith('/')
        ? _baseUri.path.substring(0, _baseUri.path.length - 1)
        : _baseUri.path;
    final normalizedSuffix =
        suffix.startsWith('/') ? suffix.substring(1) : suffix;
    return _baseUri.replace(path: '$basePath/$normalizedSuffix');
  }

  static Uri _normalizeBaseUri(String baseUrl) {
    final trimmed = baseUrl.trim();
    final raw = trimmed.isEmpty ? 'http://localhost:11434/v1' : trimmed;
    final parsed = Uri.parse(raw);

    var path = parsed.path;
    if (path.isEmpty || path == '/') {
      path = '/v1';
    } else {
      if (path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      if (!path.endsWith('/v1')) {
        path = '$path/v1';
      }
    }
    return parsed.replace(path: path);
  }

  void _startHealthMonitor() {
    _healthPoller?.cancel();
    _healthPoller = Timer.periodic(_healthPollInterval, (_) {
      unawaited(checkHealth(force: true));
    });
  }

  Future<void> _onRequestFailure(Object error) async {
    debugPrint('[Sensei LLM] Request failed: $error');
    await checkHealth(force: true);
  }

  LlmExtraction _parseExtractionResponse(String responseText) {
    final parsed = _extractJsonMap(responseText);
    if (parsed == null) {
      return const LlmExtraction(confidence: 0.0);
    }

    final subjectName = _toNullableString(
      parsed['subject_name'] ?? parsed['subjectName'],
    );
    final attributeKeyRaw = _toNullableString(
      parsed['attribute_key'] ?? parsed['attributeKey'],
    );
    final attributeValue = _toNullableString(
      parsed['attribute_value'] ?? parsed['attributeValue'],
    );
    final isQuery =
        _toBool(parsed['is_query'] ?? parsed['isQuery'], fallback: false);
    final confidence = _toDouble(parsed['confidence'], fallback: 0.82);

    return LlmExtraction(
      subjectName: subjectName,
      attributeKey:
          attributeKeyRaw != null ? UriUtils.nameToIdentifier(attributeKeyRaw) : null,
      attributeValue: attributeValue,
      isQuery: isQuery,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
    );
  }

  Map<String, dynamic>? _extractJsonMap(String responseText) {
    Map<String, dynamic>? decode(String candidate) {
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return null;
    }

    try {
      return decode(responseText.trim());
    } catch (_) {}

    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    ).firstMatch(responseText);
    if (fenced != null) {
      final payload = fenced.group(1);
      if (payload != null) {
        try {
          return decode(payload.trim());
        } catch (_) {}
      }
    }

    final objectMatch = RegExp(r'\{[\s\S]*\}').firstMatch(responseText);
    if (objectMatch != null) {
      final payload = objectMatch.group(0);
      if (payload != null) {
        try {
          return decode(payload);
        } catch (_) {}
      }
    }

    return null;
  }

  String _extractMessageContent(dynamic content) {
    if (content is String) {
      return content.trim();
    }
    if (content is List) {
      final parts = <String>[];
      for (final item in content) {
        if (item is Map<String, dynamic>) {
          final text = item['text']?.toString() ?? '';
          if (text.isNotEmpty) {
            parts.add(text);
          }
        }
      }
      return parts.join().trim();
    }
    return '';
  }

  String? _toNullableString(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  bool _toBool(dynamic value, {required bool fallback}) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.toLowerCase().trim();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
    return fallback;
  }

  double _toDouble(dynamic value, {required double fallback}) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? fallback;
    }
    return fallback;
  }

  String _buildSynthesisPrompt(
    String subjectUri,
    Map<String, String> facts,
    List<String> recentRolos,
  ) {
    final factsText =
        facts.entries.map((e) => '- ${e.key}: ${e.value}').join('\n');
    final recentText = recentRolos.isEmpty
        ? ''
        : '\nRecent activity:\n${recentRolos.map((r) => '- $r').join('\n')}';

    return 'Given these facts about $subjectUri:\n$factsText$recentText\n\n'
        'Return one concise insight sentence only.';
  }

  String _ruleBasedSummary(String text, int maxLength) {
    final firstSentence = text.split(RegExp(r'[.!?]')).first.trim();
    if (firstSentence.length <= maxLength) {
      return firstSentence;
    }
    return '${firstSentence.substring(0, maxLength - 3)}...';
  }

  LlmExtraction _pickBestExtraction(
    LlmExtraction fallback,
    LlmExtraction llmExtraction,
  ) {
    if (llmExtraction.canCreateAttribute &&
        llmExtraction.confidence >= fallback.confidence) {
      return llmExtraction;
    }
    if (!fallback.canCreateAttribute &&
        llmExtraction.isQuery &&
        llmExtraction.confidence > fallback.confidence) {
      return llmExtraction;
    }
    return fallback;
  }

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
