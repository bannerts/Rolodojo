/// A stored Sensei response tied to an input Rolo.
///
/// Rows are stored in `tbl_sensei` so assistant output history is persisted
/// independently from the input ledger text.
class SenseiResponse {
  /// Unique row identifier.
  final String id;

  /// Source input rolo id (`tbl_rolos.rolo_id`).
  final String inputRoloId;

  /// Target URI inferred from the input, if available.
  final String? targetUri;

  /// Final message returned to the UI.
  final String responseText;

  /// LLM provider used (llama/claude/grok/gemini/chatgpt), if known.
  final String? provider;

  /// Model used for this response, if known.
  final String? model;

  /// Confidence used for response generation/parsing.
  final double? confidenceScore;

  /// Creation timestamp (UTC).
  final DateTime createdAt;

  const SenseiResponse({
    required this.id,
    required this.inputRoloId,
    this.targetUri,
    required this.responseText,
    this.provider,
    this.model,
    this.confidenceScore,
    required this.createdAt,
  });
}
