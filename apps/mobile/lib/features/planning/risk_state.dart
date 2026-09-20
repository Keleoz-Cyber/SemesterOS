bool riskSnapshotUsable(
  Map<String, dynamic>? data,
  String? semesterId,
  int? revision,
  DateTime now,
) {
  if (data == null ||
      semesterId == null ||
      revision == null ||
      data['semester_id'] != semesterId ||
      data['revision'] != revision) {
    return false;
  }
  final computed = DateTime.tryParse('${data['computed_at']}');
  final until = DateTime.tryParse('${data['valid_until']}');
  return computed != null &&
      until != null &&
      until.isAfter(now) &&
      !computed.isAfter(now.add(const Duration(seconds: 30)));
}
