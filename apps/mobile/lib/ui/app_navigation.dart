import 'app_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'campus_theme.dart';
import 'assistant_scope.dart';
import 'package:forui/forui.dart';
import 'forui_theme.dart';

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
      decoration: const BoxDecoration(
        color: CampusColors.surface,
        border: Border(top: BorderSide(color: CampusColors.line)),
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
                  Semantics(
                    excludeSemantics: true,
                    button: true,
                    selected: selected == i,
                    label: labels[i],
                    onTap: () {
                      if (selected != i) onSelected(i);
                    },
                    child: FBottomNavigationBarItem(
                      icon: Icon(selected == i ? filled[i] : outlined[i]),
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

class AssistantDock extends StatelessWidget {
  const AssistantDock({super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
    child: Material(
      color: CampusColors.blueSoft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => AssistantScope.open(context),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit_note_rounded,
                        size: 24,
                        color: CampusColors.primary,
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '输入通知或日程问题',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: CampusColors.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AppIconButton(
            tooltip: '图片通知',
            onPressed: () => AssistantScope.open(context, mediaKind: 'image'),
            icon: const Icon(
              Icons.add_photo_alternate_outlined,
              size: 22,
              color: CampusColors.muted,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: AppIconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: CampusColors.teal,
                foregroundColor: Colors.white,
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
