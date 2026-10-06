import 'package:flutter_test/flutter_test.dart';
import 'package:goil_payroll_attendance/core/utils/business_time.dart';

void main() {
  test('uses the Asia/Manila calendar date, not the UTC date (OD-03)', () {
    expect(businessDateOf(DateTime.utc(2026, 10, 5, 15, 59, 59)), '2026-10-05');
    expect(businessDateOf(DateTime.utc(2026, 10, 5, 16, 0, 0)), '2026-10-06');
  });

  test('rolls over the year boundary in Manila time', () {
    expect(businessDateOf(DateTime.utc(2026, 12, 31, 16, 0, 0)), '2027-01-01');
  });

  test('does not depend on how the instant was constructed', () {
    expect(
      businessDateOf(DateTime.parse('2026-10-06T00:00:00+08:00')),
      '2026-10-06',
    );
    expect(
      businessDateOf(DateTime.parse('2026-10-05T23:59:59+08:00')),
      '2026-10-05',
    );
  });
}
