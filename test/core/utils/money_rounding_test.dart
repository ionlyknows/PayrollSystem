import 'package:flutter_test/flutter_test.dart';
import 'package:goil_payroll_attendance/core/utils/money_rounding.dart';

void main() {
  group('roundHalfUpDivision', () {
    test('rounds PHP 10.004 down and PHP 10.005 up (OD-29)', () {
      expect(roundHalfUpDivision(10004, 10), 1000); // 1000.4 centavos
      expect(roundHalfUpDivision(2001, 2), 1001); // 1000.5 centavos
    });

    test('is symmetric around zero (OD-30)', () {
      expect(roundHalfUpDivision(-10004, 10), -1000);
      expect(roundHalfUpDivision(-2001, 2), -1001);
      expect(roundHalfUpDivision(-1, 2), -1);
      expect(roundHalfUpDivision(1, 2), 1);
    });

    test('exact divisions are unchanged', () {
      expect(roundHalfUpDivision(48000, 12), 4000);
      expect(roundHalfUpDivision(0, 5), 0);
    });

    test('rounds up above one half and down below it', () {
      expect(roundHalfUpDivision(2, 3), 1);
      expect(roundHalfUpDivision(1, 3), 0);
    });

    test('handles negative denominators', () {
      expect(roundHalfUpDivision(1, -2), -1);
      expect(roundHalfUpDivision(-1, -2), 1);
    });

    test('throws on a zero denominator', () {
      expect(() => roundHalfUpDivision(1, 0), throwsArgumentError);
    });
  });
}
