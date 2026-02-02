import '../../domain/entities/dojo_uri.dart';
import '../utils/uri_utils.dart';

/// Result of a URI routing operation.
class UriRouteResult {
  /// The parsed DojoUri object.
  final DojoUri uri;

  /// Whether this is a new URI (not yet in the database).
  final bool isNew;

  /// Suggested display name based on the identifier.
  final String suggestedDisplayName;

  const UriRouteResult({
    required this.uri,
    required this.isNew,
    required this.suggestedDisplayName,
  });
}

/// The URI Router handles resolution and routing of Dojo URIs.
///
/// This is the "Librarian's" routing logic - it maps string inputs
/// to their corresponding URI paths and validates them against
/// the Dojo's URI hierarchy.
class UriRouter {
  /// Attempts to parse and route a URI string.
  ///
  /// Returns a [UriRouteResult] if valid, null otherwise.
  UriRouteResult? route(String input) {
    final uri = DojoUri.tryParse(input);
    if (uri == null) return null;

    return UriRouteResult(
      uri: uri,
      isNew: true, // Will be determined by repository lookup
      suggestedDisplayName: _identifierToDisplayName(uri.identifier),
    );
  }

  /// Routes a natural language input to the appropriate category.
  ///
  /// Attempts to infer the category from context clues in the input.
  /// Falls back to [defaultCategory] if no clues are found.
  DojoUri? routeFromNaturalInput(
    String input, {
    DojoCategory defaultCategory = DojoCategory.contact,
  }) {
    final normalizedInput = input.trim().toLowerCase();

    // Check if input is already a URI
    final existingUri = DojoUri.tryParse(normalizedInput);
    if (existingUri != null) return existingUri;

    // Infer category from keywords
    final category = _inferCategory(normalizedInput) ?? defaultCategory;

    // Extract the identifier from the input
    final identifier = UriUtils.nameToIdentifier(input);
    if (identifier.isEmpty) return null;

    return DojoUri(category: category, identifier: identifier);
  }

  /// Infers the category from natural language keywords.
  DojoCategory? _inferCategory(String input) {
    // Entity indicators
    const entityKeywords = [
      'place',
      'location',
      'address',
      'building',
      'store',
      'shop',
      'restaurant',
      'office',
      'gate',
      'landmark',
      'business',
    ];

    // Medical indicators
    const medicalKeywords = [
      'health',
      'medical',
      'symptom',
      'medicine',
      'doctor',
      'appointment',
      'prescription',
      'blood',
      'pressure',
      'weight',
      'mood',
    ];

    // System indicators
    const systemKeywords = [
      'system',
      'sync',
      'setting',
      'config',
      'preference',
      'schedule',
      'reminder',
      'alarm',
    ];

    for (final keyword in entityKeywords) {
      if (input.contains(keyword)) return DojoCategory.entity;
    }
    for (final keyword in medicalKeywords) {
      if (input.contains(keyword)) return DojoCategory.medical;
    }
    for (final keyword in systemKeywords) {
      if (input.contains(keyword)) return DojoCategory.system;
    }

    // Default: assume contact if no keywords match
    return null;
  }

  /// Converts a snake_case identifier to a Title Case display name.
  String _identifierToDisplayName(String identifier) {
    return identifier
        .split('_')
        .map((word) => word.isEmpty
            ? ''
            : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  /// Generates a unique URI by appending a suffix if needed.
  ///
  /// Used when a URI already exists and a new unique one is required.
  DojoUri makeUnique(DojoUri baseUri, Set<String> existingUris) {
    var candidate = baseUri.toString();
    var counter = 1;

    while (existingUris.contains(candidate)) {
      counter++;
      candidate = '${baseUri}_$counter';
    }

    return DojoUri.parse(candidate);
  }

  /// Validates that a URI follows all Dojo conventions.
  ///
  /// Returns a list of validation errors, or empty list if valid.
  List<String> validate(String uri) {
    final errors = <String>[];

    final segments = uri.split('.');

    if (segments.length < 3) {
      errors.add('URI must have at least 3 segments (dojo.category.identifier)');
      return errors;
    }

    if (segments[0].toLowerCase() != 'dojo') {
      errors.add('URI must start with "dojo"');
    }

    if (DojoCategory.fromPrefix(segments[1].toLowerCase()) == null) {
      errors.add(
        'Invalid category "${segments[1]}". Must be: con, ent, med, or sys',
      );
    }

    for (var i = 2; i < segments.length; i++) {
      final segment = segments[i];
      if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(segment)) {
        errors.add(
          'Segment "$segment" must be lowercase, start with a letter, '
          'and contain only letters, numbers, and underscores',
        );
      }
    }

    return errors;
  }
}
