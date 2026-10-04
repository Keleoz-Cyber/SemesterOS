import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../ui/campus_theme.dart';

/// Presentation only. Model text cannot load external media or execute links;
/// navigation and mutations remain on the app's verified result cards.
class AgentAnswer extends StatelessWidget {
  final String text;
  const AgentAnswer(this.text, {super.key});
  @override
  Widget build(BuildContext context) => MarkdownBody(
    data: text,
    selectable: true,
    imageBuilder: (_, _, alt) => Text(alt?.isNotEmpty == true ? alt! : '图片'),
    styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
      p: const TextStyle(fontSize: 16, height: 1.5, color: CampusColors.ink),
      strong: const TextStyle(
        fontWeight: FontWeight.w800,
        color: CampusColors.primary,
      ),
      a: const TextStyle(color: CampusColors.primary),
      h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      blockSpacing: 8,
      listIndent: 18,
    ),
  );
}
