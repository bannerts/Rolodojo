import '../../domain/entities/dojo_uri.dart';

/// Utility functions for working with Dojo URIs.
class UriUtils {
  UriUtils._();

  /// Converts a display name to a valid URI identifier.
  ///
  /// Examples:
  /// - "Jane Doe" → "jane_doe"
  /// - "Joe's Coffee Shop" → "joes_coffee_shop"
  /// - "Railroad Land Gate" → "railroad_land_gate"
  static String nameToIdentifier(String displayName) {
    return displayName
        .toLowerCase()
        .replaceAll(RegExp(r"[''`]"), '') // Remove apostrophes
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_') // Replace non-alphanumeric
        .replaceAll(RegExp(r'_+'), '_') // Collapse multiple underscores
        .replaceAll(RegExp(r'^_|_$'), ''); // Trim leading/trailing underscores
  }

  /// Creates a contact URI from a display name.
  ///
  /// Example: "Jane Doe" → dojo.con.jane_doe
  static DojoUri contactFromName(String displayName) {
    return DojoUri(
      category: DojoCategory.contact,
      identifier: nameToIdentifier(displayName),
    );
  }

  /// Creates an entity URI from a display name.
  ///
  /// Example: "Railroad Gate" → dojo.ent.railroad_gate
  static DojoUri entityFromName(String displayName) {
    return DojoUri(
      category: DojoCategory.entity,
      identifier: nameToIdentifier(displayName),
    );
  }

  /// Creates a medical URI from a display name.
  ///
  /// Example: "Blood Pressure" → dojo.med.blood_pressure
  static DojoUri medicalFromName(String displayName) {
    return DojoUri(
      category: DojoCategory.medical,
      identifier: nameToIdentifier(displayName),
    );
  }

  /// Creates a system URI from a display name.
  ///
  /// Example: "Sync Log" → dojo.sys.sync_log
  static DojoUri systemFromName(String displayName) {
    return DojoUri(
      category: DojoCategory.system,
      identifier: nameToIdentifier(displayName),
    );
  }

  /// Checks if a string is a valid Dojo URI.
  static bool isValidUri(String uri) {
    return DojoUri.tryParse(uri) != null;
  }

  /// Extracts the category from a URI string without full parsing.
  /// Returns null if invalid.
  static DojoCategory? getCategoryFromString(String uri) {
    final segments = uri.toLowerCase().split('.');
    if (segments.length < 2 || segments[0] != 'dojo') return null;
    return DojoCategory.fromPrefix(segments[1]);
  }

  /// Checks if a URI belongs to a specific category.
  static bool isCategory(String uri, DojoCategory category) {
    return getCategoryFromString(uri) == category;
  }

  /// Checks if the URI represents a contact.
  static bool isContact(String uri) => isCategory(uri, DojoCategory.contact);

  /// Checks if the URI represents an entity.
  static bool isEntity(String uri) => isCategory(uri, DojoCategory.entity);

  /// Checks if the URI represents a medical record.
  static bool isMedical(String uri) => isCategory(uri, DojoCategory.medical);

  /// Checks if the URI represents a system record.
  static bool isSystem(String uri) => isCategory(uri, DojoCategory.system);
}
