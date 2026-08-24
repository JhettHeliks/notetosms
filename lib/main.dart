import 'package:flutter/material.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/src/rust/frb_generated.dart';
import 'package:notetosms/ui/screens/lock_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  runApp(const NoteToSmsApp());
}

class NoteToSmsApp extends StatelessWidget {
  const NoteToSmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'notetosms',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const LockScreen(),
    );
  }
}
