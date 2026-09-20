// Opt-in synthetic Android check; never initializes accounts or application caches.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:semester_os/features/items/android_notifications.dart';

void require(bool passed, String message) {
  if (!passed) throw StateError(message);
}

Future<void> verify() async {
  final port = AndroidNotifications();
  final opened = Completer<void>();
  port.onOpen = (owner, item) {
    require(
      owner == 'synthetic-qa' && item == 'synthetic-item',
      'Notification target mismatch',
    );
    if (!opened.isCompleted) opened.complete();
  };
  await port.initialize();
  debugPrint('QA_NOTIFICATION_READY');
  for (var i = 0; i < 60 && !await port.permission(); i++) {
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  require(await port.permission(), 'Notification permission not granted');
  const id = 19092026;
  Map<String, dynamic> data(Duration wait) => {
    'title': 'SemesterOS QA synthetic reminder',
    'purpose': 'item',
    'owner_id': 'synthetic-qa',
    'item_id': 'synthetic-item',
    'trigger_at': DateTime.now().toUtc().add(wait).toIso8601String(),
  };
  try {
    await port.schedule(id, data(const Duration(seconds: 5)));
    require(
      (await port.plugin.pendingNotificationRequests()).any((r) => r.id == id),
      'Schedule missing',
    );
    var delivered = false;
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if ((await port.plugin.getActiveNotifications()).any((r) => r.id == id)) {
        delivered = true;
        break;
      }
    }
    require(delivered, 'Notification was not actually delivered');
    debugPrint('QA_NOTIFICATION_DELIVERED');
    await opened.future.timeout(const Duration(seconds: 45));
    debugPrint('QA_NOTIFICATION_OPENED');
    await port.plugin.cancel(id: id);
    require(
      !(await port.plugin.getActiveNotifications()).any((r) => r.id == id),
      'Delivered notification not cleared',
    );
    await port.schedule(id, data(const Duration(hours: 1)));
    require(
      (await port.plugin.pendingNotificationRequests()).any((r) => r.id == id),
      'Future schedule missing',
    );
    await port.plugin.cancel(id: id);
    require(
      !(await port.plugin.pendingNotificationRequests()).any((r) => r.id == id),
      'Cancelled reminder still pending',
    );
    debugPrint('QA_NOTIFICATION_PASS');
  } finally {
    await port.plugin.cancel(id: id);
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: FutureBuilder<void>(
            future: verify(),
            builder: (context, result) => Text(
              result.hasError
                  ? '合成提醒验证未通过，请查看测试日志'
                  : result.connectionState == ConnectionState.done
                  ? '合成提醒：投递与撤销通过'
                  : '正在验证合成提醒…',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    ),
  );
}
