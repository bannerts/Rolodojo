import 'package:flutter/material.dart';
import '../../core/constants/dojo_theme.dart';

/// The state of the Sensei's processing activity.
enum SenseiState {
  /// Idle, waiting for input
  idle,

  /// Processing user input
  thinking,

  /// Synthesis complete, ready to confirm
  synthesis,
}

/// A persistent, floating bottom-bar for user input.
///
/// The Sensei Bar is the primary interaction point for the Dojo.
/// It contains a text input field and a "Pulse" icon that indicates
/// the current state of the Sensei's processing.
class SenseiBar extends StatefulWidget {
  /// Callback when the user submits input.
  final ValueChanged<String>? onSubmit;

  /// Current state of the Sensei.
  final SenseiState state;

  /// Hint text for the input field.
  final String hintText;

  const SenseiBar({
    super.key,
    this.onSubmit,
    this.state = SenseiState.idle,
    this.hintText = 'Summon the Sensei...',
  });

  @override
  State<SenseiBar> createState() => _SenseiBarState();
}

class _SenseiBarState extends State<SenseiBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(SenseiBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePulseAnimation();
  }

  void _updatePulseAnimation() {
    if (widget.state == SenseiState.thinking) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
      _pulseController.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final text = _controller.text.trim();
    if (text.isNotEmpty && widget.onSubmit != null) {
      widget.onSubmit!(text);
      _controller.clear();
    }
  }

  Color _getPulseColor() {
    switch (widget.state) {
      case SenseiState.idle:
        return DojoColors.textHint;
      case SenseiState.thinking:
        return DojoColors.senseiGold;
      case SenseiState.synthesis:
        return DojoColors.success;
    }
  }

  IconData _getPulseIcon() {
    switch (widget.state) {
      case SenseiState.idle:
        return Icons.radio_button_unchecked;
      case SenseiState.thinking:
        return Icons.brightness_1;
      case SenseiState.synthesis:
        return Icons.check_circle;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DojoDimens.paddingMedium,
        vertical: DojoDimens.paddingSmall,
      ),
      decoration: const BoxDecoration(
        color: DojoColors.slate,
        border: Border(
          top: BorderSide(color: DojoColors.border, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Pulse Icon
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: widget.state == SenseiState.thinking
                      ? _pulseAnimation.value
                      : 1.0,
                  child: Icon(
                    _getPulseIcon(),
                    color: _getPulseColor(),
                    size: DojoDimens.iconMedium,
                  ),
                );
              },
            ),
            const SizedBox(width: DojoDimens.paddingSmall),

            // Text Input
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                style: const TextStyle(color: DojoColors.textPrimary),
                decoration: InputDecoration(
                  hintText: widget.hintText,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: DojoDimens.paddingMedium,
                    vertical: DojoDimens.paddingSmall,
                  ),
                  isDense: true,
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _handleSubmit(),
              ),
            ),
            const SizedBox(width: DojoDimens.paddingSmall),

            // Submit Button
            IconButton(
              onPressed: _handleSubmit,
              icon: const Icon(Icons.send_rounded),
              color: DojoColors.senseiGold,
              tooltip: 'Submit',
            ),
          ],
        ),
      ),
    );
  }
}
