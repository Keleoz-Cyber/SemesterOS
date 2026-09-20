import 'package:flutter_test/flutter_test.dart';
import 'package:semester_os/features/planning/risk_state.dart';

void main() {
  test(
    'risk belongs to one semester revision and expires with elapsed time',
    () {
      final now = DateTime.utc(2026, 9, 21, 0);
      final data = {
        'semester_id': 'a',
        'revision': 3,
        'computed_at': now.toIso8601String(),
        'valid_until': now.add(const Duration(minutes: 1)).toIso8601String(),
      };
      expect(riskSnapshotUsable(data, 'a', 3, now), isTrue);
      expect(riskSnapshotUsable(data, 'a', 4, now), isFalse);
      expect(riskSnapshotUsable(data, 'b', 3, now), isFalse);
      expect(
        riskSnapshotUsable(data, 'a', 3, now.add(const Duration(seconds: 61))),
        isFalse,
      );
      expect(riskSnapshotUsable(null, 'a', 3, now), isFalse);
    },
  );
}
