import 'package:flutter/material.dart';
import '../../ui/app_sheet.dart';
import '../items/items_controller.dart';
import 'agent_page.dart';

Future<void> openAssistantSheet(
  BuildContext context, {
  required ItemsController controller,
  required Map<String, dynamic> semester,
  String? initialText,
  String? mediaKind,
  bool autoSubmit = false,
  List<String> selectedRecordIds = const [],
  bool noticeInput = false,
}) => showAppSheet<void>(
  context: context,
  heightFactor: .90,
  builder: (context) => AgentPage(
    controller: controller,
    semester: semester,
    embedded: true,
    initialText: initialText,
    initialMediaKind: mediaKind,
    autoSubmit: autoSubmit,
    initialRecordIds: selectedRecordIds,
    initialNotice: noticeInput,
    autofocus: initialText == null && mediaKind == null,
  ),
);
