import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../ui/app_controls.dart';
import '../../ui/campus_theme.dart';
import 'clipboard_notice_classifier.dart';
import 'incoming_notice_draft.dart';

/// Foreground clipboard inspection only decides whether to offer a paste action.
/// The text is not stored or uploaded. Import still requires an explicit tap.
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
  String? _inspectedToken;
  bool reading = false, _checking = false, _plausible = false;
  bool _checkScheduled = false;
  int _generation = 0;

  bool get _canInspect {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return mounted &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed) &&
        TickerMode.valuesOf(context).enabled &&
        ModalRoute.of(context)?.isCurrent != false &&
        MediaQuery.viewInsetsOf(context).bottom == 0;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scheduleCheck();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A hidden tab, covered route or open keyboard may become available again
    // without an app resume. Checking the OS token does not reread known text.
    _scheduleCheck();
  }

  void _scheduleCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      unawaited(check());
    });
  }

  Future<void> check() async {
    if (!_canInspect || reading || _checking) return;
    _checking = true;
    final generation = _generation;
    String? next;
    var hasNativeToken = true;
    try {
      try {
        final value = await noticeInputChannel.invokeMapMethod<String, dynamic>(
          'clipboardStatus',
        );
        if (value?['has_text'] == true && value?['handled'] != true) {
          next = value?['token'] as String?;
        }
      } on MissingPluginException {
        hasNativeToken = false;
        // Other platforms have no description timestamp; inspect transiently.
        if (await Clipboard.hasStrings()) next = 'foreground-clipboard';
      }
      if (!_canInspect || generation != _generation) return;
      if (next == null || (hasNativeToken && _handled.contains(next))) {
        if (mounted) setState(() => token = null);
        return;
      }
      if (!hasNativeToken || next != _inspectedToken) {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        if (!_canInspect || generation != _generation) return;
        if (hasNativeToken) {
          final fresh = await noticeInputChannel
              .invokeMapMethod<String, dynamic>('clipboardStatus');
          if (!_canInspect || generation != _generation) return;
          if (fresh?['token'] != next || fresh?['handled'] == true) {
            // The OS clipboard changed during the read. Do not label or mark
            // the new text with the old description's dismissal token.
            setState(() => token = null);
            _scheduleCheck();
            return;
          }
        }
        // Cache only a non-content token and a yes/no result, never the text.
        _plausible = isPlausibleClipboardNotice(data?.text ?? '');
        _inspectedToken = next;
        if (!hasNativeToken) {
          next = 'clipboard:${data?.text?.hashCode}';
        }
      }
      if (mounted) {
        setState(
          () => token = _plausible && !_handled.contains(next) ? next : null,
        );
      }
    } on PlatformException {
      // A denied clipboard read does not block the normal composer.
      if (mounted) setState(() => token = null);
    } finally {
      _checking = false;
      if (generation != _generation && _canInspect) unawaited(check());
    }
  }

  Future<void> dismiss(String current) async {
    _generation++;
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
    final generation = _generation;
    setState(() => reading = true);
    try {
      final value = await Clipboard.getData(Clipboard.kTextPlain);
      if (!_canInspect || generation != _generation) return;
      await dismiss(current);
      final text = value?.text?.trim() ?? '';
      if (_canInspect && text.isNotEmpty) widget.onImport(text);
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(const SnackBar(content: Text('暂时无法读取，可以在输入框中粘贴。')));
      }
    } finally {
      if (mounted) setState(() => reading = false);
      if (generation != _generation && _canInspect) _scheduleCheck();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _generation++;
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => token == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
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
  Widget build(BuildContext context) => Material(
    color: CampusColors.blueSoft,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            key: const Key('clipboard-import'),
            onTap: onImport,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
                child: Row(
                  children: [
                    const ExcludeSemantics(
                      child: Icon(
                        Icons.content_paste_rounded,
                        size: 20,
                        color: CampusColors.muted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        reading ? '读取中…' : '整理复制的内容',
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: CampusColors.ink,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const ExcludeSemantics(
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: CampusColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        AppIconButton(
          key: const Key('clipboard-dismiss'),
          tooltip: '忽略剪贴板文字',
          onPressed: onDismiss,
          color: CampusColors.muted,
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
        const SizedBox(width: 4),
      ],
    ),
  );
}
