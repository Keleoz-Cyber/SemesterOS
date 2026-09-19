import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/import/haut_parser.dart';

void main() {
  test('preserves odd/even and discontinuous teaching weeks', () {
    expect(parseWeeks('1-8周(单),10-16周(双)，19周'), [
      1,
      3,
      5,
      7,
      10,
      12,
      14,
      16,
      19,
    ]);
  });
  test('does not invent weeks for unknown or malformed input', () {
    for (final value in ['', '待通知', '16-1周', '1-99周', '1-8周或另行通知']) {
      expect(() => parseWeeks(value), throwsFormatException);
    }
  });
  test('parses section gaps without filling missing periods', () {
    expect(parseSections('(1-2节),5-6节'), [1, 2, 5, 6]);
  });
  test('rejects malformed sections instead of silently dropping a course', () {
    expect(() => parseSections('上午'), throwsFormatException);
    expect(() => parseSections('0-2节'), throwsFormatException);
  });
  test('normalizes official field names without exporting private fields', () {
    final rows = parseHautCourses([
      {
        'kcmc': '概率论',
        'xm': '教师甲',
        'cdmc': 'A305',
        'xqj': '3',
        'zcd': '1-5周(单)',
        'jc': '1-2节',
        'jxb_id': 'class-1',
        'password': 'must-not-leave-webview',
        'student_id': 'private',
      },
    ]);
    expect(rows.single['title'], '概率论');
    expect(rows.single['weeks'], [1, 3, 5]);
    expect(rows.single['weekday'], 3);
    expect(rows.single.containsKey('password'), false);
    expect(rows.single.containsKey('student_id'), false);
  });
  test(
    'empty response and invalid row cannot look like a successful import',
    () {
      expect(() => parseHautCourses([]), throwsFormatException);
      expect(
        () => parseHautCourses([
          {'kcmc': '概率论'},
        ]),
        throwsFormatException,
      );
    },
  );
}
