import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateHeader extends StatelessWidget {
  final DateTime date;

  const DateHeader({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final noteDay = DateTime(date.year, date.month, date.day);

    String label;
    if (noteDay == today) {
      label = 'Today';
    } else if (noteDay == yesterday) {
      label = 'Yesterday';
    } else if (now.year == date.year) {
      label = DateFormat('EEE, MMM d').format(date);
    } else {
      label = DateFormat('MMM d, yyyy').format(date);
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14),
      alignment: Alignment.center,
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        elevation: 1.5,
        shadowColor: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.25),
              width: 0.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
