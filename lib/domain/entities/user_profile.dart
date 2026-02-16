/// A user profile stored separately from URI records.
///
/// This keeps owner identity/preferences in `tbl_user` rather than in
/// `tbl_records`, so personal profile settings have a dedicated table.
class UserProfile {
  static const primaryUserId = 'owner';

  /// Stable user identifier (single-user default: "owner").
  final String userId;

  /// Full display name of the user.
  final String displayName;

  /// Optional short/preferred name used by Sensei prompts.
  final String? preferredName;

  /// Flexible profile payload (timezone, locale, preferences, etc.).
  final Map<String, dynamic> profile;

  /// Timestamp of first profile creation.
  final DateTime createdAt;

  /// Timestamp of most recent update.
  final DateTime updatedAt;

  const UserProfile({
    required this.userId,
    required this.displayName,
    this.preferredName,
    this.profile = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  UserProfile copyWith({
    String? userId,
    String? displayName,
    Object? preferredName = _sentinel,
    Map<String, dynamic>? profile,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      preferredName: preferredName == _sentinel
          ? this.preferredName
          : preferredName as String?,
      profile: profile ?? this.profile,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String get senseiNameHint {
    final preferred = preferredName?.trim();
    if (preferred != null && preferred.isNotEmpty) {
      return preferred;
    }
    return displayName;
  }

  static const Object _sentinel = Object();
}
