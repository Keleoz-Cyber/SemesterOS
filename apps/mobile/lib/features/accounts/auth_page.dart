import '../../ui/app_controls.dart';
import '../../ui/app_selection.dart';
import '../../ui/brand.dart';
import '../../ui/campus_theme.dart';
import '../../core/api.dart' show userError;
import 'package:flutter/material.dart';
import '../../app/controller.dart';

class AuthPage extends StatefulWidget {
  final AppController controller;
  const AuthPage({super.key, required this.controller});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final username = TextEditingController(),
      password = TextEditingController(),
      recovery = TextEditingController();
  final form = GlobalKey<FormState>();
  int mode = 0;
  bool busy = false, obscure = true;
  String? error;
  @override
  void dispose() {
    username.dispose();
    password.dispose();
    recovery.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate() || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = Map<String, dynamic>.from(
        await widget.controller.api.request(
          'POST',
          mode == 2
              ? '/auth/recover'
              : mode == 1
              ? '/auth/register'
              : '/auth/login',
          authenticated: false,
          data: mode == 2
              ? {
                  'username': username.text.trim(),
                  'recovery_code': recovery.text.trim(),
                  'new_password': password.text,
                }
              : {'username': username.text.trim(), 'password': password.text},
        ),
      );
      if (!mounted) return;
      if (data['recovery_code'] != null) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AppDialog(
            title: const Text('保存账户恢复码'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('忘记密码时可用此码恢复账户。请妥善保存，它只在此显示一次。'),
                const SizedBox(height: 16),
                SelectableText(
                  '${data['recovery_code']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              AppTextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('我已保存'),
              ),
            ],
          ),
        );
      }
      if (mode == 2) {
        if (mounted) {
          setState(() {
            mode = 0;
            error = '密码已更新，请登录';
          });
        }
      } else {
        await widget.controller.openSession(data);
      }
    } catch (e) {
      if (mounted) setState(() => error = userError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      BrandMark(size: 44),
                      SizedBox(width: 12),
                      Text(
                        appName,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: CampusColors.ink,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 44),
                  Text(
                    mode == 2
                        ? '恢复账户'
                        : mode == 1
                        ? '创建你的账户'
                        : '登录拾日',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: CampusColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    mode == 2 ? '输入注册时保存的恢复码，设置新密码。' : '登录后同步课表、通知和个人计划。',
                    style: const TextStyle(
                      fontSize: 14,
                      color: CampusColors.muted,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (mode != 2)
                        AppSegmentedControl<int>(
                          options: const {0: '登录', 1: '注册'},
                          value: mode,
                          enabled: !busy,
                          onChanged: (value) => setState(() {
                            mode = value;
                            error = null;
                          }),
                        ),
                      const SizedBox(height: 20),
                      AppFormField(
                        key: const Key('username'),
                        controller: username,
                        autocorrect: false,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: '用户名',
                          helperText: '4—32位字母、数字或下划线',
                          helperMaxLines: 2,
                        ),
                        validator: (v) =>
                            RegExp(
                              r'^[a-zA-Z0-9_]{4,32}$',
                            ).hasMatch(v?.trim() ?? '')
                            ? null
                            : '请填写有效用户名',
                      ),
                      const SizedBox(height: 16),
                      if (mode == 2) ...[
                        AppFormField(
                          controller: recovery,
                          decoration: const InputDecoration(labelText: '账户恢复码'),
                        ),
                        const SizedBox(height: 16),
                      ],
                      AppFormField(
                        key: const Key('password'),
                        controller: password,
                        obscureText: obscure,
                        autofillHints: [
                          mode == 0
                              ? AutofillHints.password
                              : AutofillHints.newPassword,
                        ],
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: mode == 2 ? '新密码' : '密码',
                          helperText: '至少8位',
                          suffixIcon: AppIconButton(
                            onPressed: () => setState(() => obscure = !obscure),
                            icon: Icon(
                              obscure ? Icons.visibility_off : Icons.visibility,
                            ),
                            tooltip: '切换密码显示',
                          ),
                        ),
                        validator: (v) =>
                            (v?.length ?? 0) >= 8 && (v?.length ?? 0) <= 128
                            ? null
                            : '密码需要8—128位',
                      ),
                      const SizedBox(height: 20),
                      if (error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      AppButton(
                        key: const Key('auth-submit'),
                        onPressed: busy ? null : submit,
                        child: Text(
                          busy
                              ? '请稍候…'
                              : mode == 2
                              ? '恢复账户'
                              : mode == 1
                              ? '创建账户'
                              : '登录',
                        ),
                      ),
                    ],
                  ),
                  AppTextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            mode = mode == 2 ? 0 : 2;
                            error = null;
                          }),
                    child: Text(mode == 2 ? '返回登录' : '使用恢复码找回密码'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
