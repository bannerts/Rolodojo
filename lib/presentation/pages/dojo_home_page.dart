import 'package:flutter/material.dart';
import '../../core/constants/dojo_theme.dart';
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

  void _handleSummon(String text) {
    setState(() {
      _senseiState = SenseiState.thinking;
    });

    // Simulate processing delay
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        setState(() {
          _recentRolos.insert(
            0,
            _RoloPreview(
              text: text,
              timestamp: DateTime.now(),
              type: 'INPUT',
            ),
          );
          _senseiState = SenseiState.synthesis;
        });

        // Reset to idle after showing synthesis state
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            setState(() {
              _senseiState = SenseiState.idle;
            });
          }
        });
      }
    });
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
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Implement Librarian search
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
          ),
          const SizedBox(height: DojoDimens.paddingSmall),
          Text(
            'Type below to begin',
            style: TextStyle(
              color: DojoColors.textHint.withOpacity(0.5),
              fontSize: 14,
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
        return _RoloCard(rolo: rolo);
      },
    );
  }
}

/// Preview model for displaying Rolos in the stream.
class _RoloPreview {
  final String text;
  final DateTime timestamp;
  final String type;

  const _RoloPreview({
    required this.text,
    required this.timestamp,
    required this.type,
  });
}

/// A card representing a single Rolo in the stream.
class _RoloCard extends StatelessWidget {
  final _RoloPreview rolo;

  const _RoloCard({required this.rolo});

  @override
  Widget build(BuildContext context) {
    return Card(
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
          ],
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
