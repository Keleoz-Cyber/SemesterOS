import 'package:flutter/material.dart';
import 'app_controls.dart';

class AppTextEntry {
  final String keyName, label, initial;
  final bool obscure;
  final int maxLength;
  const AppTextEntry(
    this.keyName,
    this.label, {
    this.initial = '',
    this.obscure = false,
    this.maxLength = 120,
  });
}

/// Controllers live until the closing route animation has actually finished.
class AppTextEntryDialog extends StatefulWidget {
  final String title, confirmLabel;
  final String? description;
  final List<AppTextEntry> fields;
  const AppTextEntryDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.fields,
    this.description,
  });
  @override
  State<AppTextEntryDialog> createState() => _AppTextEntryDialogState();
}

class _AppTextEntryDialogState extends State<AppTextEntryDialog> {
  late final inputs = {
    for (final field in widget.fields)
      field.keyName: TextEditingController(text: field.initial),
  };
  @override
  void dispose() {
    for (final input in inputs.values) {
      input.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppDialog(
    title: Text(widget.title),
    content: Material(
      type: MaterialType.transparency,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.description != null) Text(widget.description!),
            for (final field in widget.fields)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextField(
                  controller: inputs[field.keyName],
                  obscureText: field.obscure,
                  maxLength: field.maxLength,
                  decoration: InputDecoration(
                    labelText: field.label,
                    counterText: '',
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      AppTextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      AppButton(
        onPressed: () {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.pop(context, {
            for (final field in widget.fields)
              field.keyName: field.obscure
                  ? inputs[field.keyName]!.text
                  : inputs[field.keyName]!.text.trim(),
          });
        },
        child: Text(widget.confirmLabel),
      ),
    ],
  );
}
