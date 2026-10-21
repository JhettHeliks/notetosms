import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/src/rust/storage.dart';
import 'package:notetosms/ui/widgets/note_bubble.dart';

/// Platform-aware wrapper for message bubbles:
/// - Desktop (Windows/macOS/Linux): Directly renders [NoteBubble] with cursor-anchored
///   right-click context menus. Swiping is disabled.
/// - Mobile (Android/iOS): Interactive spring-physics swipe:
///   * Swipe Left: Reveals consolidated inline action buttons (Pin/Unpin, Copy, Edit, Delete)
///     and stays open until an action is chosen or the user taps anywhere to dismiss.
///   * Swipe Right: Disabled to avoid accidental pinning while scrolling.
///   * Zero long-press bottom sheets across all platforms.
class SwipeableNoteBubble extends StatefulWidget {
  final NoteItem note;
  final bool isLocalUser;
  final String? senderName;
  final bool showSenderHeader;
  final bool isGrouped;
  final bool showRoomTag;
  final Function(bool isCompleted)? onToggleTodo;
  final Function(bool isPinned)? onTogglePin;
  final Function(String newContent)? onEdit;
  final VoidCallback? onDelete;

  const SwipeableNoteBubble({
    super.key,
    required this.note,
    this.isLocalUser = true,
    this.senderName,
    this.showSenderHeader = true,
    this.isGrouped = false,
    this.showRoomTag = false,
    this.onToggleTodo,
    this.onTogglePin,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<SwipeableNoteBubble> createState() => _SwipeableNoteBubbleState();
}

class _SwipeableNoteBubbleState extends State<SwipeableNoteBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late Animation<double> _offsetAnimation;
  double _dragOffset = 0.0;
  static const double _actionPanelWidth = 184.0;
  bool _isOpen = false;
  bool _hapticFired = false;

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _offsetAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _animateTo(double targetOffset, {VoidCallback? onComplete}) {
    _offsetAnimation = Tween<double>(
      begin: _dragOffset,
      end: targetOffset,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    )..addListener(() {
        setState(() {
          _dragOffset = _offsetAnimation.value;
        });
      });

    _animController.forward(from: 0.0).then((_) {
      if (mounted) {
        setState(() {
          _dragOffset = targetOffset;
          _isOpen = targetOffset.abs() > 10.0;
        });
        onComplete?.call();
      }
    });
  }

  void _close() {
    if (_dragOffset != 0.0 || _isOpen) {
      _animateTo(0.0);
    }
  }

  void _openActions() {
    _animateTo(-_actionPanelWidth);
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (_animController.isAnimating) {
      _animController.stop();
    }
    _hapticFired = false;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    final delta = details.primaryDelta ?? 0.0;
    setState(() {
      // Allow swiping left; clamp right drag to slight resistance (max 10.0) that snaps back
      _dragOffset = (_dragOffset + delta).clamp(
        -_actionPanelWidth - 20.0,
        10.0,
      );
    });

    if (_dragOffset <= -_actionPanelWidth * 0.4 && !_hapticFired) {
      HapticFeedback.selectionClick();
      _hapticFired = true;
    } else if (_dragOffset > -_actionPanelWidth * 0.4 && _hapticFired) {
      _hapticFired = false;
    }
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;

    if (_dragOffset < -45.0 || velocity < -350) {
      // Swipe Left: Snap open to reveal consolidated action panel and stay open
      HapticFeedback.lightImpact();
      _openActions();
    } else {
      // Released without reaching threshold or dragged right: snap back closed
      _animateTo(0.0);
    }
  }

  void _handleHorizontalDragCancel() {
    _animateTo(0.0);
  }

  @override
  Widget build(BuildContext context) {
    // Desktop: Swiping is completely disabled. Render NoteBubble directly with right-click menu.
    if (_isDesktop) {
      return NoteBubble(
        note: widget.note,
        isLocalUser: widget.isLocalUser,
        senderName: widget.senderName,
        showSenderHeader: widget.showSenderHeader,
        isGrouped: widget.isGrouped,
        showRoomTag: widget.showRoomTag,
        onToggleTodo: widget.onToggleTodo,
        onTogglePin: widget.onTogglePin,
        onEdit: widget.onEdit,
        onDelete: widget.onDelete,
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = (screenWidth * 0.78).clamp(240.0, 580.0);

    return ClipRect(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: _handleHorizontalDragStart,
        onHorizontalDragUpdate: _handleHorizontalDragUpdate,
        onHorizontalDragEnd: _handleHorizontalDragEnd,
        onHorizontalDragCancel: _handleHorizontalDragCancel,
        onTap: () {
          if (_isOpen) {
            // Tap anywhere to dismiss/close the open action tray
            _close();
          }
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background Action Layer (Reveals consolidated actions on swipe left)
            if (_dragOffset < 0 || _isOpen)
              Positioned.fill(
                child: Align(
                  alignment: widget.isLocalUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minWidth: 90.0,
                      maxWidth: maxBubbleWidth,
                    ),
                    child: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 1. Pin / Unpin Action Button
                          _ActionButton(
                            icon: widget.note.isPinned
                                ? Icons.push_pin_outlined
                                : Icons.push_pin_rounded,
                            color: AppTheme.accentAmber,
                            tooltip: widget.note.isPinned ? 'Unpin' : 'Pin',
                            onTap: () {
                              _close();
                              HapticFeedback.selectionClick();
                              widget.onTogglePin?.call(!widget.note.isPinned);
                            },
                          ),
                          const SizedBox(width: 4),

                          // 2. Copy Action Button
                          _ActionButton(
                            icon: Icons.content_copy_rounded,
                            color: colorScheme.onSurfaceVariant,
                            tooltip: 'Copy',
                            onTap: () {
                              _close();
                              Clipboard.setData(
                                  ClipboardData(text: widget.note.content));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Note copied to clipboard'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 4),

                          // 3. Edit Action Button
                          _ActionButton(
                            icon: Icons.edit_outlined,
                            color: colorScheme.primary,
                            tooltip: 'Edit',
                            onTap: () {
                              _close();
                              _showEditDialog(context);
                            },
                          ),
                          const SizedBox(width: 4),

                          // 4. Delete Action Button
                          _ActionButton(
                            icon: Icons.delete_outline_rounded,
                            color: colorScheme.error,
                            tooltip: 'Delete',
                            onTap: () {
                              _close();
                              widget.onDelete?.call();
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // Foreground Message Bubble (Slides horizontally)
            Transform.translate(
              offset: Offset(_dragOffset, 0),
              child: NoteBubble(
                note: widget.note,
                isLocalUser: widget.isLocalUser,
                senderName: widget.senderName,
                showSenderHeader: widget.showSenderHeader,
                isGrouped: widget.isGrouped,
                showRoomTag: widget.showRoomTag,
                onToggleTodo: widget.onToggleTodo,
                onTogglePin: widget.onTogglePin,
                onEdit: widget.onEdit,
                onDelete: widget.onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: widget.note.content);
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Edit Note'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          minLines: 2,
          autofocus: true,
          style: TextStyle(color: colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Edit your note...',
            filled: true,
            fillColor: colorScheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text('Cancel',
                style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
            onPressed: () {
              final newText = controller.text.trim();
              if (newText.isNotEmpty) {
                Navigator.pop(dialogCtx);
                widget.onEdit?.call(newText);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, color: color, size: 20),
        ),
      ),
    );
  }
}
