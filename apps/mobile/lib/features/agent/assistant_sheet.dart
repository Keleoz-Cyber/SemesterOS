import 'package:flutter/material.dart';
import 'dart:io';
import '../../ui/app_sheet.dart';
import '../../ui/assistant_scope.dart';
import '../../ui/motion.dart';
import '../items/items_controller.dart';
import '../media/drafts.dart';
import 'agent_page.dart';

Future<void> openAssistantSheet(
  BuildContext context, {
  required ItemsController controller,
  required Map<String, dynamic> semester,
  String? initialText,
  String? mediaKind,
  String? audioPath,
  bool autoSubmit = false,
  List<String> selectedRecordIds = const [],
  bool noticeInput = false,
  AssistantBrowsingContext? browsingContext,
}) async {
  String? retainedAudio;
  final owner = controller.owner;
  final generation = controller.api.generation;
  if (audioPath != null && owner != null) {
    final folder = await CaptureDrafts.folder(owner);
    await folder.create(recursive: true);
    retainedAudio = (await File(audioPath).copy(
      '${folder.path}/incoming-audio-${DateTime.now().microsecondsSinceEpoch}.wav',
    )).path;
  }
  try {
    if (!context.mounted ||
        owner != controller.owner ||
        generation != controller.api.generation ||
        controller.semesterId != semester['id']) {
      return;
    }
    await showAppSheet<void>(
      context: context,
      heightFactor: .90,
      transitionDuration: AppMotion.change(context),
      transitionCurve: Curves.easeOutCubic,
      builder: (context) => AgentPage(
        controller: controller,
        semester: semester,
        embedded: true,
        initialText: initialText,
        initialMediaKind: mediaKind,
        initialAudioPath: retainedAudio,
        autoSubmit: autoSubmit,
        initialRecordIds: selectedRecordIds,
        initialNotice: noticeInput,
        browsingContext: browsingContext,
        autofocus:
            initialText == null && mediaKind == null && retainedAudio == null,
      ),
    );
  } finally {
    if (retainedAudio != null && owner != null) {
      await CaptureDrafts.releaseFile(owner, retainedAudio);
    }
  }
}
