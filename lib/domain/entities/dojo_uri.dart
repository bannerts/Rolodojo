/// The category of a Dojo URI path.
///
/// Each category represents a distinct namespace in the Dojo:
/// - [contact]: People, family, and professional relations (`dojo.con.*`)
/// - [entity]: Physical places, businesses, or landmarks (`dojo.ent.*`)
/// - [medical]: Health logs, mood tracking, and symptoms (`dojo.med.*`)
/// - [system]: Internal app state, sync logs, and mastery levels (`dojo.sys.*`)
enum DojoCategory {
  contact('con'),
  entity('ent'),
  medical('med'),
  system('sys');

  final String prefix;
  const DojoCategory(this.prefix);

  static DojoCategory? fromPrefix(String prefix) {
    for (final category in DojoCategory.values) {
      if (category.prefix == prefix) return category;
    }
    return null;
  }
}

/// Represents a URI-addressable object in the Dojo.
///
/// All data objects are addressed using dot-notation URIs, enabling
/// "semantic drilling" by the Sensei. Examples:
/// - `dojo.con.jane_doe` - A contact named Jane Doe
/// - `dojo.ent.railroad_land_gate` - An entity representing a physical place
/// - `dojo.med.blood_pressure` - A medical tracking entry
/// - `dojo.sys.sync_log` - A system state record
class DojoUri {
  /// The root namespace (always 'dojo')
  static const String root = 'dojo';

  /// The category of this URI (con, ent, med, sys)
  final DojoCategory category;

  /// The unique identifier within the category (e.g., 'jane_doe')
  final String identifier;

  /// Optional sub-path for nested resources
  final List<String> subPath;

  const DojoUri._({
    required this.category,
    required this.identifier,
    this.subPath = const [],
  });

  /// Creates a DojoUri from its components.
  factory DojoUri({
    required DojoCategory category,
    required String identifier,
    List<String> subPath = const [],
  }) {
    if (identifier.isEmpty) {
      throw ArgumentError('Identifier cannot be empty');
    }
    if (!_isValidIdentifier(identifier)) {
      throw ArgumentError(
        'Identifier must be lowercase with underscores only: $identifier',
      );
    }
    for (final segment in subPath) {
      if (!_isValidIdentifier(segment)) {
        throw ArgumentError(
          'Sub-path segment must be lowercase with underscores only: $segment',
        );
      }
    }
    return DojoUri._(
      category: category,
      identifier: identifier,
      subPath: subPath,
    );
  }

  /// Parses a URI string into a DojoUri object.
  ///
  /// Returns null if the string is not a valid Dojo URI.
  /// Valid format: `dojo.<category>.<identifier>[.<subpath>...]`
  static DojoUri? tryParse(String uri) {
    final segments = uri.toLowerCase().split('.');

    // Minimum: dojo.category.identifier
    if (segments.length < 3) return null;

    // Must start with 'dojo'
    if (segments[0] != root) return null;

    // Parse category
    final category = DojoCategory.fromPrefix(segments[1]);
    if (category == null) return null;

    // Validate identifier
    final identifier = segments[2];
    if (!_isValidIdentifier(identifier)) return null;

    // Parse optional sub-path
    final subPath = <String>[];
    for (var i = 3; i < segments.length; i++) {
      if (!_isValidIdentifier(segments[i])) return null;
      subPath.add(segments[i]);
    }

    return DojoUri._(
      category: category,
      identifier: identifier,
      subPath: subPath,
    );
  }

  /// Parses a URI string, throwing if invalid.
  static DojoUri parse(String uri) {
    final result = tryParse(uri);
    if (result == null) {
      throw FormatException('Invalid Dojo URI: $uri');
    }
    return result;
  }

  /// Validates that a string segment uses lowercase and underscores only.
  static bool _isValidIdentifier(String segment) {
    if (segment.isEmpty) return false;
    return RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(segment);
  }

  /// Returns the full URI string representation.
  @override
  String toString() {
    final buffer = StringBuffer('$root.${category.prefix}.$identifier');
    for (final segment in subPath) {
      buffer.write('.$segment');
    }
    return buffer.toString();
  }

  /// Returns the parent URI (without the last segment).
  /// Returns null if this is already a root-level URI.
  DojoUri? get parent {
    if (subPath.isNotEmpty) {
      return DojoUri._(
        category: category,
        identifier: identifier,
        subPath: subPath.sublist(0, subPath.length - 1),
      );
    }
    return null;
  }

  /// Creates a child URI by appending a segment.
  DojoUri child(String segment) {
    if (!_isValidIdentifier(segment)) {
      throw ArgumentError(
        'Segment must be lowercase with underscores only: $segment',
      );
    }
    return DojoUri._(
      category: category,
      identifier: identifier,
      subPath: [...subPath, segment],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DojoUri) return false;
    if (category != other.category) return false;
    if (identifier != other.identifier) return false;
    if (subPath.length != other.subPath.length) return false;
    for (var i = 0; i < subPath.length; i++) {
      if (subPath[i] != other.subPath[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        category,
        identifier,
        Object.hashAll(subPath),
      );
}
