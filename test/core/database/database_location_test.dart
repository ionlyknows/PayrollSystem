import 'package:flutter_test/flutter_test.dart';
import 'package:goil_payroll_attendance/core/database/database_location.dart';

void main() {
  test('database name is unchanged', () {
    expect(databaseName, 'goil_payroll');
  });

  test('Windows path is under the given local application-data folder', () {
    expect(
      windowsDatabasePath(r'C:\Users\Test\AppData\Local'),
      r'C:\Users\Test\AppData\Local\GOilPayroll\goil_payroll.sqlite',
    );
  });

  test('a trailing separator is not doubled', () {
    expect(
      windowsDatabasePath(r'C:\Users\Test\AppData\Local\'),
      r'C:\Users\Test\AppData\Local\GOilPayroll\goil_payroll.sqlite',
    );
  });
}
