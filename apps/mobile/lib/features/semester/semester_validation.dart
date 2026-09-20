String? validateSemesterName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return '请填写学期名称';
  if (name.length > 80) return '学期名称不能超过80个字符';
  return null;
}

String? validateFirstMonday(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return '请选择学校校历第1周的周一';
  final date = DateTime.tryParse(text);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text) ||
      date == null ||
      date.toIso8601String().substring(0, 10) != text) {
    return '请选择有效的日期';
  }
  if (date.weekday != DateTime.monday) return '学期第1周的起始日期必须是周一';
  return null;
}

String? validateTotalWeeks(String? value) {
  final weeks = int.tryParse(value?.trim() ?? '');
  return weeks == null || weeks < 1 || weeks > 30 ? '学期总周数需为1—30的整数' : null;
}

List<Map<String, dynamic>> parseSemesterPeriods(String value) {
  final lines = value.trim().split('\n');
  if (value.trim().isEmpty) throw const FormatException('请填写至少一条节次时间');
  if (lines.length > 30) throw const FormatException('节次最多30条');
  final result = <Map<String, dynamic>>[];
  final seen = <int>{};
  final clock = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');
  for (var i = 0; i < lines.length; i++) {
    final columns = lines[i].trim().split(RegExp(r'\s+'));
    if (columns.length != 3) {
      throw FormatException('第${i + 1}行请按“节次 开始时间 结束时间”填写');
    }
    final number = int.tryParse(columns[0]);
    if (number == null || number < 1 || number > 30) {
      throw FormatException('第${i + 1}行的节次需为1—30的整数');
    }
    if (!seen.add(number)) throw FormatException('第${i + 1}行的第$number节重复了');
    if (!clock.hasMatch(columns[1]) || !clock.hasMatch(columns[2])) {
      throw FormatException('第${i + 1}行请使用24小时制，例如08:00');
    }
    if (columns[1].compareTo(columns[2]) >= 0) {
      throw FormatException('第${i + 1}行的结束时间必须晚于开始时间');
    }
    result.add({'number': number, 'start': columns[1], 'end': columns[2]});
  }
  result.sort((a, b) => (a['number'] as int).compareTo(b['number'] as int));
  for (var i = 1; i < result.length; i++) {
    if ((result[i - 1]['end'] as String).compareTo(
          result[i]['start'] as String,
        ) >
        0) {
      throw FormatException('第${result[i]['number']}节与上一节时间重叠或倒序');
    }
  }
  return result;
}

String? validateSemesterPeriods(String? value) {
  try {
    parseSemesterPeriods(value ?? '');
    return null;
  } on FormatException catch (e) {
    return e.message;
  }
}
