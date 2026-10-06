import 'package:goil_payroll_attendance/core/database/app_database.dart';
import 'package:goil_payroll_attendance/core/database/transaction_runner.dart';

/// [TransactionRunner] backed by the Drift database's own transaction support.
///
/// Queries made through the same [AppDatabase] inside [run] take part in the
/// transaction.
class DriftTransactionRunner implements TransactionRunner {
  const DriftTransactionRunner(this._db);

  final AppDatabase _db;

  @override
  Future<T> run<T>(Future<T> Function() action) => _db.transaction(action);
}
