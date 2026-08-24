import 'package:flutter/material.dart';
import 'package:notetosms/services/vault_service.dart';
import 'package:notetosms/src/rust/storage.dart';
import 'package:notetosms/ui/dialogs/join_thread_dialog.dart';
import 'package:notetosms/ui/dialogs/share_thread_dialog.dart';

class RoomDialogs {
  static Future<void> showCreateRoom(BuildContext context, VoidCallback onCreated) async {
    final nameController = TextEditingController();
    String selectedIcon = 'chat_bubble';
    int selectedColor = 0xFF1A73E8;

    final icons = [
      {'id': 'chat_bubble', 'icon': Icons.chat_bubble_outline},
      {'id': 'lock', 'icon': Icons.lock_outline},
      {'id': 'lightbulb', 'icon': Icons.lightbulb_outline},
      {'id': 'work', 'icon': Icons.work_outline},
      {'id': 'code', 'icon': Icons.code},
      {'id': 'star', 'icon': Icons.star_outline},
      {'id': 'fitness', 'icon': Icons.fitness_center},
    ];

    final colors = [
      0xFF1A73E8, // Google Blue
      0xFF6DD58C, // Emerald
      0xFFFFBA28, // Amber
      0xFFF2B8B5, // Rose
      0xFF7CDEF8, // Cyan
      0xFFA8C7FA, // Light Blue
      0xFFD0BCFF, // Purple
    ];

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setState) {
          final colorScheme = Theme.of(ctx).colorScheme;

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.add_circle_outline, color: colorScheme.primary, size: 24),
                const SizedBox(width: 10),
                const Text('Create Channel'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Channel Name',
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    style: TextStyle(color: colorScheme.onSurface),
                    decoration: const InputDecoration(
                      hintText: 'e.g. project-x, journal, finance',
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Choose Icon',
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: icons.map((item) {
                        final id = item['id'] as String;
                        final icon = item['icon'] as IconData;
                        final isSelected = selectedIcon == id;
                        return GestureDetector(
                          onTap: () => setState(() => selectedIcon = id),
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colorScheme.primary.withValues(alpha: 0.2)
                                  : colorScheme.surfaceContainerHighest,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? colorScheme.primary : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              icon,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                              size: 18,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text('Choose Color',
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 10),
                  Row(
                    children: colors.map((col) {
                      final isSelected = selectedColor == col;
                      return GestureDetector(
                        onTap: () => setState(() => selectedColor = col),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Color(col),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? Colors.white : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text('Cancel', style: TextStyle(color: colorScheme.onSurfaceVariant)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  final id = name.toLowerCase().replaceAll(RegExp(r'\s+'), '-');
                  try {
                    await VaultService.instance.createRoom(
                      id: id,
                      name: name,
                      icon: selectedIcon,
                      color: selectedColor,
                    );
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    onCreated();
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to create room: $e')),
                      );
                    }
                  }
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> showDeleteRoom(
    BuildContext context,
    String roomId,
    String roomName,
    VoidCallback onDeleted,
  ) async {
    if (roomId == 'general') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The default #general channel cannot be deleted.')),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        final colorScheme = Theme.of(dialogCtx).colorScheme;

        return AlertDialog(
          title: const Text('Delete Channel?'),
          content: Text(
            'Are you sure you want to delete #$roomName? All encrypted notes within this channel will be permanently removed.',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('Cancel', style: TextStyle(color: colorScheme.onSurfaceVariant)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () async {
                Navigator.pop(dialogCtx);
                try {
                  await VaultService.instance.deleteRoom(roomId);
                  onDeleted();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to delete channel: $e')),
                    );
                  }
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  // -------------------------------------------------------------------------
  // Room Sharing & Joining Dialogs
  // -------------------------------------------------------------------------

  static Future<void> showShareRoomDialog(BuildContext context, RoomItem room) async {
    return ShareThreadDialog.show(context, room);
  }

  static Future<void> showJoinRoomDialog(
    BuildContext context, {
    String? initialInviteData,
    required Function(RoomItem) onRoomJoined,
  }) async {
    return JoinThreadDialog.show(
      context,
      initialInviteData: initialInviteData,
      onRoomJoined: onRoomJoined,
    );
  }
}
