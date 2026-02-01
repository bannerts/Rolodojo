import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:io';
import 'package:rolodojo/core/security_service.dart'; // Path assumes Clean Arch

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('System Integrity & Security Gauntlet', () {
    const String testDbName = 'sensei_vault_test.db';
    const String testKey = 'bushido_password_2026';

    testWidgets('Verification: Database is encrypted and unreadable as plaintext', (WidgetTester tester) async {
      // 1. Setup: Create an encrypted database
      final dbPath = await getDatabasesPath();
      final path = "$dbPath/$testDbName";
      
      // Delete old test db if exists
      if (await File(path).exists()) await deleteDatabase(path);

      final db = await openDatabase(
        path,
        password: testKey,
        onCreate: (db, version) {
          return db.execute('CREATE TABLE tbl_secrets (id INTEGER PRIMARY KEY, secret_text TEXT)');
        },
        version: 1,
      );

      // 2. Insert sensitive data
      await db.insert('tbl_secrets', {'secret_text': 'CONFIDENTIAL_DOJO_DATA'});
      await db.close();

      // 3. The "Brute Force" Plaintext Check
      // We read the raw bytes of the file and search for the string "CONFIDENTIAL_DOJO_DATA"
      final File file = File(path);
      final List<int> bytes = await file.readAsBytes();
      final String rawContent = String.fromCharCodes(bytes);

      expect(
        rawContent.contains('CONFIDENTIAL_DOJO_DATA'), 
        isFalse,
        reason: 'SECURITY BREACH: Sensitive data was found in plaintext. SQLCipher is not active!'
      );
      
      print('✅ Cipher Check Passed: Raw database file is unreadable.');
    });

    testWidgets('Verification: Soft-Delete & Audit Trail Integrity', (WidgetTester tester) async {
      // Setup DB with key
      final dbPath = await getDatabasesPath();
      final path = "$dbPath/$testDbName";
      final db = await openDatabase(path, password: testKey);

      // 1. Create a "Rolo" audit link
      final String auditRoloId = 'rolo_123_delete_event';

      // 2. Insert an attribute
      await db.execute('CREATE TABLE IF NOT EXISTS tbl_attributes (key TEXT, value TEXT, last_rolo_id TEXT)');
      await db.insert('tbl_attributes', {
        'key': 'gate_code',
        'value': '5555',
        'last_rolo_id': 'rolo_001_init'
      });

      // 3. Execute Soft-Delete (The Sensei Way)
      await db.update(
        'tbl_attributes',
        {'value': null, 'last_rolo_id': auditRoloId},
        where: 'key = ?',
        whereArgs: ['gate_code'],
      );

      // 4. Verify the record still exists but value is null
      final List<Map<String, dynamic>> result = await db.query(
        'tbl_attributes',
        where: 'key = ?',
        whereArgs: ['gate_code'],
      );

      expect(result.first['value'], isNull);
      expect(result.first['last_rolo_id'], auditRoloId);
      
      await db.close();
      print('✅ Audit Check Passed: Soft-delete maintained history integrity.');
    });
  });
}
