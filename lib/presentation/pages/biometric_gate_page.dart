import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/constants/dojo_theme.dart';
import '../../core/services/biometric_service.dart';

/// The biometric authentication gate.
///
/// From ROLODOJO_UX_UI.md:
/// "Biometric Gate: A blurred overlay screen that only clears upon
/// successful FaceID/Fingerprint authentication."
class BiometricGatePage extends StatefulWidget {
  /// Called when authentication is successful.
  final VoidCallback onAuthenticated;

  /// Called when the user wants to skip (for development/testing only).
  final VoidCallback? onSkip;

  /// Whether to show skip option (should be false in production).
  final bool allowSkip;

  const BiometricGatePage({
    super.key,
    required this.onAuthenticated,
    this.onSkip,
    this.allowSkip = false,
  });

  @override
  State<BiometricGatePage> createState() => _BiometricGatePageState();
}

class _BiometricGatePageState extends State<BiometricGatePage>
    with SingleTickerProviderStateMixin {
  final BiometricService _biometricService = BiometricService();
  BiometricResult? _lastResult;
  bool _isAuthenticating = false;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Trigger authentication on first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _authenticate();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
      _lastResult = null;
    });

    final result = await _biometricService.authenticate(
      reason: 'Authenticate to enter the Dojo',
    );

    if (!mounted) return;

    setState(() {
      _isAuthenticating = false;
      _lastResult = result;
    });

    if (result == BiometricResult.success) {
      widget.onAuthenticated();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DojoColors.slate,
      body: Stack(
        children: [
          // Blurred background effect
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: DojoColors.slate.withOpacity(0.9),
              ),
            ),
          ),

          // Content
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(DojoDimens.paddingLarge),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Dojo logo/icon
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: DojoColors.graphite,
                              border: Border.all(
                                color: DojoColors.senseiGold.withOpacity(0.5),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: DojoColors.senseiGold.withOpacity(0.2),
                                  blurRadius: 20,
                                  spreadRadius: 5,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                '🥋',
                                style: TextStyle(fontSize: 48),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    // Title
                    const Text(
                      'ROLODOJO',
                      style: TextStyle(
                        color: DojoColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'The Dojo is locked',
                      style: TextStyle(
                        color: DojoColors.textSecondary.withOpacity(0.7),
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(height: 48),

                    // Status message
                    if (_lastResult != null &&
                        _lastResult != BiometricResult.success)
                      Container(
                        padding: const EdgeInsets.all(DojoDimens.paddingMedium),
                        margin:
                            const EdgeInsets.only(bottom: DojoDimens.paddingMedium),
                        decoration: BoxDecoration(
                          color: _lastResult == BiometricResult.failed
                              ? DojoColors.alert.withOpacity(0.1)
                              : DojoColors.graphite,
                          borderRadius:
                              BorderRadius.circular(DojoDimens.cardRadius),
                          border: Border.all(
                            color: _lastResult == BiometricResult.failed
                                ? DojoColors.alert.withOpacity(0.3)
                                : DojoColors.border,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _lastResult == BiometricResult.failed
                                  ? Icons.error_outline
                                  : Icons.info_outline,
                              color: _lastResult == BiometricResult.failed
                                  ? DojoColors.alert
                                  : DojoColors.textSecondary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                _biometricService.getResultMessage(_lastResult!),
                                style: TextStyle(
                                  color: _lastResult == BiometricResult.failed
                                      ? DojoColors.alert
                                      : DojoColors.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Authenticate button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isAuthenticating ? null : _authenticate,
                        icon: _isAuthenticating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: DojoColors.slate,
                                ),
                              )
                            : const Icon(Icons.fingerprint, size: 24),
                        label: Text(
                          _isAuthenticating ? 'Authenticating...' : 'Enter the Dojo',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DojoColors.senseiGold,
                          foregroundColor: DojoColors.slate,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(DojoDimens.cardRadius),
                          ),
                        ),
                      ),
                    ),

                    // Skip button (development only)
                    if (widget.allowSkip && widget.onSkip != null) ...[
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: widget.onSkip,
                        child: const Text(
                          'Skip (Dev Mode)',
                          style: TextStyle(
                            color: DojoColors.textHint,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
