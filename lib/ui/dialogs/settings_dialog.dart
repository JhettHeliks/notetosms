import 'package:flutter/material.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/services/vault_service.dart';

class SettingsDialog {
  static Future<void> showChangePassphrase(BuildContext context) async {
    final oldPassController = TextEditingController();
    final newPassController = TextEditingController();
    final confirmPassController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        final colorScheme = Theme.of(dialogCtx).colorScheme;

        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.key, color: AppTheme.accentAmber, size: 24),
              SizedBox(width: 10),
              Text('Change Passphrase'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Derives a new Argon2id key, generates a fresh random salt, and re-encrypts all notes atomically.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: oldPassController,
                  obscureText: true,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: const InputDecoration(
                    hintText: 'Current passphrase',
                    prefixIcon: Icon(Icons.lock_outline, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newPassController,
                  obscureText: true,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: const InputDecoration(
                    hintText: 'New master passphrase',
                    prefixIcon: Icon(Icons.vpn_key_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPassController,
                  obscureText: true,
                  style: TextStyle(color: colorScheme.onSurface),
                  decoration: const InputDecoration(
                    hintText: 'Confirm new passphrase',
                    prefixIcon: Icon(Icons.check_circle_outline, size: 20),
                  ),
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
                final oldPass = oldPassController.text;
                final newPass = newPassController.text;
                final confirmPass = confirmPassController.text;

                if (newPass.isEmpty) {
                  if (dialogCtx.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('New passphrase cannot be empty')),
                    );
                  }
                  return;
                }
                if (newPass != confirmPass) {
                  if (dialogCtx.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('New passphrases do not match')),
                    );
                  }
                  return;
                }

                try {
                  await VaultService.instance.changePassphrase(
                    oldPass: oldPass,
                    newPass: newPass,
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Vault re-encrypted successfully with new passphrase!'),
                        backgroundColor: colorScheme.tertiary,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Passphrase change failed: $e')),
                    );
                  }
                }
              },
              child: const Text('Re-encrypt Vault'),
            ),
          ],
        );
      },
    );
  }

  static Future<void> showSecurityInfo(BuildContext context) async {
    final dbPath = await VaultService.instance.getDatabasePath();

    if (!context.mounted) return;

    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.security, color: colorScheme.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Security & Architecture',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        'Zero-knowledge local encryption',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildSecurityItem(
                context: ctx,
                title: 'Key Derivation',
                desc: 'Argon2id (64MB memory, 3 iterations, 16-byte random salt)',
                icon: Icons.shield,
              ),
              _buildSecurityItem(
                context: ctx,
                title: 'Payload AEAD Cipher',
                desc: 'ChaCha20-Poly1305 with unique 96-bit random nonces per note',
                icon: Icons.lock,
              ),
              _buildSecurityItem(
                context: ctx,
                title: 'Memory Protection',
                desc: 'zeroize wipes derived keys & plaintext buffers from RAM on lock/drop',
                icon: Icons.memory,
              ),
              _buildSecurityItem(
                context: ctx,
                title: 'Search Index',
                desc: 'In-memory FTS5 search (zero unencrypted text leaked to disk)',
                icon: Icons.search,
              ),
              _buildSecurityItem(
                context: ctx,
                title: 'Storage Path',
                desc: dbPath,
                icon: Icons.folder_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _buildSecurityItem({
    required BuildContext context,
    required String title,
    required String desc,
    required IconData icon,
  }) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
