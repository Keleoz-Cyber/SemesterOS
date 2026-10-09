/// A timetable uses equal teaching-period rows and shorter empty breaks.
/// Only drawing coordinates change; record times and overlap checks stay real.
class TimetableScale {
  final List<int> minutes;
  final List<double> positions;
  TimetableScale(this.minutes, this.positions);

  factory TimetableScale.build(
    int first,
    int last,
    List<Map<String, dynamic>> periods,
    double minuteHeight,
    double textScale,
    List<({int start, int end})> occupied, {
    Iterable<int> markerStarts = const [],
    double markerHeight = 0,
  }) {
    final ranges = <({int start, int end})>[];
    int? clock(dynamic value) {
      final pieces = '$value'.split(':');
      if (pieces.length < 2) return null;
      final h = int.tryParse(pieces[0]), m = int.tryParse(pieces[1]);
      return h == null || m == null ? null : h * 60 + m;
    }

    for (final period in periods) {
      final a = clock(period['start']), b = clock(period['end']);
      if (a != null && b != null && b > a) ranges.add((start: a, end: b));
    }
    final markers = markerStarts
        .where((minute) => minute >= first && minute < last)
        .toSet();
    if (ranges.isEmpty && markers.isEmpty) {
      return TimetableScale([first, last], [0, (last - first) * minuteHeight]);
    }
    final boundaries = <int>{
      first,
      last,
      ...markers,
      for (final r in ranges) ...[
        r.start.clamp(first, last),
        r.end.clamp(first, last),
      ],
      // These are drawing boundaries from saved occurrences, not invented
      // teaching periods. A course outside local bell times is still occupied.
      for (final r in occupied)
        if (r.end > first && r.start < last && r.end > r.start) ...[
          r.start.clamp(first, last),
          r.end.clamp(first, last),
        ],
    }.toList()..sort();
    final ys = <double>[0];
    for (var i = 1; i < boundaries.length; i++) {
      final a = boundaries[i - 1], b = boundaries[i];
      final period = ranges
          .where((p) => p.start <= a && p.end >= b)
          .firstOrNull;
      final hasOccupancy = occupied.any((r) => r.start < b && r.end > a);
      var extent = ranges.isEmpty
          ? (b - a) * minuteHeight
          : period != null
          ? (b - a) / (period.end - period.start) * 52 * textScale.clamp(1, 1.6)
          : hasOccupancy
          ? ((b - a) * minuteHeight)
                .clamp(
                  44 * textScale.clamp(1, 1.6),
                  120 * textScale.clamp(1, 1.6),
                )
                .toDouble()
          : ((b - a) * minuteHeight).clamp(8, 18).toDouble();
      // A start-only record has no occupied interval. Give its real start
      // anchor enough drawing room for a readable marker without claiming an
      // end time or folding it into the next non-overlapping course.
      if (markers.contains(a) && extent < markerHeight + 3) {
        extent = markerHeight + 3;
      }
      ys.add(ys.last + extent);
    }
    return TimetableScale(boundaries, ys);
  }

  double at(int minute) {
    for (var i = 1; i < minutes.length; i++) {
      if (minute <= minutes[i]) {
        return positions[i - 1] +
            (minute - minutes[i - 1]) /
                (minutes[i] - minutes[i - 1]) *
                (positions[i] - positions[i - 1]);
      }
    }
    return positions.last;
  }
}
