import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/agent/conversation_session.dart';
import 'package:semester_os/features/agent/agent_controller.dart';
import 'schedule_flow_test.dart' show ScheduleFixture;
import 'api_session_test.dart' show ControlledTransport;

void main() {
  test(
    'closing and reopening within one process keeps the current conversation',
    () {
      final client = Object();
      final first = ConversationSessions.forContext(
        client,
        owner: 'a',
        generation: 1,
        semester: 's',
        context: 'assistant:s',
      );
      first.threadId = 'current';
      final reopened = ConversationSessions.forContext(
        client,
        owner: 'a',
        generation: 1,
        semester: 's',
        context: 'assistant:s',
      );
      expect(reopened.threadId, 'current');
      final coldStart = ConversationSessions.forContext(
        Object(),
        owner: 'a',
        generation: 1,
        semester: 's',
        context: 'assistant:s',
      );
      expect(coldStart.threadId, isNull);
    },
  );

  test(
    'account replacement and different semesters do not reuse conversation IDs',
    () {
      final client = Object();
      final first = ConversationSessions.forContext(
        client,
        owner: 'a',
        generation: 1,
        semester: 's',
        context: 'assistant:s',
      )..threadId = 'private';
      expect(
        ConversationSessions.forContext(
          client,
          owner: 'a',
          generation: 1,
          semester: 'another',
          context: 'assistant:another',
        ).threadId,
        isNull,
      );
      expect(
        ConversationSessions.forContext(
          client,
          owner: 'b',
          generation: 2,
          semester: 's',
          context: 'assistant:s',
        ).threadId,
        isNull,
      );
      expect(
        ConversationSessions.forContext(
          client,
          owner: 'a',
          generation: 3,
          semester: 's',
          context: 'assistant:s',
        ).threadId,
        isNull,
      );
      expect(first.threadId, 'private');
    },
  );

  test(
    'new conversation opens immediately without requesting previous history',
    () async {
      final f = ScheduleFixture();
      f.c.semesterId = 's';
      var calls = 0;
      f.api.dio.httpClientAdapter = ControlledTransport((request) async {
        calls++;
        throw StateError('New conversation must not load history');
      });
      final c = AgentController(f.c, 's');
      await c.open(fresh: true);
      expect(calls, 0);
      expect(c.loading, isFalse);
      expect(c.error, isNull);
      expect(c.threadId, isNull);
      c.dispose();
      f.c.dispose();
    },
  );
}
