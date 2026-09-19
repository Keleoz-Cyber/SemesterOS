String _normalize(String value) => value
    .replaceAll('（', '(')
    .replaceAll('）', ')')
    .replaceAll(RegExp(r'[，、;；]'), ',')
    .replaceAll(RegExp(r'\s'), '');

List<int> _ranges(String value, {required bool weeks}) {
  var text = _normalize(
    value,
  ).replaceAll(weeks ? '周' : '节', '').replaceAll('第', '');
  if (!weeks) text = text.replaceAll('(', '').replaceAll(')', '');
  final pattern = RegExp(
    weeks
        ? r'^(\d{1,2})(?:-(\d{1,2}))?(?:\((单|双)\))?$'
        : r'^(\d{1,2})(?:-(\d{1,2}))?$',
  );
  final result = <int>{};
  for (final part in text.split(',')) {
    final match = pattern.firstMatch(part);
    if (match == null) {
      throw FormatException('${weeks ? '周次' : '节次'}格式无法确认：$value');
    }
    final start = int.parse(match[1]!);
    final end = int.parse(match[2] ?? match[1]!);
    if (start < 1 || end > 30 || end < start) {
      throw FormatException('周次或节次范围不正确：$value');
    }
    final parity = weeks ? match[3] : null;
    for (var n = start; n <= end; n++) {
      if (parity == null || (parity == '单' ? n.isOdd : n.isEven)) result.add(n);
    }
  }
  if (result.isEmpty) throw FormatException('没有可确认的周次或节次');
  return result.toList()..sort();
}

List<int> parseWeeks(String value) => _ranges(value, weeks: true);
List<int> parseSections(String value) => _ranges(value, weeks: false);

List<Map<String, dynamic>> parseHautCourses(List<dynamic> rows) {
  if (rows.isEmpty) throw const FormatException('没有读取到课程，请核对学年学期；原课表保持不变');
  if (rows.length > 300) throw const FormatException('课程条目超过本次读取上限');
  final result = <Map<String, dynamic>>[];
  for (var i = 0; i < rows.length; i++) {
    if (rows[i] is! Map) throw FormatException('第${i + 1}条课程格式无法确认');
    final row = Map<String, dynamic>.from(rows[i] as Map);
    String field(String name) => (row[name] ?? '').toString().trim();
    final title = field('kcmc');
    final weekday = int.tryParse(field('xqj'));
    if (title.isEmpty || weekday == null || weekday < 1 || weekday > 7) {
      throw FormatException('第${i + 1}条课程缺少名称或星期，未跳过该条课程');
    }
    var sections = field('jc');
    if (sections.isEmpty) {
      sections = field('jcs');
      if (RegExp(r'^\d{4}$').hasMatch(sections)) {
        sections =
            '${int.parse(sections.substring(0, 2))}-${int.parse(sections.substring(2))}';
      }
    }
    result.add({
      'title': title,
      'teacher': field('xm'),
      'location': field('cdmc'),
      'source_id': field('jxb_id').isNotEmpty
          ? field('jxb_id')
          : field('kch_id'),
      'weekday': weekday,
      'weeks': parseWeeks(field('zcd')),
      'sections': parseSections(sections),
    });
  }
  return result;
}
