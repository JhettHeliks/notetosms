import 'package:flutter/material.dart';
import 'package:notetosms/src/rust/storage.dart';
import 'package:notetosms/ui/widgets/swipeable_note_bubble.dart';

/// Legacy alias for [SwipeableNoteBubble] to maintain full compatibility across views.
class ChatBubble extends StatelessWidget {
  final NoteItem note;
  final bool showRoomTag;
  final bool isPreviousInCluster;
  final bool isNextInCluster;
  final bool isLocal;
  final String? senderName;
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
    this.isLocal = true,
    this.senderName,
    required this.onToggleTodo,
    required this.onTogglePin,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return SwipeableNoteBubble(
      note: note,
      isLocalUser: isLocal,
      senderName: senderName,
      showSenderHeader: !isPreviousInCluster,
      isGrouped: isNextInCluster || isPreviousInCluster,
      showRoomTag: showRoomTag,
      onToggleTodo: onToggleTodo,
      onTogglePin: onTogglePin,
      onEdit: onEdit,
      onDelete: onDelete,
    );
  }
}
