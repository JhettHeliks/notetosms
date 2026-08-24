import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:notetosms/services/vault_service.dart';
import 'package:notetosms/src/rust/storage.dart';
import 'package:qr_flutter/qr_flutter.dart';

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
  // P2P Room Sharing & Joining Dialogs
  // -------------------------------------------------------------------------

  static Future<void> showShareRoomDialog(BuildContext context, RoomItem room) async {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return FutureBuilder<String>(
          future: VaultService.instance.generateRoomInvite(
            roomId: room.id,
            roomName: room.name,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AlertDialog(
                content: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text('Generating encrypted P2P invite ticket...',
                          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                    ],
                  ),
                ),
              );
            }

            if (snapshot.hasError) {
              return AlertDialog(
                title: const Text('Invite Error'),
                content: Text('Failed to generate P2P invite: ${snapshot.error}'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    child: const Text('Close'),
                  ),
                ],
              );
            }

            final inviteUri = snapshot.data ?? '';

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Color(room.color).withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.qr_code_2_rounded, color: Color(room.color), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Share #${room.name}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('End-to-End Encrypted P2P',
                            style: TextStyle(color: colorScheme.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: inviteUri,
                        version: QrVersions.auto,
                        size: 200.0,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Scan this QR code from another device with notetosms, or copy the invite code below to establish a direct QUIC peer connection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              inviteUri,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            tooltip: 'Copy Invite Link',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: inviteUri));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('P2P invite link copied to clipboard!'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                FilledButton.tonal(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  static Future<void> showJoinRoomDialog(
    BuildContext context, {
    required Function(RoomItem) onRoomJoined,
  }) async {
    final inviteController = TextEditingController();
    final colorScheme = Theme.of(context).colorScheme;
    bool isJoining = false;

    await showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: Row(
              children: [
                Icon(Icons.group_add_rounded, color: colorScheme.primary, size: 24),
                const SizedBox(width: 10),
                const Text('Join Shared Thread'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Paste a P2P invite code or scan a QR code from your peer to sync notes in real-time.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: inviteController,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'notetosms://invite?data=... or raw invite token',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste_rounded),
                        tooltip: 'Paste from Clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData(Clipboard.kTextPlain);
                          if (data?.text != null) {
                            inviteController.text = data!.text!.trim();
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      minimumSize: const Size(double.infinity, 44),
                    ),
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                    label: const Text('Scan QR Code with Camera'),
                    onPressed: () {
                      _showCameraScanner(context, (scannedCode) {
                        inviteController.text = scannedCode;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isJoining ? null : () => Navigator.pop(dialogCtx),
                child: Text('Cancel', style: TextStyle(color: colorScheme.onSurfaceVariant)),
              ),
              FilledButton(
                onPressed: isJoining
                    ? null
                    : () async {
                        final payload = inviteController.text.trim();
                        if (payload.isEmpty) return;

                        setState(() => isJoining = true);
                        try {
                          final room = await VaultService.instance.joinRoomByInvite(payload);
                          if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                          onRoomJoined(room);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Successfully joined shared thread #${room.name}!'),
                                backgroundColor: Colors.green.shade700,
                              ),
                            );
                          }
                        } catch (e) {
                          setState(() => isJoining = false);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to join room: $e'),
                                backgroundColor: Colors.red.shade700,
                              ),
                            );
                          }
                        }
                      },
                child: isJoining
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Join Thread'),
              ),
            ],
          );
        },
      ),
    );
  }

  static void _showCameraScanner(BuildContext context, Function(String) onScanned) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (scannerCtx) {
        return SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Scan Invite QR Code',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(scannerCtx),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: MobileScanner(
                  onDetect: (capture) {
                    final barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      if (barcode.rawValue != null) {
                        final code = barcode.rawValue!;
                        Navigator.pop(scannerCtx);
                        onScanned(code);
                        break;
                      }
                    }
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Point camera at the QR code displayed on the other device',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ],
          ),
        );
      },
    );
  }
}
