import 'package:sqflite_sqlcipher/sqflite.dart';
import '../models/attribute_model.dart';
import '../models/journal_entry_model.dart';
import '../models/record_model.dart';
import '../models/rolo_model.dart';
import '../models/sensei_response_model.dart';
import '../models/user_profile_model.dart';

/// Local data source for database operations.
///
/// This is "The Scribe" - the mechanism that writes to the Rolo Ledger
/// and Attribute Vault using SQLCipher encryption.
class LocalDataSource {
  final Database _db;

  LocalDataSource(this._db);

  // ============================================================
  // ROLO OPERATIONS (tbl_rolos - The Ledger)
  // ============================================================

  /// Inserts a new Rolo into the ledger.
  Future<void> insertRolo(RoloModel rolo) async {
    await _db.insert(
      'tbl_rolos',
      rolo.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Retrieves a Rolo by its ID.
  Future<RoloModel?> getRoloById(String id) async {
    final results = await _db.query(
      'tbl_rolos',
      where: 'rolo_id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return RoloModel.fromMap(results.first);
  }

  /// Retrieves Rolos by target URI.
  Future<List<RoloModel>> getRolosByTargetUri(String uri) async {
    final results = await _db.query(
      'tbl_rolos',
      where: 'target_uri = ?',
      whereArgs: [uri],
      orderBy: 'timestamp DESC',
    );
    return results.map((r) => RoloModel.fromMap(r)).toList();
  }

  /// Retrieves child Rolos by parent ID.
  Future<List<RoloModel>> getRolosByParentId(String parentId) async {
    final results = await _db.query(
      'tbl_rolos',
      where: 'parent_rolo_id = ?',
      whereArgs: [parentId],
      orderBy: 'timestamp ASC',
    );
    return results.map((r) => RoloModel.fromMap(r)).toList();
  }

  /// Retrieves recent Rolos with pagination.
  Future<List<RoloModel>> getRecentRolos({int limit = 50, int offset = 0}) async {
    final results = await _db.query(
      'tbl_rolos',
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    return results.map((r) => RoloModel.fromMap(r)).toList();
  }

  /// Searches Rolos by summoning text.
  Future<List<RoloModel>> searchRolos(String query) async {
    final results = await _db.query(
      'tbl_rolos',
      where: 'summoning_text LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'timestamp DESC',
    );
    return results.map((r) => RoloModel.fromMap(r)).toList();
  }

  /// Updates an existing Rolo (Ghost optimization).
  Future<void> updateRolo(RoloModel rolo) async {
    await _db.update(
      'tbl_rolos',
      rolo.toMap(),
      where: 'rolo_id = ?',
      whereArgs: [rolo.id],
    );
  }

  /// Returns the total count of Rolos.
  Future<int> countRolos() async {
    final result = await _db.rawQuery('SELECT COUNT(*) as count FROM tbl_rolos');
    return result.first['count'] as int;
  }

  // ============================================================
  // RECORD OPERATIONS (tbl_records - The Master Scroll)
  // ============================================================

  /// Inserts or updates a Record.
  Future<void> upsertRecord(RecordModel record) async {
    await _db.insert(
      'tbl_records',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves a Record by its URI.
  Future<RecordModel?> getRecordByUri(String uri) async {
    final results = await _db.query(
      'tbl_records',
      where: 'uri = ?',
      whereArgs: [uri],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return RecordModel.fromMap(results.first);
  }

  /// Retrieves Records by category prefix.
  Future<List<RecordModel>> getRecordsByCategory(String categoryPrefix) async {
    final results = await _db.query(
      'tbl_records',
      where: 'uri LIKE ?',
      whereArgs: ['dojo.$categoryPrefix.%'],
      orderBy: 'display_name ASC',
    );
    return results.map((r) => RecordModel.fromMap(r)).toList();
  }

  /// Searches Records by display name.
  Future<List<RecordModel>> searchRecordsByName(String query) async {
    final results = await _db.query(
      'tbl_records',
      where: 'display_name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'display_name ASC',
    );
    return results.map((r) => RecordModel.fromMap(r)).toList();
  }

  /// Retrieves all Records with pagination.
  Future<List<RecordModel>> getAllRecords({int? limit, int? offset}) async {
    final results = await _db.query(
      'tbl_records',
      orderBy: 'display_name ASC',
      limit: limit,
      offset: offset,
    );
    return results.map((r) => RecordModel.fromMap(r)).toList();
  }

  /// Deletes a Record by URI.
  Future<void> deleteRecord(String uri) async {
    await _db.delete(
      'tbl_records',
      where: 'uri = ?',
      whereArgs: [uri],
    );
  }

  /// Checks if a Record exists.
  Future<bool> recordExists(String uri) async {
    final result = await _db.rawQuery(
      'SELECT 1 FROM tbl_records WHERE uri = ? LIMIT 1',
      [uri],
    );
    return result.isNotEmpty;
  }

  /// Returns the total count of Records.
  Future<int> countRecords() async {
    final result = await _db.rawQuery('SELECT COUNT(*) as count FROM tbl_records');
    return result.first['count'] as int;
  }

  /// Returns the count of Records by category.
  Future<int> countRecordsByCategory(String categoryPrefix) async {
    final result = await _db.rawQuery(
      'SELECT COUNT(*) as count FROM tbl_records WHERE uri LIKE ?',
      ['dojo.$categoryPrefix.%'],
    );
    return result.first['count'] as int;
  }

  // ============================================================
  // ATTRIBUTE OPERATIONS (tbl_attributes - The Vault)
  // ============================================================

  /// Inserts or updates an Attribute.
  Future<void> upsertAttribute(AttributeModel attribute) async {
    await _db.insert(
      'tbl_attributes',
      attribute.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves an Attribute by composite key.
  Future<AttributeModel?> getAttribute(String subjectUri, String key) async {
    final results = await _db.query(
      'tbl_attributes',
      where: 'subject_uri = ? AND attr_key = ?',
      whereArgs: [subjectUri, key],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return AttributeModel.fromMap(results.first);
  }

  /// Retrieves all Attributes for a URI.
  Future<List<AttributeModel>> getAttributesByUri(
    String subjectUri, {
    bool includeDeleted = false,
  }) async {
    String where = 'subject_uri = ?';
    if (!includeDeleted) {
      where += ' AND attr_value IS NOT NULL';
    }

    final results = await _db.query(
      'tbl_attributes',
      where: where,
      whereArgs: [subjectUri],
      orderBy: 'attr_key ASC',
    );
    return results.map((r) => AttributeModel.fromMap(r)).toList();
  }

  /// Soft-deletes an Attribute (sets value to NULL).
  Future<void> softDeleteAttribute(
    String subjectUri,
    String key,
    String deletionRoloId,
  ) async {
    await _db.update(
      'tbl_attributes',
      {
        'attr_value': null,
        'last_rolo_id': deletionRoloId,
      },
      where: 'subject_uri = ? AND attr_key = ?',
      whereArgs: [subjectUri, key],
    );
  }

  /// Searches Attributes by key or value.
  Future<List<AttributeModel>> searchAttributes(String query) async {
    final results = await _db.query(
      'tbl_attributes',
      where: 'attr_key LIKE ? OR attr_value LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'subject_uri ASC',
    );
    return results.map((r) => AttributeModel.fromMap(r)).toList();
  }

  /// Retrieves all Attributes with a specific key.
  Future<List<AttributeModel>> getAttributesByKey(String key) async {
    final results = await _db.query(
      'tbl_attributes',
      where: 'attr_key = ? AND attr_value IS NOT NULL',
      whereArgs: [key],
      orderBy: 'subject_uri ASC',
    );
    return results.map((r) => AttributeModel.fromMap(r)).toList();
  }

  /// Hard-deletes all Attributes for a URI.
  Future<void> deleteAttributesByUri(String subjectUri) async {
    await _db.delete(
      'tbl_attributes',
      where: 'subject_uri = ?',
      whereArgs: [subjectUri],
    );
  }

  /// Retrieves attribute history by joining with Rolos.
  ///
  /// Note: This queries the Rolo ledger to reconstruct history.
  Future<List<Map<String, dynamic>>> getAttributeHistory(
    String subjectUri,
    String key,
  ) async {
    // Get the current attribute
    final attr = await getAttribute(subjectUri, key);
    if (attr == null) return [];

    // Get all Rolos that targeted this URI and mentioned this key
    final results = await _db.rawQuery('''
      SELECT r.rolo_id, r.summoning_text, r.timestamp
      FROM tbl_rolos r
      WHERE r.target_uri = ?
        AND r.summoning_text LIKE ?
      ORDER BY r.timestamp DESC
    ''', [subjectUri, '%$key%']);

    return results;
  }

  // ============================================================
  // USER OPERATIONS (tbl_user - Owner Profile)
  // ============================================================

  /// Inserts or updates a user profile row.
  Future<void> upsertUserProfile(UserProfileModel profile) async {
    await _db.insert(
      'tbl_user',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves a user profile by id.
  Future<UserProfileModel?> getUserProfileById(String userId) async {
    final results = await _db.query(
      'tbl_user',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (results.isEmpty) return null;
    return UserProfileModel.fromMap(results.first);
  }

  /// Retrieves the most recently updated user profile.
  Future<UserProfileModel?> getPrimaryUserProfile() async {
    final results = await _db.query(
      'tbl_user',
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (results.isEmpty) return null;
    return UserProfileModel.fromMap(results.first);
  }

  // ============================================================
  // SENSEI RESPONSE OPERATIONS (tbl_sensei - Assistant Outputs)
  // ============================================================

  /// Inserts a new Sensei response row.
  Future<void> insertSenseiResponse(SenseiResponseModel response) async {
    await _db.insert(
      'tbl_sensei',
      response.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Retrieves responses generated for a specific input rolo.
  Future<List<SenseiResponseModel>> getSenseiResponsesByInputRolo(
    String inputRoloId,
  ) async {
    final results = await _db.query(
      'tbl_sensei',
      where: 'input_rolo_id = ?',
      whereArgs: [inputRoloId],
      orderBy: 'created_at DESC',
    );
    return results.map((r) => SenseiResponseModel.fromMap(r)).toList();
  }

  /// Retrieves recent Sensei responses with pagination.
  Future<List<SenseiResponseModel>> getRecentSenseiResponses({
    int limit = 50,
    int offset = 0,
  }) async {
    final results = await _db.query(
      'tbl_sensei',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return results.map((r) => SenseiResponseModel.fromMap(r)).toList();
  }

  // ============================================================
  // JOURNAL OPERATIONS (tbl_journal - Journal Mode Ledger)
  // ============================================================

  /// Inserts a new journal row.
  Future<void> insertJournalEntry(JournalEntryModel entry) async {
    await _db.insert(
      'tbl_journal',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  /// Retrieves journal rows for a specific day key (YYYY-MM-DD).
  Future<List<JournalEntryModel>> getJournalEntriesByDate(
    String journalDate, {
    int limit = 200,
    int offset = 0,
  }) async {
    final results = await _db.query(
      'tbl_journal',
      where: 'journal_date = ?',
      whereArgs: [journalDate],
      orderBy: 'created_at ASC',
      limit: limit,
      offset: offset,
    );
    return results.map((r) => JournalEntryModel.fromMap(r)).toList();
  }

  /// Retrieves journal rows in an inclusive date range.
  Future<List<JournalEntryModel>> getJournalEntriesByDateRange(
    String startDate,
    String endDate, {
    int limit = 1000,
    int offset = 0,
  }) async {
    final results = await _db.query(
      'tbl_journal',
      where: 'journal_date >= ? AND journal_date <= ?',
      whereArgs: [startDate, endDate],
      orderBy: 'journal_date ASC, created_at ASC',
      limit: limit,
      offset: offset,
    );
    return results.map((r) => JournalEntryModel.fromMap(r)).toList();
  }

  /// Retrieves recent journal rows with pagination.
  Future<List<JournalEntryModel>> getRecentJournalEntries({
    int limit = 200,
    int offset = 0,
  }) async {
    final results = await _db.query(
      'tbl_journal',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return results.map((r) => JournalEntryModel.fromMap(r)).toList();
  }
}
