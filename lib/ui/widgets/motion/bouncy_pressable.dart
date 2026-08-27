import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A wrapper widget that applies a spring-physics press effect to its child.
///
/// Scales down to [pressedScale] on touch-down (100ms, Curves.easeOutCubic)
/// and springs back to 1.0 on release (200ms, Curves.easeOutBack).
/// Fires HapticFeedback.lightImpact on every tap.
class BouncyPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final Duration pressDownDuration;
  final Duration releaseBackDuration;
  final bool enableHaptic;

  const BouncyPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.96,
    this.pressDownDuration = const Duration(milliseconds: 100),
    this.releaseBackDuration = const Duration(milliseconds: 200),
    this.enableHaptic = true,
  });

  @override
  State<BouncyPressable> createState() => _BouncyPressableState();
}

class _BouncyPressableState extends State<BouncyPressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // value=0 means scale=1.0 (unpressed); value=1 means scale=pressedScale
    _controller = AnimationController(
      vsync: this,
      duration: widget.pressDownDuration,
      reverseDuration: widget.releaseBackDuration,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _controller.animateTo(1.0, curve: Curves.easeOutCubic);
  }

  void _onTapUp(TapUpDetails _) {
    _onRelease();
    if (widget.enableHaptic) HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  void _onTapCancel() => _onRelease();

  void _onRelease() {
    _controller.animateBack(0.0, curve: Curves.easeOutBack);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final scale = 1.0 - (1.0 - widget.pressedScale) * _controller.value;
          return Transform.scale(scale: scale, child: child);
        },
        child: widget.child,
      ),
    );
  }
}
