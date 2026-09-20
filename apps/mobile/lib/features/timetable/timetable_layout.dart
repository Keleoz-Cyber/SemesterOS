class CoursePlacement {
  final Map<String, dynamic> event;
  final int lane;
  final int laneCount;
  const CoursePlacement(this.event, this.lane, this.laneCount);
}

List<CoursePlacement> arrangeDayCourses(List<Map<String, dynamic>> events) {
  final sorted = List<Map<String, dynamic>>.of(events)
    ..sort((a, b) {
      final order = DateTime.parse(
        a['start_at'],
      ).compareTo(DateTime.parse(b['start_at']));
      return order != 0 ? order : '${a['id']}'.compareTo('${b['id']}');
    });
  final result = <CoursePlacement>[];
  final group = <({Map<String, dynamic> event, int lane})>[];
  final ends = <DateTime>[];
  DateTime? groupEnd;
  void flush() {
    for (final item in group) {
      result.add(CoursePlacement(item.event, item.lane, ends.length));
    }
    group.clear();
    ends.clear();
    groupEnd = null;
  }

  for (final event in sorted) {
    final start = DateTime.parse(event['start_at']);
    final end = DateTime.parse(event['end_at']);
    if (groupEnd != null && !start.isBefore(groupEnd!)) flush();
    var lane = ends.indexWhere((e) => !e.isAfter(start));
    if (lane < 0) {
      lane = ends.length;
      ends.add(end);
    } else {
      ends[lane] = end;
    }
    group.add((event: event, lane: lane));
    if (groupEnd == null || end.isAfter(groupEnd!)) groupEnd = end;
  }
  flush();
  return result;
}

String compactWeeks(List<dynamic> values) {
  final weeks = values.cast<int>().toSet().toList()..sort();
  if (weeks.isEmpty) return '周次待确认';
  if (weeks.length == 1) return '第${weeks.first}周';
  if (weeks.length > 2 &&
      List.generate(
        weeks.length - 1,
        (i) => weeks[i + 1] - weeks[i],
      ).every((gap) => gap == 2)) {
    return '第${weeks.first}—${weeks.last}周 · ${weeks.first.isOdd ? '单周' : '双周'}';
  }
  final ranges = <String>[];
  var start = weeks.first, end = start;
  for (final week in weeks.skip(1)) {
    if (week == end + 1) {
      end = week;
    } else {
      ranges.add(start == end ? '$start' : '$start—$end');
      start = end = week;
    }
  }
  ranges.add(start == end ? '$start' : '$start—$end');
  return '第${ranges.join('、')}周';
}
