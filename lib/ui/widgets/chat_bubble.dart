import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/src/rust/storage.dart';

class ChatBubble extends StatelessWidget {
  final NoteItem note;
  final bool showRoomTag;
  final bool isPreviousInCluster;
  final bool isNextInCluster;
  final Function(bool isCompleted) onToggleTodo;
  final Function(bool isPinned) onTogglePin;
  final Function(String newContent) onEdit;
  final VoidCallback onDelete;

  const ChatBubble({
    super.key,
    required this.note,
    this.showRoomTag = false,
    this.isPreviousInCluster = false,
    this.isNextInCluster = false,
    required this.onToggleTodo,
    required this.onTogglePin,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final date = DateTime.fromMillisecondsSinceEpoch(note.timestampMs.toInt());
    final timeStr = DateFormat('h:mm a').format(date);

    final cleanContent = _getDisplayContent(note.content, note.isTodo);

    final bubbleRadius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: Radius.circular(isPreviousInCluster ? 6 : 20),
      bottomLeft: const Radius.circular(20),
      bottomRight: Radius.circular(isNextInCluster ? 6 : 4),
    );

    final bubbleColor = note.isPinned
        ? colorScheme.secondaryContainer
        : colorScheme.primaryContainer;

    final textColor = note.isPinned
        ? colorScheme.onSecondaryContainer
        : colorScheme.onPrimaryContainer;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = (screenWidth * 0.75).clamp(240.0, 560.0);

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: EdgeInsets.only(
          bottom: isNextInCluster ? 2.5 : 10.0,
          left: 48.0,
        ),
        constraints: BoxConstraints(
          minWidth: 85.0,
          maxWidth: maxBubbleWidth,
        ),
        child: Material(
          color: bubbleColor,
          borderRadius: bubbleRadius,
          child: InkWell(
            borderRadius: bubbleRadius,
            onLongPress: () => _showContextMenu(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showRoomTag || note.isPinned || note.tags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (showRoomTag)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.accentAmber.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.push_pin, size: 10, color: AppTheme.accentAmber),
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
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
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
                  if (note.isTodo)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => onToggleTodo(!note.isCompleted),
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
                                ? Icon(Icons.check, size: 14, color: colorScheme.onTertiary)
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
                              decoration:
                                  note.isCompleted ? TextDecoration.lineThrough : null,
                              decorationColor: textColor.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(
                      note.content,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: textColor,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 11,
                            color: textColor.withValues(alpha: 0.65),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.lock,
                          size: 11,
                          color: textColor.withValues(alpha: 0.65),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getDisplayContent(String text, bool isTodo) {
    if (!isTodo) return text;
    var trimmed = text.trim();
    if (trimmed.startsWith('[ ] ') || trimmed.startsWith('[x] ') || trimmed.startsWith('[X] ')) {
      return trimmed.substring(4);
    }
    if (trimmed.startsWith('- [ ] ') || trimmed.startsWith('- [x] ') || trimmed.startsWith('- [X] ')) {
      return trimmed.substring(6);
    }
    if (trimmed.startsWith('[ ]') || trimmed.startsWith('[x] ') || trimmed.startsWith('[X]')) {
      return trimmed.substring(3);
    }
    return text;
  }

  void _showContextMenu(BuildContext context) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (bottomSheetCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: Icon(
                  note.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                  color: AppTheme.accentAmber,
                ),
                title: Text(note.isPinned ? 'Unpin Note' : 'Pin Note to Top'),
                onTap: () {
                  Navigator.pop(bottomSheetCtx);
                  onTogglePin(!note.isPinned);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppTheme.primary),
                title: const Text('Edit Note'),
                onTap: () {
                  Navigator.pop(bottomSheetCtx);
                  _showEditDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.copy_outlined, color: AppTheme.textSecondary),
                title: const Text('Copy to Clipboard'),
                onTap: () {
                  Navigator.pop(bottomSheetCtx);
                  Clipboard.setData(ClipboardData(text: note.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Note copied to clipboard')),
                  );
                },
              ),
              const Divider(color: AppTheme.border),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppTheme.accentRose),
                title: const Text('Delete Note', style: TextStyle(color: AppTheme.accentRose)),
                onTap: () {
                  Navigator.pop(bottomSheetCtx);
                  onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: note.content);
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Edit Note'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          minLines: 2,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Edit your note...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: AppTheme.onPrimary,
            ),
            onPressed: () {
              final newText = controller.text.trim();
              if (newText.isNotEmpty) {
                Navigator.pop(dialogCtx);
                onEdit(newText);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
