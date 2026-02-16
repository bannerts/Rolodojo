import '../../domain/entities/dojo_uri.dart';
import '../utils/uri_utils.dart';

/// Result of parsing a natural language input.
class ParsedInput {
  /// The subject (person/entity) the input refers to.
  final String? subjectName;

  /// The inferred URI for the subject.
  final DojoUri? subjectUri;

  /// The attribute key extracted from the input.
  final String? attributeKey;

  /// The attribute value extracted from the input.
  final String? attributeValue;

  /// Whether this is a query (asking for info) vs a statement (providing info).
  final bool isQuery;

  /// Confidence score (0.0 - 1.0) for the parsing accuracy.
  final double confidence;

  /// The original input text.
  final String originalText;

  /// True when the extracted fact belongs to owner profile (`tbl_user`).
  final bool isOwnerProfile;

  const ParsedInput({
    this.subjectName,
    this.subjectUri,
    this.attributeKey,
    this.attributeValue,
    this.isQuery = false,
    this.confidence = 0.0,
    this.isOwnerProfile = false,
    required this.originalText,
  });

  /// Returns true if this parsed input has enough data to create an attribute.
  bool get canCreateAttribute =>
      subjectUri != null && attributeKey != null && attributeValue != null;
}

/// The Input Parser (The Scribe) parses natural language into structured data.
///
/// From ROLODOJO_GLOSSARY.md:
/// "The Scribe: The Sensei's function of parsing and writing data to the ledger."
///
/// Supported patterns:
/// - "[Name]'s [attribute] is [value]" → Joe's coffee is Espresso
/// - "[Name] [attribute]: [value]" → Joe coffee: Espresso
/// - "[attribute] for [Name] is [value]" → Coffee for Joe is Espresso
/// - "Set [Name]'s [attribute] to [value]"
/// - "Remember [Name]'s [attribute] is [value]"
class InputParser {
  static const String _relationshipKey = 'relationship_to_user';

  // Pattern matchers for different input formats
  static final List<_PatternMatcher> _patterns = [
    // "My girlfriend's name is Bridget Suzanne Hale"
    _PatternMatcher(
      RegExp(
        r"^(?:my\s+)?(girlfriend|boyfriend|wife|husband|partner|fiancee?|fiancé|fiancée)\s*(?:['’]s)?\s+name\s+is\s+(.+)$",
        caseSensitive: false,
      ),
      (match) => (
        subject: _cleanSubjectValue(match.group(2)!),
        key: _relationshipKey,
        value: _normalizeRelationshipTerm(match.group(1)!),
      ),
    ),

    // "Bridget Suzanne Hale is my girlfriend"
    _PatternMatcher(
      RegExp(
        r"^(.+?)\s+is\s+my\s+(girlfriend|boyfriend|wife|husband|partner|fiancee?|fiancé|fiancée)\s*[.!]?$",
        caseSensitive: false,
      ),
      (match) => (
        subject: _cleanSubjectValue(match.group(1)!),
        key: _relationshipKey,
        value: _normalizeRelationshipTerm(match.group(2)!),
      ),
    ),

    // "[Name]'s [attribute] is [value]"
    _PatternMatcher(
      RegExp(r"^(.+?)['’]s\s+(.+?)\s+is\s+(.+)$", caseSensitive: false),
      (match) => (
        subject: match.group(1)!.trim(),
        key: match.group(2)!.trim(),
        value: match.group(3)!.trim(),
      ),
    ),

    // "[Name] lives at [address]"
    _PatternMatcher(
      RegExp(r"^(.+?)\s+(?:lives?|resides?)\s+at\s+(.+)$", caseSensitive: false),
      (match) => (
        subject: match.group(1)!.trim(),
        key: 'address',
        value: match.group(2)!.trim(),
      ),
    ),

    // "Address for [Name] is [address]"
    _PatternMatcher(
      RegExp(
        r"^address\s+for\s+(.+?)\s*(?:is|:)\s+(.+)$",
        caseSensitive: false,
      ),
      (match) => (
        subject: match.group(1)!.trim(),
        key: 'address',
        value: match.group(2)!.trim(),
      ),
    ),

    // "[Name] [attribute] is [value]"
    _PatternMatcher(
      RegExp(r"^(.+?)\s+(.+?)\s+is\s+(.+)$", caseSensitive: false),
      (match) => (
        subject: match.group(1)!.trim(),
        key: match.group(2)!.trim(),
        value: match.group(3)!.trim(),
      ),
    ),

    // "[attribute] for [Name] is [value]"
    _PatternMatcher(
      RegExp(r"^(.+?)\s+for\s+(.+?)\s+is\s+(.+)$", caseSensitive: false),
      (match) => (
        subject: match.group(2)!.trim(),
        key: match.group(1)!.trim(),
        value: match.group(3)!.trim(),
      ),
    ),

    // "Set [Name]'s [attribute] to [value]"
    _PatternMatcher(
      RegExp(r"^set\s+(.+?)['’]s\s+(.+?)\s+to\s+(.+)$", caseSensitive: false),
      (match) => (
        subject: match.group(1)!.trim(),
        key: match.group(2)!.trim(),
        value: match.group(3)!.trim(),
      ),
    ),

    // "Remember [Name]'s [attribute] is [value]"
    _PatternMatcher(
      RegExp(r"^remember\s+(.+?)['’]s\s+(.+?)\s+is\s+(.+)$", caseSensitive: false),
      (match) => (
        subject: match.group(1)!.trim(),
        key: match.group(2)!.trim(),
        value: match.group(3)!.trim(),
      ),
    ),

    // "[Name]: [attribute] = [value]"
    _PatternMatcher(
      RegExp(r"^(.+?):\s*(.+?)\s*=\s*(.+)$", caseSensitive: false),
      (match) => (
        subject: match.group(1)!.trim(),
        key: match.group(2)!.trim(),
        value: match.group(3)!.trim(),
      ),
    ),
  ];

  // Query pattern matchers
  static final List<RegExp> _queryPatterns = [
    RegExp(r"^what\s+is\s+", caseSensitive: false),
    RegExp(r"^who\s+is\s+", caseSensitive: false),
    RegExp(r"^where\s+is\s+", caseSensitive: false),
    RegExp(r"\?$"),
  ];

  /// Parses a natural language input into structured data.
  ParsedInput parse(String input) {
    final trimmedInput = input.trim();

    // Check if this is a query
    final isQuery = _queryPatterns.any((p) => p.hasMatch(trimmedInput));

    // Try each pattern
    for (final pattern in _patterns) {
      final match = pattern.regex.firstMatch(trimmedInput);
      if (match != null) {
        final result = pattern.extractor(match);
        if (_shouldDeferToLlm(result.subject, result.key, result.value)) {
          continue;
        }
        if (result.key == _relationshipKey && !_looksLikePersonName(result.subject)) {
          continue;
        }
        final subjectUri = _inferUri(result.subject);
        final attributeKey = UriUtils.nameToIdentifier(result.key);

        return ParsedInput(
          subjectName: result.subject,
          subjectUri: subjectUri,
          attributeKey: attributeKey,
          attributeValue: result.value,
          isQuery: isQuery,
          confidence: 0.9,
          originalText: trimmedInput,
        );
      }
    }

    // No pattern matched - return unparsed result
    return ParsedInput(
      isQuery: isQuery,
      confidence: 0.0,
      originalText: trimmedInput,
    );
  }

  /// Infers the URI category and creates a DojoUri from a subject name.
  DojoUri? _inferUri(String subjectName) {
    final normalized = subjectName.toLowerCase();

    // Check for entity indicators
    const entityKeywords = [
      'place',
      'location',
      'address',
      'gate',
      'store',
      'shop',
      'restaurant',
      'office',
      'building',
    ];

    for (final keyword in entityKeywords) {
      if (normalized.contains(keyword)) {
        return UriUtils.entityFromName(subjectName);
      }
    }

    // Check for medical indicators
    const medicalKeywords = [
      'blood',
      'pressure',
      'symptom',
      'medicine',
      'health',
      'weight',
      'mood',
    ];

    for (final keyword in medicalKeywords) {
      if (normalized.contains(keyword)) {
        return UriUtils.medicalFromName(subjectName);
      }
    }

    // Default to contact
    return UriUtils.contactFromName(subjectName);
  }

  /// Extracts potential attribute updates from free-form text.
  ///
  /// This is a more aggressive parser that looks for any key-value pairs
  /// even in sentences that don't follow standard patterns.
  List<({String key, String value})> extractKeyValuePairs(String input) {
    final pairs = <({String key, String value})>[];

    // Look for "key: value" patterns
    final colonPattern = RegExp(r'(\w+)\s*:\s*([^,;]+)');
    for (final match in colonPattern.allMatches(input)) {
      pairs.add((
        key: UriUtils.nameToIdentifier(match.group(1)!),
        value: match.group(2)!.trim(),
      ));
    }

    // Look for "key is value" patterns
    final isPattern = RegExp(r'(\w+)\s+is\s+([^,;.]+)', caseSensitive: false);
    for (final match in isPattern.allMatches(input)) {
      final key = match.group(1)!.toLowerCase();
      // Skip common verbs that aren't attributes
      if (!['this', 'that', 'it', 'he', 'she', 'who', 'what'].contains(key)) {
        pairs.add((
          key: UriUtils.nameToIdentifier(key),
          value: match.group(2)!.trim(),
        ));
      }
    }

    return pairs;
  }

  static String _normalizeRelationshipTerm(String raw) {
    final normalized = raw.toLowerCase().trim();
    if (normalized == 'fiancé' || normalized == 'fiancée') {
      return 'fiancee';
    }
    return normalized;
  }

  static String _cleanSubjectValue(String value) {
    var normalized = value.trim();
    normalized = normalized.replaceAll(RegExp("^[\"“”']+"), '');
    normalized = normalized.replaceAll(RegExp("[\"“”']+\$"), '');
    return normalized.trim();
  }

  static bool _looksLikePersonName(String raw) {
    final cleaned = _cleanSubjectValue(raw);
    if (cleaned.isEmpty || !RegExp(r'[A-Za-z]').hasMatch(cleaned)) {
      return false;
    }

    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    if (tokens.length >= 2) {
      return true;
    }

    if (tokens.isEmpty) {
      return false;
    }
    final token = tokens.first;
    return token.length >= 2 && RegExp(r'[A-Z]').hasMatch(token);
  }

  static bool _shouldDeferToLlm(
    String subject,
    String key,
    String value,
  ) {
    final normalizedSubject = subject.trim().toLowerCase();
    final normalizedKey = key.trim().toLowerCase();
    final normalizedValue = value.trim().toLowerCase();

    // Self-introduction lines are often multi-clause and best resolved by LLM
    // with full context (owner profile + vault hints).
    if (normalizedSubject == 'my' && normalizedKey == 'name') {
      return true;
    }

    // Guard against over-captured address subjects like:
    // "My Name is Scott Bannert and I live at ...".
    if (normalizedKey == 'address') {
      if (normalizedSubject.contains(' and i ') ||
          normalizedSubject.contains(' my name is ') ||
          normalizedSubject.contains(' i live ') ||
          normalizedSubject.contains(' is ')) {
        return true;
      }
    }

    // Guard against name values swallowing an extra clause.
    if (normalizedKey == 'name') {
      if (normalizedValue.contains(' and i live ') ||
          normalizedValue.contains(' and my ') ||
          normalizedValue.contains(' my address ') ||
          normalizedValue.contains(' lives at ')) {
        return true;
      }
    }

    return false;
  }
}

/// Internal pattern matcher helper.
class _PatternMatcher {
  final RegExp regex;
  final ({String subject, String key, String value}) Function(RegExpMatch) extractor;

  const _PatternMatcher(this.regex, this.extractor);
}
