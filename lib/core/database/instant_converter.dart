import 'package:drift/drift.dart';

/// Canonical database text form of an instant (design 3.2, OD-02):
/// UTC, `YYYY-MM-DDTHH:MM:SS.ffffffZ`, always exactly six fractional digits.
///
/// A fixed width makes SQLite TEXT comparison (CHECK constraints, ORDER BY,
/// range filters) chronologically correct. Years are assumed to be 0000-9999.
String formatCanonicalInstant(DateTime value) {
  final utc = value.toUtc();
  String pad(int v, int width) => v.toString().padLeft(width, '0');
  return '${pad(utc.year, 4)}-${pad(utc.month, 2)}-${pad(utc.day, 2)}'
      'T${pad(utc.hour, 2)}:${pad(utc.minute, 2)}:${pad(utc.second, 2)}'
      '.${pad(utc.millisecond, 3)}${pad(utc.microsecond, 3)}Z';
}

/// Current instant in canonical form, used as the client-side default for
/// `created_at` / `updated_at`.
String canonicalNowUtc() => formatCanonicalInstant(DateTime.now());

/// Shared converter for every stored instant column.
///
/// Writes always use [formatCanonicalInstant]. Reads accept any valid ISO-8601
/// text that carries a zone designator, including older 3-digit or whole-second
/// `Z` values, so existing rows stay readable without being rewritten.
class CanonicalInstantConverter extends TypeConverter<DateTime, String> {
  const CanonicalInstantConverter();

  @override
  DateTime fromSql(String fromDb) => DateTime.parse(fromDb).toUtc();

  @override
  String toSql(DateTime value) => formatCanonicalInstant(value);
}
