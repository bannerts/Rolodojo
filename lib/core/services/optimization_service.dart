import '../../domain/entities/rolo.dart';
import '../../domain/repositories/rolo_repository.dart';

/// Statistics about the database optimization.
class OptimizationStats {
  /// Number of Rolos before optimization.
  final int originalRoloCount;

  /// Number of Rolos that were ghosted.
  final int ghostedCount;

  /// Estimated space saved in bytes.
  final int spaceSavedBytes;

  /// Time taken for optimization.
  final Duration duration;

  const OptimizationStats({
    required this.originalRoloCount,
    required this.ghostedCount,
    required this.spaceSavedBytes,
    required this.duration,
  });

  /// Percentage of Rolos that were ghosted.
  double get ghostedPercentage =>
      originalRoloCount > 0 ? (ghostedCount / originalRoloCount) * 100 : 0;

  /// Human-readable space saved.
  String get spaceSavedFormatted {
    if (spaceSavedBytes < 1024) {
      return '$spaceSavedBytes B';
    } else if (spaceSavedBytes < 1024 * 1024) {
      return '${(spaceSavedBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      return '${(spaceSavedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
  }
}

/// A Ghost Rolo is a compressed version of an old Rolo.
///
/// The original summoning_text is replaced with a summary,
/// reducing storage while preserving the audit trail.
class GhostRolo {
  /// Original Rolo ID (preserved for audit trail).
  final String originalId;

  /// Type of the original Rolo.
  final RoloType type;

  /// Compressed summary of the original text.
  final String summary;

  /// Target URI (preserved).
  final String? targetUri;

  /// Original timestamp (preserved).
  final DateTime timestamp;

  /// Length of original summoning text.
  final int originalTextLength;

  const GhostRolo({
    required this.originalId,
    required this.type,
    required this.summary,
    this.targetUri,
    required this.timestamp,
    required this.originalTextLength,
  });

  /// Creates a Ghost Rolo from a regular Rolo.
  factory GhostRolo.fromRolo(Rolo rolo) {
    return GhostRolo(
      originalId: rolo.id,
      type: rolo.type,
      summary: _generateSummary(rolo.summoningText),
      targetUri: rolo.targetUri,
      timestamp: rolo.timestamp,
      originalTextLength: rolo.summoningText.length,
    );
  }

  /// Generates a compressed summary of the text.
  static String _generateSummary(String text) {
    if (text.length <= 50) return text;

    // Take first 47 chars + "..."
    return '${text.substring(0, 47)}...';
  }

  /// Converts to a Rolo for storage.
  Rolo toRolo() {
    return Rolo(
      id: originalId,
      type: type,
      summoningText: '[GHOST] $summary',
      targetUri: targetUri,
      metadata: RoloMetadata(
        trigger: 'Ghost_Optimization',
        confidenceScore: 1.0,
      ),
      timestamp: timestamp,
    );
  }

  /// Estimated bytes saved by ghosting this Rolo.
  int get bytesSaved => originalTextLength - summary.length - 8; // 8 for [GHOST]
}

/// The Optimization Service manages database optimization.
///
/// From ROLODOJO_PLAN.md:
/// "Optimization: Synthesis of 'Ghost' records to keep the local DB lightweight."
///
/// Ghost records preserve the audit trail while reducing storage:
/// - Original Rolo ID is kept
/// - Summoning text is replaced with a summary
/// - Timestamps and URIs are preserved
/// - Metadata is updated to indicate ghosting
class OptimizationService {
  final RoloRepository _roloRepository;

  /// Minimum age in days before a Rolo can be ghosted.
  final int minAgeDays;

  /// Minimum text length to consider for ghosting.
  final int minTextLength;

  OptimizationService({
    required RoloRepository roloRepository,
    this.minAgeDays = 90,
    this.minTextLength = 100,
  }) : _roloRepository = roloRepository;

  /// Analyzes the database and returns potential optimization stats.
  ///
  /// Does not actually modify any data.
  Future<OptimizationStats> analyzeForOptimization() async {
    final startTime = DateTime.now();
    final allRolos = await _roloRepository.getRecent(limit: 100000);

    final cutoffDate = DateTime.now().subtract(Duration(days: minAgeDays));
    var ghostableCount = 0;
    var potentialSavings = 0;

    for (final rolo in allRolos) {
      if (_canGhost(rolo, cutoffDate)) {
        ghostableCount++;
        final ghost = GhostRolo.fromRolo(rolo);
        potentialSavings += ghost.bytesSaved.clamp(0, 10000);
      }
    }

    return OptimizationStats(
      originalRoloCount: allRolos.length,
      ghostedCount: ghostableCount,
      spaceSavedBytes: potentialSavings,
      duration: DateTime.now().difference(startTime),
    );
  }

  /// Performs the optimization, ghosting eligible Rolos.
  ///
  /// Compresses old Rolos by replacing their summoning text
  /// with a short summary while preserving IDs and audit trail.
  Future<OptimizationStats> optimize() async {
    final startTime = DateTime.now();
    final allRolos = await _roloRepository.getRecent(limit: 100000);

    final cutoffDate = DateTime.now().subtract(Duration(days: minAgeDays));
    var ghostedCount = 0;
    var spaceSaved = 0;

    for (final rolo in allRolos) {
      if (_canGhost(rolo, cutoffDate)) {
        final ghost = GhostRolo.fromRolo(rolo);

        await _roloRepository.update(ghost.toRolo());

        ghostedCount++;
        spaceSaved += ghost.bytesSaved.clamp(0, 10000);
      }
    }

    return OptimizationStats(
      originalRoloCount: allRolos.length,
      ghostedCount: ghostedCount,
      spaceSavedBytes: spaceSaved,
      duration: DateTime.now().difference(startTime),
    );
  }

  /// Checks if a Rolo can be ghosted.
  bool _canGhost(Rolo rolo, DateTime cutoffDate) {
    // Don't ghost recent Rolos
    if (rolo.timestamp.isAfter(cutoffDate)) return false;

    // Don't ghost already-ghosted Rolos
    if (rolo.summoningText.startsWith('[GHOST]')) return false;

    // Only ghost long texts
    if (rolo.summoningText.length < minTextLength) return false;

    // Don't ghost synthesis Rolos (they're already summarized)
    if (rolo.type == RoloType.synthesis) return false;

    return true;
  }

  /// Checks if a Rolo is a Ghost record.
  bool isGhost(Rolo rolo) {
    return rolo.summoningText.startsWith('[GHOST]');
  }

  /// Gets the count of Ghost records.
  Future<int> getGhostCount() async {
    final rolos = await _roloRepository.search('[GHOST]');
    return rolos.length;
  }

  /// Gets database statistics.
  Future<Map<String, dynamic>> getDatabaseStats() async {
    final allRolos = await _roloRepository.getRecent(limit: 100000);
    final ghostCount = allRolos.where((r) => isGhost(r)).length;

    var totalTextLength = 0;
    for (final rolo in allRolos) {
      totalTextLength += rolo.summoningText.length;
    }

    return {
      'total_rolos': allRolos.length,
      'ghost_rolos': ghostCount,
      'regular_rolos': allRolos.length - ghostCount,
      'total_text_bytes': totalTextLength,
      'average_text_length': allRolos.isNotEmpty
          ? (totalTextLength / allRolos.length).round()
          : 0,
    };
  }
}
