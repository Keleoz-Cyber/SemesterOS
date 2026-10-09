import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/calendar/timetable_scale.dart';

void main() {
  const periods = <Map<String, dynamic>>[
    {'number': 4, 'start': '11:10', 'end': '12:00'},
    {'number': 5, 'start': '14:00', 'end': '14:50'},
  ];

  test('lunch points reserve drawing space without becoming occupied time', () {
    final ordinary = TimetableScale.build(670, 890, periods, .95, 1, []);
    final occupied = <({int start, int end})>[];
    final withPoint = TimetableScale.build(
      670,
      890,
      periods,
      .95,
      1,
      occupied,
      markerStarts: [730],
      markerHeight: 64,
    );
    expect(occupied, isEmpty);
    expect(withPoint.minutes, contains(730));
    expect(withPoint.at(840) - withPoint.at(730), greaterThanOrEqualTo(67));
    expect(ordinary.at(840) - ordinary.at(720), closeTo(18, .01));
    expect(withPoint.at(720), closeTo(ordinary.at(720), .01));
    expect(withPoint.at(730), greaterThan(withPoint.at(720)));
    expect(withPoint.at(840), greaterThan(withPoint.at(730)));
  });

  test(
    'different close starts stay distinct while coincident starts share room',
    () {
      TimetableScale make(Iterable<int> starts) => TimetableScale.build(
        670,
        890,
        periods,
        1.4,
        1.6,
        [],
        markerStarts: starts,
        markerHeight: 102.4,
      );
      final unique = make([730, 740]);
      final duplicate = make([730, 730, 740]);
      expect(unique.at(740) - unique.at(730), closeTo(105.4, .01));
      expect(unique.at(840) - unique.at(740), closeTo(105.4, .01));
      expect(duplicate.minutes, unique.minutes);
      expect(duplicate.positions, unique.positions);
    },
  );

  test('without bell times the ordinary minute scale stays unchanged', () {
    final scale = TimetableScale.build(
      480,
      1200,
      [],
      .95,
      1,
      [(start: 840, end: 950)],
      markerStarts: [730],
      markerHeight: 64,
    );
    expect(scale.at(730), closeTo((730 - 480) * .95, .01));
    expect(scale.at(840), closeTo((840 - 480) * .95, .01));
    expect(scale.at(950), closeTo((950 - 480) * .95, .01));
  });
}
