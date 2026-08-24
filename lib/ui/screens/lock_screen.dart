import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/services/vault_service.dart';
import 'package:notetosms/ui/screens/chat_screen.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final TextEditingController _passphraseController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();

  bool _isCheckingStatus = true;
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _obscureText = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkVaultStatus();
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _checkVaultStatus() async {
    setState(() => _isCheckingStatus = true);
    try {
      final status = await VaultService.instance.getStatus();
      setState(() {
        _isInitialized = status.isInitialized;
        _isCheckingStatus = false;
      });
    } catch (e) {
      setState(() {
        _isInitialized = false;
        _isCheckingStatus = false;
      });
    }
  }

  Future<void> _handleUnlockOrSetup() async {
    final pass = _passphraseController.text;
    if (pass.isEmpty) {
      setState(() => _errorMessage = 'Please enter a passphrase.');
      return;
    }

    if (!_isInitialized) {
      final confirm = _confirmController.text;
      if (pass != confirm) {
        setState(() => _errorMessage = 'Passphrases do not match.');
        return;
      }
      if (pass.length < 6) {
        setState(() => _errorMessage = 'Passphrase must be at least 6 characters.');
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      HapticFeedback.lightImpact();
      final status = await VaultService.instance.unlockOrInit(pass);

      if (status.isUnlocked && mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const ChatScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '').replaceAll('anyhow: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isCheckingStatus) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: colorScheme.primary),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // App Logo / Vault Icon
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withValues(alpha: 0.18),
                          blurRadius: 32,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.shield_outlined,
                      size: 52,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  _isInitialized ? 'Unlock notetosms' : 'Create notetosms Vault',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isInitialized
                      ? 'Enter your passphrase to decrypt your private notes.'
                      : 'Choose a master passphrase to initialize your zero-knowledge encrypted database.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 32),

                // Error Banner
                if (_errorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accentRose.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppTheme.accentRose.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppTheme.accentRose, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              color: AppTheme.accentRose,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // Passphrase Input
                TextField(
                  controller: _passphraseController,
                  obscureText: _obscureText,
                  textInputAction:
                      _isInitialized ? TextInputAction.done : TextInputAction.next,
                  onSubmitted: (_) {
                    if (_isInitialized) _handleUnlockOrSetup();
                  },
                  style: TextStyle(color: colorScheme.onSurface, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: 'Master passphrase',
                    prefixIcon: Icon(Icons.lock_outline, size: 20, color: colorScheme.primary),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureText ? Icons.visibility_off : Icons.visibility,
                        color: colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscureText = !_obscureText),
                    ),
                  ),
                ),

                // Confirmation Input (on first setup)
                if (!_isInitialized) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmController,
                    obscureText: _obscureText,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _handleUnlockOrSetup(),
                    style: TextStyle(color: colorScheme.onSurface, fontSize: 15),
                    decoration: InputDecoration(
                      hintText: 'Confirm passphrase',
                      prefixIcon: Icon(Icons.check_circle_outline, size: 20, color: colorScheme.tertiary),
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Unlock / Setup Action Button
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    onPressed: _isLoading ? null : _handleUnlockOrSetup,
                    child: _isLoading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: colorScheme.onPrimary,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            _isInitialized ? 'Unlock notetosms' : 'Initialize notetosms Vault',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 36),

                // Security Badges Footer
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.lock, size: 14, color: colorScheme.tertiary),
                      const SizedBox(width: 6),
                      Text(
                        'Argon2id  •  ChaCha20-Poly1305  •  zeroize',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
