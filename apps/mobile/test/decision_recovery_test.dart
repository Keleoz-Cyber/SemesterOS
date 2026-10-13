import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:semester_os/features/agent/agent_controller.dart';
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'api_session_test.dart' show ControlledTransport, body;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'lost confirmation response queries receipt without repeating write',
    () async {
      final f = ScheduleFixture();
      await f.c.bind('s');
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var posts = 0;
      final pending = <String, dynamic>{
        'id': 'r',
        'thread_id': 't',
        'status': 'needs_confirmation',
        'preview': {'token': 'p'},
      };
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/decision')) {
          posts++;
          throw DioException(
            requestOptions: r,
            type: DioExceptionType.connectionError,
            error: const SocketException('lost response'),
          );
        }
        if (r.path.endsWith('/agent/runs/r')) {
          return body({
            ...pending,
            'status': 'applied',
            'receipt': {'semester_id': 's', 'revision': 1},
          });
        }
        return old.respond(r);
      });
      final c = AgentController(f.c, 's')
        ..threadId = 't'
        ..runs = [pending];
      await c.decide(pending, true);
      expect(posts, 1);
      expect(c.runs.single['status'], 'applied');
      expect(c.uncertainDecisions, isEmpty);
      expect(await f.c.decisions.read(), isEmpty);
      c.dispose();
      f.c.dispose();
    },
  );
  test(
    'journal survives controller recreation and recovery never confirms a preview',
    () async {
      final f = ScheduleFixture();
      await f.c.bind('s');
      final old = f.api.dio.httpClientAdapter as ControlledTransport;
      var writes = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((r) async {
        if (r.path.endsWith('/agent/runs/r')) {
          return body({'id': 'r', 'status': 'needs_confirmation'});
        }
        if (r.path.endsWith('/decision')) writes++;
        return old.respond(r);
      });
      await f.c.decisions.update('r', {'semester_id': 's', 'thread_id': 't'});
      await f.c.recoverDecisions();
      expect(writes, 0);
      expect(f.c.recoveryNotice, contains('尚未保存'));
      expect(f.c.recoveryThread, 't');
      expect((await f.c.decisions.read()).single['id'], 'r');
      f.c.dispose();
    },
  );
}
