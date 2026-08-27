import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/services/vault_service.dart';
import 'package:notetosms/src/rust/storage.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';

class ShareThreadCard extends StatefulWidget {
  final RoomItem room;
  final VoidCallback? onDismiss;

  const ShareThreadCard({
    super.key,
    required this.room,
    this.onDismiss,
  });

  @override
  State<ShareThreadCard> createState() => _ShareThreadCardState();
}

class _ShareThreadCardState extends State<ShareThreadCard>
    with SingleTickerProviderStateMixin {
  late Future<String> _inviteFuture;
  late final AnimationController _entranceController;
  late final Animation<double> _entranceScale;
  late final Animation<double> _entranceOpacity;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _entranceScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOutBack),
    );
    _entranceOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _entranceController, curve: Curves.easeOut),
    );
    _loadInviteCode();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ShareThreadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _entranceController.reset();
      _loadInviteCode();
    }
  }

  void _loadInviteCode() {
    setState(() {
      _inviteFuture = _fetchInvite();
    });
  }

  Future<String> _fetchInvite() async {
    try {
      final ticket = await VaultService.instance.exportRoomTicket(roomId: widget.room.id);
      if (ticket.isNotEmpty) return ticket;
    } catch (_) {}
    return await VaultService.instance.exportRoomInvite(widget.room.id);
  }

  void _copyToClipboard(String data) {
    Clipboard.setData(ClipboardData(text: data));
    HapticFeedback.lightImpact();
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppTheme.tertiary, size: 18),
            SizedBox(width: 10),
            Text('Invite code copied!'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _shareLink(String data) {
    HapticFeedback.lightImpact();
    Share.share(data, subject: 'Join #${widget.room.name} on notetosms');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final roomColor = Color(widget.room.color);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Header ────────────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: roomColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.qr_code_2_rounded, color: roomColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Share #${widget.room.name}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Scan to join — end-to-end encrypted',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.onDismiss != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: 'Dismiss',
                    color: colorScheme.onSurfaceVariant,
                    onPressed: widget.onDismiss,
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // ── FutureBuilder body ────────────────────────────────────────
            FutureBuilder<String>(
              future: _inviteFuture,
              builder: (context, snapshot) {
                // Loading
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            color: colorScheme.primary,
                            strokeWidth: 3,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Generating secure invite code...',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Error
                if (snapshot.hasError ||
                    !snapshot.hasData ||
                    (snapshot.data ?? '').isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 38,
                          color: AppTheme.accentRose,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Failed to generate invite code',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '${snapshot.error ?? "Unknown error"}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('Retry'),
                          onPressed: _loadInviteCode,
                        ),
                      ],
                    ),
                  );
                }

                // Success — run entrance animation once ticket is ready
                _entranceController.forward();

                final inviteData = snapshot.data!;
                final displayCode = inviteData.length > 28
                    ? '${inviteData.substring(0, 14)}...${inviteData.substring(inviteData.length - 14)}'
                    : inviteData;

                return AnimatedBuilder(
                  animation: _entranceController,
                  builder: (context, child) => FadeTransition(
                    opacity: _entranceOpacity,
                    child: ScaleTransition(
                      scale: _entranceScale,
                      child: child,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── M3 Expressive QR Plate ─────────────────────────
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withValues(alpha: 0.08),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: SizedBox(
                          width: 210,
                          height: 210,
                          child: PrettyQrView.data(
                            data: inviteData,
                            errorCorrectLevel: QrErrorCorrectLevel.M,
                            decoration: PrettyQrDecoration(
                              shape: PrettyQrSmoothSymbol(
                                color: colorScheme.primary,
                                roundFactor: 0.8,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── Invite code pill ──────────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.key_rounded,
                              size: 14,
                              color: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                displayCode,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                  letterSpacing: 0.4,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── Action buttons ────────────────────────────────
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              icon: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  _copied
                                      ? Icons.check_circle_rounded
                                      : Icons.copy_rounded,
                                  key: ValueKey(_copied),
                                  size: 17,
                                ),
                              ),
                              label: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Text(
                                  _copied ? 'Copied!' : 'Copy Code',
                                  key: ValueKey(_copied),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                              onPressed: () => _copyToClipboard(inviteData),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              icon: const Icon(Icons.share_rounded, size: 17),
                              label: const Text(
                                'Share Link',
                                style: TextStyle(fontSize: 13),
                              ),
                              onPressed: () => _shareLink(inviteData),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
