import 'package:flutter/material.dart';
import '../../core/constants/dojo_theme.dart';
import '../../core/services/input_parser.dart';
import '../../core/services/librarian_service.dart';
import '../../domain/entities/attribute.dart';
import '../../domain/entities/record.dart';
import '../../domain/entities/rolo.dart';

/// The Librarian search page.
///
/// Provides a unified search interface to find any URI, attribute,
/// or Rolo in the Dojo.
class SearchPage extends StatefulWidget {
  /// Optional LibrarianService. If not provided, search will be simulated.
  final LibrarianService? librarianService;

  const SearchPage({
    super.key,
    this.librarianService,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final InputParser _parser = InputParser();

  List<SearchResult> _results = [];
  bool _isSearching = false;
  String _lastQuery = '';

  // Simulated data for demo (when no real service is provided)
  final List<_SimulatedRecord> _simulatedRecords = [
    _SimulatedRecord('dojo.con.joe', 'Joe Smith', {'coffee': 'Espresso'}),
    _SimulatedRecord('dojo.con.sarah', 'Sarah Johnson', {'birthday': 'March 15'}),
    _SimulatedRecord('dojo.ent.railroad', 'Railroad Gate', {'gate_code': '1234'}),
    _SimulatedRecord('dojo.con.mike', 'Mike Davis', {'phone': '555-0123'}),
  ];

  @override
  void initState() {
    super.initState();
    _searchFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _lastQuery = '';
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _lastQuery = query;
    });

    // Use real service if available, otherwise simulate
    if (widget.librarianService != null) {
      final results = await widget.librarianService!.search(query);
      if (mounted && _lastQuery == query) {
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    } else {
      // Simulated search for demo
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted && _lastQuery == query) {
        setState(() {
          _results = _simulateSearch(query);
          _isSearching = false;
        });
      }
    }
  }

  List<SearchResult> _simulateSearch(String query) {
    final normalizedQuery = query.toLowerCase();
    final results = <SearchResult>[];

    for (final record in _simulatedRecords) {
      // Match on name or URI
      if (record.displayName.toLowerCase().contains(normalizedQuery) ||
          record.uri.toLowerCase().contains(normalizedQuery)) {
        results.add(SearchResult(
          type: SearchResultType.record,
          title: record.displayName,
          subtitle: record.uri,
          uri: record.uri,
          score: 80,
        ));
      }

      // Match on attributes
      for (final entry in record.attributes.entries) {
        if (entry.key.toLowerCase().contains(normalizedQuery) ||
            entry.value.toLowerCase().contains(normalizedQuery)) {
          results.add(SearchResult(
            type: SearchResultType.attribute,
            title: '${_formatKey(entry.key)}: ${entry.value}',
            subtitle: record.uri,
            uri: record.uri,
            score: 60,
          ));
        }
      }
    }

    return results;
  }

  String _formatKey(String key) {
    return key
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DojoColors.slate,
      appBar: AppBar(
        backgroundColor: DojoColors.slate,
        title: const Text('Search the Vault'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(DojoDimens.paddingMedium),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              style: const TextStyle(color: DojoColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search URIs, attributes, or text...',
                prefixIcon: const Icon(Icons.search, color: DojoColors.textHint),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: DojoColors.textHint),
                        onPressed: () {
                          _searchController.clear();
                          _performSearch('');
                        },
                      )
                    : null,
              ),
              onChanged: _performSearch,
            ),
          ),

          // Results
          Expanded(
            child: _buildResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: DojoColors.senseiGold),
      );
    }

    if (_lastQuery.isEmpty) {
      return _buildEmptyState();
    }

    if (_results.isEmpty) {
      return _buildNoResults();
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: DojoDimens.paddingMedium),
      itemCount: _results.length,
      itemBuilder: (context, index) {
        final result = _results[index];
        return _SearchResultCard(
          result: result,
          onTap: () => _showResultDetails(result),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: DojoColors.textHint.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'Search the Vault',
            style: TextStyle(
              color: DojoColors.textHint.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Find contacts, entities, and facts',
            style: TextStyle(
              color: DojoColors.textHint.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          _buildSearchHints(),
        ],
      ),
    );
  }

  Widget _buildSearchHints() {
    return Container(
      padding: const EdgeInsets.all(DojoDimens.paddingMedium),
      margin: const EdgeInsets.symmetric(horizontal: DojoDimens.paddingLarge),
      decoration: BoxDecoration(
        color: DojoColors.graphite,
        borderRadius: BorderRadius.circular(DojoDimens.cardRadius),
        border: Border.all(color: DojoColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, color: DojoColors.senseiGold, size: 16),
              SizedBox(width: 8),
              Text(
                'Try searching for:',
                style: TextStyle(
                  color: DojoColors.senseiGold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildHintChip('Joe'),
          _buildHintChip('coffee'),
          _buildHintChip('gate code'),
          _buildHintChip('dojo.con'),
        ],
      ),
    );
  }

  Widget _buildHintChip(String text) {
    return GestureDetector(
      onTap: () {
        _searchController.text = text;
        _performSearch(text);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: DojoColors.slate,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: const TextStyle(color: DojoColors.textSecondary, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 48,
            color: DojoColors.textHint.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'No results for "$_lastQuery"',
            style: TextStyle(
              color: DojoColors.textHint.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Try a different search term',
            style: TextStyle(
              color: DojoColors.textHint.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  void _showResultDetails(SearchResult result) {
    showModalBottomSheet(
      context: context,
      backgroundColor: DojoColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DojoDimens.cardRadius),
        ),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(DojoDimens.paddingMedium),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _getResultIcon(result.type),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.title,
                    style: const TextStyle(
                      color: DojoColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (result.uri != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: DojoColors.slate,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  result.uri!,
                  style: const TextStyle(
                    color: DojoColors.senseiGold,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              result.subtitle,
              style: const TextStyle(
                color: DojoColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context, result);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: DojoColors.senseiGold,
                  foregroundColor: DojoColors.slate,
                ),
                child: const Text('View Details'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _getResultIcon(SearchResultType type) {
    switch (type) {
      case SearchResultType.record:
        return const Icon(Icons.person, color: DojoColors.senseiGold);
      case SearchResultType.attribute:
        return const Icon(Icons.label, color: DojoColors.success);
      case SearchResultType.rolo:
        return const Icon(Icons.history, color: DojoColors.textSecondary);
    }
  }
}

/// A card displaying a single search result.
class _SearchResultCard extends StatelessWidget {
  final SearchResult result;
  final VoidCallback? onTap;

  const _SearchResultCard({
    required this.result,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: DojoDimens.paddingSmall),
      child: ListTile(
        leading: _getIcon(),
        title: Text(
          result.title,
          style: const TextStyle(color: DojoColors.textPrimary),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          result.subtitle,
          style: const TextStyle(color: DojoColors.textHint, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: DojoColors.textHint,
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _getIcon() {
    switch (result.type) {
      case SearchResultType.record:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: DojoColors.senseiGold.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.person, color: DojoColors.senseiGold, size: 20),
        );
      case SearchResultType.attribute:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: DojoColors.success.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.label, color: DojoColors.success, size: 20),
        );
      case SearchResultType.rolo:
        return Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: DojoColors.textSecondary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.history, color: DojoColors.textSecondary, size: 20),
        );
    }
  }
}

/// Simulated record for demo purposes.
class _SimulatedRecord {
  final String uri;
  final String displayName;
  final Map<String, String> attributes;

  const _SimulatedRecord(this.uri, this.displayName, this.attributes);
}
