import 'package:flutter/material.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/services/vault_service.dart';
import 'package:notetosms/src/rust/storage.dart';
import 'package:notetosms/ui/dialogs/share_thread_dialog.dart';

class ThreadSettingsDialog extends StatefulWidget {
  final RoomItem room;
  final VoidCallback? onRoomUpdated;

  const ThreadSettingsDialog({
    super.key,
    required this.room,
    this.onRoomUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required RoomItem room,
    VoidCallback? onRoomUpdated,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ThreadSettingsDialog(
        room: room,
        onRoomUpdated: onRoomUpdated,
      ),
    );
  }

  @override
  State<ThreadSettingsDialog> createState() => _ThreadSettingsDialogState();
}

class _ThreadSettingsDialogState extends State<ThreadSettingsDialog> {
  late bool _isBgSyncEnabled;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _isBgSyncEnabled = widget.room.isBackgroundSyncEnabled;
  }

  Future<void> _toggleBgSync(bool value) async {
    setState(() {
      _isBgSyncEnabled = value;
      _updating = true;
    });

    try {
      await VaultService.instance.setRoomBackgroundSync(
        roomId: widget.room.id,
        enabled: value,
      );
      widget.onRoomUpdated?.call();
    } catch (e) {
      if (mounted) {
        setState(() => _isBgSyncEnabled = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update sync setting: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'lock':
        return Icons.lock_outline;
      case 'lightbulb':
        return Icons.lightbulb_outline;
      case 'work':
        return Icons.work_outline;
      case 'code':
        return Icons.code;
      case 'star':
        return Icons.star_outline;
      case 'fitness':
        return Icons.fitness_center;
      case 'rocket_launch':
        return Icons.rocket_launch_rounded;
      case 'chat_bubble':
      default:
        return Icons.chat_bubble_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final roomColor = Color(widget.room.color);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: colorScheme.surfaceContainerHigh,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: roomColor.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(_getIconData(widget.room.icon), color: roomColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${widget.room.name}',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Channel Settings & Sync',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // Background Keep-Alive Toggle Switch Container
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isBgSyncEnabled
                      ? colorScheme.primary.withValues(alpha: 0.4)
                      : colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (_isBgSyncEnabled ? colorScheme.primary : colorScheme.onSurfaceVariant)
                          .withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isBgSyncEnabled ? Icons.sync_rounded : Icons.sync_disabled_rounded,
                      color: _isBgSyncEnabled ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Background Keep-Alive',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Maintain active QUIC connection when app is minimized to receive incoming peer notes in real-time.',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _isBgSyncEnabled,
                    onChanged: _updating ? null : _toggleBgSync,
                    activeTrackColor: colorScheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Encryption & Security Badge
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: AppTheme.tertiary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'ChaCha20-Poly1305 End-to-End Encrypted',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Share Thread Action
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                ShareThreadDialog.show(context, widget.room);
              },
              icon: const Icon(Icons.qr_code_rounded, size: 18),
              label: const Text('Share Thread / Show QR Code'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.surfaceContainerHighest,
            foregroundColor: colorScheme.onSurface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
