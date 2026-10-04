import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/items/items_controller.dart';
import 'package:semester_os/features/items/reminder_settings.dart';
import 'package:semester_os/features/items/reminder_sync.dart';
import 'package:semester_os/ui/app_controls.dart';
import 'api_session_test.dart' show ControlledTransport;
import 'centers_flow_test.dart' show settleIo;
import 'controller_test.dart' show MemoryStore;
import 'planning_flow_test.dart' show ioTap;
import 'reminder_sync_test.dart' show PreciseNotifications, rule;
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'ui_polish_test.dart' show mount;

class SettingsNotifications extends PreciseNotifications
    implements NotificationSettingsPort {
  bool failPermissionReads = false;
  int settingsOpens = 0, permissionRequests = 0;

  @override
  Future<bool> permission({bool request = false}) async {
    if (request) permissionRequests++;
    if (failPermissionReads) throw PlatformException(code: 'unavailable');
    return super.permission(request: request);
  }

  @override
  Future<void> openNotificationSettings() async {
    settingsOpens++;
  }
}

Future<
  ({
    ItemsController controller,
    SettingsNotifications port,
    List<String> requests,
  })
>
setup(WidgetTester tester) async {
  final data = ScheduleFixture();
  final port = SettingsNotifications()
    ..allowed = false
    ..precise = false;
  final controller = ItemsController(
    data.api,
    MemoryStore(),
    ReminderSync(port),
  );
  await tester.runAsync(() => controller.bind('s'));
  data.c.dispose();
  controller.reminderFeed = [rule('saved')];
  final requests = <String>[];
  data.api.dio.httpClientAdapter = ControlledTransport((request) async {
    requests.add(request.path);
    throw StateError('Notification settings must not require the network');
  });
  return (controller: controller, port: port, requests: requests);
}

Finder notificationButton() => find.descendant(
  of: find.ancestor(of: find.text('系统通知'), matching: find.byType(AppTile)),
  matching: find.byType(AppTextButton),
);

Future<void> returnFromSettings(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await settleIo(tester);
}

Future<void> closePage(WidgetTester tester, ItemsController controller) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 100));
  controller.dispose();
}

void main() {
  testWidgets(
    'failed permission read still opens system settings and clears on resume',
    (tester) async {
      final f = await setup(tester);
      f.port.failPermissionReads = true;
      await mount(tester, ReminderSettingsPage(controller: f.controller));
      await settleIo(tester);
      expect(find.text('未允许，提醒规则仍会保留'), findsNothing);
      expect(find.textContaining('读取'), findsWidgets);

      await ioTap(tester, notificationButton());
      expect(f.port.settingsOpens, 1);
      expect(f.port.permissionRequests, 0);
      expect(f.requests, isEmpty);

      f.port
        ..failPermissionReads = false
        ..allowed = true;
      await returnFromSettings(tester);
      expect(find.text('已允许'), findsOneWidget);
      expect(find.textContaining('读取'), findsNothing);
      expect(f.port.scheduleCalls, 1);
      expect(f.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await closePage(tester, f.controller);
    },
  );

  testWidgets(
    'denied notifications open settings without another prompt or cloud request',
    (tester) async {
      final f = await setup(tester);
      await mount(tester, ReminderSettingsPage(controller: f.controller));
      await settleIo(tester);
      expect(f.port.scheduleCalls, 0);

      await ioTap(tester, notificationButton());
      expect(f.port.settingsOpens, 1);
      expect(f.port.permissionRequests, 0);
      expect(f.requests, isEmpty);
      expect(f.port.scheduleCalls, 0);

      f.port.allowed = true;
      await returnFromSettings(tester);
      expect(find.text('已允许'), findsOneWidget);
      expect(f.port.scheduleCalls, 1);
      expect(f.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await closePage(tester, f.controller);
    },
  );
}
