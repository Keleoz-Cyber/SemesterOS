import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'haut_parser.dart' show parseSections, parseWeeks;

/// Only timetable fields cross the school WebView bridge.
class HljuImportBundle {
  const HljuImportBundle({
    required this.courses,
    required this.extras,
    required this.sourceTerm,
    required this.warnings,
    required this.metadata,
    this.sourceFirstMonday,
  });

  final List<Map<String, dynamic>> courses;
  final List<Map<String, dynamic>> extras;
  final String sourceTerm;
  final String? sourceFirstMonday;
  final List<String> warnings;
  final Map<String, dynamic> metadata;
}

String _text(dynamic value) => value == null ? '' : value.toString().trim();

String _plain(String value) => value
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('\r', '')
    .trim();

String _nativeKey(Map<String, dynamic> row) =>
    _text(row['source_key']).isNotEmpty
    ? _text(row['source_key'])
    : _text(row['SKID']);

String _sourceId(Map<String, dynamic> row, String kind, List<Object?> parts) {
  final hash = sha256
      .convert(utf8.encode(jsonEncode([kind, ...parts])))
      .toString();
  final key = _nativeKey(row);
  // Identity deliberately excludes fields that change when a class is moved.
  // Content deduplication is handled separately below.
  return key.isEmpty ? 'hlju:$hash' : 'hlju:$key:${hash.substring(0, 16)}';
}

String _courseTitle(String value) => value
    .replaceFirst(RegExp(r'^\s*[（(]免听[）)]\s*'), '')
    .replaceFirst(RegExp(r'\s*【[^】]*】\s*$'), '')
    .trim();

String _examType(String raw) =>
    (RegExp(r'【([^】]*考试[^】]*)】').firstMatch(raw)?[1] ?? '考试')
        .replaceAll(RegExp(r'\d{2,4}[秋春]'), '')
        .replaceAll(RegExp(r'[（(]\s*\d+\s*分钟[）)]'), '')
        .replaceAll(RegExp(r'\s'), '')
        .replaceAll('考试考试', '考试');

String? _clock(dynamic value) {
  final text = _text(value);
  if (text.isEmpty) return null;
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::00)?$').firstMatch(text);
  if (match == null || int.parse(match[1]!) > 23 || int.parse(match[2]!) > 59) {
    throw FormatException('课表时刻无法确认：$text');
  }
  return '${match[1]!.padLeft(2, '0')}:${match[2]}';
}

DateTime? _date(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final result = DateTime(year, month, day);
  return result.year == year && result.month == month && result.day == day
      ? result
      : null;
}

String _iso(DateTime day, String time) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}T$time:00+08:00';

int? _examYear(Map<String, dynamic> value, String raw, int month) {
  final label = RegExp(r'(\d{2,4})(秋|春)').firstMatch(raw);
  if (label != null) {
    final short = int.parse(label[1]!);
    final year = short < 100 ? 2000 + short : short;
    return label[2] == '秋' && month < 7 ? year + 1 : year;
  }
  final term = RegExp(
    r'(\d{4})\s*[-—–]\s*(\d{4})',
  ).firstMatch('${_text(value['year'])} ${_text(value['sourceTerm'])}');
  if (term == null) return null;
  final first = int.parse(term[1]!);
  final second = int.parse(term[2]!);
  if (second != first + 1) return null;
  return month < 7 ? second : first;
}

Map<String, dynamic> _exam(
  Map<String, dynamic> packet,
  Map<String, dynamic> row,
  String raw,
  List<String> warnings,
) {
  final lines = raw.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty);
  final title = lines.firstWhere(
    (e) =>
        !e.startsWith('【') &&
        !RegExp(r'^\d{1,4}[-年/月]').hasMatch(e) &&
        !RegExp(r'^\d{1,2}:\d{2}').hasMatch(e),
    orElse: () => '',
  );
  if (title.isEmpty) throw const FormatException('考试名称无法确认，请核对原课表');
  final result = <String, dynamic>{
    'kind': 'exam',
    'title': _courseTitle(title),
    'source_id': _sourceId(row, 'exam', [
      _examType(raw),
      if (_nativeKey(row).isEmpty) _courseTitle(title),
    ]),
    'raw_text': raw,
  };
  final fullDate = RegExp(
    r'(\d{4})[-年](\d{1,2})[-月](\d{1,2})(?:日)?',
  ).firstMatch(raw);
  final shortDate = RegExp(r'(\d{1,2})月(\d{1,2})日').firstMatch(raw);
  int? year, month, day;
  if (fullDate != null) {
    year = int.parse(fullDate[1]!);
    month = int.parse(fullDate[2]!);
    day = int.parse(fullDate[3]!);
  } else if (shortDate != null) {
    month = int.parse(shortDate[1]!);
    day = int.parse(shortDate[2]!);
    year = _examYear(packet, raw, month);
  }
  final time = RegExp(
    r'(\d{1,2}:\d{2})\s*[-—–至]\s*(\d{1,2}:\d{2})',
  ).firstMatch(raw);
  DateTime? date;
  if (year != null && month != null && day != null) {
    date = _date(
      '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
    );
    if (date == null) throw FormatException('考试日期无法确认：$raw');
  }
  if (date != null && time != null) {
    final start = _clock(time[1])!;
    final end = _clock(time[2])!;
    if (end.compareTo(start) <= 0) {
      throw const FormatException('考试结束时刻早于开始时刻，请核对原课表');
    }
    result['start_at'] = _iso(date, start);
    result['end_at'] = _iso(date, end);
  } else {
    final singleTime = RegExp(r'\d{1,2}:\d{2}').firstMatch(raw);
    if (date != null && singleTime != null) {
      result['start_at'] = _iso(date, _clock(singleTime[0])!);
    } else {
      warnings.add('${result['title']}的考试日期或时刻需要核对');
      if (date != null) result['date'] = _iso(date, '00:00').substring(0, 10);
    }
  }
  // A missing venue remains missing. The selected table column is not a venue.
  final venue = RegExp(r'(?:地点|考场)\s*[:：]\s*([^\n\[\]]+)').firstMatch(raw);
  if (venue != null && venue[1]!.trim().isNotEmpty) {
    result['location'] = venue[1]!.trim();
  }
  return result;
}

List<Map<String, dynamic>> _unplaced(Map<String, dynamic> row, String raw) {
  // Practice records live in the school's remarks row, not a weekday cell.
  final parts = raw.split(RegExp(r'[,，]\s*(?=[^,，\n]+\s*\[\d[^\]]*周\])'));
  final result = <Map<String, dynamic>>[];
  for (final part in parts) {
    final match = RegExp(
      r'^\s*(.+?)\s*\[([^\]]*周[^\]]*)\]\s*(.*)$',
      dotAll: true,
    ).firstMatch(part);
    if (match == null) throw const FormatException('未排课课程的名称或周次无法确认，请核对备注');
    final title = _courseTitle(match[1]!);
    if (title.isEmpty) throw const FormatException('未排课课程缺少名称');
    final weeks = parseWeeks(match[2]!);
    final tail = match[3]!.trim();
    final noteAt = tail.indexOf(RegExp(r'备注\s*[:：]'));
    final teacher = (noteAt < 0 ? tail : tail.substring(0, noteAt)).trim();
    final note = noteAt < 0
        ? ''
        : tail.substring(noteAt).replaceFirst(RegExp(r'^备注\s*[:：]'), '').trim();
    result.add({
      'kind': 'unplaced_course',
      'title': title,
      if (teacher.isNotEmpty) 'teacher': teacher,
      'weeks': weeks,
      if (note.isNotEmpty && note != '无') 'notes': note,
      'raw_text': part.trim(),
      'source_id': _sourceId(row, 'unplaced_course', [title]),
    });
  }
  return result;
}

Map<String, dynamic> _course(Map<String, dynamic> row, String raw) {
  final lines = raw
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (lines.isEmpty) throw const FormatException('课程内容为空');
  final timeLine = RegExp(r'^\d{1,2}:\d{2}\s*[-—–]\s*\d{1,2}:\d{2}$');
  final titleIndex = lines.indexWhere((e) => !timeLine.hasMatch(e));
  if (titleIndex < 0) throw const FormatException('课程缺少名称');
  final title = _courseTitle(lines[titleIndex]);
  final week = RegExp(r'\[([^\]]*周[^\]]*)\]').firstMatch(raw);
  if (title.isEmpty || week == null) {
    throw const FormatException('课程名称或周次无法确认，请核对原课表');
  }
  final weeks = parseWeeks(week[1]!);
  var sectionsText = '';
  final section = RegExp(r'第\s*(\d+(?:\s*[-—–]\s*\d+)?)\s*节').firstMatch(raw);
  if (section != null) {
    sectionsText = section[1]!.replaceAll(RegExp(r'[—–]'), '-');
  } else if (_text(row['section_start']).isNotEmpty) {
    sectionsText =
        '${row['section_start']}-${row['section_end'] ?? row['section_start']}';
  } else if (_text(row['KSJC']).isNotEmpty) {
    sectionsText = '${row['KSJC']}-${row['JSJC'] ?? row['KSJC']}';
  }
  final sections = parseSections(sectionsText);
  var weekday = int.tryParse(_text(row['weekday']));
  final key = _text(row['key']).isEmpty ? _text(row['KEY']) : _text(row['key']);
  weekday ??= int.tryParse(
    RegExp(r'^xq([1-7])_jc\d+$').firstMatch(key)?[1] ?? '',
  );
  if (weekday == null || weekday < 1 || weekday > 7) {
    throw const FormatException('课程星期无法确认，请核对原课表');
  }
  final teacherLine = titleIndex + 1 < lines.length
      ? lines[titleIndex + 1]
      : '';
  final teacher =
      RegExp(r'^\[\s*\d[^\]]*周').hasMatch(teacherLine) ||
          teacherLine.startsWith('第')
      ? ''
      : teacherLine.replaceAll(RegExp(r'^\[|\]$'), '').trim();
  final locationAt = week.end;
  final location =
      RegExp(
        r'^\s*\[([^\]]*)\]',
      ).firstMatch(raw.substring(locationAt))?[1]?.trim() ??
      '';
  String? start = _clock(row['start_time'] ?? row['KSSJ']);
  String? end = _clock(row['end_time'] ?? row['JSSJ']);
  if (start == null && end == null && timeLine.hasMatch(lines.first)) {
    final times = lines.first.split(RegExp(r'\s*[-—–]\s*'));
    start = _clock(times[0]);
    end = _clock(times[1]);
  }
  if (start != null && end != null && end.compareTo(start) <= 0) {
    throw const FormatException('课程结束时刻早于开始时刻，请核对原课表');
  }
  return {
    'title': title,
    'teacher': teacher,
    'location': location,
    'weekday': weekday,
    'weeks': weeks,
    'sections': sections,
    'source_id': _sourceId(row, 'course', [
      if (_nativeKey(row).isEmpty)
        lines[titleIndex]
            .replaceFirst(RegExp(r'^\s*[（(]免听[）)]\s*'), '')
            .replaceAll(RegExp(r'\s'), ''),
      weekday,
      sections,
    ]),
    if (row['attendance_exempt'] == true ||
        RegExp(r'^\s*[（(]免听[）)]').hasMatch(lines[titleIndex]))
      'attendance_exempt': true,
    'start_time': ?start,
    'end_time': ?end,
  };
}

HljuImportBundle parseHljuImport(dynamic value) {
  if (value is! Map) throw const FormatException('课表格式无法确认');
  final packet = Map<String, dynamic>.from(value);
  final rows = packet['rows'];
  if (rows is! List || rows.isEmpty) {
    throw const FormatException('没有读取到课程，请核对学期；原课表保持不变');
  }
  if (rows.length > 600) throw const FormatException('课程条目超过本次读取上限');
  final courses = <Map<String, dynamic>>[];
  final extras = <Map<String, dynamic>>[];
  final warnings = <String>[];
  final seen = <String, Map<String, dynamic>>{};
  final identities = <String, List<Map<String, dynamic>>>{};
  for (var i = 0; i < rows.length; i++) {
    if (rows[i] is! Map) throw FormatException('第${i + 1}条课程格式无法确认');
    final row = Map<String, dynamic>.from(rows[i] as Map);
    final raw = _plain(_text(row['raw_text'] ?? row['SKSJ']));
    if (raw.isEmpty) throw FormatException('第${i + 1}条课程内容为空，未跳过该条课程');
    final key = _text(row['key'] ?? row['KEY']);
    final List<Map<String, dynamic>> parsed;
    final isExam = RegExp(r'【[^】]*考试[^】]*】').hasMatch(raw);
    if (isExam) {
      parsed = [_exam(packet, row, raw, warnings)];
    } else if (key == 'bz') {
      parsed = _unplaced(row, raw);
    } else {
      parsed = [_course(row, raw)];
    }
    for (final result in parsed) {
      // Fixed-column tables render the same meeting more than once.
      final String fingerprint;
      if (result['kind'] == null) {
        fingerprint = jsonEncode([
          result['source_id'],
          Map.from(result)..remove('source_id'),
        ]);
      } else {
        // API and table copies often differ only in HTML or line breaks.
        // For an exam without a year, keep its explicit month/day and clocks
        // in the key: two unknown-date exams must not collapse into one.
        final unresolved =
            result['kind'] == 'exam' &&
                result['start_at'] == null &&
                result['date'] == null
            ? RegExp(
                r'\d{1,2}月\d{1,2}日|\d{1,2}:\d{2}',
              ).allMatches(raw).map((e) => e[0]).toList()
            : null;
        fingerprint = jsonEncode([
          result['kind'],
          result['title'],
          result['weeks'],
          result['location'],
          result['date'],
          result['start_at'],
          result['end_at'],
          unresolved != null && unresolved.isEmpty
              ? raw.replaceAll(RegExp(r'\s'), '')
              : unresolved,
        ]);
      }
      final existing = seen[fingerprint];
      if (existing != null) {
        for (final name in ['teacher', 'notes', 'location']) {
          if (_text(existing[name]).isEmpty && _text(result[name]).isNotEmpty) {
            existing[name] = result[name];
          }
        }
        continue;
      }
      seen[fingerprint] = result;
      final identity = result['source_id'] as String;
      final sameIdentity = identities.putIfAbsent(identity, () => []);
      if (sameIdentity.isNotEmpty) {
        if (result['kind'] == 'exam') {
          throw FormatException('${result['title']}有两条无法区分的考试，请核对原课表');
        }
        // Some classes really have two separate week ranges at the same slot.
        // Keep both, using the stable upstream order and an explicit review hint.
        if (sameIdentity.length == 1) {
          sameIdentity.first['source_id'] = '$identity:1';
        }
        result['source_id'] = '$identity:${sameIdentity.length + 1}';
        warnings.add('${result['title']}有多条同名安排，请核对周次');
      }
      sameIdentity.add(result);
      if (result['kind'] == null) {
        courses.add(result);
      } else {
        extras.add(result);
      }
    }
  }
  String? monday;
  if (_text(packet['first_monday']).isNotEmpty) {
    monday = _text(packet['first_monday']);
    final date = _date(monday);
    if (date == null || date.weekday != DateTime.monday) {
      warnings.add('第一周日期需要手动核对');
      monday = null;
    }
  }
  final incomingWarnings = packet['warnings'];
  if (incomingWarnings is List) {
    for (final warning in incomingWarnings) {
      if (warning is String && warning.trim().isNotEmpty) {
        warnings.add(warning.trim());
      }
    }
  }
  return HljuImportBundle(
    courses: courses,
    extras: extras,
    sourceTerm: _text(packet['sourceTerm']),
    sourceFirstMonday: monday,
    warnings: warnings.toSet().toList(),
    metadata: packet['metadata'] is Map
        ? Map<String, dynamic>.from(packet['metadata'] as Map)
        : const {},
  );
}
