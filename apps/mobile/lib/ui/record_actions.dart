import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
import 'app_sheet.dart';
import 'campus_theme.dart';

/// A secondary record action shown as one accessible, full-width row.
class RecordActionTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  const RecordActionTile({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: FItem.raw(
      style: const FItemStyleDelta.delta(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      onPress: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 40,
              child: Icon(icon, color: CampusColors.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.visible,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      overflow: TextOverflow.visible,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.45,
                        color: CampusColors.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: CampusColors.muted,
                size: 20,
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class RecordMenuAction<T> {
  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
  const RecordMenuAction(
    this.value,
    this.label,
    this.icon, {
    this.destructive = false,
  });
}

/// Secondary record actions use a thumb-reachable sheet with full touch rows.
class RecordMenuButton<T> extends StatelessWidget {
  final List<RecordMenuAction<T>> actions;
  final ValueChanged<T> onSelected;
  final bool enabled;
  const RecordMenuButton({
    super.key,
    required this.actions,
    required this.onSelected,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: '更多操作',
    child: FButton.icon(
      semanticsLabel: '更多操作',
      semanticsTooltip: '更多操作',
      variant: FButtonVariant.ghost,
      size: FButtonSizeVariant.lg,
      onPress: !enabled
          ? null
          : () async {
              final value = await showAppSheet<T>(
                context: context,
                builder: (sheetContext) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '更多操作',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      for (final action in actions)
                        FItem.raw(
                          variant: action.destructive
                              ? FItemVariant.destructive
                              : FItemVariant.primary,
                          prefix: Icon(
                            action.icon,
                            color: action.destructive
                                ? Theme.of(context).colorScheme.error
                                : CampusColors.primary,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 24),
                            child: Text(
                              action.label,
                              overflow: TextOverflow.visible,
                              style: TextStyle(
                                fontSize: 16,
                                color: action.destructive
                                    ? Theme.of(context).colorScheme.error
                                    : CampusColors.ink,
                              ),
                            ),
                          ),
                          onPress: () =>
                              Navigator.pop(sheetContext, action.value),
                        ),
                    ],
                  ),
                ),
              );
              if (value != null && context.mounted) onSelected(value);
            },
      child: const Icon(Icons.more_horiz_rounded),
    ),
  );
}
