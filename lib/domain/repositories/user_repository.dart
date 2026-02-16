import '../entities/user_profile.dart';

/// Repository interface for app user profile (`tbl_user`) operations.
abstract class UserRepository {
  /// Creates or updates a user profile row.
  Future<UserProfile> upsert(UserProfile profile);

  /// Returns a profile by id, or null if it does not exist.
  Future<UserProfile?> getById(String userId);

  /// Returns the primary owner profile (single-user mode), if present.
  Future<UserProfile?> getPrimary();
}
