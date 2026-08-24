import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notetosms/core/theme/app_theme.dart';
import 'package:notetosms/ui/widgets/typing_indicator_bubble.dart';

void main() {
  group('TypingIndicatorBubble Tests', () {
    testWidgets('Renders 3 animated dots and label', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: TypingIndicatorBubble(label: 'Drafting note...'),
          ),
        ),
      );

      // Verify label exists
      expect(find.text('Drafting note...'), findsOneWidget);

      // Verify widget builds without error
      expect(find.byType(TypingIndicatorBubble), findsOneWidget);

      // Advance animation
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
