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
    // Initializing the 3 Pillars of the Rockstone Schema
    await db.execute('''
      CREATE TABLE tbl_rolos (
        rolo_id TEXT PRIMARY KEY,
        type TEXT,
        summoning_text TEXT,
        target_uri TEXT,
        metadata TEXT,
        timestamp TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE tbl_records (
        uri TEXT PRIMARY KEY,
        display_name TEXT,
        payload TEXT,
        last_rolo_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE tbl_attributes (
        subject_uri TEXT,
        attr_key TEXT,
        attr_value TEXT,
        last_rolo_id TEXT,
        is_encrypted INTEGER,
        PRIMARY KEY (subject_uri, attr_key)
      )
    ''');
  }
}
