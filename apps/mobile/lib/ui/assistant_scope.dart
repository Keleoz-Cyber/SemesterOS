import 'package:flutter/material.dart';

/// The visible calendar selection, separate from the real current date.
@immutable
class AssistantBrowsingContext {
  final DateTime startDate, endDate;
  const AssistantBrowsingContext({
    required this.startDate,
    required this.endDate,
  });

  static String dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> toJson() => {
    'start_date': dateKey(startDate),
    'end_date': dateKey(endDate),
  };

  static AssistantBrowsingContext? fromJson(dynamic value) {
    if (value is! Map) return null;
    final start = DateTime.tryParse('${value['start_date']}');
    final end = DateTime.tryParse('${value['end_date']}');
    if (start == null || end == null || end.isBefore(start)) return null;
    return AssistantBrowsingContext(startDate: start, endDate: end);
  }

  String get label {
    final showYear =
        startDate.year != DateTime.now().year || startDate.year != endDate.year;
    final first =
        '${showYear ? '${startDate.year}年' : ''}${startDate.month}月${startDate.day}日';
    if (dateKey(startDate) == dateKey(endDate)) return first;
    return '$first—${startDate.year != endDate.year ? '${endDate.year}年' : ''}${endDate.month}月${endDate.day}日';
  }
}

typedef AssistantOpener =
    Future<void> Function(
      BuildContext context, {
      String? initialText,
      String? mediaKind,
      bool autoSubmit,
      AssistantBrowsingContext? browsingContext,
    });

/// A single product entry point shared by the main dock and contextual actions.
class AssistantScope extends InheritedWidget {
  final AssistantOpener onOpen;
  const AssistantScope({super.key, required this.onOpen, required super.child});
  static AssistantScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AssistantScope>();
  static Future<void> open(
    BuildContext context, {
    String? initialText,
    String? mediaKind,
    bool autoSubmit = false,
    AssistantBrowsingContext? browsingContext,
  }) async {
    final scope = maybeOf(context);
    if (scope == null) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('请返回主页面使用智能输入')));
      return;
    }
    await scope.onOpen(
      context,
      initialText: initialText,
      mediaKind: mediaKind,
      autoSubmit: autoSubmit,
      browsingContext: browsingContext,
    );
  }

  @override
  bool updateShouldNotify(covariant AssistantScope oldWidget) =>
      onOpen != oldWidget.onOpen;
}
