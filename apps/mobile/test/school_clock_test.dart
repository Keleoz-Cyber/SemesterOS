import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/app/controller.dart';

void main() {
  tearDown(() => debugSchoolClock = null);

  void expectLiveSchoolTime() {
    final before = DateTime.now().toUtc().add(const Duration(hours: 8));
    final now = schoolNow();
    final after = DateTime.now().toUtc().add(const Duration(hours: 8));
    expect(now.isBefore(before), isFalse);
    expect(now.isAfter(after), isFalse);
  }

  test('school clock defaults to the current UTC+08 wall time', () {
    expect(debugSchoolClock, isNull);
    expectLiveSchoolTime();
  });

  test('debug school clock can fix a preview wall time', () {
    final fixed = DateTime.utc(2026, 10, 9, 13, 18);
    debugSchoolClock = () => fixed;
    expect(schoolNow(), fixed);
  });

  test('resetting debug school clock restores the current wall time', () {
    debugSchoolClock = () => DateTime.utc(2026, 10, 9, 13, 18);
    debugSchoolClock = null;
    expectLiveSchoolTime();
  });
}
