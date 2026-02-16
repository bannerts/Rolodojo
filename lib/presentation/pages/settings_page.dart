import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/constants/dojo_theme.dart';
import '../../core/dojo_provider.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/optimization_service.dart';
import '../../core/services/sensei_llm_service.dart';
import '../../domain/entities/user_profile.dart';

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
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _preferredNameController = TextEditingController();
  final TextEditingController _timezoneController = TextEditingController();
  final TextEditingController _localeController = TextEditingController();

  bool _biometricsAvailable = false;
  bool _isExporting = false;
  bool _isImporting = false;
  bool _isCheckingLlm = false;
  bool _isSwitchingLlmProvider = false;
  bool _isSavingApiKey = false;
  bool _isSavingModel = false;
  bool _isLoadingProfile = false;
  bool _isSavingProfile = false;
  bool _profileLoaded = false;
  SenseiLlmService? _senseiLlm;
  LlmProvider _selectedProvider = LlmProvider.localLlama;
  LlmHealthStatus _llmHealthStatus = const LlmHealthStatus();
  LlmParseDebugSnapshot? _lastParseDebugSnapshot;
  Map<String, dynamic> _userProfilePayload = const {};

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindLlmService();
    if (!_profileLoaded && !_isLoadingProfile) {
      unawaited(_loadPrimaryUserProfile());
    }
  }

  @override
  void dispose() {
    _senseiLlm?.healthStatus.removeListener(_handleLlmHealthChanged);
    _senseiLlm?.parseDebugSnapshot.removeListener(_handleParseDebugChanged);
    _displayNameController.dispose();
    _preferredNameController.dispose();
    _timezoneController.dispose();
    _localeController.dispose();
    super.dispose();
  }

  void _bindLlmService() {
    final provider = DojoProvider.of(context);
    final nextService = provider.senseiLlm;
    if (identical(_senseiLlm, nextService)) {
      return;
    }

    _senseiLlm?.healthStatus.removeListener(_handleLlmHealthChanged);
    _senseiLlm?.parseDebugSnapshot.removeListener(_handleParseDebugChanged);
    _senseiLlm = nextService;
    _senseiLlm!.healthStatus.addListener(_handleLlmHealthChanged);
    _senseiLlm!.parseDebugSnapshot.addListener(_handleParseDebugChanged);
    _selectedProvider = _senseiLlm!.currentProvider;
    _llmHealthStatus = _senseiLlm!.healthStatus.value;
    _lastParseDebugSnapshot = _senseiLlm!.parseDebugSnapshot.value;

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

  void _handleParseDebugChanged() {
    final snapshot = _senseiLlm?.parseDebugSnapshot.value;
    if (!mounted) {
      return;
    }
    setState(() {
      _lastParseDebugSnapshot = snapshot;
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

          // Owner Profile Section
          _buildSectionHeader('Owner Profile'),
          _buildSettingsCard([
            Padding(
              padding: const EdgeInsets.all(DojoDimens.paddingMedium),
              child: _buildOwnerProfilePanel(),
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
                      '${_senseiLlm!.configuredModelFor(_selectedProvider)}',
              trailing: _isSavingModel
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DojoColors.senseiGold,
                      ),
                    )
                  : const Icon(Icons.chevron_right, color: DojoColors.textHint),
              onTap: _senseiLlm == null || _isSavingModel
                  ? null
                  : _showModelEditorDialog,
            ),
            const Divider(color: DojoColors.border, height: 1),
            _buildSettingsTile(
              icon: Icons.vpn_key_outlined,
              title: 'Credentials',
              subtitle: _providerCredentialStatus(),
              trailing: _selectedProvider.isLocal
                  ? null
                  : _isSavingApiKey
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: DojoColors.senseiGold,
                          ),
                        )
                      : const Icon(Icons.chevron_right, color: DojoColors.textHint),
              onTap: _selectedProvider.isLocal || _isSavingApiKey
                  ? null
                  : _showApiKeyEditorDialog,
            ),
            const Divider(color: DojoColors.border, height: 1),
            _buildSettingsTile(
              icon: Icons.bug_report_outlined,
              title: 'Prompt Context Inspector',
              subtitle: _promptInspectorSubtitle(),
              trailing:
                  const Icon(Icons.chevron_right, color: DojoColors.textHint),
              onTap: _showPromptContextInspectorDialog,
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

  Future<void> _loadPrimaryUserProfile() async {
    if (_isLoadingProfile) return;
    setState(() {
      _isLoadingProfile = true;
    });

    try {
      final dojo = DojoProvider.of(context).dojoService;
      final profile = await dojo.getPrimaryUserProfile();
      if (!mounted) return;

      final resolved = profile ??
          UserProfile(
            userId: UserProfile.primaryUserId,
            displayName: 'Dojo User',
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          );

      _displayNameController.text = resolved.displayName;
      _preferredNameController.text = resolved.preferredName ?? '';
      _timezoneController.text = resolved.profile['timezone']?.toString() ?? '';
      _localeController.text = resolved.profile['locale']?.toString() ?? '';
      _userProfilePayload = Map<String, dynamic>.from(resolved.profile);
      _profileLoaded = true;
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to load user profile: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingProfile = false;
        });
      }
    }
  }

  Future<void> _savePrimaryUserProfile() async {
    final displayName = _displayNameController.text.trim();
    final preferredName = _preferredNameController.text.trim();
    final timezone = _timezoneController.text.trim();
    final locale = _localeController.text.trim();

    if (displayName.isEmpty) {
      _showSnackBar('Display name is required');
      return;
    }

    if (_isSavingProfile) return;
    setState(() {
      _isSavingProfile = true;
    });

    try {
      final dojo = DojoProvider.of(context).dojoService;
      final mergedPayload = Map<String, dynamic>.from(_userProfilePayload);
      if (timezone.isEmpty) {
        mergedPayload.remove('timezone');
      } else {
        mergedPayload['timezone'] = timezone;
      }
      if (locale.isEmpty) {
        mergedPayload.remove('locale');
      } else {
        mergedPayload['locale'] = locale;
      }

      final updated = await dojo.upsertPrimaryUserProfile(
        displayName: displayName,
        preferredName: preferredName.isEmpty ? null : preferredName,
        profile: mergedPayload,
      );

      _userProfilePayload = Map<String, dynamic>.from(updated.profile);
      if (mounted) {
        _showSnackBar('Owner profile saved');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Failed to save profile: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSavingProfile = false;
        });
      }
    }
  }

  Widget _buildOwnerProfilePanel() {
    if (_isLoadingProfile && !_profileLoaded) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: DojoColors.senseiGold,
          ),
        ),
      );
    }

    final busy = _isLoadingProfile || _isSavingProfile;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Profile details used for Sensei context',
          style: TextStyle(color: DojoColors.textHint, fontSize: 12),
        ),
        const SizedBox(height: DojoDimens.paddingSmall),
        _buildProfileField(
          controller: _displayNameController,
          label: 'Display Name',
          hint: 'Dojo User',
          enabled: !busy,
        ),
        const SizedBox(height: DojoDimens.paddingSmall),
        _buildProfileField(
          controller: _preferredNameController,
          label: 'Preferred Name',
          hint: 'Scott',
          enabled: !busy,
        ),
        const SizedBox(height: DojoDimens.paddingSmall),
        _buildProfileField(
          controller: _timezoneController,
          label: 'Timezone',
          hint: 'America/Chicago',
          enabled: !busy,
        ),
        const SizedBox(height: DojoDimens.paddingSmall),
        _buildProfileField(
          controller: _localeController,
          label: 'Locale',
          hint: 'en_US',
          enabled: !busy,
        ),
        const SizedBox(height: DojoDimens.paddingMedium),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: busy ? null : _savePrimaryUserProfile,
            icon: _isSavingProfile
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 16),
            label: const Text('Save Profile'),
            style: ElevatedButton.styleFrom(
              backgroundColor: DojoColors.senseiGold,
              foregroundColor: DojoColors.slate,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool enabled,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      style: const TextStyle(color: DojoColors.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: DojoColors.textHint),
        hintStyle: const TextStyle(color: DojoColors.textHint),
        isDense: true,
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
    if (_senseiLlm?.isApiKeyConfigured(_selectedProvider) == true) {
      return 'API key configured (stored on this device)';
    }
    return 'Missing API key. Tap to add.';
  }

  String _promptInspectorSubtitle() {
    final snapshot = _lastParseDebugSnapshot;
    if (snapshot == null) {
      return 'No parse captured yet. Submit a summoning.';
    }

    final sentLabel = snapshot.sentToProvider ? 'sent' : 'fallback';
    final local = snapshot.timestamp.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return 'Last parse $sentLabel via ${snapshot.provider.label} at $hh:$mm:$ss';
  }

  void _showPromptContextInspectorDialog() {
    final snapshot = _lastParseDebugSnapshot;
    showDialog(
      context: context,
      builder: (dialogContext) {
        if (snapshot == null) {
          return AlertDialog(
            backgroundColor: DojoColors.graphite,
            title: const Text(
              'Prompt Context Inspector',
              style: TextStyle(color: DojoColors.textPrimary),
            ),
            content: const Text(
              'No parse context has been captured yet. Submit a summoning to populate this panel.',
              style: TextStyle(color: DojoColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        }

        final localTime = snapshot.timestamp.toLocal();
        final timestamp =
            '${localTime.year}-${localTime.month.toString().padLeft(2, '0')}-'
            '${localTime.day.toString().padLeft(2, '0')} '
            '${localTime.hour.toString().padLeft(2, '0')}:'
            '${localTime.minute.toString().padLeft(2, '0')}:'
            '${localTime.second.toString().padLeft(2, '0')}';

        Widget buildCodeBlock(String text) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(DojoDimens.paddingSmall),
            decoration: BoxDecoration(
              color: DojoColors.slate,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DojoColors.border),
            ),
            child: SelectableText(
              text,
              style: const TextStyle(
                color: DojoColors.textSecondary,
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          );
        }

        return AlertDialog(
          backgroundColor: DojoColors.graphite,
          title: const Row(
            children: [
              Icon(Icons.bug_report_outlined, color: DojoColors.senseiGold),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Prompt Context Inspector',
                  style: TextStyle(color: DojoColors.textPrimary),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Provider: ${snapshot.provider.label}',
                    style: const TextStyle(
                      color: DojoColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Model: ${snapshot.model}',
                    style: const TextStyle(color: DojoColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Captured: $timestamp',
                    style: const TextStyle(color: DojoColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sent to provider: ${snapshot.sentToProvider ? 'yes' : 'no (fallback used)'}',
                    style: TextStyle(
                      color: snapshot.sentToProvider
                          ? DojoColors.success
                          : DojoColors.alert,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Note: ${snapshot.note}',
                    style: const TextStyle(color: DojoColors.textHint, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Input',
                    style: TextStyle(
                      color: DojoColors.senseiGold,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  buildCodeBlock(snapshot.input),
                  const SizedBox(height: 12),
                  const Text(
                    'Exact Context Block Sent',
                    style: TextStyle(
                      color: DojoColors.senseiGold,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  buildCodeBlock(snapshot.contextBlock),
                  const SizedBox(height: 12),
                  const Text(
                    'Full Extraction Prompt Payload',
                    style: TextStyle(
                      color: DojoColors.senseiGold,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  buildCodeBlock(snapshot.extractionPrompt),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showApiKeyEditorDialog() async {
    final senseiLlm = _senseiLlm;
    if (senseiLlm == null || _selectedProvider.isLocal) {
      return;
    }

    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) {
        var obscure = true;
        var isSubmitting = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit({required bool clear}) async {
              final apiKey = clear ? '' : controller.text.trim();
              if (!clear && apiKey.isEmpty) {
                _showSnackBar('Enter an API key or tap Clear');
                return;
              }

              setDialogState(() {
                isSubmitting = true;
              });
              if (mounted) {
                setState(() {
                  _isSavingApiKey = true;
                });
              }

              try {
                await senseiLlm.setApiKey(_selectedProvider, apiKey);
                await senseiLlm.checkHealth(force: true);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (mounted) {
                  _showSnackBar(
                    clear
                        ? 'API key cleared for ${_selectedProvider.label}'
                        : 'API key saved for ${_selectedProvider.label}',
                  );
                }
              } catch (e) {
                if (mounted) {
                  _showSnackBar('Failed to update API key: $e');
                }
                if (dialogContext.mounted) {
                  setDialogState(() {
                    isSubmitting = false;
                  });
                }
              } finally {
                if (mounted) {
                  setState(() {
                    _isSavingApiKey = false;
                  });
                }
              }
            }

            return AlertDialog(
              backgroundColor: DojoColors.graphite,
              title: Row(
                children: [
                  const Icon(Icons.vpn_key_outlined, color: DojoColors.senseiGold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_selectedProvider.label} API Key',
                      style: const TextStyle(color: DojoColors.textPrimary),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Stored securely on this device. Existing keys are never shown.',
                    style: TextStyle(color: DojoColors.textHint, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    obscureText: obscure,
                    enabled: !isSubmitting,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(color: DojoColors.textPrimary),
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: 'Paste key for ${_selectedProvider.label}',
                      suffixIcon: IconButton(
                        onPressed: isSubmitting
                            ? null
                            : () {
                                setDialogState(() {
                                  obscure = !obscure;
                                });
                              },
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                          color: DojoColors.textHint,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: isSubmitting ? null : () => submit(clear: true),
                  child: const Text('Clear'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : () => submit(clear: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DojoColors.senseiGold,
                    foregroundColor: DojoColors.slate,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }

  Future<void> _showModelEditorDialog() async {
    final senseiLlm = _senseiLlm;
    if (senseiLlm == null) {
      return;
    }

    final currentConfigured = senseiLlm.configuredModelFor(_selectedProvider);
    final controller = TextEditingController(text: currentConfigured);
    await showDialog(
      context: context,
      builder: (dialogContext) {
        var isSubmitting = false;
        final suggestions = _llmHealthStatus.provider == _selectedProvider
            ? _llmHealthStatus.availableModels
            : const <String>[];

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit({required bool resetToDefault}) async {
              final model = resetToDefault ? '' : controller.text.trim();
              if (!resetToDefault && model.isEmpty) {
                _showSnackBar('Enter a model name or tap Reset');
                return;
              }

              setDialogState(() {
                isSubmitting = true;
              });
              if (mounted) {
                setState(() {
                  _isSavingModel = true;
                });
              }

              try {
                await senseiLlm.setConfiguredModel(_selectedProvider, model);
                await senseiLlm.checkHealth(force: true);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                if (mounted) {
                  _showSnackBar(
                    resetToDefault
                        ? 'Model reset for ${_selectedProvider.label}'
                        : 'Model updated for ${_selectedProvider.label}',
                  );
                }
              } catch (e) {
                if (mounted) {
                  _showSnackBar('Failed to update model: $e');
                }
                if (dialogContext.mounted) {
                  setDialogState(() {
                    isSubmitting = false;
                  });
                }
              } finally {
                if (mounted) {
                  setState(() {
                    _isSavingModel = false;
                  });
                }
              }
            }

            return AlertDialog(
              backgroundColor: DojoColors.graphite,
              title: Row(
                children: [
                  const Icon(Icons.smart_toy_outlined, color: DojoColors.senseiGold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_selectedProvider.label} Model',
                      style: const TextStyle(color: DojoColors.textPrimary),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose a specific model id for this provider.',
                    style: TextStyle(color: DojoColors.textHint, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    enabled: !isSubmitting,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: const TextStyle(color: DojoColors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Model ID',
                      hintText: 'e.g. gpt-4.1, claude-3-7-sonnet',
                    ),
                  ),
                  if (suggestions.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Available models detected:',
                      style: TextStyle(color: DojoColors.textHint, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: suggestions
                          .take(8)
                          .map(
                            (model) => ActionChip(
                              label: Text(model),
                              onPressed: isSubmitting
                                  ? null
                                  : () {
                                      setDialogState(() {
                                        controller.text = model;
                                      });
                                    },
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: isSubmitting ? null : () => submit(resetToDefault: true),
                  child: const Text('Reset'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting ? null : () => submit(resetToDefault: false),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DojoColors.senseiGold,
                    foregroundColor: DojoColors.slate,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
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
