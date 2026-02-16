import 'package:flutter/material.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart' as path;
import '../data/datasources/local_data_source.dart';
import '../data/repositories/rolo_repository_impl.dart';
import '../data/repositories/record_repository_impl.dart';
import '../data/repositories/attribute_repository_impl.dart';
import '../domain/repositories/rolo_repository.dart';
import '../domain/repositories/record_repository.dart';
import '../domain/repositories/attribute_repository.dart';
import 'services/security_service.dart';
import 'services/dojo_service.dart';
import 'services/librarian_service.dart';
import 'services/backup_service.dart';
import 'services/sensei_llm_service.dart';
import 'services/synthesis_service.dart';

/// Provides initialized Dojo services to the widget tree.
///
/// All services are wired to the encrypted SQLCipher database
/// through the repository layer. The local LLM is initialized
/// for on-device inference (Zero-Cloud policy).
class DojoProvider extends InheritedWidget {
  final DojoService dojoService;
  final LibrarianService librarianService;
  final BackupService backupService;
  final SenseiLlmService senseiLlm;
  final SynthesisService synthesisService;
  final RoloRepository roloRepository;
  final RecordRepository recordRepository;
  final AttributeRepository attributeRepository;

  const DojoProvider({
    required this.dojoService,
    required this.librarianService,
    required this.backupService,
    required this.senseiLlm,
    required this.synthesisService,
    required this.roloRepository,
    required this.recordRepository,
    required this.attributeRepository,
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

  /// Opens the encrypted database, initializes the local LLM,
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

    // Initialize local LLM server (Ollama/OpenAI-compatible endpoint).
    const llmBaseUrl = String.fromEnvironment(
      'LLAMA_BASE_URL',
      defaultValue: 'http://localhost:11434/v1',
    );
    const llmModel = String.fromEnvironment(
      'LLAMA_MODEL',
      defaultValue: 'llama3.3',
    );
    final senseiLlm = LocalLlmService(
      baseUrl: llmBaseUrl,
      modelName: llmModel,
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
      child: child,
    );
  }
}
