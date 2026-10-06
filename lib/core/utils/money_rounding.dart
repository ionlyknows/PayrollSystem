/// Divides [numerator] by [denominator] and rounds to the nearest integer,
/// half-up, symmetric around zero (OD-29, OD-30).
///
/// Works only with integers, so no floating point is involved. Example:
/// 10.005 pesos is 1000.5 centavos, which is `roundHalfUpDivision(2001, 2)`
/// = 1001 centavos (10.01 pesos). Negative values mirror positive values:
/// `roundHalfUpDivision(-2001, 2)` = -1001.
int roundHalfUpDivision(int numerator, int denominator) {
  if (denominator == 0) {
    throw ArgumentError.value(denominator, 'denominator', 'must not be zero');
  }

  var n = numerator;
  var d = denominator;
  if (d < 0) {
    n = -n;
    d = -d;
  }

  final isNegative = n < 0;
  final absN = n.abs();
  final quotient = absN ~/ d;
  final remainder = absN % d;
  final rounded = (2 * remainder >= d) ? quotient + 1 : quotient;

  return isNegative ? -rounded : rounded;
}
