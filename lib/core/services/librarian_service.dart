import '../../domain/entities/attribute.dart';
import '../../domain/entities/record.dart';
import '../../domain/entities/rolo.dart';
import '../../domain/repositories/attribute_repository.dart';
import '../../domain/repositories/record_repository.dart';
import '../../domain/repositories/rolo_repository.dart';

/// A search result item from the Librarian.
class SearchResult {
  /// The type of result.
  final SearchResultType type;

  /// The primary display text.
  final String title;

  /// Secondary text (URI, attribute key, etc.)
  final String subtitle;

  /// The URI associated with this result.
  final String? uri;

  /// Relevance score (higher = more relevant).
  final double score;

  /// The underlying data (Rolo, Record, or Attribute).
  final dynamic data;

  const SearchResult({
    required this.type,
    required this.title,
    required this.subtitle,
    this.uri,
    this.score = 0.0,
    this.data,
  });
}

/// Types of search results.
enum SearchResultType {
  record,
  attribute,
  rolo,
}

/// The Librarian Service handles searching and retrieving data from the Dojo.
///
/// From ROLODOJO_GLOSSARY.md:
/// "The Librarian: The Sensei's function of searching, retrieving,
/// and presenting data to the user."
class LibrarianService {
  final RoloRepository _roloRepository;
  final RecordRepository _recordRepository;
  final AttributeRepository _attributeRepository;

  LibrarianService({
    required RoloRepository roloRepository,
    required RecordRepository recordRepository,
    required AttributeRepository attributeRepository,
  })  : _roloRepository = roloRepository,
        _recordRepository = recordRepository,
        _attributeRepository = attributeRepository;

  /// Performs a unified search across all data types.
  ///
  /// Searches Records, Attributes, and Rolos for matches.
  /// Results are sorted by relevance score.
  Future<List<SearchResult>> search(String query) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final normalizedQuery = query.toLowerCase().trim();
    final results = <SearchResult>[];

    // Search records by name
    final records = await _recordRepository.searchByName(query);
    for (final record in records) {
      results.add(SearchResult(
        type: SearchResultType.record,
        title: record.displayName,
        subtitle: record.uri,
        uri: record.uri,
        score: _calculateScore(record.displayName, normalizedQuery),
        data: record,
      ));
    }

    // Search attributes by key or value
    final attributes = await _attributeRepository.search(query);
    for (final attr in attributes) {
      results.add(SearchResult(
        type: SearchResultType.attribute,
        title: '${_formatKey(attr.key)}: ${attr.value ?? "(deleted)"}',
        subtitle: attr.subjectUri,
        uri: attr.subjectUri,
        score: _calculateScore(
          '${attr.key} ${attr.value ?? ""}',
          normalizedQuery,
        ),
        data: attr,
      ));
    }

    // Search rolos by summoning text
    final rolos = await _roloRepository.search(query);
    for (final rolo in rolos) {
      results.add(SearchResult(
        type: SearchResultType.rolo,
        title: rolo.summoningText,
        subtitle: '${rolo.type.value} • ${_formatDate(rolo.timestamp)}',
        uri: rolo.targetUri,
        score: _calculateScore(rolo.summoningText, normalizedQuery),
        data: rolo,
      ));
    }

    // Sort by score (highest first)
    results.sort((a, b) => b.score.compareTo(a.score));

    return results;
  }

  /// Searches only Records.
  Future<List<Record>> searchRecords(String query) async {
    return _recordRepository.searchByName(query);
  }

  /// Searches only Attributes.
  Future<List<Attribute>> searchAttributes(String query) async {
    return _attributeRepository.search(query);
  }

  /// Searches only Rolos.
  Future<List<Rolo>> searchRolos(String query) async {
    return _roloRepository.search(query);
  }

  /// Gets all attributes for a specific URI.
  Future<List<Attribute>> getAttributesForUri(String uri) async {
    return _attributeRepository.getByUri(uri);
  }

  /// Gets the history of Rolos targeting a specific URI.
  Future<List<Rolo>> getRolosForUri(String uri) async {
    return _roloRepository.getByTargetUri(uri);
  }

  /// Gets a Record by its URI.
  Future<Record?> getRecord(String uri) async {
    return _recordRepository.getByUri(uri);
  }

  /// Gets a Rolo by its ID.
  Future<Rolo?> getRolo(String id) async {
    return _roloRepository.getById(id);
  }

  /// Calculates a simple relevance score.
  double _calculateScore(String text, String query) {
    final normalizedText = text.toLowerCase();
    var score = 0.0;

    // Exact match
    if (normalizedText == query) {
      score += 100;
    }
    // Starts with query
    else if (normalizedText.startsWith(query)) {
      score += 80;
    }
    // Contains query as word
    else if (normalizedText.contains(' $query ') ||
        normalizedText.contains(' $query') ||
        normalizedText.contains('$query ')) {
      score += 60;
    }
    // Contains query
    else if (normalizedText.contains(query)) {
      score += 40;
    }

    // Bonus for shorter matches (more specific)
    score += (100 - text.length.clamp(0, 100)) * 0.1;

    return score;
  }

  String _formatKey(String key) {
    return key
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays > 365) {
      return '${dt.year}/${dt.month}/${dt.day}';
    } else if (diff.inDays > 30) {
      return '${diff.inDays ~/ 30}mo ago';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else {
      return 'Just now';
    }
  }
}
