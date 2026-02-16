import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/uri_utils.dart';
import 'input_parser.dart';

/// Result of an LLM inference call.
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

/// Supported LLM providers.
enum LlmProvider {
  localLlama(
    id: 'llama',
    label: 'Local Llama',
    isLocal: true,
    apiKeyEnvVar: '',
  ),
  claude(
    id: 'claude',
    label: 'Claude',
    isLocal: false,
    apiKeyEnvVar: 'CLAUDE_API_KEY',
  ),
  grok(
    id: 'grok',
    label: 'Grok',
    isLocal: false,
    apiKeyEnvVar: 'GROK_API_KEY',
  ),
  gemini(
    id: 'gemini',
    label: 'Gemini',
    isLocal: false,
    apiKeyEnvVar: 'GEMINI_API_KEY',
  ),
  chatGpt(
    id: 'chatgpt',
    label: 'ChatGPT',
    isLocal: false,
    apiKeyEnvVar: 'OPENAI_API_KEY',
  );

  final String id;
  final String label;
  final bool isLocal;
  final String apiKeyEnvVar;

  const LlmProvider({
    required this.id,
    required this.label,
    required this.isLocal,
    required this.apiKeyEnvVar,
  });

  bool get requiresApiKey => !isLocal;

  static LlmProvider fromId(String raw) {
    final normalized = raw.toLowerCase().trim();
    for (final provider in LlmProvider.values) {
      if (provider.id == normalized ||
          provider.label.toLowerCase() == normalized) {
        return provider;
      }
    }
    if (normalized == 'openai' || normalized == 'chatgpt') {
      return LlmProvider.chatGpt;
    }
    if (normalized == 'llama' || normalized == 'local') {
      return LlmProvider.localLlama;
    }
    return LlmProvider.localLlama;
  }
}

/// Context fed to parsing requests so Sensei stays anchored to Dojo rules.
class LlmParsingContext {
  final String? userProfileSummary;
  final String? parserSubjectUriHint;
  final List<String> recentSummonings;
  final List<String> recentTargetUris;
  final List<String> hintAttributes;

  const LlmParsingContext({
    this.userProfileSummary,
    this.parserSubjectUriHint,
    this.recentSummonings = const [],
    this.recentTargetUris = const [],
    this.hintAttributes = const [],
  });

  bool get hasAnyHints =>
      (userProfileSummary?.trim().isNotEmpty ?? false) ||
      (parserSubjectUriHint?.trim().isNotEmpty ?? false) ||
      recentSummonings.isNotEmpty ||
      recentTargetUris.isNotEmpty ||
      hintAttributes.isNotEmpty;
}

/// Connection and readiness state for the active provider.
class LlmHealthStatus {
  final LlmProvider provider;
  final bool serverReachable;
  final bool modelAvailable;
  final bool apiKeyConfigured;
  final String endpoint;
  final String configuredModel;
  final String? activeModel;
  final List<String> availableModels;
  final String message;
  final DateTime? checkedAt;

  const LlmHealthStatus({
    this.provider = LlmProvider.localLlama,
    this.serverReachable = false,
    this.modelAvailable = false,
    this.apiKeyConfigured = true,
    this.endpoint = '',
    this.configuredModel = '',
    this.activeModel,
    this.availableModels = const [],
    this.message = 'LLM health has not been checked yet.',
    this.checkedAt,
  });

  /// True when this provider can be used for inference.
  bool get isHealthy =>
      serverReachable &&
      modelAvailable &&
      (!provider.requiresApiKey || apiKeyConfigured);
}

/// Abstract interface for Sensei LLM operations.
abstract class SenseiLlmService {
  bool get isReady;
  String get baseUrl;
  String get configuredModelName;
  String configuredModelFor(LlmProvider provider);
  String get activeModelName;
  LlmProvider get currentProvider;
  List<LlmProvider> get supportedProviders;
  ValueListenable<LlmHealthStatus> get healthStatus;
  bool isApiKeyConfigured(LlmProvider provider);

  Future<void> initialize({
    required String modelPath,
    int contextSize = 2048,
    int threads = 4,
  });

  Future<void> selectProvider(LlmProvider provider);
  Future<void> setApiKey(LlmProvider provider, String apiKey);
  Future<void> setConfiguredModel(LlmProvider provider, String modelName);
  Future<LlmHealthStatus> checkHealth({bool force = false});

  Future<LlmExtraction> parseInput(
    String input, {
    LlmParsingContext context = const LlmParsingContext(),
  });

  Future<LlmResult> synthesize({
    required String subjectUri,
    required Map<String, String> facts,
    List<String> recentRolos = const [],
  });

  /// Answers a user question using supplied vault context.
  ///
  /// The model must stay grounded in [vaultContext] and avoid fabricating data.
  Future<String> answerWithVault({
    required String question,
    required String vaultContext,
    String? userProfileSummary,
  });

  /// Answers a prompt grounded in an arbitrary context block.
  Future<String> answerWithContext({
    required String prompt,
    required String context,
    String? systemInstruction,
    int maxTokens = 280,
    double temperature = 0.2,
  });

  Future<String> summarize(String text, {int maxLength = 50});
  Future<void> dispose();
}

/// Multi-provider LLM client.
///
/// - Local Llama via OpenAI-compatible endpoint (Ollama/local server)
/// - Claude (Anthropic)
/// - Grok (xAI OpenAI-compatible)
/// - Gemini (Google)
/// - ChatGPT (OpenAI)
///
/// If the active provider is unhealthy, Sensei falls back to deterministic
/// parser logic and keeps the Dojo functional.
class LocalLlmService implements SenseiLlmService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _apiKeyStoragePrefix = 'sensei_provider_api_key_';
  static const String _modelStoragePrefix = 'sensei_provider_model_';

  LocalLlmService({
    LlmProvider initialProvider = LlmProvider.localLlama,
    String localBaseUrl = 'http://localhost:11434/v1',
    String localModel = 'llama3.3',
    List<String> localFallbackModels = const ['openchat-3.6'],
    String claudeBaseUrl = 'https://api.anthropic.com/v1',
    String claudeModel = 'claude-3-5-sonnet-latest',
    String claudeApiKey = '',
    String grokBaseUrl = 'https://api.x.ai/v1',
    String grokModel = 'grok-2-latest',
    String grokApiKey = '',
    String geminiBaseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    String geminiModel = 'gemini-1.5-flash',
    String geminiApiKey = '',
    String chatGptBaseUrl = 'https://api.openai.com/v1',
    String chatGptModel = 'gpt-4o-mini',
    String chatGptApiKey = '',
    Duration requestTimeout = const Duration(seconds: 15),
    Duration healthPollInterval = const Duration(seconds: 30),
  })  : _currentProvider = initialProvider,
        _requestTimeout = requestTimeout,
        _healthPollInterval = healthPollInterval {
    _httpClient.connectionTimeout = requestTimeout;
    _providerConfigs = <LlmProvider, _ProviderConfig>{
      LlmProvider.localLlama: _ProviderConfig(
        baseUri: _normalizeOpenAiBaseUri(localBaseUrl, defaultBase: 'http://localhost:11434/v1'),
        configuredModel: _trimOrDefault(localModel, 'llama3.3'),
        defaultConfiguredModel: _trimOrDefault(localModel, 'llama3.3'),
        apiKey: '',
        fallbackModels: localFallbackModels
            .map((m) => m.trim())
            .where((m) => m.isNotEmpty)
            .toList(growable: false),
      ),
      LlmProvider.claude: _ProviderConfig(
        baseUri: _normalizeRequiredSuffix(
          claudeBaseUrl,
          defaultBase: 'https://api.anthropic.com/v1',
          requiredSuffix: '/v1',
        ),
        configuredModel: _trimOrDefault(claudeModel, 'claude-3-5-sonnet-latest'),
        defaultConfiguredModel: _trimOrDefault(
          claudeModel,
          'claude-3-5-sonnet-latest',
        ),
        apiKey: claudeApiKey.trim(),
      ),
      LlmProvider.grok: _ProviderConfig(
        baseUri: _normalizeOpenAiBaseUri(
          grokBaseUrl,
          defaultBase: 'https://api.x.ai/v1',
        ),
        configuredModel: _trimOrDefault(grokModel, 'grok-2-latest'),
        defaultConfiguredModel: _trimOrDefault(grokModel, 'grok-2-latest'),
        apiKey: grokApiKey.trim(),
      ),
      LlmProvider.gemini: _ProviderConfig(
        baseUri: _normalizeGeminiBaseUri(
          geminiBaseUrl,
          defaultBase: 'https://generativelanguage.googleapis.com/v1',
        ),
        configuredModel: _trimOrDefault(geminiModel, 'gemini-1.5-flash'),
        defaultConfiguredModel: _trimOrDefault(geminiModel, 'gemini-1.5-flash'),
        apiKey: geminiApiKey.trim(),
      ),
      LlmProvider.chatGpt: _ProviderConfig(
        baseUri: _normalizeOpenAiBaseUri(
          chatGptBaseUrl,
          defaultBase: 'https://api.openai.com/v1',
        ),
        configuredModel: _trimOrDefault(chatGptModel, 'gpt-4o-mini'),
        defaultConfiguredModel: _trimOrDefault(chatGptModel, 'gpt-4o-mini'),
        apiKey: chatGptApiKey.trim(),
      ),
    };
  }

  static String _trimOrDefault(String raw, String fallback) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }

  bool _isReady = false;
  final Duration _requestTimeout;
  final Duration _healthPollInterval;
  final HttpClient _httpClient = HttpClient();
  final ValueNotifier<LlmHealthStatus> _healthStatusNotifier =
      ValueNotifier(const LlmHealthStatus());
  late final Map<LlmProvider, _ProviderConfig> _providerConfigs;
  final Map<LlmProvider, String> _activeModels = <LlmProvider, String>{};
  Uri? _activeGeminiBaseUri;
  LlmProvider _currentProvider;
  DateTime? _lastHealthCheck;
  LlmProvider? _lastHealthProvider;
  Timer? _healthPoller;

  _ProviderConfig get _activeConfig => _providerConfigs[_currentProvider]!;

  @override
  bool get isReady => _isReady;

  @override
  String get baseUrl => _activeConfig.baseUri.toString();

  @override
  String get configuredModelName => _activeConfig.configuredModel;

  @override
  String configuredModelFor(LlmProvider provider) {
    final config = _providerConfigs[provider];
    if (config == null) {
      return '';
    }
    return config.configuredModel;
  }

  @override
  String get activeModelName =>
      _activeModels[_currentProvider] ?? _activeConfig.configuredModel;

  @override
  LlmProvider get currentProvider => _currentProvider;

  @override
  List<LlmProvider> get supportedProviders => LlmProvider.values;

  @override
  ValueListenable<LlmHealthStatus> get healthStatus => _healthStatusNotifier;

  @override
  bool isApiKeyConfigured(LlmProvider provider) {
    if (provider.isLocal) {
      return true;
    }
    final config = _providerConfigs[provider];
    return config != null && config.hasApiKey;
  }

  @override
  Future<void> initialize({
    required String modelPath,
    int contextSize = 2048,
    int threads = 4,
  }) async {
    await _hydrateApiKeysFromStorage();
    await _hydrateModelsFromStorage();
    debugPrint(
      '[Sensei LLM] Initializing provider=${_currentProvider.label} '
      'endpoint=$baseUrl configuredModel=$configuredModelName marker=$modelPath',
    );
    await checkHealth(force: true);
    _startHealthMonitor();
  }

  @override
  Future<void> selectProvider(LlmProvider provider) async {
    if (_currentProvider == provider) {
      return;
    }

    _currentProvider = provider;
    _lastHealthCheck = null;
    _lastHealthProvider = null;
    debugPrint('[Sensei LLM] Provider switched to ${provider.label}');
    await checkHealth(force: true);
  }

  @override
  Future<void> setApiKey(LlmProvider provider, String apiKey) async {
    if (!provider.requiresApiKey) {
      return;
    }

    final config = _providerConfigs[provider];
    if (config == null) {
      return;
    }

    final sanitized = apiKey.trim();
    config.apiKey = sanitized;
    if (provider == LlmProvider.gemini) {
      _activeGeminiBaseUri = null;
    }

    final storageKey = _apiKeyStorageKey(provider);
    if (sanitized.isEmpty) {
      await _secureStorage.delete(key: storageKey);
    } else {
      await _secureStorage.write(key: storageKey, value: sanitized);
    }

    _lastHealthCheck = null;
    _lastHealthProvider = null;
    if (_currentProvider == provider) {
      await checkHealth(force: true);
    }
  }

  @override
  Future<void> setConfiguredModel(LlmProvider provider, String modelName) async {
    final config = _providerConfigs[provider];
    if (config == null) {
      return;
    }

    final sanitized = modelName.trim();
    final nextModel = sanitized.isEmpty
        ? config.defaultConfiguredModel
        : sanitized;
    config.configuredModel = nextModel;
    _activeModels.remove(provider);
    if (provider == LlmProvider.gemini) {
      _activeGeminiBaseUri = null;
    }

    final storageKey = _modelStorageKey(provider);
    if (nextModel == config.defaultConfiguredModel) {
      await _secureStorage.delete(key: storageKey);
    } else {
      await _secureStorage.write(key: storageKey, value: nextModel);
    }

    _lastHealthCheck = null;
    _lastHealthProvider = null;
    if (_currentProvider == provider) {
      await checkHealth(force: true);
    }
  }

  @override
  Future<LlmHealthStatus> checkHealth({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastHealthCheck != null &&
        _lastHealthProvider == _currentProvider &&
        now.difference(_lastHealthCheck!) < const Duration(seconds: 5)) {
      return _healthStatusNotifier.value;
    }
    _lastHealthCheck = now;
    _lastHealthProvider = _currentProvider;

    try {
      final status = await _checkHealthForProvider(now);
      _isReady = status.isHealthy;
      _healthStatusNotifier.value = status;
      return status;
    } catch (e) {
      final status = LlmHealthStatus(
        provider: _currentProvider,
        serverReachable: false,
        modelAvailable: false,
        apiKeyConfigured: !_currentProvider.requiresApiKey || _activeConfig.hasApiKey,
        endpoint: baseUrl,
        configuredModel: configuredModelName,
        activeModel: _activeModels[_currentProvider],
        availableModels: const [],
        message: '${_currentProvider.label} health check failed: $e',
        checkedAt: now,
      );
      _isReady = false;
      _healthStatusNotifier.value = status;
      debugPrint('[Sensei LLM] Health check failed: $e');
      return status;
    }
  }

  Future<LlmHealthStatus> _checkHealthForProvider(DateTime now) {
    switch (_currentProvider) {
      case LlmProvider.localLlama:
        return _checkOpenAiCompatibleHealth(
          now: now,
          provider: _currentProvider,
          allowMissingApiKey: true,
          allowConfiguredModelWhenListEmpty: false,
          fallbackModels: _activeConfig.fallbackModels,
        );
      case LlmProvider.grok:
      case LlmProvider.chatGpt:
        return _checkOpenAiCompatibleHealth(
          now: now,
          provider: _currentProvider,
          allowMissingApiKey: false,
          allowConfiguredModelWhenListEmpty: true,
        );
      case LlmProvider.claude:
        return _checkClaudeHealth(now);
      case LlmProvider.gemini:
        return _checkGeminiHealth(now);
    }
  }

  Future<LlmHealthStatus> _checkOpenAiCompatibleHealth({
    required DateTime now,
    required LlmProvider provider,
    required bool allowMissingApiKey,
    required bool allowConfiguredModelWhenListEmpty,
    List<String> fallbackModels = const [],
  }) async {
    final config = _providerConfigs[provider]!;
    if (!allowMissingApiKey && !config.hasApiKey) {
      return _missingApiKeyStatus(now, provider, config);
    }

    final headers = config.hasApiKey ? _bearerHeaders(config.apiKey) : const <String, String>{};
    final response = await _getJson(
      _openAiEndpoint(config.baseUri, 'models'),
      headers: headers,
    );
    final availableModels = _parseOpenAiModelIds(response);
    final resolvedModel = _resolveModelName(
      configuredModel: config.configuredModel,
      availableModels: availableModels,
      fallbackModels: fallbackModels,
      allowConfiguredModelWhenListEmpty: allowConfiguredModelWhenListEmpty,
    );
    final modelAvailable = resolvedModel != null;
    if (resolvedModel != null) {
      _activeModels[provider] = resolvedModel;
    } else {
      _activeModels.remove(provider);
    }

    return LlmHealthStatus(
      provider: provider,
      serverReachable: true,
      modelAvailable: modelAvailable,
      apiKeyConfigured: !provider.requiresApiKey || config.hasApiKey,
      endpoint: config.baseUri.toString(),
      configuredModel: config.configuredModel,
      activeModel: resolvedModel,
      availableModels: availableModels,
      message: _buildModelHealthMessage(
        provider: provider,
        endpoint: config.baseUri.toString(),
        configuredModel: config.configuredModel,
        resolvedModel: resolvedModel,
        availableModels: availableModels,
      ),
      checkedAt: now,
    );
  }

  Future<LlmHealthStatus> _checkClaudeHealth(DateTime now) async {
    final config = _activeConfig;
    if (!config.hasApiKey) {
      return _missingApiKeyStatus(now, LlmProvider.claude, config);
    }

    final response = await _getJson(
      _endpoint(config.baseUri, 'models'),
      headers: _claudeHeaders(config.apiKey),
    );
    final availableModels = _parseOpenAiModelIds(response);
    final resolvedModel = _resolveModelName(
      configuredModel: config.configuredModel,
      availableModels: availableModels,
      fallbackModels: const [],
      allowConfiguredModelWhenListEmpty: true,
    );
    if (resolvedModel != null) {
      _activeModels[LlmProvider.claude] = resolvedModel;
    } else {
      _activeModels.remove(LlmProvider.claude);
    }

    return LlmHealthStatus(
      provider: LlmProvider.claude,
      serverReachable: true,
      modelAvailable: resolvedModel != null,
      apiKeyConfigured: true,
      endpoint: config.baseUri.toString(),
      configuredModel: config.configuredModel,
      activeModel: resolvedModel,
      availableModels: availableModels,
      message: _buildModelHealthMessage(
        provider: LlmProvider.claude,
        endpoint: config.baseUri.toString(),
        configuredModel: config.configuredModel,
        resolvedModel: resolvedModel,
        availableModels: availableModels,
      ),
      checkedAt: now,
    );
  }

  Future<LlmHealthStatus> _checkGeminiHealth(DateTime now) async {
    final config = _activeConfig;
    if (!config.hasApiKey) {
      return _missingApiKeyStatus(now, LlmProvider.gemini, config);
    }

    try {
      final primary = await _resolveGeminiHealthAgainstBase(
        now: now,
        config: config,
        baseUri: config.baseUri,
      );
      _activeGeminiBaseUri = config.baseUri;
      return primary;
    } catch (_) {
      final fallbackBase = _geminiAlternativeBaseUri(config.baseUri);
      if (fallbackBase == null) {
        rethrow;
      }

      try {
        final fallback = await _resolveGeminiHealthAgainstBase(
          now: now,
          config: config,
          baseUri: fallbackBase,
        );
        _activeGeminiBaseUri = fallbackBase;
        return fallback;
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<LlmHealthStatus> _resolveGeminiHealthAgainstBase({
    required DateTime now,
    required _ProviderConfig config,
    required Uri baseUri,
  }) async {
    final response = await _getJson(_geminiModelsEndpoint(baseUri, config.apiKey));
    final availableModels = _parseGeminiModelIds(response);
    final resolvedModel = _resolveModelName(
      configuredModel: config.configuredModel,
      availableModels: availableModels,
      fallbackModels: const [],
      allowConfiguredModelWhenListEmpty: true,
    );
    if (resolvedModel != null) {
      _activeModels[LlmProvider.gemini] = resolvedModel;
    } else {
      _activeModels.remove(LlmProvider.gemini);
    }

    return LlmHealthStatus(
      provider: LlmProvider.gemini,
      serverReachable: true,
      modelAvailable: resolvedModel != null,
      apiKeyConfigured: true,
      endpoint: baseUri.toString(),
      configuredModel: config.configuredModel,
      activeModel: resolvedModel,
      availableModels: availableModels,
      message: _buildModelHealthMessage(
        provider: LlmProvider.gemini,
        endpoint: baseUri.toString(),
        configuredModel: config.configuredModel,
        resolvedModel: resolvedModel,
        availableModels: availableModels,
      ),
      checkedAt: now,
    );
  }

  LlmHealthStatus _missingApiKeyStatus(
    DateTime now,
    LlmProvider provider,
    _ProviderConfig config,
  ) {
    return LlmHealthStatus(
      provider: provider,
      serverReachable: false,
      modelAvailable: false,
      apiKeyConfigured: false,
      endpoint: config.baseUri.toString(),
      configuredModel: config.configuredModel,
      activeModel: null,
      availableModels: const [],
      message:
          '${provider.label} is selected but API key is missing. '
          'Add it in Settings > LLM Provider > Credentials or set '
          '${provider.apiKeyEnvVar}.',
      checkedAt: now,
    );
  }

  @override
  Future<LlmExtraction> parseInput(
    String input, {
    LlmParsingContext context = const LlmParsingContext(),
  }) async {
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
      final responseText = await _createCompletion(
        systemPrompt: '$_senseiCorePrompt\n$_extractionSystemPrompt',
        userPrompt: _buildExtractionPrompt(input, context),
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
        '[Sensei LLM] Parse (${_currentProvider.label}) took '
        '${stopwatch.elapsedMilliseconds}ms',
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
      final llmText = await _createCompletion(
        systemPrompt: '$_senseiCorePrompt\n$_synthesisSystemPrompt',
        userPrompt: _buildSynthesisPrompt(subjectUri, facts, recentRolos),
        maxTokens: 180,
        temperature: 0.3,
      );
      final normalized = llmText.trim();
      stopwatch.stop();
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
      stopwatch.stop();
      final fallback = _ruleBasedSynthesis(subjectUri, facts, recentRolos);
      return LlmResult(
        text: fallback,
        confidence: 0.65,
        inferenceTimeMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  @override
  Future<String> answerWithVault({
    required String question,
    required String vaultContext,
    String? userProfileSummary,
  }) async {
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty) {
      return 'Please ask a question.';
    }

    final context = vaultContext.trim();
    final health = await checkHealth();
    if (!health.isHealthy) {
      return _ruleBasedVaultAnswer(trimmedQuestion, context);
    }

    try {
      final answer = await _createCompletion(
        systemPrompt: '$_senseiCorePrompt\n$_qaSystemPrompt',
        userPrompt: _buildVaultQaPrompt(
          question: trimmedQuestion,
          vaultContext: context,
          userProfileSummary: userProfileSummary,
        ),
        maxTokens: 280,
        temperature: 0.2,
      );
      final normalized = answer.trim();
      if (normalized.isEmpty) {
        return _ruleBasedVaultAnswer(trimmedQuestion, context);
      }
      return normalized;
    } catch (e) {
      await _onRequestFailure(e);
      return _ruleBasedVaultAnswer(trimmedQuestion, context);
    }
  }

  @override
  Future<String> answerWithContext({
    required String prompt,
    required String context,
    String? systemInstruction,
    int maxTokens = 280,
    double temperature = 0.2,
  }) async {
    final trimmedPrompt = prompt.trim();
    if (trimmedPrompt.isEmpty) {
      return '';
    }

    final health = await checkHealth();
    if (!health.isHealthy) {
      return '';
    }

    final contextBlock = context.trim().isEmpty
        ? '- No context provided.'
        : context.trim();
    final instruction = (systemInstruction ?? '').trim();
    final system = instruction.isEmpty
        ? '$_senseiCorePrompt\n$_contextAnswerSystemPrompt'
        : '$_senseiCorePrompt\n$instruction';

    try {
      final result = await _createCompletion(
        systemPrompt: system,
        userPrompt: 'Context:\n$contextBlock\n\nPrompt: "$trimmedPrompt"',
        maxTokens: maxTokens,
        temperature: temperature,
      );
      return result.trim();
    } catch (e) {
      await _onRequestFailure(e);
      return '';
    }
  }

  @override
  Future<String> summarize(String text, {int maxLength = 50}) async {
    if (text.length <= maxLength) {
      return text;
    }

    final health = await checkHealth();
    if (!health.isHealthy) {
      return _ruleBasedSummary(text, maxLength);
    }

    try {
      final summary = await _createCompletion(
        systemPrompt: '$_senseiCorePrompt\n$_summarySystemPrompt',
        userPrompt: 'Summarize this in at most $maxLength characters:\n\n$text',
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
    debugPrint('[Sensei LLM] Client disposed');
  }

  Future<String> _createCompletion({
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
    required double temperature,
  }) {
    switch (_currentProvider) {
      case LlmProvider.localLlama:
      case LlmProvider.grok:
      case LlmProvider.chatGpt:
        return _createOpenAiCompatibleCompletion(
          config: _activeConfig,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          maxTokens: maxTokens,
          temperature: temperature,
        );
      case LlmProvider.claude:
        return _createClaudeCompletion(
          config: _activeConfig,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          maxTokens: maxTokens,
          temperature: temperature,
        );
      case LlmProvider.gemini:
        return _createGeminiCompletion(
          config: _activeConfig,
          systemPrompt: systemPrompt,
          userPrompt: userPrompt,
          maxTokens: maxTokens,
          temperature: temperature,
        );
    }
  }

  Future<String> _createOpenAiCompatibleCompletion({
    required _ProviderConfig config,
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
    required double temperature,
  }) async {
    final headers = config.hasApiKey ? _bearerHeaders(config.apiKey) : const <String, String>{};
    final response = await _postJson(
      _openAiEndpoint(config.baseUri, 'chat/completions'),
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
      headers: headers,
    );
    final content = _parseOpenAiCompletion(response);
    if (content.isEmpty) {
      throw const FormatException('Empty completion content.');
    }
    return content;
  }

  Future<String> _createClaudeCompletion({
    required _ProviderConfig config,
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
    required double temperature,
  }) async {
    final response = await _postJson(
      _endpoint(config.baseUri, 'messages'),
      <String, dynamic>{
        'model': activeModelName,
        'max_tokens': maxTokens,
        'temperature': temperature,
        'system': systemPrompt,
        'messages': [
          {'role': 'user', 'content': userPrompt},
        ],
      },
      headers: _claudeHeaders(config.apiKey),
    );
    final content = _parseClaudeCompletion(response);
    if (content.isEmpty) {
      throw const FormatException('Empty Claude completion content.');
    }
    return content;
  }

  Future<String> _createGeminiCompletion({
    required _ProviderConfig config,
    required String systemPrompt,
    required String userPrompt,
    required int maxTokens,
    required double temperature,
  }) async {
    final baseUri = _activeGeminiBaseUri ?? config.baseUri;
    final response = await _postJson(
      _geminiGenerateEndpoint(baseUri, activeModelName, config.apiKey),
      <String, dynamic>{
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': userPrompt},
            ],
          },
        ],
        'generationConfig': {
          'temperature': temperature,
          'maxOutputTokens': maxTokens,
        },
      },
    );
    final content = _parseGeminiCompletion(response);
    if (content.isEmpty) {
      throw const FormatException('Empty Gemini completion content.');
    }
    return content;
  }

  String _parseOpenAiCompletion(Map<String, dynamic> response) {
    final choices = response['choices'];
    if (choices is! List || choices.isEmpty) {
      return '';
    }
    final firstChoice = choices.first;
    if (firstChoice is! Map<String, dynamic>) {
      return '';
    }
    final message = firstChoice['message'];
    if (message is! Map<String, dynamic>) {
      return '';
    }
    return _extractMessageContent(message['content']);
  }

  String _parseClaudeCompletion(Map<String, dynamic> response) {
    final content = response['content'];
    if (content is! List) {
      return '';
    }
    final parts = <String>[];
    for (final part in content) {
      if (part is Map<String, dynamic>) {
        final type = part['type']?.toString() ?? '';
        if (type == 'text') {
          final text = part['text']?.toString() ?? '';
          if (text.isNotEmpty) {
            parts.add(text);
          }
        }
      }
    }
    return parts.join('\n').trim();
  }

  String _parseGeminiCompletion(Map<String, dynamic> response) {
    final candidates = response['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      return '';
    }
    final first = candidates.first;
    if (first is! Map<String, dynamic>) {
      return '';
    }
    final content = first['content'];
    if (content is! Map<String, dynamic>) {
      return '';
    }
    final parts = content['parts'];
    if (parts is! List || parts.isEmpty) {
      return '';
    }
    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is Map<String, dynamic>) {
        final text = part['text']?.toString() ?? '';
        if (text.isNotEmpty) {
          if (buffer.isNotEmpty) {
            buffer.writeln();
          }
          buffer.write(text);
        }
      }
    }
    return buffer.toString().trim();
  }

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final request = await _httpClient.getUrl(uri).timeout(_requestTimeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    headers.forEach(request.headers.set);

    final response = await request.close().timeout(_requestTimeout);
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'GET ${uri.toString()} failed (${response.statusCode}): $body',
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
    Map<String, dynamic> payload, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final request = await _httpClient.postUrl(uri).timeout(_requestTimeout);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    headers.forEach(request.headers.set);
    request.add(utf8.encode(jsonEncode(payload)));

    final response = await request.close().timeout(_requestTimeout);
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'POST ${uri.toString()} failed (${response.statusCode}): $body',
        uri: uri,
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected JSON object response.');
    }
    return decoded;
  }

  Map<String, String> _bearerHeaders(String apiKey) {
    return <String, String>{
      HttpHeaders.authorizationHeader: 'Bearer ${apiKey.trim()}',
    };
  }

  Map<String, String> _claudeHeaders(String apiKey) {
    return <String, String>{
      'x-api-key': apiKey.trim(),
      'anthropic-version': '2023-06-01',
    };
  }

  List<String> _parseOpenAiModelIds(Map<String, dynamic> response) {
    final data = response['data'];
    if (data is! List) {
      return const [];
    }
    final ids = <String>[];
    for (final item in data) {
      if (item is Map<String, dynamic>) {
        final id = item['id']?.toString() ?? '';
        if (id.isNotEmpty) {
          ids.add(id);
        }
      }
    }
    return ids;
  }

  List<String> _parseGeminiModelIds(Map<String, dynamic> response) {
    final models = response['models'];
    if (models is! List) {
      return const [];
    }
    final ids = <String>[];
    for (final item in models) {
      if (item is Map<String, dynamic>) {
        final name = item['name']?.toString() ?? '';
        if (name.isEmpty) {
          continue;
        }
        ids.add(name.startsWith('models/') ? name.substring(7) : name);
      }
    }
    return ids;
  }

  String _buildModelHealthMessage({
    required LlmProvider provider,
    required String endpoint,
    required String configuredModel,
    required String? resolvedModel,
    required List<String> availableModels,
  }) {
    if (resolvedModel == null) {
      final known = availableModels.isEmpty
          ? 'none'
          : availableModels.take(5).join(', ');
      return '${provider.label} connected at $endpoint, but model '
          '"$configuredModel" is unavailable. Found: $known';
    }
    if (!_isModelMatch(configuredModel, resolvedModel)) {
      return '${provider.label} connected at $endpoint. Configured '
          '"$configuredModel" not found; using "$resolvedModel".';
    }
    return '${provider.label} connected at $endpoint using "$resolvedModel".';
  }

  String? _resolveModelName({
    required String configuredModel,
    required List<String> availableModels,
    required List<String> fallbackModels,
    required bool allowConfiguredModelWhenListEmpty,
  }) {
    if (availableModels.isEmpty) {
      return allowConfiguredModelWhenListEmpty
          ? configuredModel
          : null;
    }

    final configured = _findModel(configuredModel, availableModels);
    if (configured != null) {
      return configured;
    }

    for (final fallback in fallbackModels) {
      final candidate = _findModel(fallback, availableModels);
      if (candidate != null) {
        return candidate;
      }
    }
    return null;
  }

  String? _findModel(String desired, List<String> availableModels) {
    for (final available in availableModels) {
      if (_isModelMatch(desired, available)) {
        return available;
      }
    }
    return null;
  }

  bool _isModelMatch(String desiredModel, String availableModelId) {
    final desired = desiredModel.toLowerCase().trim();
    final available = availableModelId.toLowerCase().trim();
    return available == desired ||
        available.startsWith('$desired:') ||
        available.endsWith('/$desired');
  }

  Uri _openAiEndpoint(Uri baseUri, String suffix) {
    return _endpoint(baseUri, suffix);
  }

  Uri _endpoint(Uri baseUri, String suffix) {
    return baseUri.replace(path: _joinPath(baseUri.path, suffix));
  }

  Uri _geminiModelsEndpoint(Uri baseUri, String apiKey) {
    return baseUri.replace(
      path: _joinPath(baseUri.path, 'models'),
      queryParameters: <String, String>{'key': apiKey},
    );
  }

  Uri _geminiGenerateEndpoint(Uri baseUri, String model, String apiKey) {
    final modelName = model.startsWith('models/') ? model : 'models/$model';
    return baseUri.replace(
      path: _joinPath(baseUri.path, '$modelName:generateContent'),
      queryParameters: <String, String>{'key': apiKey},
    );
  }

  Uri? _geminiAlternativeBaseUri(Uri baseUri) {
    var path = baseUri.path;
    if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.endsWith('/v1beta')) {
      return baseUri.replace(
        path: '${path.substring(0, path.length - '/v1beta'.length)}/v1',
      );
    }
    if (path.endsWith('/v1')) {
      return baseUri.replace(
        path: '${path.substring(0, path.length - '/v1'.length)}/v1beta',
      );
    }
    return null;
  }

  String _joinPath(String basePath, String suffix) {
    final normalizedBase = basePath.endsWith('/')
        ? basePath.substring(0, basePath.length - 1)
        : basePath;
    final normalizedSuffix =
        suffix.startsWith('/') ? suffix.substring(1) : suffix;
    return '$normalizedBase/$normalizedSuffix';
  }

  static Uri _normalizeOpenAiBaseUri(
    String baseUrl, {
    required String defaultBase,
  }) {
    return _normalizeRequiredSuffix(
      baseUrl,
      defaultBase: defaultBase,
      requiredSuffix: '/v1',
    );
  }

  static Uri _normalizeGeminiBaseUri(
    String rawBaseUrl, {
    required String defaultBase,
  }) {
    final raw = rawBaseUrl.trim().isEmpty ? defaultBase : rawBaseUrl.trim();
    final parsed = Uri.parse(raw);
    var path = parsed.path;
    if (path.isEmpty || path == '/') {
      path = '/v1';
    } else {
      if (path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      final hasVersion = path.endsWith('/v1') || path.endsWith('/v1beta');
      if (!hasVersion) {
        path = '$path/v1';
      }
    }
    return parsed.replace(path: path);
  }

  static Uri _normalizeRequiredSuffix(
    String rawBaseUrl, {
    required String defaultBase,
    required String requiredSuffix,
  }) {
    final raw = rawBaseUrl.trim().isEmpty ? defaultBase : rawBaseUrl.trim();
    final parsed = Uri.parse(raw);
    var path = parsed.path;
    if (path.isEmpty || path == '/') {
      path = requiredSuffix;
    } else {
      if (path.endsWith('/')) {
        path = path.substring(0, path.length - 1);
      }
      if (!path.endsWith(requiredSuffix)) {
        path = '$path$requiredSuffix';
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
    debugPrint('[Sensei LLM] Request failed (${_currentProvider.label}): $error');
    await checkHealth(force: true);
  }

  Future<void> _hydrateApiKeysFromStorage() async {
    for (final provider in LlmProvider.values) {
      if (!provider.requiresApiKey) {
        continue;
      }
      final config = _providerConfigs[provider];
      if (config == null) {
        continue;
      }

      try {
        final storedKey = await _secureStorage.read(
          key: _apiKeyStorageKey(provider),
        );
        final sanitized = storedKey?.trim() ?? '';
        if (sanitized.isNotEmpty) {
          config.apiKey = sanitized;
        }
      } catch (e) {
        debugPrint(
          '[Sensei LLM] Failed to read stored API key for ${provider.label}: $e',
        );
      }
    }
  }

  Future<void> _hydrateModelsFromStorage() async {
    for (final provider in LlmProvider.values) {
      final config = _providerConfigs[provider];
      if (config == null) {
        continue;
      }

      try {
        final storedModel = await _secureStorage.read(
          key: _modelStorageKey(provider),
        );
        final sanitized = storedModel?.trim() ?? '';
        if (sanitized.isNotEmpty) {
          config.configuredModel = sanitized;
        }
      } catch (e) {
        debugPrint(
          '[Sensei LLM] Failed to read stored model for ${provider.label}: $e',
        );
      }
    }
  }

  String _apiKeyStorageKey(LlmProvider provider) {
    return '$_apiKeyStoragePrefix${provider.id}';
  }

  String _modelStorageKey(LlmProvider provider) {
    return '$_modelStoragePrefix${provider.id}';
  }

  String _buildExtractionPrompt(String input, LlmParsingContext context) {
    final contextBlock = _buildContextBlock(context);
    return '''Extract structured data from this input.
Return ONLY valid JSON with keys:
- subject_name (string or null)
- attribute_key (snake_case string or null)
- attribute_value (string or null)
- is_query (boolean)
- confidence (number 0..1)

$contextBlock
Input: "$input"''';
  }

  String _buildContextBlock(LlmParsingContext context) {
    if (!context.hasAnyHints) {
      return 'Context: none';
    }

    final lines = <String>['Context:'];
    final userProfile = context.userProfileSummary?.trim();
    if (userProfile != null && userProfile.isNotEmpty) {
      lines.add('- user_profile: $userProfile');
    }
    final uriHint = context.parserSubjectUriHint?.trim();
    if (uriHint != null && uriHint.isNotEmpty) {
      lines.add('- parser_subject_uri_hint: $uriHint');
    }
    if (context.recentTargetUris.isNotEmpty) {
      lines.add('- recent_target_uris: ${context.recentTargetUris.take(5).join(', ')}');
    }
    if (context.hintAttributes.isNotEmpty) {
      lines.add('- known_attribute_keys: ${context.hintAttributes.take(8).join(', ')}');
    }
    if (context.recentSummonings.isNotEmpty) {
      final cleaned = context.recentSummonings
          .take(3)
          .map((s) => _truncate(s.replaceAll('\n', ' '), 120))
          .join(' | ');
      lines.add('- recent_summonings: $cleaned');
    }
    return lines.join('\n');
  }

  static String _truncate(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }

  static const _senseiCorePrompt = '''You are the Sensei for ROLODOJO.
You operate as a structured ledger assistant.
Rules:
- Use only information present in the input/context.
- Preserve exact values for facts.
- Attribute keys must be snake_case.
- Dojo URIs follow dojo.<category>.<identifier>.
- Valid categories include con (contact), ent (entity), med (medical), sys (system).
- Return strict machine-readable output when requested.''';

  static const _extractionSystemPrompt = '''Extract subject, attribute key/value, and query intent.
If extraction is uncertain, lower confidence and keep fields null.''';

  static const _synthesisSystemPrompt =
      'Generate one concise, factual insight from provided ledger facts.';

  static const _qaSystemPrompt = '''You are Sensei answering vault-grounded questions.
Rules:
- Treat the vault context as your only source of truth.
- Do not invent facts not present in the context.
- If information is missing, explicitly say it is not found in the vault.
- Keep answers direct and practical.''';

  static const _contextAnswerSystemPrompt =
      'Answer the prompt grounded in the provided context only. '
      'If context is insufficient, say so clearly.';

  static const _summarySystemPrompt =
      'Summarize briefly without adding unverified details.';

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

  String _buildVaultQaPrompt({
    required String question,
    required String vaultContext,
    String? userProfileSummary,
  }) {
    final profile = userProfileSummary?.trim();
    final profileLine = (profile == null || profile.isEmpty)
        ? 'User profile: unavailable'
        : 'User profile: $profile';
    final contextBlock = vaultContext.isEmpty
        ? 'Vault context:\n- No matching vault facts were found.'
        : 'Vault context:\n$vaultContext';

    return '$profileLine\n\n'
        '$contextBlock\n\n'
        'Question: "$question"\n\n'
        'Instructions:\n'
        '- Answer using vault context only.\n'
        '- If the answer is missing, explicitly say it is not in the vault.\n'
        '- Cite key facts from the vault context in plain text.\n'
        '- Be concise and useful.';
  }

  String _ruleBasedSummary(String text, int maxLength) {
    final firstSentence = text.split(RegExp(r'[.!?]')).first.trim();
    if (firstSentence.length <= maxLength) {
      return firstSentence;
    }
    return '${firstSentence.substring(0, maxLength - 3)}...';
  }

  String _ruleBasedVaultAnswer(String question, String vaultContext) {
    if (vaultContext.isEmpty ||
        vaultContext.toLowerCase().contains('no matching vault facts')) {
      return 'I could not find that in the vault yet. '
          'Try adding the fact first, then ask again.';
    }

    final lines = vaultContext
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && line.startsWith('-'))
        .take(4)
        .toList(growable: false);
    if (lines.isEmpty) {
      return 'I found related vault entries, but not enough structure to answer '
          'that confidently. Please ask with a specific name or attribute.';
    }

    final facts = lines.join('\n');
    return 'Here is what I found in your vault relevant to "$question":\n$facts';
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

  /// Enhanced rule-based extraction fallback.
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

  /// Rule-based synthesis fallback.
  String _ruleBasedSynthesis(
    String subjectUri,
    Map<String, String> facts,
    List<String> recentRolos,
  ) {
    if (facts.isEmpty) return '';

    final parts = <String>[];

    if (facts.length >= 3) {
      parts.add(
        '${subjectUri.split('.').last} has ${facts.length} known attributes',
      );
    }

    for (final entry in facts.entries) {
      if (entry.key.contains('birthday') || entry.key.contains('anniversary')) {
        parts.add('Note: ${entry.key} is ${entry.value}');
      }
    }

    if (recentRolos.length >= 2) {
      parts.add('Active recently with ${recentRolos.length} interactions');
    }

    return parts.isEmpty ? 'No new insights detected' : parts.join('. ');
  }
}

class _ProviderConfig {
  final Uri baseUri;
  String configuredModel;
  final String defaultConfiguredModel;
  String apiKey;
  final List<String> fallbackModels;

  _ProviderConfig({
    required this.baseUri,
    required this.configuredModel,
    required this.defaultConfiguredModel,
    required this.apiKey,
    this.fallbackModels = const [],
  });

  bool get hasApiKey => apiKey.trim().isNotEmpty;
}
