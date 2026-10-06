/// Runs a unit of work atomically: it either completes fully or leaves no
/// trace if an error is thrown.
///
/// Repository pattern for future features:
///
///     Presentation
///         -> domain repository interface (per feature)
///         -> data repository implementation (receives AppDatabase)
///         -> Drift database -> SQLite
///
/// Domain and presentation code may depend on this interface. Only the data
/// layer touches Drift. This file must stay free of Drift imports; a test
/// enforces that.
abstract interface class TransactionRunner {
  /// Runs [action] inside a single transaction and returns its result.
  ///
  /// If [action] throws, the transaction is rolled back and the same error
  /// is rethrown to the caller.
  Future<T> run<T>(Future<T> Function() action);
}
