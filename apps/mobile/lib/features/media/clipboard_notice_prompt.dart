import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../ui/app_controls.dart';
import '../../ui/campus_theme.dart';
import 'incoming_notice_draft.dart';

/// Clipboard content is read only in response to the import button.
class ClipboardNoticePrompt extends StatefulWidget {
  final ValueChanged<String> onImport;
  const ClipboardNoticePrompt({super.key, required this.onImport});
  @override
  State<ClipboardNoticePrompt> createState() => _ClipboardNoticePromptState();
}

class _ClipboardNoticePromptState extends State<ClipboardNoticePrompt>
    with WidgetsBindingObserver {
  static final _handled = <String>{};
  String? token;
  bool reading = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => check());
  }

  Future<void> check() async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (!mounted ||
        reading ||
        (lifecycle != null && lifecycle != AppLifecycleState.resumed)) {
      return;
    }
    String? next;
    try {
      final value = await noticeInputChannel.invokeMapMethod<String, dynamic>(
        'clipboardStatus',
      );
      if (value?['has_text'] == true && value?['handled'] != true) {
        next = value?['token'] as String?;
      }
    } on MissingPluginException {
      if (await Clipboard.hasStrings()) next = 'foreground-clipboard';
    } on PlatformException {
      // A denied clipboard description does not block the normal composer.
    }
    if (mounted) setState(() => token = _handled.contains(next) ? null : next);
  }

  Future<void> dismiss(String current) async {
    _handled.add(current);
    if (_handled.length > 32) _handled.remove(_handled.first);
    if (mounted) setState(() => token = null);
    try {
      await noticeInputChannel.invokeMethod<void>('markClipboardHandled', {
        'token': current,
      });
    } on MissingPluginException {
      // Other platforms use a process-local marker without inspecting text.
    } on PlatformException {
      // This process still remembers the dismissal.
    }
  }

  Future<void> importText() async {
    final current = token;
    if (current == null || reading) return;
    setState(() => reading = true);
    try {
      final value = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) return;
      await dismiss(current);
      final text = value?.text?.trim() ?? '';
      if (mounted && text.isNotEmpty) widget.onImport(text);
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('暂时无法读取，可以在输入框中粘贴。')));
      }
    } finally {
      if (mounted) setState(() => reading = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => token == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ClipboardNoticeRibbon(
            reading: reading,
            onImport: reading ? null : importText,
            onDismiss: reading ? null : () => unawaited(dismiss(token!)),
          ),
        );
}

/// A contextual clipboard hint stays lighter than the page's real content.
class ClipboardNoticeRibbon extends StatelessWidget {
  final bool reading;
  final Future<void> Function()? onImport;
  final VoidCallback? onDismiss;
  const ClipboardNoticeRibbon({
    super.key,
    this.reading = false,
    required this.onImport,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: CampusColors.line)),
    ),
    child: Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final text = TextPainter(
            text: const TextSpan(text: '已复制文字', style: TextStyle(fontSize: 14)),
            textScaler: MediaQuery.textScalerOf(context),
            textDirection: Directionality.of(context),
          )..layout();
          final captionWidth = text.width;
          text.dispose();
          final stacked =
              captionWidth +
                  MediaQuery.textScalerOf(context).scale(14) * 4 +
                  126 >
              bounds.maxWidth;
          final caption = Row(
            children: [
              const ExcludeSemantics(
                child: Icon(
                  Icons.content_paste_rounded,
                  size: 18,
                  color: CampusColors.muted,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  '已复制文字',
                  style: TextStyle(fontSize: 14, color: CampusColors.muted),
                ),
              ),
            ],
          );
          final paste = AppTextButton(
            key: const Key('clipboard-import'),
            onPressed: onImport,
            child: Text(reading ? '读取中…' : '粘贴'),
          );
          final dismiss = AppIconButton(
            tooltip: '忽略剪贴板文字',
            onPressed: onDismiss,
            color: CampusColors.muted,
            icon: const Icon(Icons.close_rounded, size: 18),
          );
          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: caption),
                    dismiss,
                  ],
                ),
                Align(alignment: AlignmentDirectional.centerEnd, child: paste),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: caption),
              const SizedBox(width: 12),
              paste,
              const SizedBox(width: 8),
              dismiss,
            ],
          );
        },
      ),
    ),
  );
}
