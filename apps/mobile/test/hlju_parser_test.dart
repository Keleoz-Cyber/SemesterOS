import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/import/hlju_parser.dart';

Map<String, dynamic> packet(List<Map<String, dynamic>> rows) => {
  'year': '2026-2027',
  'term': '1',
  'sourceTerm': '2026-2027第一学期课表',
  'rows': rows,
};

void main() {
  test('preserves exempt attendance and actual full-block course time', () {
    final value = parseHljuImport(
      packet([
        {
          'raw_text': '（免听）概率论【002】\n教师甲\n[1-12周][教学楼-336]\n第3-4节',
          'weekday': 2,
          'source_key': 'schedule-a',
          'start_time': '10:00',
          'end_time': '11:35',
          'password': 'not-exported',
        },
      ]),
    );
    final course = value.courses.single;
    expect(course['title'], '概率论');
    expect(course['teacher'], '教师甲');
    expect(course['weeks'], List.generate(12, (i) => i + 1));
    expect(course['sections'], [3, 4]);
    expect(course['weekday'], 2);
    expect(course['attendance_exempt'], true);
    expect(course['start_time'], '10:00');
    expect(course['end_time'], '11:35');
    expect(course['source_id'], startsWith('hlju:schedule-a:'));
    expect(course.containsKey('password'), false);
  });

  test('deduplicates mirrored rows without combining distinct weeks', () {
    final a = {
      'raw_text': '课程甲【001】\n教师甲\n[1-4周(单)][A101]\n第1-2节',
      'weekday': 1,
    };
    final b = {
      'raw_text': '课程甲【001】\n教师甲\n[6-8周(双)][A101]\n第1-2节',
      'weekday': 1,
    };
    final value = parseHljuImport(packet([a, Map.from(a), b]));
    expect(value.courses, hasLength(2));
    expect(value.courses[0]['weeks'], [1, 3]);
    expect(value.courses[1]['weeks'], [6, 8]);
    expect(value.courses[0]['source_id'], isNot(value.courses[1]['source_id']));
  });

  test('exam dates use explicit term year and missing room stays absent', () {
    final value = parseHljuImport(
      packet([
        {
          'raw_text': '【26秋随堂结课考试（120分钟）考试】\n课程甲\n10月25日\n15:40-17:40',
          'weekday': 7,
        },
      ]),
    );
    expect(value.courses, isEmpty);
    final exam = value.extras.single;
    expect(exam['kind'], 'exam');
    expect(exam['title'], '课程甲');
    expect(exam['start_at'], '2026-10-25T15:40:00+08:00');
    expect(exam['end_at'], '2026-10-25T17:40:00+08:00');
    expect(exam.containsKey('location'), false);
    final startOnly = parseHljuImport(
      packet([
        {'raw_text': '【结课考试】\n课程甲\n10月25日\n15:40'},
      ]),
    );
    expect(startOnly.extras.single['start_at'], '2026-10-25T15:40:00+08:00');
    expect(startOnly.extras.single.containsKey('end_at'), false);
    final unknown = parseHljuImport({
      'sourceTerm': '',
      'rows': [
        {'raw_text': '【结课考试】\n课程甲\n10月25日\n15:40-17:40'},
        {'raw_text': '【结课考试】\n\n课程甲\n10月25日\n15:40-17:40'},
      ],
    });
    expect(unknown.extras, hasLength(1));
    expect(unknown.extras.first.containsKey('start_at'), false);
    expect(unknown.warnings, isNotEmpty);
    expect(
      () => parseHljuImport({
        'sourceTerm': '',
        'rows': [
          {'raw_text': '【结课考试】\n课程甲\n10月25日\n15:40-17:40'},
          {'raw_text': '【结课考试】\n课程甲\n10月26日\n15:40-17:40'},
        ],
      }),
      throwsFormatException,
    );
  });

  test(
    'unplaced practice remains unplaced and calendar Monday is validated',
    () {
      final data = packet([
        {'raw_text': '实践甲 [1-16周] 教师甲 备注:无,实践乙 [1-16周] 教师乙 备注:无', 'key': 'bz'},
      ]);
      data['first_monday'] = '2026-08-24';
      final value = parseHljuImport(data);
      expect(value.courses, isEmpty);
      expect(value.extras, hasLength(2));
      expect(value.extras.first['title'], '实践甲');
      expect(value.extras.first['kind'], 'unplaced_course');
      expect(value.extras.first.containsKey('start_at'), false);
      expect(value.extras.first.containsKey('weekday'), false);
      expect(value.sourceFirstMonday, '2026-08-24');
      data['first_monday'] = '2026-08-25';
      final invalidCalendar = parseHljuImport(data);
      expect(invalidCalendar.sourceFirstMonday, isNull);
      expect(invalidCalendar.extras, hasLength(2));
      expect(invalidCalendar.warnings, contains('第一周日期需要手动核对'));
    },
  );

  test(
    'malformed nonempty course never silently becomes successful import',
    () {
      expect(() => parseHljuImport(packet([])), throwsFormatException);
      expect(
        () => parseHljuImport(
          packet([
            {'raw_text': '课程甲\n时间待通知', 'weekday': 1},
          ]),
        ),
        throwsFormatException,
      );
      expect(
        () => parseHljuImport(
          packet([
            {'raw_text': '课程甲【001】\n教师甲\n[待定周][A101]\n第1-2节', 'weekday': 1},
          ]),
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'schedule changes retain source identity while content stays distinct',
    () {
      Map<String, dynamic> course(String weeks, String teacher, String venue) =>
          {
            'raw_text': '课程甲【001】\n[$teacher]\n[$weeks周][$venue]\n第1-2节',
            'weekday': 1,
            'source_key': 'official-schedule-1',
          };
      final before = parseHljuImport(packet([course('1-4', '教师甲', 'A101')]));
      final after = parseHljuImport(packet([course('2-8', '教师乙', 'B202')]));
      expect(
        before.courses.single['source_id'],
        after.courses.single['source_id'],
      );
      expect(
        before.courses.single['weeks'],
        isNot(after.courses.single['weeks']),
      );
      final oldExam = parseHljuImport(
        packet([
          {'raw_text': '【26秋随堂结课考试（120分钟）考试】\n课程甲\n10月25日\n15:40-17:40'},
        ]),
      );
      final movedExam = parseHljuImport(
        packet([
          {'raw_text': '【26秋随堂结课考试（90分钟）考试】\n\n课程甲\n11月2日\n14:00-15:30'},
        ]),
      );
      expect(
        oldExam.extras.single['source_id'],
        movedExam.extras.single['source_id'],
      );
      expect(
        oldExam.extras.single['start_at'],
        isNot(movedExam.extras.single['start_at']),
      );
    },
  );
}
