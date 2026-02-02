import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/dojo_theme.dart';

/// A card that flips to reveal the audit trail (source Rolo) for a fact.
///
/// From ROLODOJO_UX_UI.md:
/// "The Flip Interaction: Tapping a fact 'flips' the card to reveal its
/// last_rolo_id and the original text that generated it."
class FlipCard extends StatefulWidget {
  /// The front content (the fact/attribute).
  final Widget front;

  /// The back content (the audit trail).
  final Widget back;

  /// Callback when the card is flipped.
  final VoidCallback? onFlip;

  const FlipCard({
    super.key,
    required this.front,
    required this.back,
    this.onFlip,
  });

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _showFront = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _flip() {
    if (_showFront) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    setState(() {
      _showFront = !_showFront;
    });
    widget.onFlip?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _flip,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final angle = _animation.value * math.pi;
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle);

          return Transform(
            transform: transform,
            alignment: Alignment.center,
            child: angle < math.pi / 2
                ? widget.front
                : Transform(
                    transform: Matrix4.identity()..rotateY(math.pi),
                    alignment: Alignment.center,
                    child: widget.back,
                  ),
          );
        },
      ),
    );
  }
}

/// A pre-styled flip card for displaying attributes with their audit trail.
class AttributeFlipCard extends StatelessWidget {
  /// The attribute key (e.g., "coffee_order").
  final String attributeKey;

  /// The attribute value.
  final String? attributeValue;

  /// The source Rolo ID.
  final String roloId;

  /// The original summoning text from the source Rolo.
  final String? summoningText;

  /// When the attribute was last updated.
  final DateTime? timestamp;

  /// Callback when the card is tapped.
  final VoidCallback? onTap;

  /// Callback when viewing the full Rolo is requested.
  final VoidCallback? onViewRolo;

  const AttributeFlipCard({
    super.key,
    required this.attributeKey,
    this.attributeValue,
    required this.roloId,
    this.summoningText,
    this.timestamp,
    this.onTap,
    this.onViewRolo,
  });

  String _formatKey(String key) {
    return key
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return 'Unknown';
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inDays > 365) {
      return '${dt.year}/${dt.month}/${dt.day}';
    } else if (diff.inDays > 30) {
      return '${diff.inDays ~/ 30} months ago';
    } else if (diff.inDays > 0) {
      return '${diff.inDays} days ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours} hours ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes} min ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlipCard(
      onFlip: onTap,
      front: _buildFront(),
      back: _buildBack(),
    );
  }

  Widget _buildFront() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DojoDimens.paddingMedium),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatKey(attributeKey),
                    style: const TextStyle(
                      color: DojoColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    attributeValue ?? '(deleted)',
                    style: TextStyle(
                      color: attributeValue != null
                          ? DojoColors.textPrimary
                          : DojoColors.textHint,
                      fontSize: 16,
                      fontStyle: attributeValue == null
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.flip_to_back,
              color: DojoColors.textHint,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBack() {
    return Card(
      color: DojoColors.slate,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DojoDimens.cardRadius),
          border: Border.all(color: DojoColors.senseiGold.withOpacity(0.3)),
        ),
        padding: const EdgeInsets.all(DojoDimens.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                const Icon(
                  Icons.history,
                  color: DojoColors.senseiGold,
                  size: 16,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Audit Trail',
                  style: TextStyle(
                    color: DojoColors.senseiGold,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.flip_to_front,
                  color: DojoColors.textHint,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Source text
            if (summoningText != null) ...[
              const Text(
                'Source:',
                style: TextStyle(
                  color: DojoColors.textHint,
                  fontSize: 10,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '"$summoningText"',
                style: const TextStyle(
                  color: DojoColors.textSecondary,
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
            ],

            // Metadata
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rolo ID:',
                        style: TextStyle(
                          color: DojoColors.textHint,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        roloId.substring(0, 8),
                        style: const TextStyle(
                          color: DojoColors.textSecondary,
                          fontSize: 11,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Updated:',
                        style: TextStyle(
                          color: DojoColors.textHint,
                          fontSize: 10,
                        ),
                      ),
                      Text(
                        _formatTimestamp(timestamp),
                        style: const TextStyle(
                          color: DojoColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // View full Rolo button
            if (onViewRolo != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: onViewRolo,
                  icon: const Icon(Icons.article_outlined, size: 16),
                  label: const Text('View Full Rolo'),
                  style: TextButton.styleFrom(
                    foregroundColor: DojoColors.senseiGold,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
