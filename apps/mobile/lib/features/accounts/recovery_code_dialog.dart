import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../ui/app_controls.dart';
import '../../ui/campus_theme.dart';

class RecoveryCodeDialog extends StatefulWidget {
  final String code;
  const RecoveryCodeDialog({super.key, required this.code});
  @override
  State<RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<RecoveryCodeDialog> {
  bool copied = false;
  @override
  Widget build(BuildContext context) => AppDialog(
    title: const Text('保存账户恢复码'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '忘记密码时用它找回账户，仅显示一次。',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: CampusColors.muted,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: CampusColors.blueSoft,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            widget.code,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.5,
              letterSpacing: 1.2,
              color: CampusColors.primary,
            ),
          ),
        ),
        AppTextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: widget.code));
            if (mounted) setState(() => copied = true);
          },
          icon: Icon(
            copied ? Icons.check_rounded : Icons.copy_rounded,
            size: 18,
          ),
          label: Text(copied ? '已复制' : '复制恢复码'),
        ),
      ],
    ),
    actions: [
      AppButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('我已保存'),
      ),
    ],
  );
}
