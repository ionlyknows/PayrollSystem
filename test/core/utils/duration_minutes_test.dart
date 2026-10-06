import 'package:flutter_test/flutter_test.dart';
import 'package:goil_payroll_attendance/core/utils/duration_minutes.dart';

void main() {
  test('minutes round-trip for the documented examples (OD-28)', () {
    for (final minutes in [30, 60, 90, 720]) {
      expect(minutesFromDuration(durationFromMinutes(minutes)), minutes);
    }
  });

  test('a 12-hour shift is 720 minutes', () {
    expect(minutesFromDuration(const Duration(hours: 12)), 720);
    expect(12 * minutesPerHour, 720);
  });

  test('a duration with leftover seconds is rejected', () {
    expect(
      () => minutesFromDuration(const Duration(seconds: 90)),
      throwsArgumentError,
    );
  });
}
