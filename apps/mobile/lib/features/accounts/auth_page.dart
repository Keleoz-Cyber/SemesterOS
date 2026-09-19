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
          builder: (context) => AlertDialog(
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
              TextButton(
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
      if (mounted) setState(() => error = '$e');
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
                  const Icon(
                    Icons.school_rounded,
                    size: 64,
                    color: Color(0xFF4F46E5),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '学期OS',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
                  ),
                  const Text('把分散的安排，整理成自己的学期', textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  const Text(
                    '课表导入测试版',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF667085), fontSize: 14),
                  ),
                  const SizedBox(height: 32),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('登录')),
                      ButtonSegment(value: 1, label: Text('注册')),
                    ],
                    selected: {mode == 2 ? 0 : mode},
                    onSelectionChanged: busy
                        ? null
                        : (v) => setState(() {
                            mode = v.first;
                            error = null;
                          }),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    key: const Key('username'),
                    controller: username,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '学期OS用户名',
                      helperText: '4—32位字母、数字或下划线',
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
                    TextFormField(
                      controller: recovery,
                      decoration: const InputDecoration(labelText: '账户恢复码'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    key: const Key('password'),
                    controller: password,
                    obscureText: obscure,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: mode == 2 ? '新密码' : '密码',
                      helperText: '至少12个字符；与学校教务密码无关',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => obscure = !obscure),
                        icon: Icon(
                          obscure ? Icons.visibility_off : Icons.visibility,
                        ),
                        tooltip: '切换密码显示',
                      ),
                    ),
                    validator: (v) =>
                        (v?.length ?? 0) >= 12 && (v?.length ?? 0) <= 128
                        ? null
                        : '密码需为12—128个字符',
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
                  FilledButton(
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
                  TextButton(
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
