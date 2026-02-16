import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/user_repository.dart';
import '../datasources/local_data_source.dart';
import '../models/user_profile_model.dart';

/// Implementation of UserRepository using local SQLCipher database.
class UserRepositoryImpl implements UserRepository {
  final LocalDataSource _dataSource;

  UserRepositoryImpl(this._dataSource);

  @override
  Future<UserProfile> upsert(UserProfile profile) async {
    final model = UserProfileModel.fromEntity(profile);
    await _dataSource.upsertUserProfile(model);
    return profile;
  }

  @override
  Future<UserProfile?> getById(String userId) async {
    final model = await _dataSource.getUserProfileById(userId);
    return model?.toEntity();
  }

  @override
  Future<UserProfile?> getPrimary() async {
    final model = await _dataSource.getPrimaryUserProfile();
    return model?.toEntity();
  }
}
