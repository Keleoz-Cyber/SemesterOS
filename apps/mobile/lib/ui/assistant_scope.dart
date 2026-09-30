import 'package:flutter/material.dart';

typedef AssistantOpener =
    Future<void> Function(
      BuildContext context, {
      String? initialText,
      String? mediaKind,
      bool autoSubmit,
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
    );
  }

  @override
  bool updateShouldNotify(covariant AssistantScope oldWidget) =>
      onOpen != oldWidget.onOpen;
}
