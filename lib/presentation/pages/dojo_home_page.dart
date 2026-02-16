import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/constants/dojo_theme.dart';
import '../../core/dojo_provider.dart';
import '../../core/services/sensei_llm_service.dart';
import '../../core/services/synthesis_service.dart';
import '../../domain/entities/attribute.dart';
import '../../domain/entities/rolo.dart';
import '../widgets/flip_card.dart';
import '../widgets/sensei_bar.dart';
import 'search_page.dart';
import 'settings_page.dart';

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
  List<Rolo> _recentRolos = [];
  bool _isLoading = true;
  String? _lastSynthesisMessage;
  List<SynthesisSuggestion> _pendingSuggestions = [];
  SenseiLlmService? _senseiLlm;
  LlmHealthStatus _llmHealthStatus = const LlmHealthStatus();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindLlmService();
    if (_isLoading) {
      _loadRecentRolos();
    }
  }

  @override
  void dispose() {
    _senseiLlm?.healthStatus.removeListener(_handleLlmHealthChanged);
    super.dispose();
  }

  void _bindLlmService() {
    final provider = DojoProvider.of(context);
    final nextService = provider.senseiLlm;
    if (identical(_senseiLlm, nextService)) {
      return;
    }

    _senseiLlm?.healthStatus.removeListener(_handleLlmHealthChanged);
    _senseiLlm = nextService;
    _senseiLlm!.healthStatus.addListener(_handleLlmHealthChanged);
    _llmHealthStatus = _senseiLlm!.healthStatus.value;

    if (_llmHealthStatus.checkedAt == null) {
      unawaited(_senseiLlm!.checkHealth(force: true));
    }
  }

  void _handleLlmHealthChanged() {
    final nextStatus = _senseiLlm?.healthStatus.value;
    if (!mounted || nextStatus == null) {
      return;
    }
    setState(() {
      _llmHealthStatus = nextStatus;
    });
  }

  Future<void> _retryLlmHealthCheck() async {
    final llm = _senseiLlm;
    if (llm == null) return;
    await llm.checkHealth(force: true);
  }

  Future<void> _loadRecentRolos() async {
    final dojo = DojoProvider.of(context).dojoService;
    final rolos = await dojo.getRecentRolos(limit: 50);
    if (mounted) {
      setState(() {
        _recentRolos = rolos;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSummon(String text) async {
    setState(() {
      _senseiState = SenseiState.thinking;
    });

    try {
      final dojo = DojoProvider.of(context).dojoService;
      final result = await dojo.processSummoning(text);

      if (mounted) {
        setState(() {
          _senseiState =
              result.attribute != null ? SenseiState.synthesis : SenseiState.idle;
          _lastSynthesisMessage =
              result.attribute != null ? result.message : null;
        });

        await _loadRecentRolos();

        // Check for synthesis suggestions from the new Rolo
        final synthesisService = DojoProvider.of(context).synthesisService;
        final suggestions = await synthesisService.analyzeRolo(result.rolo);
        if (mounted && suggestions.isNotEmpty) {
          setState(() {
            _pendingSuggestions = suggestions;
          });
        }

        if (result.attribute != null) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() {
                _senseiState = SenseiState.idle;
                _lastSynthesisMessage = null;
              });
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _senseiState = SenseiState.idle;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: DojoColors.alert,
          ),
        );
      }
    }
  }

  String _formatKey(String key) {
    return key
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final provider = DojoProvider.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Text('🥋', style: TextStyle(fontSize: 24)),
            SizedBox(width: DojoDimens.paddingSmall),
            Text('ROLODOJO'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_outlined),
            onPressed: () => _showVaultView(context),
            tooltip: 'View Vault',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SearchPage(
                    librarianService: provider.librarianService,
                  ),
                ),
              );
            },
            tooltip: 'Search the Vault',
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SettingsPage(
                    backupService: provider.backupService,
                  ),
                ),
              );
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_llmHealthStatus.checkedAt != null && !_llmHealthStatus.isHealthy)
            _buildLlmHealthBanner(),
          if (_lastSynthesisMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: DojoDimens.paddingMedium,
                vertical: DojoDimens.paddingSmall,
              ),
              color: DojoColors.success.withOpacity(0.15),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: DojoColors.success, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _lastSynthesisMessage!,
                      style: const TextStyle(color: DojoColors.success, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          // Synthesis suggestion cards
          if (_pendingSuggestions.isNotEmpty)
            _buildSuggestionBanner(),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: DojoColors.senseiGold),
                  )
                : _recentRolos.isEmpty
                    ? _buildEmptyState()
                    : _buildStream(),
          ),
          SenseiBar(
            state: _senseiState,
            onSubmit: _handleSummon,
          ),
        ],
      ),
    );
  }

  Widget _buildSuggestionBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: DojoDimens.paddingMedium,
        vertical: DojoDimens.paddingSmall,
      ),
      padding: const EdgeInsets.all(DojoDimens.paddingMedium),
      decoration: BoxDecoration(
        color: DojoColors.senseiGold.withOpacity(0.1),
        borderRadius: BorderRadius.circular(DojoDimens.cardRadius),
        border: Border.all(color: DojoColors.senseiGold.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: DojoColors.senseiGold, size: 16),
              SizedBox(width: 8),
              Text(
                'Sensei Suggestion',
                style: TextStyle(
                  color: DojoColors.senseiGold,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._pendingSuggestions.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_formatKey(s.attributeKey)}: ${s.attributeValue}  '
                        '(${(s.confidence * 100).toInt()}%)',
                        style: const TextStyle(
                          color: DojoColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.check_circle,
                        color: DojoColors.success,
                        size: 20,
                      ),
                      onPressed: () => _acceptSuggestion(s),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(
                        Icons.cancel,
                        color: DojoColors.alert,
                        size: 20,
                      ),
                      onPressed: () => _dismissSuggestion(s),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildLlmHealthBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: DojoDimens.paddingMedium,
        vertical: DojoDimens.paddingSmall,
      ),
      color: DojoColors.alert.withOpacity(0.12),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: DojoColors.alert,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _llmHealthStatus.message,
              style: const TextStyle(
                color: DojoColors.alert,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: _retryLlmHealthCheck,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Future<void> _acceptSuggestion(SynthesisSuggestion suggestion) async {
    final dojo = DojoProvider.of(context).dojoService;
    await dojo.processSummoning(
      "Set ${suggestion.targetUri.split('.').last}'s "
      '${suggestion.attributeKey} to ${suggestion.attributeValue}',
    );
    setState(() {
      _pendingSuggestions.remove(suggestion);
    });
    await _loadRecentRolos();
  }

  void _dismissSuggestion(SynthesisSuggestion suggestion) {
    setState(() {
      _pendingSuggestions.remove(suggestion);
    });
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
              Icon(Icons.lightbulb_outline, color: DojoColors.senseiGold, size: 16),
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
      reverse: true,
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

  void _showRoloDetails(BuildContext context, Rolo rolo) {
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
                    rolo.type.value,
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
              rolo.summoningText,
              style: const TextStyle(color: DojoColors.textPrimary, fontSize: 15),
            ),
            if (rolo.targetUri != null) ...[
              const SizedBox(height: 16),
              const Divider(color: DojoColors.border),
              const SizedBox(height: 8),
              _buildDetailRow('Target URI', rolo.targetUri),
              _buildDetailRow('Timestamp', rolo.timestamp.toIso8601String()),
              if (rolo.metadata.trigger != null)
                _buildDetailRow('Trigger', rolo.metadata.trigger),
              if (rolo.metadata.confidenceScore != null)
                _buildDetailRow(
                  'Confidence',
                  '${(rolo.metadata.confidenceScore! * 100).toInt()}%',
                ),
            ],
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
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

  void _showVaultView(BuildContext context) async {
    final dojo = DojoProvider.of(context).dojoService;
    final provider = DojoProvider.of(context);
    final records = await provider.recordRepository.getAll();

    final recordAttributes = <String, List<Attribute>>{};
    final roloTexts = <String, String>{};
    for (final record in records) {
      final attrs = await dojo.getAttributes(record.uri);
      if (attrs.isNotEmpty) {
        recordAttributes[record.uri] = attrs;
        // Load the source Rolo's summoning text for each attribute
        for (final attr in attrs) {
          if (!roloTexts.containsKey(attr.lastRoloId)) {
            final rolo = await dojo.getRolo(attr.lastRoloId);
            if (rolo != null) {
              roloTexts[attr.lastRoloId] = rolo.summoningText;
            }
          }
        }
      }
    }

    if (!mounted) return;

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
                    '${records.length} records',
                    style: const TextStyle(color: DojoColors.textHint, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Divider(color: DojoColors.border, height: 1),
            Expanded(
              child: recordAttributes.isEmpty
                  ? const Center(
                      child: Text(
                        'No records yet',
                        style: TextStyle(color: DojoColors.textHint),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(DojoDimens.paddingMedium),
                      itemCount: recordAttributes.length,
                      itemBuilder: (context, index) {
                        final uri = recordAttributes.keys.elementAt(index);
                        final attrs = recordAttributes[uri]!;
                        final record = records.firstWhere((r) => r.uri == uri);

                        return _VaultRecordCard(
                          uri: uri,
                          displayName: record.displayName,
                          attributes: attrs,
                          roloTexts: roloTexts,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getTypeBadgeColor(RoloType type) {
    switch (type) {
      case RoloType.input:
        return DojoColors.senseiGold;
      case RoloType.synthesis:
        return DojoColors.success;
      case RoloType.request:
        return DojoColors.textSecondary;
    }
  }
}

/// A card representing a single Rolo in the stream.
class _RoloCard extends StatelessWidget {
  final Rolo rolo;
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
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _getTypeBadgeColor(),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      rolo.type.value,
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
                    style: const TextStyle(color: DojoColors.textHint, fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: DojoDimens.paddingSmall),
              Text(
                rolo.summoningText,
                style: const TextStyle(color: DojoColors.textPrimary, fontSize: 15),
              ),
              if (rolo.targetUri != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.link, color: DojoColors.senseiGold, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      rolo.targetUri!,
                      style: const TextStyle(
                        color: DojoColors.senseiGold,
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
      case RoloType.input:
        return DojoColors.senseiGold;
      case RoloType.synthesis:
        return DojoColors.success;
      case RoloType.request:
        return DojoColors.textSecondary;
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

/// Card showing a record and its attributes in the Vault view.
class _VaultRecordCard extends StatelessWidget {
  final String uri;
  final String displayName;
  final List<Attribute> attributes;
  final Map<String, String> roloTexts;

  const _VaultRecordCard({
    required this.uri,
    required this.displayName,
    required this.attributes,
    this.roloTexts = const {},
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: DojoDimens.paddingSmall),
      child: Padding(
        padding: const EdgeInsets.all(DojoDimens.paddingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayName,
                    style: const TextStyle(
                      color: DojoColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  uri,
                  style: const TextStyle(
                    color: DojoColors.senseiGold,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(color: DojoColors.border, height: 1),
            const SizedBox(height: 8),
            ...attributes.map((attr) => AttributeFlipCard(
                  attributeKey: attr.key,
                  attributeValue: attr.value,
                  roloId: attr.lastRoloId,
                  summoningText: roloTexts[attr.lastRoloId],
                  timestamp: attr.updatedAt ?? DateTime.now(),
                )),
          ],
        ),
      ),
    );
  }
}
