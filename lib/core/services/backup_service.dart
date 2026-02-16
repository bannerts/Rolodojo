import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import '../../data/models/attribute_model.dart';
import '../../data/models/record_model.dart';
import '../../data/models/rolo_model.dart';
import '../../domain/entities/attribute.dart';
import '../../domain/entities/record.dart';
import '../../domain/entities/rolo.dart';
import '../../domain/repositories/attribute_repository.dart';
import '../../domain/repositories/record_repository.dart';
import '../../domain/repositories/rolo_repository.dart';
import 'security_service.dart';

/// Metadata about a backup file.
class BackupMetadata {
  /// Version of the backup format.
  final String version;

  /// When the backup was created.
  final DateTime createdAt;

  /// Device identifier that created the backup.
  final String? deviceId;

  /// Number of Rolos in the backup.
  final int roloCount;

  /// Number of Records in the backup.
  final int recordCount;

  /// Number of Attributes in the backup.
  final int attributeCount;

  const BackupMetadata({
    required this.version,
    required this.createdAt,
    this.deviceId,
    required this.roloCount,
    required this.recordCount,
    required this.attributeCount,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'created_at': createdAt.toUtc().toIso8601String(),
      'device_id': deviceId,
      'rolo_count': roloCount,
      'record_count': recordCount,
      'attribute_count': attributeCount,
    };
  }

  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    return BackupMetadata(
      version: json['version'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      deviceId: json['device_id'] as String?,
      roloCount: json['rolo_count'] as int,
      recordCount: json['record_count'] as int,
      attributeCount: json['attribute_count'] as int,
    );
  }

  /// Total number of items in the backup.
  int get totalItems => roloCount + recordCount + attributeCount;
}

/// Result of a backup operation.
class BackupResult {
  /// Whether the operation succeeded.
  final bool success;

  /// Path to the backup file (for export).
  final String? filePath;

  /// Metadata about the backup.
  final BackupMetadata? metadata;

  /// Error message if failed.
  final String? error;

  const BackupResult({
    required this.success,
    this.filePath,
    this.metadata,
    this.error,
  });

  factory BackupResult.success({
    required String filePath,
    required BackupMetadata metadata,
  }) {
    return BackupResult(
      success: true,
      filePath: filePath,
      metadata: metadata,
    );
  }

  factory BackupResult.failure(String error) {
    return BackupResult(
      success: false,
      error: error,
    );
  }
}

/// Result of a restore operation.
class RestoreResult {
  /// Whether the operation succeeded.
  final bool success;

  /// Number of items restored.
  final int itemsRestored;

  /// Metadata from the restored backup.
  final BackupMetadata? metadata;

  /// Error message if failed.
  final String? error;

  const RestoreResult({
    required this.success,
    this.itemsRestored = 0,
    this.metadata,
    this.error,
  });

  factory RestoreResult.success({
    required int itemsRestored,
    required BackupMetadata metadata,
  }) {
    return RestoreResult(
      success: true,
      itemsRestored: itemsRestored,
      metadata: metadata,
    );
  }

  factory RestoreResult.failure(String error) {
    return RestoreResult(
      success: false,
      error: error,
    );
  }
}

/// The Backup Service handles encrypted export/import of Dojo data.
///
/// From ROLODOJO_SECURITY.md:
/// "Encrypted Export: Backups are exported as a single encrypted .dojo file."
///
/// The backup format is a JSON structure containing all Rolos, Records,
/// and Attributes. The file is encrypted using the master key from
/// flutter_secure_storage.
class BackupService {
  static const String _backupVersion = '1.0';
  static const String _fileExtension = '.dojo';

  final RoloRepository _roloRepository;
  final RecordRepository _recordRepository;
  final AttributeRepository _attributeRepository;
  final SecurityService _securityService;

  BackupService({
    required RoloRepository roloRepository,
    required RecordRepository recordRepository,
    required AttributeRepository attributeRepository,
    SecurityService? securityService,
  })  : _roloRepository = roloRepository,
        _recordRepository = recordRepository,
        _attributeRepository = attributeRepository,
        _securityService = securityService ?? SecurityService();

  /// Exports all Dojo data to an encrypted .dojo file.
  ///
  /// [directory] - The directory to save the backup file.
  /// [filename] - Optional custom filename (default: rolodojo_YYYYMMDD_HHMMSS)
  Future<BackupResult> exportBackup({
    required String directory,
    String? filename,
  }) async {
    try {
      // Collect all data
      final rolos = await _roloRepository.getRecent(limit: 100000);
      final records = await _recordRepository.getAll();
      final attributes = await _collectAllAttributes(records);

      // Create backup structure
      final backupData = {
        'metadata': BackupMetadata(
          version: _backupVersion,
          createdAt: DateTime.now().toUtc(),
          roloCount: rolos.length,
          recordCount: records.length,
          attributeCount: attributes.length,
        ).toJson(),
        'rolos': rolos.map((r) => RoloModel.fromEntity(r).toMap()).toList(),
        'records': records.map((r) => RecordModel.fromEntity(r).toMap()).toList(),
        'attributes':
            attributes.map((a) => AttributeModel.fromEntity(a).toMap()).toList(),
      };

      // Convert to JSON
      final jsonData = jsonEncode(backupData);

      // Generate filename
      final now = DateTime.now();
      final defaultFilename =
          'rolodojo_${now.year}${_pad(now.month)}${_pad(now.day)}_'
          '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
      final finalFilename = filename ?? defaultFilename;

      // Write to encrypted file using the master key
      final filePath = path.join(directory, '$finalFilename$_fileExtension');
      final file = File(filePath);

      // Encrypt using AES-256 derived from the master key
      final encryptedData = await _encrypt(jsonData);
      await file.writeAsBytes(encryptedData);

      return BackupResult.success(
        filePath: filePath,
        metadata: BackupMetadata.fromJson(backupData['metadata'] as Map<String, dynamic>),
      );
    } catch (e) {
      return BackupResult.failure('Export failed: $e');
    }
  }

  /// Imports data from an encrypted .dojo file.
  ///
  /// [filePath] - Path to the .dojo file.
  /// [merge] - If true, merges with existing data. If false, replaces all data.
  Future<RestoreResult> importBackup({
    required String filePath,
    bool merge = true,
  }) async {
    try {
      // Read file
      final file = File(filePath);
      if (!await file.exists()) {
        return RestoreResult.failure('File not found: $filePath');
      }

      // Decrypt file contents using the master key
      final encryptedData = await file.readAsBytes();
      final jsonData = await _decrypt(encryptedData);
      final backupData = jsonDecode(jsonData) as Map<String, dynamic>;

      // Validate backup version
      final metadata =
          BackupMetadata.fromJson(backupData['metadata'] as Map<String, dynamic>);
      if (!_isVersionCompatible(metadata.version)) {
        return RestoreResult.failure(
          'Incompatible backup version: ${metadata.version}',
        );
      }

      var itemsRestored = 0;

      // Restore Rolos
      final rolosData = backupData['rolos'] as List<dynamic>;
      for (final roloMap in rolosData) {
        final rolo = RoloModel.fromMap(roloMap as Map<String, dynamic>);
        try {
          final existing = await _roloRepository.getById(rolo.id);
          if (existing == null || !merge) {
            await _roloRepository.create(rolo.toEntity());
            itemsRestored++;
          }
        } catch (_) {
          // Skip if already exists and merge is true
        }
      }

      // Restore Records
      final recordsData = backupData['records'] as List<dynamic>;
      for (final recordMap in recordsData) {
        final record = RecordModel.fromMap(recordMap as Map<String, dynamic>);
        try {
          await _recordRepository.upsert(record.toEntity());
          itemsRestored++;
        } catch (_) {
          // Skip on error
        }
      }

      // Restore Attributes
      final attributesData = backupData['attributes'] as List<dynamic>;
      for (final attrMap in attributesData) {
        final attr = AttributeModel.fromMap(attrMap as Map<String, dynamic>);
        try {
          await _attributeRepository.upsert(attr.toEntity());
          itemsRestored++;
        } catch (_) {
          // Skip on error
        }
      }

      return RestoreResult.success(
        itemsRestored: itemsRestored,
        metadata: metadata,
      );
    } catch (e) {
      return RestoreResult.failure('Import failed: $e');
    }
  }

  /// Reads metadata from a backup file without importing.
  Future<BackupMetadata?> readBackupMetadata(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final encryptedData = await file.readAsBytes();
      final jsonData = await _decrypt(encryptedData);
      final backupData = jsonDecode(jsonData) as Map<String, dynamic>;

      return BackupMetadata.fromJson(
        backupData['metadata'] as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  /// Collects all attributes from all records.
  Future<List<Attribute>> _collectAllAttributes(List<Record> records) async {
    final attributes = <Attribute>[];
    for (final record in records) {
      final recordAttrs = await _attributeRepository.getByUri(
        record.uri,
        includeDeleted: true,
      );
      attributes.addAll(recordAttrs);
    }
    return attributes;
  }

  bool _isVersionCompatible(String version) {
    // For now, only accept version 1.x
    return version.startsWith('1.');
  }

  String _pad(int value) => value.toString().padLeft(2, '0');

  /// Generates a default backup filename.
  String generateFilename() {
    final now = DateTime.now();
    return 'rolodojo_${now.year}${_pad(now.month)}${_pad(now.day)}_'
        '${_pad(now.hour)}${_pad(now.minute)}${_pad(now.second)}';
  }

  /// Encrypts plaintext using AES-256-CBC derived from the master key.
  ///
  /// Format: [16-byte IV][AES-256-CBC encrypted data]
  /// The master key from Secure Storage is derived into a 32-byte AES key.
  Future<Uint8List> _encrypt(String plaintext) async {
    final masterKey = await _securityService.getMasterKey();
    final key = crypto.Key(Uint8List.fromList(
      _deriveKey(utf8.encode(masterKey)),
    ));
    final iv = crypto.IV.fromSecureRandom(16);

    final encrypter = crypto.Encrypter(crypto.AES(key, mode: crypto.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(utf8.encode(plaintext), iv: iv);

    // Prepend IV to encrypted data
    final result = Uint8List(16 + encrypted.bytes.length);
    result.setRange(0, 16, iv.bytes);
    result.setRange(16, result.length, encrypted.bytes);
    return result;
  }

  /// Decrypts data encrypted by [_encrypt].
  Future<String> _decrypt(Uint8List encryptedData) async {
    if (encryptedData.length < 17) {
      throw const FormatException('Invalid encrypted data: too short');
    }

    final masterKey = await _securityService.getMasterKey();
    final key = crypto.Key(Uint8List.fromList(
      _deriveKey(utf8.encode(masterKey)),
    ));
    final iv = crypto.IV(encryptedData.sublist(0, 16));
    final ciphertext = encryptedData.sublist(16);

    final encrypter = crypto.Encrypter(crypto.AES(key, mode: crypto.AESMode.cbc));
    final decrypted = encrypter.decryptBytes(crypto.Encrypted(ciphertext), iv: iv);
    return utf8.decode(decrypted);
  }

  /// Derives a 32-byte AES key from the master key bytes.
  ///
  /// Uses a simple but deterministic key derivation to produce
  /// a 32-byte key suitable for AES-256.
  List<int> _deriveKey(List<int> keyBytes) {
    final derived = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      derived[i] = keyBytes[i % keyBytes.length];
      derived[i] ^= keyBytes[(i * 7 + 13) % keyBytes.length];
      derived[i] = (derived[i] + i) & 0xFF;
    }
    return derived;
  }
}
