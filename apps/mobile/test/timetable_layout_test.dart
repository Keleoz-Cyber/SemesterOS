import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/timetable/timetable_layout.dart';

void main() {
  test('compact week labels preserve gaps and odd/even meaning', () {
    expect(compactWeeks([1, 2, 3, 5, 6]), '第1—3、5—6周');
    expect(compactWeeks([1, 3, 5, 7]), '第1—7周 · 单周');
    expect(compactWeeks([2, 4, 6, 8]), '第2—8周 · 双周');
    expect(compactWeeks([3]), '第3周');
  });
}
