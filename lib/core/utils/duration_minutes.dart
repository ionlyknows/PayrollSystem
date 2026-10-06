/// Number of minutes in one hour.
const int minutesPerHour = 60;

/// Converts stored integer minutes (OD-28) to a [Duration].
Duration durationFromMinutes(int minutes) => Duration(minutes: minutes);

/// Converts a [Duration] to integer minutes for storage (OD-28).
///
/// Throws [ArgumentError] if the duration is not a whole number of minutes.
/// How leftover seconds are treated is an open decision (OD-17), so no
/// rounding or truncation is applied here.
int minutesFromDuration(Duration duration) {
  if (duration.inMicroseconds % Duration.microsecondsPerMinute != 0) {
    throw ArgumentError.value(
      duration,
      'duration',
      'must be a whole number of minutes',
    );
  }
  return duration.inMinutes;
}
