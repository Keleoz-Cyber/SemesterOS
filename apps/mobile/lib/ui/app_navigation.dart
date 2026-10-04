import 'app_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'assistant_scope.dart';
import 'package:forui/forui.dart';
import 'forui_theme.dart';
import 'accessibility.dart';
import 'motion.dart';

class AppNavigation extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  const AppNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  static const labels = ['今日', '日程', '计划', '学期'];
  static const outlined = [
    Icons.today_outlined,
    Icons.calendar_view_week_outlined,
    Icons.checklist_rounded,
    Icons.auto_stories_outlined,
  ];
  static const filled = [
    Icons.today_rounded,
    Icons.calendar_view_week_rounded,
    Icons.checklist_rounded,
    Icons.auto_stories_rounded,
  ];
  @override
  Widget build(BuildContext context) => ShiriForuiTheme(
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AssistantDock(),
            FBottomNavigationBar(
              index: selected,
              onChange: (value) {
                if (selected != value) {
                  HapticFeedback.selectionClick();
                  onSelected(value);
                }
              },
              children: [
                for (var i = 0; i < labels.length; i++)
                  SemanticTab(
                    index: i,
                    total: labels.length,
                    childHandlesInput: true,
                    // Replace this one native tab's duplicate label/count only.
                    // Its keyboard and pointer handlers remain in the F item.
                    replaceNativeSemantics: true,
                    selected: selected == i,
                    label: labels[i],
                    onTap: () {
                      if (selected != i) onSelected(i);
                    },
                    child: FBottomNavigationBarItem(
                      icon: _NavigationGlyph(
                        selected: selected == i,
                        outlined: outlined[i],
                        filled: filled[i],
                      ),
                      label: Text(labels[i]),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _NavigationGlyph extends StatelessWidget {
  final bool selected;
  final IconData outlined, filled;
  const _NavigationGlyph({
    required this.selected,
    required this.outlined,
    required this.filled,
  });
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 24,
    child: AnimatedSwitcher(
      key: ValueKey(AppMotion.reduced(context)),
      duration: AppMotion.feedback(context),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: animation.drive(
            Tween(begin: const Offset(0, .08), end: Offset.zero),
          ),
          child: child,
        ),
      ),
      child: Icon(
        selected ? filled : outlined,
        key: ValueKey(selected),
        size: 24,
      ),
    ),
  );
}

class AssistantDock extends StatelessWidget {
  const AssistantDock({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
    child: Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: SemanticButton(
              key: const Key('assistant-dock-input'),
              label: '输入通知或日程问题',
              onPressed: () => AssistantScope.open(context),
              childHandlesInput: true,
              child: InkWell(
                onTap: () => AssistantScope.open(context),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.edit_note_rounded,
                          size: 24,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final style = TextStyle(
                                fontSize: 14,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              );
                              String caption = '记录';
                              for (final value in const [
                                '输入通知或日程问题',
                                '输入通知',
                                '记录',
                              ]) {
                                final text = TextPainter(
                                  text: TextSpan(text: value, style: style),
                                  textDirection: Directionality.of(context),
                                  textScaler: MediaQuery.textScalerOf(context),
                                )..layout();
                                final fits = text.width <= constraints.maxWidth;
                                text.dispose();
                                if (fits) {
                                  caption = value;
                                  break;
                                }
                              }
                              return ExcludeSemantics(
                                child: Text(caption, style: style, maxLines: 1),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          AppIconButton(
            tooltip: '图片通知',
            onPressed: () => AssistantScope.open(context, mediaKind: 'image'),
            icon: Icon(
              Icons.add_photo_alternate_outlined,
              size: 22,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: AppIconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Theme.of(context).colorScheme.onSecondary,
              ),
              tooltip: '语音输入',
              onPressed: () => AssistantScope.open(context, mediaKind: 'audio'),
              icon: const Icon(Icons.mic_none_rounded, size: 22),
            ),
          ),
        ],
      ),
    ),
  );
}
