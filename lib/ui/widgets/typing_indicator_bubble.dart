import 'dart:math' as math;
import 'package:flutter/material.dart';

class TypingIndicatorBubble extends StatefulWidget {
  final String? label;

  const TypingIndicatorBubble({super.key, this.label});

  @override
  State<TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<TypingIndicatorBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final bubbleRadius = const BorderRadius.only(
      topLeft: Radius.circular(20),
      topRight: Radius.circular(20),
      bottomRight: Radius.circular(20),
      bottomLeft: Radius.circular(4),
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 4.0, bottom: 8.0, top: 4.0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHigh,
          borderRadius: bubbleRadius,
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.2),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildDot(0, colorScheme.primary),
                    const SizedBox(width: 5),
                    _buildDot(1, colorScheme.primary),
                    const SizedBox(width: 5),
                    _buildDot(2, colorScheme.primary),
                  ],
                );
              },
            ),
            if (widget.label != null) ...[
              const SizedBox(width: 10),
              Text(
                widget.label!,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDot(int index, Color color) {
    final delay = index * 0.2;
    final progress = (_controller.value + delay) % 1.0;
    // Bouncing oscillation curve
    final bounce = math.sin(progress * math.pi);
    final offsetY = -4.0 * math.max(0.0, bounce);
    final scale = 0.8 + 0.35 * math.max(0.0, bounce);

    return Transform.translate(
      offset: Offset(0, offsetY),
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: 7.5,
          height: 7.5,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.6 + 0.4 * math.max(0.0, bounce)),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
