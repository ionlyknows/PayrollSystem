import 'package:flutter_test/flutter_test.dart';
import 'package:goil_payroll_attendance/core/utils/id_generator.dart';

void main() {
  final uuidV4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  test('newId returns a lowercase hyphenated UUID v4', () {
    expect(IdGenerator.newId(), matches(uuidV4));
  });

  test('newId returns unique values', () {
    final ids = {for (var i = 0; i < 1000; i++) IdGenerator.newId()};
    expect(ids.length, 1000);
  });
}
