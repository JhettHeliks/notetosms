import 'package:flutter/material.dart';
import 'package:notetosms/ui/screens/auth_gate.dart';

/// Backward-compatible alias that delegates to [AuthGate].
class LockScreen extends StatelessWidget {
  final String? initialInviteData;

  const LockScreen({super.key, this.initialInviteData});

  @override
  Widget build(BuildContext context) {
    return AuthGate(initialInviteData: initialInviteData);
  }
}
