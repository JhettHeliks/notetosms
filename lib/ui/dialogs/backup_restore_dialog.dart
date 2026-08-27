import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/services/vault_service.dart';

class BackupRestoreDialog {
  static Future<void> show(BuildContext context, {VoidCallback? onRestoreComplete}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: const Duration(milliseconds: 350),
        reverseDuration: const Duration(milliseconds: 280),
      ),
      builder: (bottomSheetCtx) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: _BackupRestoreSheet(onRestoreComplete: onRestoreComplete),
        );
      },
    );
  }
}

class _BackupRestoreSheet extends StatefulWidget {
  final VoidCallback? onRestoreComplete;

  const _BackupRestoreSheet({this.onRestoreComplete});

  @override
  State<_BackupRestoreSheet> createState() => _BackupRestoreSheetState();
}

class _BackupRestoreSheetState extends State<_BackupRestoreSheet> {
  bool _isLoading = false;
  String _statusMessage = '';

  String _formatTimestamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }

  Future<void> _exportEncryptedBackup() async {
    setState(() {
      _isLoading = true;
      _statusMessage = 'Creating encrypted vault snapshot...';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = 'notetosms_backup_${_formatTimestamp()}.vault';
      final filePath = '${tempDir.path}${Platform.pathSeparator}$fileName';

      await VaultService.instance.exportEncryptedBackup(destinationPath: filePath);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });

      final xFile = XFile(filePath, name: fileName, mimeType: 'application/octet-stream');
      await Share.shareXFiles(
        [xFile],
        subject: 'notetosms Encrypted Vault Backup',
        text: 'Encrypted backup for notetosms vault ($fileName)',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppTheme.tertiary, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Encrypted vault exported: $fileName')),
              ],
            ),
            backgroundColor: AppTheme.surfaceContainerHigh,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export encrypted backup: $e'),
          backgroundColor: AppTheme.accentRose,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _exportPlaintextBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.accentAmber, size: 24),
            SizedBox(width: 10),
            Text('Export Plaintext?'),
          ],
        ),
        content: const Text(
          'Plaintext backups store all note contents in clear readable JSON format without encryption.\n\n'
          'Anyone with access to this file can read your private notes. Are you sure you want to export unencrypted data?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.accentAmber),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Export Unencrypted', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Exporting plaintext JSON notes...';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final fileName = 'notetosms_notes_${_formatTimestamp()}.json';
      final filePath = '${tempDir.path}${Platform.pathSeparator}$fileName';

      await VaultService.instance.exportUnencryptedBackup(destinationPath: filePath);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });

      final xFile = XFile(filePath, name: fileName, mimeType: 'application/json');
      await Share.shareXFiles(
        [xFile],
        subject: 'notetosms Plaintext Notes Backup',
        text: 'Unencrypted JSON notes backup ($fileName)',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_outline, color: AppTheme.tertiary, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Plaintext notes exported: $fileName')),
              ],
            ),
            backgroundColor: AppTheme.surfaceContainerHigh,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to export plaintext backup: $e'),
          backgroundColor: AppTheme.accentRose,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _restoreBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty || result.files.single.path == null) {
        return;
      }

      final sourcePath = result.files.single.path!;
      final isJson = sourcePath.toLowerCase().endsWith('.json');

      String? passphrase;
      if (!isJson) {
        passphrase = await _showPassphrasePrompt();
      }

      setState(() {
        _isLoading = true;
        _statusMessage = 'Restoring and decrypting backup records...';
      });

      await VaultService.instance.importBackup(
        sourcePath: sourcePath,
        passphrase: passphrase != null && passphrase.trim().isNotEmpty ? passphrase : null,
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });

      widget.onRestoreComplete?.call();
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: AppTheme.tertiary, size: 22),
              SizedBox(width: 10),
              Expanded(child: Text('Backup restored successfully!')),
            ],
          ),
          backgroundColor: AppTheme.surfaceContainerHigh,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _statusMessage = '';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Restore failed: $e'),
          backgroundColor: AppTheme.accentRose,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<String?> _showPassphrasePrompt() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_rounded, color: AppTheme.primary, size: 24),
            SizedBox(width: 10),
            Text('Backup Passphrase'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the master passphrase used when this backup was created.\n\nLeave blank if it uses the same master passphrase as your current vault.',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Backup passphrase (optional)',
                prefixIcon: Icon(Icons.key_rounded, size: 20),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surfaceContainerLow,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: AppTheme.border, width: 0.5),
        ),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.backup_rounded, color: AppTheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Text(
                'Backup & Restore',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Export your encrypted database or plaintext notes, or restore from an existing backup file.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),
          if (_isLoading) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border, width: 0.5),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ] else ...[
            _buildOptionTile(
              icon: Icons.shield_rounded,
              iconColor: AppTheme.primary,
              title: 'Export Encrypted Backup',
              subtitle: 'Full ChaCha20 + Argon2 encrypted vault snapshot (.vault)',
              onTap: _exportEncryptedBackup,
            ),
            const SizedBox(height: 12),
            _buildOptionTile(
              icon: Icons.code_rounded,
              iconColor: AppTheme.accentAmber,
              title: 'Export Plaintext Backup',
              subtitle: 'Unencrypted JSON format for external tools or migration (.json)',
              badgeText: 'Plaintext',
              badgeColor: AppTheme.accentAmber,
              onTap: _exportPlaintextBackup,
            ),
            const SizedBox(height: 12),
            _buildOptionTile(
              icon: Icons.settings_backup_restore_rounded,
              iconColor: AppTheme.secondary,
              title: 'Restore from Backup',
              subtitle: 'Merge rooms and notes from a .vault or .json backup file',
              onTap: _restoreBackup,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOptionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? badgeText,
    Color? badgeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border, width: 0.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (badgeText != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (badgeColor ?? AppTheme.primary).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: (badgeColor ?? AppTheme.primary).withValues(alpha: 0.4),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            badgeText,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: badgeColor ?? AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
