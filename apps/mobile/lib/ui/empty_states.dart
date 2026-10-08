import 'package:flutter/material.dart';

import 'app_controls.dart';
import 'empty_scene.dart';
import 'motion.dart';

/// Optional help page. Entry callbacks are supplied by the real app routes.
class OnboardingGuide extends StatelessWidget {
  final VoidCallback onComplete;
  final VoidCallback? onTimetable, onNotice, onPlanning;
  const OnboardingGuide({
    super.key,
    required this.onComplete,
    this.onTimetable,
    this.onNotice,
    this.onPlanning,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('拾日使用说明'),
      leading: AppIconButton(
        tooltip: '返回',
        onPressed: onComplete,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
    ),
    body: SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(
            child: AppEmptyScene(size: 180, kind: EmptySceneKind.collect),
          ),
          AppTile(
            title: const Text('课程表'),
            subtitle: const Text('建立学期，再导入课表或手动添加课程。'),
            leading: const Icon(Icons.calendar_month_outlined),
            onTap: onTimetable,
            trailing: onTimetable == null
                ? null
                : const Icon(Icons.chevron_right_rounded),
          ),
          const SizedBox(height: 12),
          const Center(
            child: AppEmptyScene(size: 180, kind: EmptySceneKind.adapt),
          ),
          AppTile(
            title: const Text('通知与日程'),
            subtitle: const Text('输入通知文字、图片或录音，核对结果后保存事项。'),
            leading: const Icon(Icons.edit_note_rounded),
            onTap: onNotice,
            trailing: onNotice == null
                ? null
                : const Icon(Icons.chevron_right_rounded),
          ),
          const SizedBox(height: 12),
          const Center(
            child: AppEmptyScene(size: 180, kind: EmptySceneKind.plan),
          ),
          AppTile(
            title: const Text('任务与学习安排'),
            subtitle: const Text('查看待办与截止日期，按需要安排学习时间。'),
            leading: const Icon(Icons.checklist_rounded),
            onTap: onPlanning,
            trailing: onPlanning == null
                ? null
                : const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    ),
  );
}

class EmptyTimetable extends StatelessWidget {
  final VoidCallback? onAddCourse, onImport;
  final String title;
  final String? message, actionLabel;
  const EmptyTimetable({
    super.key,
    this.onAddCourse,
    this.onImport,
    this.title = '暂无课程',
    this.message,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.calendar_month_outlined,
    scene: EmptySceneKind.timetable,
    title: title,
    message: message ?? '导入课表或手动添加课程。',
    action: onImport == null && onAddCourse == null
        ? null
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton.icon(
                onPressed: onImport ?? onAddCourse,
                icon: Icon(
                  onImport == null
                      ? Icons.add_rounded
                      : Icons.file_download_outlined,
                ),
                label: Text(
                  actionLabel ?? (onImport == null ? '添加课程' : '导入课表'),
                ),
              ),
              if (onImport != null && onAddCourse != null)
                AppTextButton(
                  onPressed: onAddCourse,
                  child: const Text('手动添加课程'),
                ),
            ],
          ),
  );
}

class EmptyItems extends StatelessWidget {
  final VoidCallback? onAddItem;
  final String title, actionLabel;
  final String? customMessage;
  const EmptyItems({
    super.key,
    this.onAddItem,
    this.customMessage,
    this.title = '暂无事项',
    this.actionLabel = '添加事项',
  });

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.checklist_rounded,
    scene: EmptySceneKind.tasks,
    title: title,
    message: customMessage ?? '添加作业、考试或待办事项。',
    action: onAddItem == null
        ? null
        : AppButton.icon(
            onPressed: onAddItem,
            icon: const Icon(Icons.add_rounded),
            label: Text(actionLabel),
          ),
  );
}

class NoSearchResults extends StatelessWidget {
  final String query, title, clearLabel;
  final String? message;
  final VoidCallback? onClear;
  const NoSearchResults({
    super.key,
    required this.query,
    this.onClear,
    this.title = '没有找到结果',
    this.message,
    this.clearLabel = '清除搜索',
  });

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.search_off_rounded,
    scene: EmptySceneKind.search,
    title: title,
    message:
        message ??
        (query.trim().isEmpty ? '换个关键词或清除搜索条件。' : '没有找到与“$query”匹配的结果。'),
    action: onClear == null
        ? null
        : AppOutlineButton(onPressed: onClear, child: Text(clearLabel)),
  );
}

class NetworkError extends StatelessWidget {
  final VoidCallback onRetry;
  final String? message;
  final String title;
  const NetworkError({
    super.key,
    required this.onRetry,
    this.message,
    this.title = '暂时无法连接',
  });

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: EmptyState(
      icon: Icons.cloud_off_outlined,
      scene: EmptySceneKind.offline,
      title: title,
      message: message ?? '请检查网络连接后重试。',
      action: AppButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: const Text('重试'),
      ),
    ),
  );
}

/// 数据加载失败
class DataLoadError extends StatelessWidget {
  final VoidCallback onRetry;
  final String? errorMessage;

  const DataLoadError({super.key, required this.onRetry, this.errorMessage});

  @override
  Widget build(BuildContext context) {
    return ErrorState(message: errorMessage ?? '数据加载失败', onRetry: onRetry);
  }
}

/// 操作失败提示
class OperationFailed extends StatelessWidget {
  final String operation;
  final String? reason;
  final VoidCallback? onRetry;

  const OperationFailed({
    super.key,
    required this.operation,
    this.reason,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).colorScheme.error.withValues(
              alpha: MediaQuery.highContrastOf(context) ? 1 : 0.3,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$operation失败',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  if (reason != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      reason!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: 12),
              AppIconButton(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                color: Theme.of(context).colorScheme.error,
                tooltip: '重试',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
