import 'package:flutter/material.dart';
import '../../ui/app_controls.dart';
import '../../ui/campus_theme.dart';
import '../../ui/motion.dart' show SuccessCheckmark;
import '../../ui/app_loading.dart';
import 'agent_motion.dart';

/// Animate a receipt only when this visible turn has just been saved. Loading
/// history, reopening the assistant and recycling offscreen rows stay static.
class AgentTurnFeedback extends StatefulWidget {
  final String status;
  final Widget child;
  const AgentTurnFeedback({
    super.key,
    required this.status,
    required this.child,
  });
  @override
  State<AgentTurnFeedback> createState() => _AgentTurnFeedbackState();
}

class _AgentTurnFeedbackState extends State<AgentTurnFeedback> {
  bool newlySaved = false;
  @override
  void didUpdateWidget(covariant AgentTurnFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != 'applied' && widget.status == 'applied') {
      newlySaved = true;
    } else if (widget.status != 'applied') {
      newlySaved = false;
    }
  }

  @override
  Widget build(BuildContext context) =>
      _ReceiptMotion(animate: newlySaved, child: widget.child);
}

class _ReceiptMotion extends InheritedWidget {
  final bool animate;
  const _ReceiptMotion({required this.animate, required super.child});
  @override
  bool updateShouldNotify(_ReceiptMotion oldWidget) =>
      animate != oldWidget.animate;
}

class AssistantWelcome extends StatelessWidget {
  final ValueChanged<String> onPrompt;
  final List<(String, String, IconData)> choices;
  const AssistantWelcome({
    super.key,
    required this.onPrompt,
    this.choices = const [
      ('今天的安排', '我今天有哪些安排？', Icons.today_outlined),
      ('本周空闲', '这周哪天有一小时空闲？', Icons.schedule_rounded),
    ],
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.edit_note_rounded,
              size: 26,
              color: CampusColors.primary,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '粘贴通知，或直接提问',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const Text(
          '快捷查询',
          style: TextStyle(fontSize: 12, color: CampusColors.muted),
        ),
        const SizedBox(height: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final choice in choices)
              AppTile(
                leading: Icon(choice.$3, size: 20, color: CampusColors.primary),
                title: Text(choice.$1, style: const TextStyle(fontSize: 15)),
                trailing: const Icon(
                  Icons.north_east_rounded,
                  size: 18,
                  color: CampusColors.muted,
                ),
                onTap: () => onPrompt(choice.$2),
              ),
          ],
        ),
      ],
    ),
  );
}

class AssistantUserMessage extends StatefulWidget {
  final String text;
  final String? attachment;
  final VoidCallback? onEdit, onSource;
  const AssistantUserMessage({
    super.key,
    required this.text,
    this.attachment,
    this.onEdit,
    this.onSource,
  });
  @override
  State<AssistantUserMessage> createState() => _AssistantUserMessageState();
}

class _AssistantUserMessageState extends State<AssistantUserMessage> {
  bool expanded = false;
  bool get longMessage =>
      widget.text.runes.length > 180 || widget.text.split('\n').length > 5;
  @override
  void didUpdateWidget(covariant AssistantUserMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) expanded = false;
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .86,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Material(
            color: CampusColors.blueSoft,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18),
              topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18),
              bottomRight: Radius.circular(6),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (longMessage && !expanded)
                    Text(
                      widget.text,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, height: 1.45),
                    )
                  else
                    SelectableText(
                      widget.text,
                      style: const TextStyle(fontSize: 16, height: 1.45),
                    ),
                  if (longMessage)
                    AppTextButton(
                      onPressed: () => setState(() => expanded = !expanded),
                      child: Text(
                        expanded ? '收起' : '展开消息',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (widget.attachment != null || widget.onEdit != null)
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                if (widget.attachment != null)
                  AppTextButton.icon(
                    onPressed: widget.onSource,
                    icon: Icon(
                      widget.attachment == '图片通知'
                          ? Icons.image_outlined
                          : Icons.mic_none_rounded,
                      size: 16,
                    ),
                    label: Text(
                      widget.attachment!,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (widget.onEdit != null)
                  AppIconButton(
                    tooltip: '编辑并重发',
                    onPressed: widget.onEdit,
                    icon: const Icon(
                      Icons.edit_outlined,
                      size: 16,
                      color: CampusColors.muted,
                    ),
                  ),
              ],
            ),
        ],
      ),
    ),
  );
}

class AssistantActivity extends StatelessWidget {
  final String stage;
  final VoidCallback? onStop;
  const AssistantActivity({super.key, required this.stage, this.onStop});
  @override
  Widget build(BuildContext context) => Row(
    children: [
      ExcludeSemantics(child: AppLoadingIndicator(label: stage, compact: true)),
      const SizedBox(width: 10),
      Expanded(
        child: AssistantArrival(
          revision: stage,
          shift: 0,
          duration: const Duration(milliseconds: 150),
          child: Semantics(
            liveRegion: true,
            child: Text(
              stage,
              style: const TextStyle(fontSize: 14, color: CampusColors.muted),
            ),
          ),
        ),
      ),
      if (onStop != null)
        AppTextButton(onPressed: onStop, child: const Text('停止')),
    ],
  );
}

class AssistantInlineError extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;
  const AssistantInlineError({super.key, required this.text, this.onRetry});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: const BoxDecoration(
        color: CampusColors.warningSoft,
        border: Border(left: BorderSide(color: CampusColors.warning, width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: CampusColors.warning,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
          if (onRetry != null)
            AppTextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}

class AssistantSavedAction extends StatelessWidget {
  final String text;
  final VoidCallback? onUndo;
  final VoidCallback? onOpen;
  const AssistantSavedAction({
    super.key,
    required this.text,
    this.onUndo,
    this.onOpen,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final actions = [
          if (onOpen != null)
            AppTextButton(onPressed: onOpen, child: const Text('查看')),
          if (onUndo != null)
            AppTextButton(onPressed: onUndo, child: const Text('撤销')),
        ];
        final status = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child:
                  context
                          .dependOnInheritedWidgetOfExactType<_ReceiptMotion>()
                          ?.animate ==
                      true
                  ? const SuccessCheckmark(size: 20, color: CampusColors.teal)
                  : const Icon(
                      Icons.check_circle_rounded,
                      color: CampusColors.teal,
                      size: 20,
                    ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
        if (constraints.maxWidth < 320 ||
            MediaQuery.textScalerOf(context).scale(16) > 21) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              status,
              if (actions.isNotEmpty)
                Wrap(alignment: WrapAlignment.end, children: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: status),
            ...actions,
          ],
        );
      },
    ),
  );
}
