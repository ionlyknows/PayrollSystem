/// Base type for application failures.
abstract class Failure {
  const Failure(this.message, [this.cause]);

  /// Human-readable description of the failure.
  final String message;

  /// Optional underlying error or exception.
  final Object? cause;

  @override
  String toString() => '$runtimeType: $message';
}

/// Failure for errors that are not otherwise categorized.
class UnexpectedFailure extends Failure {
  const UnexpectedFailure([
    super.message = 'An unexpected error occurred.',
    super.cause,
  ]);
}
