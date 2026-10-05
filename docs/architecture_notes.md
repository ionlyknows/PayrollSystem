# G-Oil Payroll & Attendance: Architecture Notes

Status: Phase 4.3.3. Documentation only. Nothing here is implemented.

## Current baseline

- Flutter + Dart, targeting Windows desktop and Android.
- Feature-first structure under `lib/` (`core/` and `features/`).
- No state-management package and no routing package.
- State is handled with Flutter built-ins only (`StatefulWidget`,
  `ValueNotifier`, `ChangeNotifier`, `InheritedWidget`) while the app is a skeleton.
- Routing is a minimal `onGenerateRoute` in `lib/core/routing/`.
- Dependencies are exactly what the generated Flutter project provides
  (see `pubspec.yaml`). Nothing has been added.

## Approved stack (from the project definition)

These are part of the approved stack but are NOT yet added or implemented:

- SQLite + Drift for offline/local storage
- Supabase + PostgreSQL for cloud database, authentication, and sync
- Supabase Auth using email/password

## Not yet decided (Project Manager decision required)

- State-management approach (a package, or Flutter built-ins only)
- Routing approach (a package, or the built-in Navigator)

No package for either will be added until the Project Manager approves it.

## Rules for adding a dependency

A package is added only when all of these are true:

1. A task approved by the Project Manager needs it.
2. Flutter's built-in tools or the Dart SDK cannot reasonably do the job.
3. It supports both Windows desktop and Android.
4. It is actively maintained.
5. The reason is recorded in the task report.

## Principles that apply to any future choice

- Business rules stay out of UI widgets.
- Features depend on repository interfaces, not on concrete data sources.
- Configurable business values (rates, deduction rules) are never hard-coded.
- Offline-first with idempotent, retry-safe synchronization.
- Backend/database enforces authorization; client checks are not enough.