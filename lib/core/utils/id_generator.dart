import 'package:uuid/uuid.dart';

/// Generates primary-key identifiers (OD-01: UUID v4, canonical lowercase text).
class IdGenerator {
  IdGenerator._();

  static const Uuid _uuid = Uuid();

  static String newId() => _uuid.v4().toLowerCase();
}
