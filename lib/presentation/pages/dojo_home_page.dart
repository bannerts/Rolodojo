import 'package:flutter/material.dart';
import '../../core/constants/dojo_theme.dart';
import '../../core/services/input_parser.dart';
import '../../core/utils/uri_utils.dart';
import '../widgets/flip_card.dart';
import '../widgets/sensei_bar.dart';

/// The main home page of the Dojo application.
///
/// Displays "The Stream" (chronological feed of Rolos) with
/// the Sensei Bar as a persistent floating bottom input.
class DojoHomePage extends StatefulWidget {
  const DojoHomePage({super.key});

  @override
  State<DojoHomePage> createState() => _DojoHomePageState();
}

class _DojoHomePageState extends State<DojoHomePage> {
  SenseiState _senseiState = SenseiState.idle;
  final List<_RoloPreview> _recentRolos = [];
  final InputParser _parser = InputParser();

  void _handleSummon(String text) {
    setState(() {
      _senseiState = SenseiState.thinking;
    });

    // Parse the input
    final parsed = _parser.parse(text);

    // Simulate processing delay
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        // Create the input Rolo
        final inputRolo = _RoloPreview(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: text,
          timestamp: DateTime.now(),
          type: parsed.isQuery ? 'REQUEST' : 'INPUT',
        );

        setState(() {
          _recentRolos.insert(0, inputRolo);
        });

        // If structured data was extracted, show synthesis
        if (parsed.canCreateAttribute) {
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted) {
              final synthesisRolo = _RoloPreview(
                id: '${DateTime.now().millisecondsSinceEpoch}_synth',
                text: 'Updated ${parsed.subjectName}\'s ${_formatKey(parsed.attributeKey!)} to "${parsed.attributeValue}"',
                timestamp: DateTime.now(),
                type: 'SYNTHESIS',
                parsedData: parsed,
              );

              setState(() {
                _recentRolos.insert(0, synthesisRolo);
                _senseiState = SenseiState.synthesis;
              });

              // Reset to idle
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  setState(() {
                    _senseiState = SenseiState.idle;
                  });
                }
              });
            }
          });
        } else {
          setState(() {
            _senseiState = SenseiState.idle;
          });
        }
      }
    });
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
      appBar: AppBar(
        title: const Row(
          children: [
            Text(
              '🥋',
              style: TextStyle(fontSize: 24),
            ),
            SizedBox(width: DojoDimens.paddingSmall),
            Text('ROLODOJO'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            onPressed: () {
              _showVaultView(context);
            },
            tooltip: 'View Vault',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              _showSearchDialog(context);
            },
            tooltip: 'Search the Vault',
          ),
        ],
      ),
      body: Column(
        children: [
          // The Stream - Chronological feed of Rolos
          Expanded(
            child: _recentRolos.isEmpty
                ? _buildEmptyState()
                : _buildStream(),
          ),

          // The Sensei Bar - Persistent bottom input
          SenseiBar(
            state: _senseiState,
            onSubmit: _handleSummon,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DojoDimens.paddingLarge),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.self_improvement,
              size: 64,
              color: DojoColors.textHint.withOpacity(0.5),
            ),
            const SizedBox(height: DojoDimens.paddingMedium),
            Text(
              'The Dojo awaits your first summoning',
              style: TextStyle(
                color: DojoColors.textHint.withOpacity(0.7),
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: DojoDimens.paddingLarge),
            _buildExampleCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildExampleCard() {
    return Container(
      padding: const EdgeInsets.all(DojoDimens.paddingMedium),
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
              Icon(Icons.lightbulb_outline,
                color: DojoColors.senseiGold,
                size: 16,
              ),
              SizedBox(width: 8),
              Text(
                'Try saying:',
                style: TextStyle(
                  color: DojoColors.senseiGold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildExampleText("Joe's coffee is Espresso"),
          _buildExampleText("Gate code for Railroad is 1234"),
          _buildExampleText("Remember Sarah's birthday is March 15"),
        ],
      ),
    );
  }

  Widget _buildExampleText(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Text('• ', style: TextStyle(color: DojoColors.textHint)),
          Expanded(
            child: Text(
              '"$text"',
              style: const TextStyle(
                color: DojoColors.textSecondary,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStream() {
    return ListView.builder(
      padding: const EdgeInsets.all(DojoDimens.paddingMedium),
      reverse: true, // Newest at bottom (per UX spec)
      itemCount: _recentRolos.length,
      itemBuilder: (context, index) {
        final rolo = _recentRolos[index];
        return _RoloCard(
          rolo: rolo,
          onTap: () => _showRoloDetails(context, rolo),
        );
      },
    );
  }

  void _showRoloDetails(BuildContext context, _RoloPreview rolo) {
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getTypeBadgeColor(rolo.type),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    rolo.type,
                    style: const TextStyle(
                      color: DojoColors.slate,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'ID: ${rolo.id.substring(0, 8)}...',
                  style: const TextStyle(
                    color: DojoColors.textHint,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Summoning Text:',
              style: TextStyle(color: DojoColors.textHint, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text(
              rolo.text,
              style: const TextStyle(color: DojoColors.textPrimary, fontSize: 15),
            ),
            if (rolo.parsedData != null) ...[
              const SizedBox(height: 16),
              const Divider(color: DojoColors.border),
              const SizedBox(height: 8),
              const Text(
                'Extracted Data:',
                style: TextStyle(color: DojoColors.textHint, fontSize: 12),
              ),
              const SizedBox(height: 8),
              _buildParsedDataRow('Subject', rolo.parsedData!.subjectName),
              _buildParsedDataRow('URI', rolo.parsedData!.subjectUri?.toString()),
              _buildParsedDataRow('Attribute', rolo.parsedData!.attributeKey),
              _buildParsedDataRow('Value', rolo.parsedData!.attributeValue),
              _buildParsedDataRow(
                'Confidence',
                '${(rolo.parsedData!.confidence * 100).toInt()}%',
              ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildParsedDataRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: DojoColors.textHint, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '—',
              style: TextStyle(
                color: value != null ? DojoColors.senseiGold : DojoColors.textHint,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showVaultView(BuildContext context) {
    // Extract unique subjects from rolos with parsed data
    final subjects = <String, ParsedInput>{};
    for (final rolo in _recentRolos) {
      if (rolo.parsedData?.subjectUri != null) {
        subjects[rolo.parsedData!.subjectUri!.toString()] = rolo.parsedData!;
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: DojoColors.graphite,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DojoDimens.cardRadius),
        ),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(DojoDimens.paddingMedium),
              child: Row(
                children: [
                  const Icon(Icons.folder, color: DojoColors.senseiGold),
                  const SizedBox(width: 8),
                  const Text(
                    'The Vault',
                    style: TextStyle(
                      color: DojoColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${subjects.length} records',
                    style: const TextStyle(
                      color: DojoColors.textHint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: DojoColors.border, height: 1),
            Expanded(
              child: subjects.isEmpty
                  ? const Center(
                      child: Text(
                        'No records yet',
                        style: TextStyle(color: DojoColors.textHint),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(DojoDimens.paddingMedium),
                      itemCount: subjects.length,
                      itemBuilder: (context, index) {
                        final uri = subjects.keys.elementAt(index);
                        final data = subjects[uri]!;
                        return AttributeFlipCard(
                          attributeKey: data.attributeKey!,
                          attributeValue: data.attributeValue,
                          roloId: DateTime.now().millisecondsSinceEpoch.toString(),
                          summoningText: data.originalText,
                          timestamp: DateTime.now(),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DojoColors.graphite,
        title: const Row(
          children: [
            Icon(Icons.search, color: DojoColors.senseiGold),
            SizedBox(width: 8),
            Text('Search the Vault', style: TextStyle(color: DojoColors.textPrimary)),
          ],
        ),
        content: const Text(
          'Full Librarian search will be implemented in Phase 3.',
          style: TextStyle(color: DojoColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Color _getTypeBadgeColor(String type) {
    switch (type) {
      case 'INPUT':
        return DojoColors.senseiGold;
      case 'SYNTHESIS':
        return DojoColors.success;
      case 'REQUEST':
        return DojoColors.textSecondary;
      default:
        return DojoColors.textHint;
    }
  }
}

/// Preview model for displaying Rolos in the stream.
class _RoloPreview {
  final String id;
  final String text;
  final DateTime timestamp;
  final String type;
  final ParsedInput? parsedData;

  const _RoloPreview({
    required this.id,
    required this.text,
    required this.timestamp,
    required this.type,
    this.parsedData,
  });
}

/// A card representing a single Rolo in the stream.
class _RoloCard extends StatelessWidget {
  final _RoloPreview rolo;
  final VoidCallback? onTap;

  const _RoloCard({required this.rolo, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        margin: const EdgeInsets.only(bottom: DojoDimens.paddingSmall),
        child: Padding(
          padding: const EdgeInsets.all(DojoDimens.paddingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with type badge and timestamp
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _getTypeBadgeColor(),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      rolo.type,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: DojoColors.slate,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatTimestamp(rolo.timestamp),
                    style: const TextStyle(
                      color: DojoColors.textHint,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: DojoDimens.paddingSmall),

              // Summoning text
              Text(
                rolo.text,
                style: const TextStyle(
                  color: DojoColors.textPrimary,
                  fontSize: 15,
                ),
              ),

              // Parsed data indicator
              if (rolo.parsedData?.canCreateAttribute == true) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: DojoColors.success,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${rolo.parsedData!.subjectUri} → ${rolo.parsedData!.attributeKey}',
                      style: const TextStyle(
                        color: DojoColors.success,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _getTypeBadgeColor() {
    switch (rolo.type) {
      case 'INPUT':
        return DojoColors.senseiGold;
      case 'SYNTHESIS':
        return DojoColors.success;
      case 'REQUEST':
        return DojoColors.textSecondary;
      default:
        return DojoColors.textHint;
    }
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h ago';
    } else {
      return '${dt.month}/${dt.day}';
    }
  }
}
