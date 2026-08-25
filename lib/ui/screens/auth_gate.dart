import 'package:flutter/material.dart';
import 'package:notetosms/services/vault_service.dart';
import 'package:notetosms/ui/screens/create_vault_screen.dart';
import 'package:notetosms/ui/screens/unlock_vault_screen.dart';

class AuthGate extends StatefulWidget {
  final String? initialInviteData;

  const AuthGate({super.key, this.initialInviteData});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isChecking = true;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _checkVault();
  }

  Future<void> _checkVault() async {
    try {
      final isInit = await VaultService.instance.isVaultInitialized();
      if (mounted) {
        setState(() {
          _isInitialized = isInit;
          _isChecking = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _isChecking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      final colorScheme = Theme.of(context).colorScheme;
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: colorScheme.primary,
          ),
        ),
      );
    }

    if (_isInitialized) {
      return UnlockVaultScreen(initialInviteData: widget.initialInviteData);
    } else {
      return CreateVaultScreen(initialInviteData: widget.initialInviteData);
    }
  }
}
