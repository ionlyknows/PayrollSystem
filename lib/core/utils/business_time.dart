/// Asia/Manila (OD-03) is UTC+8 and does not currently observe daylight
/// saving time, so a fixed offset is used instead of a timezone database.
const Duration manilaUtcOffset = Duration(hours: 8);

/// Returns the Asia/Manila calendar date (`YYYY-MM-DD`) that [instant]
/// belongs to. The result never depends on the device time zone.
String businessDateOf(DateTime instant) {
  final manila = instant.toUtc().add(manilaUtcOffset);
  final year = manila.year.toString().padLeft(4, '0');
  final month = manila.month.toString().padLeft(2, '0');
  final day = manila.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
