import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/constants/dojo_theme.dart';
import '../../core/dojo_provider.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/optimization_service.dart';
import '../../core/services/sensei_llm_service.dart';

/// The Dojo settings page.
///
/// Provides access to:
/// - Backup & Restore
/// - Security settings
/// - About information
class SettingsPage extends StatefulWidget {
  /// Optional BackupService for real operations.
  final BackupService? backupService;

  const SettingsPage({
    super.key,
    this.backupService,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final BiometricService _biometricService = BiometricService();
  bool _biometricsAvailable = false;
  bool _isExporting = false;
  bool _isImporting = false;
  bool _isCheckingLlm = false;
  bool _isSwitchingLlmProvider = false;
  SenseiLlmService? _senseiLlm;
  LlmProvider _selectedProvider = LlmProvider.localLlama;
  LlmHealthStatus _llmHealthStatus = const LlmHealthStatus();

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindLlmService();
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
    _selectedProvider = _senseiLlm!.currentProvider;
    _llmHealthStatus = _senseiLlm!.healthStatus.value;

    if (_llmHealthStatus.checkedAt == null) {
      unawaited(_refreshLlmHealth());
    }
  }

  void _handleLlmHealthChanged() {
    final next = _senseiLlm?.healthStatus.value;
    if (!mounted || next == null) return;
    setState(() {
      _selectedProvider = _senseiLlm?.currentProvider ?? _selectedProvider;
      _llmHealthStatus = next;
    });
  }

  Future<void> _checkBiometrics() async {
    final available = await _biometricService.isAvailable();
    if (mounted) {
      setState(() {
        _biometricsAvailable = available;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DojoColors.slate,
      appBar: AppBar(
        backgroundColor: DojoColors.slate,
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(DojoDimens.paddingMedium),
        children: [
          // Backup & Restore Section
          _buildSectionHeader('Backup & Restore'),
          _buildSettingsCard([
            _buildSettingsTile(
              icon: Icons.cloud_upload_outlined,
              title: 'Export Backup',
              subtitle: 'Save your Dojo data as an encrypted .dojo file',
              trailing: _isExporting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DojoColors.senseiGold,
                      ),
                    )
                  : const Icon(Icons.chevron_right, color: DojoColors.textHint),
              onTap: _isExporting ? null : _handleExport,
            ),
            const Divider(color: DojoColors.border, height: 1),
            _buildSettingsTile(
              icon: Icons.cloud_download_outlined,
              title: 'Import Backup',
              subtitle: 'Restore from a .dojo backup file',
              trailing: _isImporting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DojoColors.senseiGold,
                      ),
                    )
                  : const Icon(Icons.chevron_right, color: DojoColors.textHint),
              onTap: _isImporting ? null : _handleImport,
            ),
          ]),

          const SizedBox(height: DojoDimens.paddingMedium),

          // Security Section
          _buildSectionHeader('Security'),
          _buildSettingsCard([
            _buildSettingsTile(
              icon: Icons.fingerprint,
              title: 'Biometric Lock',
              subtitle: _biometricsAvailable
                  ? 'Require Face ID or Fingerprint to access'
                  : 'Not available on this device',
              trailing: Switch(
                value: _biometricsAvailable,
                onChanged: _biometricsAvailable
                    ? (value) {
                        // TODO: Toggle biometric requirement
                        _showSnackBar('Biometric lock is always enabled');
                      }
                    : null,
                activeColor: DojoColors.senseiGold,
              ),
            ),
            const Divider(color: DojoColors.border, height: 1),
            _buildSettingsTile(
              icon: Icons.lock_outline,
              title: 'Encryption',
              subtitle: 'AES-256 via SQLCipher',
              trailing: const Icon(
                Icons.check_circle,
                color: DojoColors.success,
              ),
            ),
          ]),

          const SizedBox(height: DojoDimens.paddingMedium),

          // LLM Provider Section
          _buildSectionHeader('LLM Provider'),
          _buildSettingsCard([
            _buildSettingsTile(
              icon: Icons.hub_outlined,
              title: 'Provider',
              subtitle: _selectedProvider.label,
              trailing: _isSwitchingLlmProvider
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DojoColors.senseiGold,
                      ),
                    )
                  : const Icon(Icons.chevron_right, color: DojoColors.textHint),
              onTap: _isSwitchingLlmProvider ? null : _showLlmProviderPicker,
            ),
            const Divider(color: DojoColors.border, height: 1),
            _buildSettingsTile(
              icon: _llmHealthStatus.isHealthy
                  ? Icons.check_circle
                  : Icons.warning_amber_rounded,
              title: 'Connection Health',
              subtitle: _providerHealthMessage(),
              trailing: _isCheckingLlm
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DojoColors.senseiGold,
                      ),
                    )
                  : TextButton(
                      onPressed: _refreshLlmHealth,
                      child: const Text('Check'),
                    ),
            ),
            const Divider(color: DojoColors.border, height: 1),
            _buildSettingsTile(
              icon: Icons.hub_outlined,
              title: 'Endpoint',
              subtitle: _senseiLlm?.baseUrl ?? 'Not configured',
              trailing: null,
            ),
            const Divider(color: DojoColors.border, height: 1),
            _buildSettingsTile(
              icon: Icons.smart_toy_outlined,
              title: 'Model',
              subtitle: _senseiLlm == null
                  ? 'Not configured'
                  : 'active: ${_senseiLlm!.activeModelName} / configured: '
                      '${_senseiLlm!.configuredModelName}',
              trailing: null,
            ),
            const Divider(color: DojoColors.border, height: 1),
            _buildSettingsTile(
              icon: Icons.vpn_key_outlined,
              title: 'Credentials',
              subtitle: _providerCredentialStatus(),
              trailing: null,
            ),
          ]),

          const SizedBox(height: DojoDimens.paddingMedium),

          // Data Section
          _buildSectionHeader('Data Management'),
          _buildSettingsCard([
            _buildSettingsTile(
              icon: Icons.auto_awesome,
              title: 'Sensei Synthesis',
              subtitle: 'AI-suggested attributes from your data',
              trailing:
                  const Icon(Icons.chevron_right, color: DojoColors.textHint),
              onTap: () => _showSynthesisInfo(),
            ),
            const Divider(color: DojoColors.border, height: 1),
            _buildSettingsTile(
              icon: Icons.cleaning_services_outlined,
              title: 'Optimize Database',
              subtitle: 'Create Ghost records for old data',
              trailing:
                  const Icon(Icons.chevron_right, color: DojoColors.textHint),
              onTap: () => _showOptimizationDialog(),
            ),
          ]),

          const SizedBox(height: DojoDimens.paddingMedium),

          // About Section
          _buildSectionHeader('About'),
          _buildSettingsCard([
            _buildSettingsTile(
              icon: Icons.info_outline,
              title: 'ROLODOJO',
              subtitle: 'Version 1.0.0',
              trailing: null,
            ),
            const Divider(color: DojoColors.border, height: 1),
            _buildSettingsTile(
              icon: Icons.article_outlined,
              title: 'Privacy Policy',
              subtitle: 'Local-first with optional cloud LLMs',
              trailing:
                  const Icon(Icons.chevron_right, color: DojoColors.textHint),
              onTap: () => _showPrivacyInfo(),
            ),
          ]),

          const SizedBox(height: DojoDimens.paddingLarge),

          // Footer
          Center(
            child: Column(
              children: [
                const Text(
                  '🥋',
                  style: TextStyle(fontSize: 32),
                ),
                const SizedBox(height: 8),
                Text(
                  'The Dojo is your sanctuary',
                  style: TextStyle(
                    color: DojoColors.textHint.withOpacity(0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: DojoDimens.paddingLarge),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(
        left: DojoDimens.paddingSmall,
        bottom: DojoDimens.paddingSmall,
      ),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          color: DojoColors.textHint,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: DojoColors.graphite,
        borderRadius: BorderRadius.circular(DojoDimens.cardRadius),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: DojoColors.slate,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: DojoColors.senseiGold, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(color: DojoColors.textPrimary),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: DojoColors.textHint, fontSize: 12),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }

  void _handleExport() async {
    setState(() => _isExporting = true);

    if (widget.backupService != null) {
      try {
        final result = await widget.backupService!.exportBackup(
          directory: '/tmp',
        );
        if (mounted) {
          setState(() => _isExporting = false);
          if (result.success) {
            final meta = result.metadata!;
            _showSnackBar(
              'Exported ${meta.totalItems} items to ${result.filePath}',
            );
          } else {
            _showSnackBar('Export failed: ${result.error}');
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isExporting = false);
          _showSnackBar('Export error: $e');
        }
      }
    } else {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() => _isExporting = false);
        _showSnackBar('Backup exported successfully (demo mode)');
      }
    }
  }

  void _handleImport() async {
    setState(() => _isImporting = true);

    // In production, use file_picker to select a .dojo file
    // For now, show a message since we can't pick files without the package
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _isImporting = false);
      _showSnackBar('Import requires file_picker package for file selection');
    }
  }

  void _showSynthesisInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DojoColors.graphite,
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: DojoColors.senseiGold),
            SizedBox(width: 8),
            Text(
              'Sensei Synthesis',
              style: TextStyle(color: DojoColors.textPrimary),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The Sensei analyzes your Rolo patterns to suggest new attributes.',
              style: TextStyle(color: DojoColors.textSecondary),
            ),
            SizedBox(height: 16),
            Text(
              'Pattern Detection:',
              style: TextStyle(
                color: DojoColors.senseiGold,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '• Frequently mentioned contacts\n'
              '• Co-occurring URIs\n'
              '• Unextracted key-value pairs\n'
              '• Relationship suggestions',
              style: TextStyle(color: DojoColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  String _providerHealthMessage() {
    if (_senseiLlm == null) {
      return 'LLM service not configured';
    }
    if (_llmHealthStatus.checkedAt == null) {
      return 'Checking ${_selectedProvider.label} health...';
    }
    if (_llmHealthStatus.provider != _selectedProvider) {
      return 'Switching to ${_selectedProvider.label}...';
    }
    return _llmHealthStatus.message;
  }

  String _providerCredentialStatus() {
    if (_selectedProvider.isLocal) {
      return 'No API key required for local provider';
    }
    if (_llmHealthStatus.provider == _selectedProvider &&
        _llmHealthStatus.apiKeyConfigured) {
      return 'API key detected via ${_selectedProvider.apiKeyEnvVar}';
    }
    return 'Missing API key. Set ${_selectedProvider.apiKeyEnvVar}.';
  }

  void _showLlmProviderPicker() {
    if (_senseiLlm == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: DojoColors.graphite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DojoDimens.cardRadius),
        ),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                DojoDimens.paddingMedium,
                DojoDimens.paddingMedium,
                DojoDimens.paddingMedium,
                DojoDimens.paddingSmall,
              ),
              child: Row(
                children: [
                  Icon(Icons.hub_outlined, color: DojoColors.senseiGold),
                  SizedBox(width: 8),
                  Text(
                    'Select LLM Provider',
                    style: TextStyle(
                      color: DojoColors.textPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            ..._senseiLlm!.supportedProviders.map(
              (provider) => ListTile(
                leading: Icon(
                  provider.isLocal ? Icons.memory_outlined : Icons.cloud_outlined,
                  color: provider == _selectedProvider
                      ? DojoColors.senseiGold
                      : DojoColors.textHint,
                ),
                title: Text(
                  provider.label,
                  style: const TextStyle(color: DojoColors.textPrimary),
                ),
                subtitle: Text(
                  provider.isLocal ? 'Local endpoint' : 'Online API',
                  style: const TextStyle(color: DojoColors.textHint, fontSize: 12),
                ),
                trailing: provider == _selectedProvider
                    ? const Icon(Icons.check_circle, color: DojoColors.success)
                    : null,
                onTap: () {
                  Navigator.of(context).pop();
                  _switchProvider(provider);
                },
              ),
            ),
            const SizedBox(height: DojoDimens.paddingSmall),
          ],
        ),
      ),
    );
  }

  Future<void> _switchProvider(LlmProvider provider) async {
    if (_senseiLlm == null ||
        _isSwitchingLlmProvider ||
        provider == _selectedProvider) {
      return;
    }

    setState(() {
      _isSwitchingLlmProvider = true;
      _selectedProvider = provider;
    });

    try {
      await _senseiLlm!.selectProvider(provider);
      await _senseiLlm!.checkHealth(force: true);
    } finally {
      if (mounted) {
        setState(() {
          _isSwitchingLlmProvider = false;
        });
      }
    }
  }

  Future<void> _refreshLlmHealth() async {
    if (_isCheckingLlm || _senseiLlm == null) {
      return;
    }
    setState(() {
      _isCheckingLlm = true;
    });
    try {
      await _senseiLlm!.checkHealth(force: true);
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingLlm = false;
        });
      }
    }
  }

  void _showOptimizationDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DojoColors.graphite,
        title: const Row(
          children: [
            Icon(Icons.cleaning_services_outlined, color: DojoColors.senseiGold),
            SizedBox(width: 8),
            Text(
              'Ghost Records',
              style: TextStyle(color: DojoColors.textPrimary),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ghost records compress old Rolos to keep the database lightweight.',
              style: TextStyle(color: DojoColors.textSecondary),
            ),
            SizedBox(height: 16),
            Text(
              'How it works:',
              style: TextStyle(
                color: DojoColors.senseiGold,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '• Rolos older than 90 days are summarized\n'
              '• Original text is removed\n'
              '• Audit trail is preserved\n'
              '• Reduces database size by ~60%',
              style: TextStyle(color: DojoColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Capture provider before popping the dialog (context becomes invalid after pop)
              final provider = DojoProvider.of(this.context);
              Navigator.pop(context);
              try {
                final optimizationService = OptimizationService(
                  roloRepository: provider.roloRepository,
                );
                final stats = await optimizationService.optimize();
                if (mounted) {
                  _showSnackBar(
                    'Ghosted ${stats.ghostedCount} Rolos, '
                    'saved ${stats.spaceSavedFormatted}',
                  );
                }
              } catch (e) {
                if (mounted) {
                  _showSnackBar('Optimization failed: $e');
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: DojoColors.senseiGold,
              foregroundColor: DojoColors.slate,
            ),
            child: const Text('Optimize'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DojoColors.graphite,
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: DojoColors.success),
            SizedBox(width: 8),
            Text(
              'Privacy Modes',
              style: TextStyle(color: DojoColors.textPrimary),
            ),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Local mode keeps all inference on-device. Online LLM modes are optional and send only request payloads to your selected provider.',
              style: TextStyle(color: DojoColors.textSecondary),
            ),
            SizedBox(height: 16),
            Text(
              '✓ Local SQLCipher encryption (AES-256)\n'
              '✓ Keys stored in Secure Storage\n'
              '✓ Local Llama by default\n'
              '✓ Optional Claude/Grok/Gemini/ChatGPT provider routing\n'
              '✓ No analytics or telemetry\n'
              '✓ Open-source audit trail',
              style: TextStyle(color: DojoColors.success, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: DojoColors.graphite,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}
