import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/services/vault_service.dart';
import 'package:notetosms/src/rust/storage.dart';

class JoinThreadDialog extends StatefulWidget {
  final String? initialInviteData;
  final Function(RoomItem) onRoomJoined;

  const JoinThreadDialog({
    super.key,
    this.initialInviteData,
    required this.onRoomJoined,
  });

  static Future<void> show(
    BuildContext context, {
    String? initialInviteData,
    required Function(RoomItem) onRoomJoined,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => JoinThreadDialog(
        initialInviteData: initialInviteData,
        onRoomJoined: onRoomJoined,
      ),
    );
  }

  @override
  State<JoinThreadDialog> createState() => _JoinThreadDialogState();
}

class _JoinThreadDialogState extends State<JoinThreadDialog> {
  late final TextEditingController _controller;
  RoomInvite? _parsedInvite;
  bool _isParsing = false;
  bool _isJoining = false;
  String? _parseError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialInviteData ?? '');
    _controller.addListener(_onTextChanged);
    if (_controller.text.isNotEmpty) {
      _tryParseInvite(_controller.text);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() {
        _parsedInvite = null;
        _parseError = null;
      });
      return;
    }
    _tryParseInvite(text);
  }

  Future<void> _tryParseInvite(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    setState(() {
      _isParsing = true;
      _parseError = null;
    });

    try {
      final invite = await VaultService.instance.parseRoomInvite(trimmed);
      if (mounted) {
        setState(() {
          _parsedInvite = invite;
          _isParsing = false;
          _parseError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _parsedInvite = null;
          _isParsing = false;
          _parseError = trimmed.length > 20
              ? 'Could not parse invite token. Please verify format.'
              : null;
        });
      }
    }
  }

  Future<void> _handleJoin() async {
    final input = _controller.text.trim();
    if (input.isEmpty) return;

    setState(() => _isJoining = true);

    try {
      RoomItem room;
      try {
        room = await VaultService.instance.importRoomInvite(input);
      } catch (_) {
        // Try P2P join as fallback
        room = await VaultService.instance.joinRoomByInvite(input);
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onRoomJoined(room);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully joined thread #${room.name}!'),
            backgroundColor: AppTheme.tertiary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isJoining = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join thread: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
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

  void _showCameraScanner() {
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
                    const Text(
                      'Scan Invite QR Code',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
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
                        _controller.text = code;
                        break;
                      }
                    }
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Point camera at the QR code displayed on the peer device',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      backgroundColor: colorScheme.surfaceContainerHigh,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.group_add_rounded, color: colorScheme.primary, size: 24),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Join Shared Thread',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste a thread invite code or deep link to import and synchronize encrypted notes.',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13, height: 1.35),
            ),
            const SizedBox(height: 16),

            // Token input field
            TextField(
              controller: _controller,
              maxLines: 3,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText: 'notetosms://join?data=... or raw invite token',
                suffixIcon: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.paste_rounded, size: 20),
                      tooltip: 'Paste from Clipboard',
                      onPressed: () async {
                        final data = await Clipboard.getData(Clipboard.kTextPlain);
                        if (data?.text != null) {
                          _controller.text = data!.text!.trim();
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // QR scanner button
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                minimumSize: const Size(double.infinity, 42),
              ),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
              label: const Text('Scan QR Code with Camera'),
              onPressed: _showCameraScanner,
            ),

            if (_isParsing) ...[
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 10),
                  Text('Inspecting invite...', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ],

            if (_parseError != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _parseError!,
                        style: TextStyle(fontSize: 11.5, color: colorScheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Preview Card
            if (_parsedInvite != null) ...[
              const SizedBox(height: 16),
              Text(
                'Thread Preview',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colorScheme.primary),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.tertiary.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Color(_parsedInvite!.color).withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getIconData(_parsedInvite!.icon),
                        color: Color(_parsedInvite!.color),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '#${_parsedInvite!.name}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Created ${DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(_parsedInvite!.createdAt.toInt()))}',
                            style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.lock_rounded, size: 12, color: AppTheme.tertiary),
                              const SizedBox(width: 4),
                              Text(
                                'End-to-End Encrypted',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.tertiary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isJoining ? null : () => Navigator.pop(context),
          child: Text('Cancel', style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          ),
          onPressed: _isJoining || _controller.text.trim().isEmpty ? null : _handleJoin,
          icon: _isJoining
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(_isJoining ? 'Joining...' : 'Join Channel'),
        ),
      ],
    );
  }
}
