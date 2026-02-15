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
  Future<Database> openEncryptedDatabase(String path, {int version = 1}) async {
    final password = await getMasterKey();
    
    return await openDatabase(
      path,
      password: password,
      version: version,
      onCreate: (db, version) async {
        // This is where Claude Code will build the Rockstone Schema
        await _initializeSchema(db);
      },
    );
  }

  static Future<void> _initializeSchema(Database db) async {
    // Enable foreign key enforcement for SQLite
    await db.execute('PRAGMA foreign_keys = ON');

    // Initializing the 3 Pillars of the Rockstone Schema

    // tbl_rolos - The Ledger (immutable history)
    await db.execute('''
      CREATE TABLE tbl_rolos (
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

    // Indexes for tbl_rolos
    await db.execute(
      'CREATE INDEX idx_rolos_target_uri ON tbl_rolos(target_uri)',
    );
    await db.execute(
      'CREATE INDEX idx_rolos_timestamp ON tbl_rolos(timestamp DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_rolos_parent ON tbl_rolos(parent_rolo_id)',
    );

    // tbl_records - The Master Scroll (current state of truth)
    await db.execute('''
      CREATE TABLE tbl_records (
        uri TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        payload TEXT,
        last_rolo_id TEXT,
        updated_at TEXT,
        FOREIGN KEY (last_rolo_id) REFERENCES tbl_rolos(rolo_id)
          ON DELETE SET NULL
      )
    ''');

    // Index for tbl_records
    await db.execute(
      'CREATE INDEX idx_records_display_name ON tbl_records(display_name)',
    );

    // tbl_attributes - The Vault (flexible key-value storage)
    await db.execute('''
      CREATE TABLE tbl_attributes (
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

    // Indexes for tbl_attributes
    await db.execute(
      'CREATE INDEX idx_attributes_key ON tbl_attributes(attr_key)',
    );
  }
}
