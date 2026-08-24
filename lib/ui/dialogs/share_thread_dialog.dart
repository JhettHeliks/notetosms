import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/services/vault_service.dart';
import 'package:notetosms/src/rust/storage.dart';
import 'package:qr_flutter/qr_flutter.dart';

class ShareThreadDialog extends StatefulWidget {
  final RoomItem room;

  const ShareThreadDialog({super.key, required this.room});

  static Future<void> show(BuildContext context, RoomItem room) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => ShareThreadDialog(room: room),
    );
  }

  @override
  State<ShareThreadDialog> createState() => _ShareThreadDialogState();
}

class _ShareThreadDialogState extends State<ShareThreadDialog> {
  late Future<String> _inviteFuture;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _inviteFuture = _loadInvite();
  }

  Future<String> _loadInvite() async {
    try {
      return await VaultService.instance.exportRoomInvite(widget.room.id);
    } catch (e) {
      // Fall back to P2P invite if export fails
      return await VaultService.instance.generateRoomInvite(
        roomId: widget.room.id,
        roomName: widget.room.name,
      );
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
    final colorScheme = Theme.of(context).colorScheme;
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
                  'Share #${widget.room.name}',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                Text(
                  'End-to-End Encrypted Thread',
                  style: TextStyle(
                    color: AppTheme.tertiary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: FutureBuilder<String>(
        future: _inviteFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: colorScheme.primary),
                  const SizedBox(height: 18),
                  Text(
                    'Generating encrypted invite token...',
                    style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, size: 40, color: colorScheme.error),
                const SizedBox(height: 12),
                Text(
                  'Could not create invite: ${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
              ],
            );
          }

          final inviteData = snapshot.data ?? '';

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // QR Code Container
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: inviteData,
                    version: QrVersions.auto,
                    size: 190.0,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Scan this QR code from another device or share the invite token below to join this encrypted thread.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5, height: 1.35),
                ),
                const SizedBox(height: 14),

                // Token display and copy container
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _copied
                          ? AppTheme.tertiary.withValues(alpha: 0.6)
                          : colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          inviteData,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: inviteData));
                          setState(() => _copied = true);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Invite token copied to clipboard!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                          Future.delayed(const Duration(seconds: 2), () {
                            if (mounted) setState(() => _copied = false);
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            _copied ? Icons.check_circle_rounded : Icons.copy_rounded,
                            size: 20,
                            color: _copied ? AppTheme.tertiary : colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 18),
                    label: Text(_copied ? 'Copied to Clipboard!' : 'Copy Invite Code'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: inviteData));
                      setState(() => _copied = true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Invite token copied to clipboard!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _copied = false);
                      });
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
