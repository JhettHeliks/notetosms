import 'package:flutter/material.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/src/rust/frb_generated.dart';
import 'package:notetosms/ui/screens/lock_screen.dart';
import 'package:notetosms/ui/views/bubble_chat_view.dart';

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
      initialRoute: '/',
      onGenerateRoute: (settings) {
        final uri = Uri.tryParse(settings.name ?? '/');

        if (uri != null) {
          // 1. Handle thread join deep links (e.g. notetosms://join?data=... or chatnotes://join?data=...)
          if (uri.scheme == 'notetosms' || uri.scheme == 'chatnotes') {
            if (uri.host == 'join' || uri.path.startsWith('/join')) {
              final rawInvite = settings.name ?? uri.toString();
              return MaterialPageRoute(
                builder: (context) => LockScreen(initialInviteData: rawInvite),
                settings: settings,
              );
            }
          }

          // 2. Handle web/relative path /join?data=...
          if (uri.path == '/join' || uri.path.startsWith('/join/')) {
            final rawInvite = settings.name ?? uri.toString();
            return MaterialPageRoute(
              builder: (context) => LockScreen(initialInviteData: rawInvite),
              settings: settings,
            );
          }

          // 3. Handle explicit bubble route (e.g. /bubble?roomId=project-x)
          if (uri.path == '/bubble' || uri.path.startsWith('/bubble/')) {
            String roomId = uri.queryParameters['roomId'] ?? 'general';
            if (uri.pathSegments.length > 1 && uri.pathSegments[0] == 'bubble') {
              roomId = uri.pathSegments[1];
            }
            return MaterialPageRoute(
              builder: (context) => BubbleChatView(roomId: roomId),
              settings: settings,
            );
          }

          // 4. Handle room deep link URI (e.g. notetosms://room/project-x or chatnotes://room/project-x)
          if (uri.scheme == 'notetosms' || uri.scheme == 'chatnotes') {
            if (uri.host == 'room' || uri.path.startsWith('/room')) {
              String roomId = 'general';
              if (uri.pathSegments.isNotEmpty) {
                roomId = uri.pathSegments.last;
              } else if (uri.queryParameters.containsKey('roomId')) {
                roomId = uri.queryParameters['roomId']!;
              }
              return MaterialPageRoute(
                builder: (context) => BubbleChatView(roomId: roomId),
                settings: settings,
              );
            }
          }

          // 5. Handle web/standard path /room/:roomId
          if (uri.path.startsWith('/room/')) {
            final roomId = uri.pathSegments.length > 1 ? uri.pathSegments[1] : 'general';
            return MaterialPageRoute(
              builder: (context) => BubbleChatView(roomId: roomId),
              settings: settings,
            );
          }
        }

        // Default initial home route
        return MaterialPageRoute(
          builder: (context) => const LockScreen(),
          settings: settings,
        );
      },
    );
  }
}
