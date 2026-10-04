import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';

/// Source text is a document to read, rather than another status card.
class NoticePaper extends StatelessWidget {
  final String title, text;
  const NoticePaper({super.key, required this.title, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
    decoration: BoxDecoration(
      color: CampusColors.surface,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: CampusColors.line),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(
              Icons.subject_rounded,
              size: 18,
              color: CampusColors.teal,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  color: CampusColors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const Divider(height: 24, color: CampusColors.line),
        SelectableText(
          text,
          style: const TextStyle(
            fontSize: 16,
            height: 1.65,
            color: CampusColors.ink,
          ),
        ),
      ],
    ),
  );
}
