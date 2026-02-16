import 'dart:convert';

import '../../domain/entities/user_profile.dart';

/// Data model for `tbl_user` rows.
class UserProfileModel extends UserProfile {
  const UserProfileModel({
    required super.userId,
    required super.displayName,
    super.preferredName,
    super.profile,
    required super.createdAt,
    required super.updatedAt,
  });

  factory UserProfileModel.fromEntity(UserProfile profile) {
    return UserProfileModel(
      userId: profile.userId,
      displayName: profile.displayName,
      preferredName: profile.preferredName,
      profile: profile.profile,
      createdAt: profile.createdAt,
      updatedAt: profile.updatedAt,
    );
  }

  factory UserProfileModel.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> payload = const {};
    final profileJson = map['profile_json'] as String?;
    if (profileJson != null && profileJson.isNotEmpty) {
      try {
        final parsed = jsonDecode(profileJson);
        if (parsed is Map<String, dynamic>) {
          payload = parsed;
        }
      } catch (_) {
        payload = const {};
      }
    }

    return UserProfileModel(
      userId: map['user_id'] as String,
      displayName: map['display_name'] as String? ?? 'Dojo User',
      preferredName: map['preferred_name'] as String?,
      profile: payload,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'display_name': displayName,
      'preferred_name': preferredName,
      'profile_json': jsonEncode(profile),
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  UserProfile toEntity() {
    return UserProfile(
      userId: userId,
      displayName: displayName,
      preferredName: preferredName,
      profile: profile,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
