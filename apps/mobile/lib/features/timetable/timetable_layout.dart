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
