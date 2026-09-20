import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/timetable/timetable_layout.dart';

Map<String, dynamic> event(String id, String start, String end) => {
  'id': id,
  'title': id,
  'start_at': '2026-09-21T$start:00+08:00',
  'end_at': '2026-09-21T$end:00+08:00',
};

void main() {
  test(
    'overlapping courses get separate lanes without losing either record',
    () {
      final input = [
        event('a', '08:00', '10:00'),
        event('b', '09:00', '11:00'),
      ];
      final placed = arrangeDayCourses(input);
      expect(placed.length, 2);
      expect(placed[0].lane, isNot(placed[1].lane));
      expect(placed.every((e) => e.laneCount == 2), true);
      expect(input[0]['id'], 'a');
    },
  );

  test('adjacent courses share a lane, chained overlaps reuse free space', () {
    final placed = arrangeDayCourses([
      event('c', '10:00', '12:00'),
      event('a', '08:00', '10:00'),
      event('b', '09:00', '11:00'),
      event('d', '12:00', '13:00'),
    ]);
    expect(placed.map((e) => e.event['id']).toList(), ['a', 'b', 'c', 'd']);
    expect(placed[0].lane, placed[2].lane);
    expect(placed[2].laneCount, 2);
    expect(placed[3].laneCount, 1);
  });

  test('compact week labels preserve gaps and odd/even meaning', () {
    expect(compactWeeks([1, 2, 3, 5, 6]), '第1—3、5—6周');
    expect(compactWeeks([1, 3, 5, 7]), '第1—7周 · 单周');
    expect(compactWeeks([2, 4, 6, 8]), '第2—8周 · 双周');
    expect(compactWeeks([3]), '第3周');
  });
}
