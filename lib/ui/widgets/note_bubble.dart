import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/src/rust/storage.dart';

/// Material 3 Expressive message bubble for both local and remote notes.
///
/// On Desktop (Windows/macOS/Linux), right-clicking opens a cursor-anchored
/// context menu. On Mobile (Android/iOS), right-click listeners are idle in favor
/// of swipe gestures. Long-press menus are completely removed across all platforms.
class NoteBubble extends StatelessWidget {
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

  const NoteBubble({
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

  bool get _isDesktop =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final date = DateTime.fromMillisecondsSinceEpoch(note.timestampMs.toInt());
    final timeStr = DateFormat('h:mm a').format(date);

    // M3 Expressive Bubble BorderRadius
    final borderRadius = isLocalUser
        ? BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft: const Radius.circular(22),
            bottomRight: Radius.circular(isGrouped ? 12 : 4),
          )
        : BorderRadius.only(
            topLeft: Radius.circular(isGrouped ? 12 : 4),
            topRight: const Radius.circular(22),
            bottomLeft: const Radius.circular(22),
            bottomRight: const Radius.circular(22),
          );

    // Container Colors
    final containerColor = note.isPinned
        ? colorScheme.secondaryContainer
        : isLocalUser
            ? colorScheme.primaryContainer
            : colorScheme.surfaceContainerHighest;

    final textColor = note.isPinned
        ? colorScheme.onSecondaryContainer
        : isLocalUser
            ? colorScheme.onPrimaryContainer
            : colorScheme.onSurface;

    final metaColor = (note.isPinned
            ? colorScheme.onSecondaryContainer
            : isLocalUser
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant)
        .withValues(alpha: 0.7);

    final cleanContent = _getDisplayContent(note.content, note.isTodo);

    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = (screenWidth * 0.78).clamp(240.0, 580.0);

    final bubbleBody = Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment:
            isLocalUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sender Header for Incoming Messages
          if (!isLocalUser &&
              showSenderHeader &&
              senderName != null &&
              senderName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 5.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_rounded,
                    size: 13,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    senderName!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),

          // Room / Pin / Tags Badges
          if (showRoomTag || note.isPinned || note.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment:
                    isLocalUser ? WrapAlignment.end : WrapAlignment.start,
                children: [
                  if (showRoomTag)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '#${note.roomId}',
                        style: TextStyle(
                          fontSize: 10,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (note.isPinned)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accentAmber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.push_pin,
                              size: 10, color: AppTheme.accentAmber),
                          SizedBox(width: 3),
                          Text(
                            'PINNED',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accentAmber,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ...note.tags.map((tag) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '#$tag',
                          style: TextStyle(
                            fontSize: 10,
                            color: textColor.withValues(alpha: 0.8),
                          ),
                        ),
                      )),
                ],
              ),
            ),

          // Message Body (Todo or Normal Text)
          if (note.isTodo)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => onToggleTodo?.call(!note.isCompleted),
                  child: Container(
                    width: 20,
                    height: 20,
                    margin: const EdgeInsets.only(top: 2, right: 10),
                    decoration: BoxDecoration(
                      color: note.isCompleted
                          ? colorScheme.tertiary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: note.isCompleted
                            ? colorScheme.tertiary
                            : textColor.withValues(alpha: 0.6),
                        width: 1.8,
                      ),
                    ),
                    child: note.isCompleted
                        ? Icon(Icons.check,
                            size: 14, color: colorScheme.onTertiary)
                        : null,
                  ),
                ),
                Expanded(
                  child: Text(
                    cleanContent,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: note.isCompleted
                          ? textColor.withValues(alpha: 0.5)
                          : textColor,
                      decoration: note.isCompleted
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: textColor.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            )
          else
            Align(
              alignment:
                  isLocalUser ? Alignment.centerRight : Alignment.centerLeft,
              child: Text(
                note.content,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.4,
                  color: textColor,
                ),
              ),
            ),

          const SizedBox(height: 4),

          // Inline Timestamp & Encryption Badge
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 11,
                  color: metaColor,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.lock_rounded,
                size: 11,
                color: metaColor,
              ),
            ],
          ),
        ],
      ),
    );

    // If Desktop: Wrap in GestureDetector with onSecondaryTapDown for native cursor context menu
    final interactiveBubble = _isDesktop
        ? GestureDetector(
            onSecondaryTapDown: (details) =>
                _showDesktopContextMenu(context, details.globalPosition),
            child: bubbleBody,
          )
        : bubbleBody;

    return Align(
      alignment: isLocalUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 90.0,
          maxWidth: maxBubbleWidth,
        ),
        child: interactiveBubble,
      ),
    );
  }

  void _showDesktopContextMenu(BuildContext context, Offset globalPosition) {
    final colorScheme = Theme.of(context).colorScheme;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: colorScheme.surfaceContainerHigh,
      elevation: 6,
      items: [
        PopupMenuItem(
          value: 'pin',
          child: _MenuLabelWithIcon(
            icon: note.isPinned
                ? Icons.push_pin_outlined
                : Icons.push_pin_rounded,
            label: note.isPinned ? 'Unpin Note' : 'Pin Note to Top',
            iconColor: AppTheme.accentAmber,
          ),
        ),
        const PopupMenuItem(
          value: 'copy',
          child: _MenuLabelWithIcon(
            icon: Icons.content_copy_rounded,
            label: 'Copy Text',
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: _MenuLabelWithIcon(
            icon: Icons.edit_outlined,
            label: 'Edit Note',
            iconColor: colorScheme.primary,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'delete',
          child: _MenuLabelWithIcon(
            icon: Icons.delete_outline_rounded,
            label: 'Delete Note',
            isError: true,
            iconColor: colorScheme.error,
          ),
        ),
      ],
    ).then((action) {
      if (action == null || !context.mounted) return;
      if (action == 'pin') {
        onTogglePin?.call(!note.isPinned);
      } else if (action == 'copy') {
        Clipboard.setData(ClipboardData(text: note.content));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Note copied to clipboard'),
            duration: Duration(seconds: 2),
          ),
        );
      } else if (action == 'edit') {
        _showEditDialog(context);
      } else if (action == 'delete') {
        onDelete?.call();
      }
    });
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: note.content);
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
                onEdit?.call(newText);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _getDisplayContent(String text, bool isTodo) {
    if (!isTodo) return text;
    var trimmed = text.trim();
    if (trimmed.startsWith('[ ] ') ||
        trimmed.startsWith('[x] ') ||
        trimmed.startsWith('[X] ')) {
      return trimmed.substring(4);
    }
    if (trimmed.startsWith('- [ ] ') ||
        trimmed.startsWith('- [x] ') ||
        trimmed.startsWith('- [X] ')) {
      return trimmed.substring(6);
    }
    if (trimmed.startsWith('[ ]') ||
        trimmed.startsWith('[x] ') ||
        trimmed.startsWith('[X]')) {
      return trimmed.substring(3);
    }
    return text;
  }
}

class _MenuLabelWithIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isError;
  final Color? iconColor;

  const _MenuLabelWithIcon({
    required this.icon,
    required this.label,
    this.isError = false,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color =
        isError ? colorScheme.error : (iconColor ?? colorScheme.onSurface);

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
            color: isError ? colorScheme.error : colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
