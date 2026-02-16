import 'package:flutter/material.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart' as path;
import '../data/datasources/local_data_source.dart';
import '../data/repositories/rolo_repository_impl.dart';
import '../data/repositories/record_repository_impl.dart';
import '../data/repositories/attribute_repository_impl.dart';
import '../data/repositories/journal_repository_impl.dart';
import '../data/repositories/sensei_repository_impl.dart';
import '../data/repositories/user_repository_impl.dart';
import '../domain/repositories/rolo_repository.dart';
import '../domain/repositories/record_repository.dart';
import '../domain/repositories/attribute_repository.dart';
import '../domain/repositories/journal_repository.dart';
import '../domain/repositories/sensei_repository.dart';
import '../domain/repositories/user_repository.dart';
import '../domain/entities/user_profile.dart';
import 'services/security_service.dart';
import 'services/dojo_service.dart';
import 'services/librarian_service.dart';
import 'services/location_service.dart';
import 'services/backup_service.dart';
import 'services/sensei_llm_service.dart';
import 'services/synthesis_service.dart';

/// Provides initialized Dojo services to the widget tree.
///
/// All services are wired to the encrypted SQLCipher database
/// through the repository layer. The Sensei LLM is initialized
/// in local-first mode with optional provider switching.
class DojoProvider extends InheritedWidget {
  final DojoService dojoService;
  final LibrarianService librarianService;
  final BackupService backupService;
  final SenseiLlmService senseiLlm;
  final SynthesisService synthesisService;
  final RoloRepository roloRepository;
  final RecordRepository recordRepository;
  final AttributeRepository attributeRepository;
  final JournalRepository journalRepository;
  final UserRepository userRepository;
  final SenseiRepository senseiRepository;

  const DojoProvider({
    required this.dojoService,
    required this.librarianService,
    required this.backupService,
    required this.senseiLlm,
    required this.synthesisService,
    required this.roloRepository,
    required this.recordRepository,
    required this.attributeRepository,
    required this.journalRepository,
    required this.userRepository,
    required this.senseiRepository,
    required super.child,
    super.key,
  });

  static DojoProvider of(BuildContext context) {
    final provider =
        context.dependOnInheritedWidgetOfExactType<DojoProvider>();
    assert(provider != null, 'No DojoProvider found in widget tree');
    return provider!;
  }

  @override
  bool updateShouldNotify(DojoProvider oldWidget) => false;

  /// Opens the encrypted database, initializes the Sensei LLM,
  /// and creates all service instances.
  static Future<DojoProvider> initialize({required Widget child}) async {
    final securityService = SecurityService();
    final dbPath = await getDatabasesPath();
    final fullPath = path.join(dbPath, 'sensei_vault.db');
    final db = await securityService.openEncryptedDatabase(fullPath);

    final dataSource = LocalDataSource(db);

    final roloRepo = RoloRepositoryImpl(dataSource);
    final recordRepo = RecordRepositoryImpl(dataSource);
    final attributeRepo = AttributeRepositoryImpl(dataSource);
    final journalRepo = JournalRepositoryImpl(dataSource);
    final userRepo = UserRepositoryImpl(dataSource);
    final senseiRepo = SenseiRepositoryImpl(dataSource);
    final locationService = LocationService();

    final primaryUser = await userRepo.getPrimary();
    if (primaryUser == null) {
      final now = DateTime.now().toUtc();
      await userRepo.upsert(
        UserProfile(
          userId: UserProfile.primaryUserId,
          displayName: 'Dojo User',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    // Initialize LLM providers (local-first with optional online providers).
    const llmProviderRaw = String.fromEnvironment(
      'LLM_PROVIDER',
      defaultValue: 'llama',
    );
    const llmBaseUrl = String.fromEnvironment(
      'LLAMA_BASE_URL',
      defaultValue: 'http://localhost:11434/v1',
    );
    const llmModel = String.fromEnvironment(
      'LLAMA_MODEL',
      defaultValue: 'llama3.3',
    );
    const claudeBaseUrl = String.fromEnvironment(
      'CLAUDE_BASE_URL',
      defaultValue: 'https://api.anthropic.com/v1',
    );
    const claudeModel = String.fromEnvironment(
      'CLAUDE_MODEL',
      defaultValue: 'claude-3-5-sonnet-latest',
    );
    const claudeApiKey = String.fromEnvironment('CLAUDE_API_KEY');
    const grokBaseUrl = String.fromEnvironment(
      'GROK_BASE_URL',
      defaultValue: 'https://api.x.ai/v1',
    );
    const grokModel = String.fromEnvironment(
      'GROK_MODEL',
      defaultValue: 'grok-2-latest',
    );
    const grokApiKey = String.fromEnvironment('GROK_API_KEY');
    const geminiBaseUrl = String.fromEnvironment(
      'GEMINI_BASE_URL',
      defaultValue: 'https://generativelanguage.googleapis.com/v1beta',
    );
    const geminiModel = String.fromEnvironment(
      'GEMINI_MODEL',
      defaultValue: 'gemini-1.5-flash',
    );
    const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');
    const chatGptBaseUrl = String.fromEnvironment(
      'OPENAI_BASE_URL',
      defaultValue: 'https://api.openai.com/v1',
    );
    const chatGptModel = String.fromEnvironment(
      'OPENAI_MODEL',
      defaultValue: 'gpt-4o-mini',
    );
    const chatGptApiKey = String.fromEnvironment('OPENAI_API_KEY');
    final senseiLlm = LocalLlmService(
      initialProvider: LlmProvider.fromId(llmProviderRaw),
      localBaseUrl: llmBaseUrl,
      localModel: llmModel,
      claudeBaseUrl: claudeBaseUrl,
      claudeModel: claudeModel,
      claudeApiKey: claudeApiKey,
      grokBaseUrl: grokBaseUrl,
      grokModel: grokModel,
      grokApiKey: grokApiKey,
      geminiBaseUrl: geminiBaseUrl,
      geminiModel: geminiModel,
      geminiApiKey: geminiApiKey,
      chatGptBaseUrl: chatGptBaseUrl,
      chatGptModel: chatGptModel,
      chatGptApiKey: chatGptApiKey,
    );
    try {
      // modelPath is retained for interface compatibility.
      await senseiLlm.initialize(modelPath: 'ollama://local-server');
    } catch (e) {
      // LLM initialization is non-fatal; rule-based fallback is used.
      debugPrint('[Sensei] LLM init skipped: $e');
    }

    final dojoService = DojoService(
      roloRepository: roloRepo,
      recordRepository: recordRepo,
      attributeRepository: attributeRepo,
      senseiLlm: senseiLlm,
      senseiRepository: senseiRepo,
      journalRepository: journalRepo,
      userRepository: userRepo,
      locationService: locationService,
    );

    final librarianService = LibrarianService(
      roloRepository: roloRepo,
      recordRepository: recordRepo,
      attributeRepository: attributeRepo,
    );

    final backupService = BackupService(
      roloRepository: roloRepo,
      recordRepository: recordRepo,
      attributeRepository: attributeRepo,
      securityService: securityService,
    );

    final synthesisService = SynthesisService(
      roloRepository: roloRepo,
      recordRepository: recordRepo,
      attributeRepository: attributeRepo,
    );

    return DojoProvider(
      dojoService: dojoService,
      librarianService: librarianService,
      backupService: backupService,
      senseiLlm: senseiLlm,
      synthesisService: synthesisService,
      roloRepository: roloRepo,
      recordRepository: recordRepo,
      attributeRepository: attributeRepo,
      journalRepository: journalRepo,
      userRepository: userRepo,
      senseiRepository: senseiRepo,
      child: child,
    );
  }
}
