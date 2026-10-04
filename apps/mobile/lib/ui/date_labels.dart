/// Human-readable dates in the school's timezone. Short columns keep just time.
String studentDate(DateTime day, {bool weekday = false}) {
  final year = DateTime.now().toUtc().add(const Duration(hours: 8)).year;
  return '${day.year == year ? '' : '${day.year}年'}${day.month}月${day.day}日${weekday ? ' 周${'一二三四五六日'[day.weekday - 1]}' : ''}';
}

String shortCampusLocation(String value) => value
    .replaceAllMapped(
      RegExp(r'莲\s*([0-9]+)\s*号?(?:教学)?楼\s*'),
      (m) => '莲${m[1]}-',
    )
    .replaceAll('教学楼', '')
    .replaceAll('惟学楼', '惟学-')
    .replaceAll('文科组团楼', '文科-')
    .replaceAll(RegExp(r'\s+'), '')
    .trim();
