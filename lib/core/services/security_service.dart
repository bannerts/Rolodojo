import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';

class SecurityService {
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'rolo_dojo_master_key';
  
  /// Retrieves the existing master key or generates a new one on first boot.
  Future<String> getMasterKey() async {
    String? key = await _storage.read(key: _keyName);
    
    if (key == null) {
      // Generate a high-entropy random key
      key = const Uuid().v4() + const Uuid().v4(); 
      await _storage.write(key: _keyName, value: key);
    }
    
    return key;
  }

  /// Helper to open the database with SQLCipher encryption.
  Future<Database> openEncryptedDatabase(String path, {int version = 3}) async {
    final password = await getMasterKey();
    
    return await openDatabase(
      path,
      password: password,
      version: version,
      onCreate: (db, version) async {
        // This is where Claude Code will build the Rockstone Schema
        await _initializeSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _applyMigrations(db, oldVersion, newVersion);
      },
    );
  }

  static Future<void> _initializeSchema(Database db) async {
    // Enable foreign key enforcement for SQLite
    await db.execute('PRAGMA foreign_keys = ON');

    // Initializing the core Rockstone tables

    await _createRoloSchema(db);
    await _createRecordSchema(db);
    await _createAttributeSchema(db);
    await _createUserSchema(db);
    await _createSenseiSchema(db);
    await _createJournalSchema(db);
  }

  static Future<void> _applyMigrations(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await db.execute('PRAGMA foreign_keys = ON');

    if (oldVersion < 2) {
      await _createUserSchema(db);
      await _createSenseiSchema(db);
    }
    if (oldVersion < 3) {
      await _createJournalSchema(db);
    }
  }

  static Future<void> _createRoloSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tbl_rolos (
        rolo_id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        summoning_text TEXT,
        target_uri TEXT,
        parent_rolo_id TEXT,
        metadata TEXT,
        timestamp TEXT NOT NULL,
        FOREIGN KEY (parent_rolo_id) REFERENCES tbl_rolos(rolo_id)
          ON DELETE SET NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rolos_target_uri ON tbl_rolos(target_uri)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rolos_timestamp ON tbl_rolos(timestamp DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_rolos_parent ON tbl_rolos(parent_rolo_id)',
    );
  }

  static Future<void> _createRecordSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tbl_records (
        uri TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        payload TEXT,
        last_rolo_id TEXT,
        updated_at TEXT,
        FOREIGN KEY (last_rolo_id) REFERENCES tbl_rolos(rolo_id)
          ON DELETE SET NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_records_display_name ON tbl_records(display_name)',
    );
  }

  static Future<void> _createAttributeSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tbl_attributes (
        subject_uri TEXT NOT NULL,
        attr_key TEXT NOT NULL,
        attr_value TEXT,
        last_rolo_id TEXT,
        is_encrypted INTEGER DEFAULT 0,
        updated_at TEXT,
        PRIMARY KEY (subject_uri, attr_key),
        FOREIGN KEY (subject_uri) REFERENCES tbl_records(uri)
          ON DELETE CASCADE,
        FOREIGN KEY (last_rolo_id) REFERENCES tbl_rolos(rolo_id)
          ON DELETE SET NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_attributes_key ON tbl_attributes(attr_key)',
    );
  }

  static Future<void> _createUserSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tbl_user (
        user_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        preferred_name TEXT,
        profile_json TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_user_updated_at ON tbl_user(updated_at DESC)',
    );
  }

  static Future<void> _createSenseiSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tbl_sensei (
        sensei_id TEXT PRIMARY KEY,
        input_rolo_id TEXT NOT NULL,
        target_uri TEXT,
        response_text TEXT NOT NULL,
        provider TEXT,
        model TEXT,
        confidence_score REAL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (input_rolo_id) REFERENCES tbl_rolos(rolo_id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sensei_input_rolo ON tbl_sensei(input_rolo_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sensei_created_at ON tbl_sensei(created_at DESC)',
    );
  }

  static Future<void> _createJournalSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS tbl_journal (
        journal_id TEXT PRIMARY KEY,
        journal_date TEXT NOT NULL,
        role TEXT NOT NULL,
        entry_type TEXT NOT NULL,
        content TEXT NOT NULL,
        source_rolo_id TEXT,
        metadata TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (source_rolo_id) REFERENCES tbl_rolos(rolo_id)
          ON DELETE SET NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_journal_date_created ON tbl_journal(journal_date, created_at)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_journal_created_at ON tbl_journal(created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_journal_type ON tbl_journal(entry_type)',
    );
  }
}
