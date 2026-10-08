import 'package:flutter/widgets.dart';

/// Presentation-only source geometry; no draft or route state is stored here.
class AssistantSurfaceOrigin extends InheritedWidget {
  const AssistantSurfaceOrigin({
    super.key,
    required this.sourceKey,
    required super.child,
  });
  final GlobalKey sourceKey;
  static Rect? rectOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AssistantSurfaceOrigin>();
    final box = scope?.sourceKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  bool updateShouldNotify(AssistantSurfaceOrigin oldWidget) =>
      sourceKey != oldWidget.sourceKey;
}
