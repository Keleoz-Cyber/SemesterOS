import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'assistant_scope.dart';
import 'v2/shiri_tokens.dart';
import 'v2/widgets/glass_dock.dart';
import 'v2/widgets/performance_scope.dart';

class AppNavigation extends StatelessWidget {
  static double reserveHeight(BuildContext context) =>
      GlassDock.heightFor(context) +
      ShiriLayout.pillHeight +
      ShiriLayout.pillGapAboveDock +
      ShiriLayout.dockBottomInset +
      MediaQuery.viewPaddingOf(context).bottom;
  final VoidCallback? onAssistantOpen, onAssistantImage;
  final int selected;
  final ValueChanged<int> onSelected;
  final bool showAssistant, collapsed;
  final Widget? microphone;
  final GlobalKey? sourceKey;
  final AssistantBrowsingContext? browsingContext;
  const AppNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
    this.showAssistant = true,
    this.collapsed = false,
    this.microphone,
    this.sourceKey,
    this.browsingContext,
    this.onAssistantOpen,
    this.onAssistantImage,
  });
  static const labels = ['今日', '日程', '任务', '学期'];
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
  static const names = ['today', 'schedule', 'tasks', 'semester'];
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showAssistant) ...[
            AssistantDock(
              key: sourceKey,
              collapsed: collapsed,
              microphone: microphone,
              browsingContext: browsingContext,
              onOpen: onAssistantOpen,
              onImage: onAssistantImage,
            ),
            const SizedBox(height: ShiriLayout.pillGapAboveDock),
          ],
          GlassDock(
            index: selected,
            onSelect: onSelected,
            lowEnd: ShiriPerformance.lowEndOf(context),
            items: [
              for (var i = 0; i < labels.length; i++)
                GlassDockItem(
                  label: labels[i],
                  icon: _glyph(context, i, false),
                  selectedIcon: _glyph(context, i, true),
                ),
            ],
          ),
        ],
      ),
    ),
  );
  Widget _glyph(BuildContext context, int index, bool filled) =>
      SvgPicture.asset(
        'assets/icons/nav-${names[index]}${filled ? '-filled' : ''}.svg',
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(
          filled ? context.shiri.colors.primary : context.shiri.colors.ink500,
          BlendMode.srcIn,
        ),
        excludeFromSemantics: true,
      );
}

class AssistantDock extends StatelessWidget {
  const AssistantDock({
    super.key,
    this.collapsed = false,
    this.microphone,
    this.browsingContext,
    this.onOpen,
    this.onImage,
  });
  final VoidCallback? onOpen, onImage;
  final bool collapsed;
  final Widget? microphone;
  final AssistantBrowsingContext? browsingContext;
  @override
  Widget build(BuildContext context) => AssistantPill(
    collapsed: collapsed,
    microphone:
        microphone ??
        Tooltip(
          message: '语音输入',
          child: InkWell(
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: context.shiri.colors.focusRing.withValues(alpha: .15),
            onTap: () => AssistantScope.open(
              context,
              mediaKind: 'audio',
              browsingContext: browsingContext,
            ),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: ShiriGradients.brand,
              ),
              child: const Icon(Icons.mic_rounded, color: Color(0xFF142238)),
            ),
          ),
        ),
    lowEnd: ShiriPerformance.lowEndOf(context),
    placeholder: '输入通知或日程问题',
    onOpen:
        onOpen ??
        () => AssistantScope.open(context, browsingContext: browsingContext),
    onImage:
        onImage ??
        () => AssistantScope.open(
          context,
          mediaKind: 'image',
          browsingContext: browsingContext,
        ),
  );
}
