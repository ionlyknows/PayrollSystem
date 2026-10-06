# G-Oil Payroll & Attendance: Database Design Specification

Status: Phase 4.6.1. Specification only. Nothing in this document is implemented.

This document describes the intended database design. It adds no tables, code,
dependencies, or sync behavior. Any item not fixed by the approved requirements is
marked `OPEN DECISION (OD-nn)`. Decisions resolved by the Project Manager are marked
`RESOLVED (OD-nn)`. Resolved and open decisions are consolidated in section 11.
No open decision may be silently resolved in code.

## 1. Database architecture overview

- Local database: SQLite, accessed through Drift (added in a later phase).
- Cloud database: Supabase PostgreSQL.
- The app is offline-first. The local database is the primary operational data source.
- Cloud synchronization is a later phase. Its design is only anticipated here (section 9).
- Authentication uses Supabase Auth (email/password). Passwords and password hashes are
  never stored in application tables.
- Authorization is enforced by the backend/database. Client-side checks are never
  sufficient on their own.
- The 34 approved logical tables are specified in section 5. No other tables are added.
  Where a design need has no approved table, it is listed as an open decision instead
  (for example OD-24 for devices).

## 2. Local vs cloud responsibility

| Concern | Local (SQLite/Drift) | Cloud (Supabase PostgreSQL) |
|---|---|---|
| Day-to-day operational reads/writes | Primary | Receives data via sync (later) |
| Identity and passwords | None stored | Supabase Auth |
| Authorization | Convenience checks only | Authoritative (row-level security and constraints) |
| Strong integrity (non-overlap, immutability triggers) | Domain-layer enforcement, plus SQLite constraints where supported | Database constraints and triggers |
| Sensitive final actions (section 2.1) | Cannot be finalized offline | Requires online server authorization (RESOLVED, OD-19) |
| Official payroll export | Only after Owner approval | Owner approval is verified server-side |
| Audit log | Written locally, queued for upload | Authoritative, append-only |
| Backup/restore | Local database file | Cloud-side backup is outside this specification (OD-26) |

Rules that follow from this:

- A locally stored fact is not trusted merely because it exists locally. The cloud
  re-validates it when it syncs.
- Constraints PostgreSQL can enforce but SQLite cannot (such as exclusion constraints)
  must also be enforced by domain logic locally. The cloud is the final authority.

### 2.1 Actions requiring online server authorization (RESOLVED, OD-19)

The following actions require online server authorization:

1. Owner final payroll approval.
2. Owner payroll finalization/locking.
3. Owner approval of a remittance shortage that will become a payroll deduction.
4. Owner approval/release of CA/Vale.
5. Other irreversible Owner-only financial actions that materially affect finalized financial records.

These actions must not be finalized using local-only authorization while offline. Normal data
entry, attendance recording, preparation, review, and other non-final workflows may continue
offline under the approved offline-first design.

Remaining open (OD-19): the specific actions covered by item 5 must be enumerated when each
feature is specified, and how a server authorization is evidenced in stored rows is not yet designed.

## 3. UUID and timestamp conventions

### 3.1 Identifiers

- Every table has primary key `id`, a UUID generated on the client at creation time.
- The same `id` is used in the local and cloud databases. IDs are never reassigned.
- Local storage type: TEXT (canonical lowercase hyphenated form). Cloud type: `uuid`.
- Foreign keys are named `<entity>_id` and reference the parent's `id`.
- RESOLVED (OD-01): UUID version 4 (random) is used for all primary identifiers. It provides
  globally unique identifiers suitable for offline-first operation and does not expose timestamps.
- OPEN DECISION (OD-24): whether devices are identified by an approved `devices` table.
  Where this document mentions a `device_id` column, it is a UUID with no foreign key.

### 3.2 Timestamps and dates

- Instants (`*_at` columns) are stored in UTC. Cloud type: `timestamptz`.
- Calendar dates (`*_date`, `effective_from`, `effective_to`) have no time or zone. They are
  stored locally as ISO 8601 date text (`YYYY-MM-DD`) and interpreted in the business time zone,
  Asia/Manila (RESOLVED, OD-02 and OD-03).
- RESOLVED (OD-03): the official business time zone is Asia/Manila. Payroll periods, attendance
  dates, schedules, holidays, and all other business dates use Philippine business time. Payroll
  and attendance calculations must never depend on the time zone of the computer or device they
  run on. The zone decides which calendar date an instant belongs to.
- RESOLVED (OD-02): SQLite uses ISO 8601 representation. Instants are stored as UTC ISO 8601
  values. Business/local dates and displayed times are interpreted using Asia/Manila. One fixed
  textual format is used for every table (for example always with the `Z` UTC designator).
- Standard column names: `created_at`, `updated_at`, plus event-specific names such
  as `requested_at`, `reviewed_at`, `released_at`, `voided_at`.
- A device clock is not fully trustworthy. Attendance and audit times recorded offline
  are device times. A server-received timestamp is a sync-phase addition (section 9).
  OPEN DECISION (OD-11): whether a trusted time source is required for attendance.

### 3.3 Standard column sets

| Set | Used by | Columns |
|---|---|---|
| STD-M (mutable) | Master/reference data and workflow headers | `id`, `created_at`, `updated_at`, `created_by`, `updated_by` |
| STD-L (append-only) | Ledger/event/history rows | `id`, `created_at`, `created_by` |

- `created_by` / `updated_by` reference `user_profiles.id`. They are nullable only for
  system-generated rows (such as seed data).
- Append-only rows are never updated or deleted. A mistake is fixed by adding a new
  reversing or superseding row.
- Documented exception: `employee_pay_rates` (section 5.5) is a closed-and-replaced historical
  table. It uses the STD-L columns plus `updated_at` and `updated_by`, and it permits exactly two
  controlled post-insert mutation types:
  1. Closing: set `effective_to`, `updated_at` and `updated_by`.
  2. Voiding: set `voided_at`, `voided_by` and `void_reason`.

  No other pay-rate value is modified after insertion. `updated_at` and `updated_by` stay NULL on
  initial insert and are set only by the closing update. Voiding does not require `updated_at` or
  `updated_by`.

### 3.4 Data types

| Logical type | Cloud | Local |
|---|---|---|
| uuid | `uuid` | TEXT |
| text | `text` | TEXT |
| int | `integer` | INTEGER |
| bool | `boolean` | INTEGER (0/1) |
| date | `date` | TEXT, ISO 8601 `YYYY-MM-DD` (OD-02) |
| instant | `timestamptz` | TEXT, UTC ISO 8601 (OD-02) |
| money | `bigint` (integer centavos) | INTEGER (integer centavos) (OD-04) |
| duration | `integer` (minutes) | INTEGER (minutes) (OD-28) |
| json | `jsonb` | TEXT |

- Floating-point types are never used for money or hours.
- RESOLVED (OD-04): monetary values are stored as integer centavos in both the local and cloud
  databases. Example: PHP 480.00 is stored as `48000`. Floating-point values are never used for
  financial amounts. The unit is the Philippine peso.
- RESOLVED (OD-28): durations are stored as integer minutes in both the local and cloud databases
  (logical type `duration`). Examples: 30 minutes = 30, 1 hour = 60, 1.5 hours = 90, a 12-hour
  shift = 720. Payroll and attendance calculations derive hours from minutes. Floating-point
  hour values are never stored for durations. Columns holding durations are named `*_minutes`.
  Leave quantities (days) are not durations in this sense and stay open under OD-13.
- RESOLVED (OD-29): all payroll calculations use centavo-safe integer arithmetic, with no
  floating point. When a calculation produces a fraction of a centavo, the result is rounded to
  the nearest centavo using half-up rounding. Examples: PHP 10.004 becomes PHP 10.00 and
  PHP 10.005 becomes PHP 10.01.
- RESOLVED (OD-30): rounding is applied at the level of each independently calculated payroll
  line/record, before that amount is included in any total. Independently calculated lines include
  basic pay, tardiness deduction, overtime pay, each individual deduction, each individual
  adjustment, and any other calculated earning or deduction. Calculation order:
  1. Calculate each payroll earning/deduction line.
  2. Round that line to the nearest centavo using half-up rounding (OD-29).
  3. Store the resulting integer-centavo amount.
  4. Sum the already-rounded line amounts to calculate payroll totals.
  5. Calculate net pay from the resulting integer-centavo totals.

  Rounding is never deferred to the final payroll total.
- RESOLVED (OD-30), negative amounts: half-up rounding is symmetric around zero. The absolute value
  is rounded half-up, then the negative sign is restored. Examples: 10.004 becomes 10.00, 10.005
  becomes 10.01, -10.004 becomes -10.00, and -10.005 becomes -10.01. All monetary values remain
  integer centavos, and floating-point monetary values are never used.

### 3.5 Naming and referential rules

- Tables use plural snake_case names and columns use snake_case names.
  Drift maps them to Dart names later.
- All foreign keys are `ON DELETE RESTRICT` and `ON UPDATE RESTRICT`. There is no
  cascading delete anywhere in this design.
- Business rows are never hard-deleted. Reference data is deactivated (`is_active = false`).
  Transactional data is voided (`voided_at`, `voided_by`, `void_reason`).
- Local SQLite must run with foreign keys enabled.

## 4. Entity/table inventory

Row classes:

- **M**: mutable master/reference data. Changes are audited.
- **V**: effective-dated version. Rows are closed and replaced, never edited in place.
- **L**: append-only ledger/event/history.
- **S**: snapshot. Frozen once its parent is finalized.
- **E**: operational/ephemeral.

| # | Table | Class | Group |
|---|---|---|---|
| 1 | roles | M | Identity |
| 2 | user_profiles | M | Identity |
| 3 | employees | M | Workforce |
| 4 | positions | M | Workforce |
| 5 | employee_pay_rates | V | Workforce |
| 6 | schedules | M | Scheduling |
| 7 | shift_assignments | M | Scheduling |
| 8 | attendance_records | M (capture), then immutable | Attendance |
| 9 | attendance_corrections | L | Attendance |
| 10 | leave_types | M | Leave |
| 11 | leave_requests | M | Leave |
| 12 | leave_transactions | L | Leave |
| 13 | holidays | M | Calendar |
| 14 | overtime_records | M | Overtime |
| 15 | cash_advances | M (status header) | CA/Vale |
| 16 | advance_transactions | L | CA/Vale |
| 17 | deduction_categories | M | Deductions |
| 18 | deduction_rules | V (via rule version) | Deductions |
| 19 | remittance_records | M (capture), then immutable | Remittance |
| 20 | remittance_assignments | L | Remittance |
| 21 | remittance_reviews | L | Remittance |
| 22 | payroll_periods | S | Payroll |
| 23 | payroll_records | S | Payroll |
| 24 | payroll_earnings | S | Payroll |
| 25 | payroll_deductions | S | Payroll |
| 26 | payroll_adjustments | L | Payroll |
| 27 | payroll_settings | M | Configuration |
| 28 | business_rule_versions | V | Configuration |
| 29 | audit_logs | L | Audit |
| 30 | notifications | E | Notifications |
| 31 | biometric_records | event metadata only; provisional (OD-21) | Biometrics |
| 32 | sync_queue | E | Sync |
| 33 | sync_conflicts | E / L | Sync |
| 34 | backup_records | L | Backup |

## 5. Table-by-table schema specification

Notation: "R" = required (NOT NULL), "N" = nullable. Each table also carries its
standard column set (section 3.3) unless stated. Money columns are `money`, hours columns
are `duration` (integer minutes, OD-28). Every `money` column holds integer centavos (OD-04). Every foreign key is
`RESTRICT` (section 3.5).

### 5.1 roles

- **Purpose:** Defines the four approved roles: Owner, Manager, Cashier, Employee.
- **Primary key:** `id`. **Standard columns:** STD-M.

| Column | Type | Null | Notes |
|---|---|---|---|
| code | text | R | Stable machine code (`owner`, `manager`, `cashier`, `employee`) |
| name | text | R | Display name |
| description | text | N | |
| is_system | bool | R | True for the four approved roles |

- **Foreign keys:** none.
- **Unique:** `code`.
- **Indexes:** unique index on `code`.
- **History/audit:** Role rows are seed data and are not user-editable. Changes are audited.
- OPEN DECISION (OD-05): where the permission matrix lives (database table, backend
  policy only, or app constants). No permissions table is approved.

### 5.2 user_profiles

- **Purpose:** Application profile for each Supabase Auth account, holding the role.
- **Primary key:** `id`. **Standard columns:** STD-M.

| Column | Type | Null | Notes |
|---|---|---|---|
| auth_user_id | uuid | R | The Supabase Auth user id. Cloud may reference `auth.users`; local has no such table |
| role_id | uuid | R | FK to `roles` |
| display_name | text | R | |
| is_active | bool | R | Disabled accounts are deactivated, not deleted |

- **Foreign keys:** `role_id` to `roles.id`.
- **Unique:** `auth_user_id`.
- **Indexes:** unique on `auth_user_id`; index on `role_id`.
- **History/audit:** Role changes and activation changes are audited (old and new role).
  No credentials of any kind are stored.
- OPEN DECISION (OD-05): one role per user (this single `role_id` column) or multiple roles.
- OPEN DECISION (OD-06): whether an email copy is stored here or only in Supabase Auth.

### 5.3 employees

- **Purpose:** The people who are paid. This is the stable anchor for attendance, leave,
  CA, and payroll.
- **Primary key:** `id`. **Standard columns:** STD-M.

| Column | Type | Null | Notes |
|---|---|---|---|
| employee_code | text | R | Human-facing unique code |
| user_profile_id | uuid | N | FK to `user_profiles`; null if the employee has no login |
| first_name | text | R | |
| middle_name | text | N | |
| last_name | text | R | |
| position_id | uuid | N | FK to `positions`; current position |
| hire_date | date | R | |
| separation_date | date | N | |
| employment_status | text | R | Values: OPEN DECISION (OD-07) |
| phone | text | N | |
| address | text | N | |

- **Foreign keys:** `user_profile_id` to `user_profiles.id`; `position_id` to `positions.id`.
- **Unique:** `employee_code`; `user_profile_id` (where not null, partial unique).
- **Indexes:** unique on `employee_code`; partial unique on `user_profile_id`;
  index on `position_id`; index on `employment_status`.
- **History/audit:** Employees are never deleted; separation uses `separation_date` and
  status. Payroll snapshots keep name and position as they were at calculation time.
  Changes to status and position are audited.
- OPEN DECISION (OD-06): whether every employee must have a login, and whether a user
  (for example the Owner) may exist without an employee row.
- OPEN DECISION (OD-07): which personal/identification fields are collected
  (for example government IDs), employment status values, and rehire handling.
  None are included here.
- OPEN DECISION (OD-08): whether position history must be kept (this design keeps only
  the current position plus audit history).

### 5.4 positions

- **Purpose:** Job titles (for example Cashier, Attendant).
- **Primary key:** `id`. **Standard columns:** STD-M.

| Column | Type | Null | Notes |
|---|---|---|---|
| code | text | R | |
| name | text | R | |
| description | text | N | |
| is_active | bool | R | |

- **Foreign keys:** none. **Unique:** `code`. **Indexes:** unique on `code`.
- **History/audit:** Positions are deactivated, not deleted. Changes are audited.
- OPEN DECISION (OD-08): whether a position implies a default pay rate. This design
  does not; pay rates belong only to `employee_pay_rates`.
- Position is separate from role: a position is a job title, a role is an authorization level.

### 5.5 employee_pay_rates

- **Purpose:** Effective-dated daily rate per employee. This is the only source of pay rates.
- **Primary key:** `id`. **Standard columns:** STD-L plus `updated_at` and `updated_by`, plus the void columns below.
  This table is a documented exception to the STD-L immutability rule (section 3.3): it permits
  two controlled post-insert mutations, closing (`effective_to`, `updated_at`, `updated_by`) and
  voiding (`voided_at`, `voided_by`, `void_reason`).

| Column | Type | Null | Notes |
|---|---|---|---|
| employee_id | uuid | R | FK to `employees` |
| daily_rate | money | R | Must be greater than 0 |
| effective_from | date | R | First day the rate applies |
| effective_to | date | N | Null means open-ended (currently in force) |
| reason | text | N | |
| updated_at | instant | N | Set only by the closing update of `effective_to`. Null until then |
| updated_by | uuid | N | FK to `user_profiles`. Set only by the closing update. Null until then |
| voided_at | instant | N | Voids a mistaken row without deleting it |
| voided_by | uuid | N | FK to `user_profiles` |
| void_reason | text | N | |

- **Foreign keys:** `employee_id` to `employees.id`; `updated_by` to `user_profiles.id`;
  `voided_by` to `user_profiles.id`.
- **Derived, not stored:** hourly rate = daily rate / 12 (rounded half-up to the nearest centavo per line, OD-29 and OD-30). The 12 comes from the configured
  standard shift length (section 5.28), never from a constant in code or schema.
- **Unique/non-overlap rule (required):** for one employee, non-voided rows must never
  have overlapping effective periods.
  - Cloud: an exclusion constraint on `(employee_id, date range of effective_from..effective_to)`,
    applied to non-voided rows, using `btree_gist`.
  - Local: SQLite has no exclusion constraints, so the repository must check overlap
    inside the same transaction that inserts the row. Cloud re-validates on sync.
  - Also: at most one open-ended (`effective_to IS NULL`) non-voided row per employee
    (partial unique index).
- **CHECK:** `effective_to IS NULL OR effective_to >= effective_from` (final form depends on OD-09).
- **Indexes:** `(employee_id, effective_from)`; partial unique index for the open-ended row.
- **History/audit:** Rate values are never changed in place: `employee_id`, `daily_rate` and
  `effective_from` are not edited after insert. A rate change closes the current row by setting
  `effective_to`, then inserts a new row. The closing update must record `updated_at` and
  `updated_by` (both NULL on initial insert), and it is audited. Voiding a mistaken row sets
  `voided_at`, `voided_by` and `void_reason` only, and is also audited. No other post-insert
  mutation is permitted. No separate closed-at or closed-by columns exist. Payroll snapshots copy
  the rate used, so later rate changes never
  alter finalized payroll.
- OPEN DECISION (OD-09): whether `effective_to` is inclusive or exclusive (a half-open
  range `[from, to)` is recommended, but not confirmed), whether rate changes need approval
  and by whom, and whether back-dated rates are allowed once a payroll period is finalized.

### 5.6 schedules

- **Purpose:** A named container for shift assignments over a date range.
- **Primary key:** `id`. **Standard columns:** STD-M.

| Column | Type | Null | Notes |
|---|---|---|---|
| name | text | N | |
| start_date | date | R | |
| end_date | date | R | |
| status | text | R | Values: OPEN DECISION (OD-10) |
| published_at | instant | N | |
| published_by | uuid | N | FK to `user_profiles` |

- **Foreign keys:** `published_by` to `user_profiles.id`.
- **CHECK:** `end_date >= start_date`.
- **Unique:** none decided.
- **Indexes:** `(start_date, end_date)`; `status`.
- **History/audit:** Publishing and status changes are audited. Schedules are not deleted.
- OPEN DECISION (OD-10): schedule status values, whether schedules must align with the
  14-day payroll period, and whether overlapping schedules are allowed.

### 5.7 shift_assignments

- **Purpose:** Assigns an employee to a shift on a date.
- **Primary key:** `id`. **Standard columns:** STD-M.

| Column | Type | Null | Notes |
|---|---|---|---|
| schedule_id | uuid | R | FK to `schedules` |
| employee_id | uuid | R | FK to `employees` |
| shift_date | date | R | |
| scheduled_start_at | instant | R | Copied at assignment time from the configured standard time-in unless overridden |
| scheduled_end_at | instant | R | Copied from the configured standard shift length unless overridden |
| status | text | R | For example assigned or cancelled: OPEN DECISION (OD-10) |
| note | text | N | |

- **Foreign keys:** `schedule_id` to `schedules.id`; `employee_id` to `employees.id`.
- **Why the times are stored:** the standard 6:00 AM time-in and 12-hour shift are configurable.
  Storing the scheduled times on the assignment keeps old schedules correct if the
  configuration later changes. The values are filled from configuration, not hard-coded.
- **CHECK:** `scheduled_end_at > scheduled_start_at`.
- **Unique:** none decided (see OD-10).
- **Indexes:** `(employee_id, shift_date)`; `(schedule_id)`; `(shift_date)`.
- **History/audit:** Changes to a published assignment are audited. Cancellation uses
  status, not deletion.
- OPEN DECISION (OD-10): whether one employee may have more than one shift per date,
  how rest days are represented, and how overnight shifts are dated.

### 5.8 attendance_records

- **Purpose:** The original recorded time-in/time-out for an employee on a work date.
- **Primary key:** `id`. **Standard columns:** STD-M (until closed).

| Column | Type | Null | Notes |
|---|---|---|---|
| employee_id | uuid | R | FK to `employees` |
| shift_assignment_id | uuid | N | FK to `shift_assignments`; null for unscheduled work |
| work_date | date | R | Business-date of the shift |
| time_in_at | instant | N | |
| time_out_at | instant | N | Null until the employee clocks out |
| source | text | R | How it was captured. Values: OPEN DECISION (OD-11) |
| recorded_by | uuid | R | FK to `user_profiles` |
| status | text | R | Values: OPEN DECISION (OD-11) |

- **Foreign keys:** `employee_id`, `shift_assignment_id`, `recorded_by`.
- **CHECK:** `time_out_at IS NULL OR time_in_at IS NULL OR time_out_at >= time_in_at`.
- **Unique:** none decided (see OD-11).
- **Indexes:** `(employee_id, work_date)`; `(work_date)`; `(shift_assignment_id)`.
- **Derived values are not stored here:** late minutes, deduction hours, and hours worked
  are computed at payroll time from effective times and the active rule version, then
  frozen in the payroll snapshot (sections 5.22 to 5.25).
- **History/audit:** Once time-in and time-out are captured, the original values are never
  overwritten. Any later change goes through `attendance_corrections`.
- OPEN DECISION (OD-11): capture sources, status values, one record per employee per
  day or several, how a missed punch is represented, and whether a trusted time source is needed.

### 5.9 attendance_corrections

- **Purpose:** Preserves the original and corrected values whenever attendance changes.
- **Primary key:** `id`. **Standard columns:** STD-L.

| Column | Type | Null | Notes |
|---|---|---|---|
| attendance_record_id | uuid | R | FK to `attendance_records` |
| original_time_in_at | instant | N | Copied from the effective value when the correction is requested |
| original_time_out_at | instant | N | Same |
| corrected_time_in_at | instant | N | |
| corrected_time_out_at | instant | N | |
| reason | text | R | |
| requested_by | uuid | R | FK to `user_profiles` |
| requested_at | instant | R | |
| status | text | R | Values: OPEN DECISION (OD-12) |
| reviewed_by | uuid | N | FK to `user_profiles` |
| reviewed_at | instant | N | |
| review_note | text | N | |
| supersedes_correction_id | uuid | N | FK to `attendance_corrections`; set when a later correction replaces an earlier one |

- **Foreign keys:** `attendance_record_id`, `requested_by`, `reviewed_by`, `supersedes_correction_id`.
- **Effective value rule:** the effective attendance time is the corrected value of the
  latest approved, non-superseded correction, otherwise the original attendance value.
  This is computed by a query or view, not by editing `attendance_records`.
- **Indexes:** `(attendance_record_id, requested_at)`; `(status)`.
- **History/audit:** Append-only. Original and corrected values are both kept forever.
  A decision (review) is recorded as the row's review fields set once; the status fields
  are the only values that may change, and each change is audited.
- OPEN DECISION (OD-12): who approves corrections, the status values, and how a correction
  that touches a finalized payroll period is handled (see OD-20).
### 5.10 leave_types

- **Purpose:** Catalogue of leave categories.
- **Primary key:** `id`. **Standard columns:** STD-M.

| Column | Type | Null | Notes |
|---|---|---|---|
| code | text | R | |
| name | text | R | |
| is_active | bool | R | |

- **Foreign keys:** none. **Unique:** `code`. **Indexes:** unique on `code`.
- **History/audit:** Deactivated, never deleted. Changes are audited.
- OPEN DECISION (OD-13): leave rules are not in the approved requirements. Whether a leave
  type is paid or unpaid, its entitlement, and its accrual are all undecided and
  are intentionally not modeled here.

### 5.11 leave_requests

- **Purpose:** An employee's request for leave and its decision.
- **Primary key:** `id`. **Standard columns:** STD-M.

| Column | Type | Null | Notes |
|---|---|---|---|
| employee_id | uuid | R | FK to `employees` |
| leave_type_id | uuid | R | FK to `leave_types` |
| start_date | date | R | |
| end_date | date | R | |
| requested_days | OPEN DECISION (OD-13) | R | Unit (days or minutes) depends on the leave rules. OD-28 covers durations only |
| reason | text | N | |
| status | text | R | Values: OPEN DECISION (OD-13) |
| requested_at | instant | R | |
| reviewed_by | uuid | N | FK to `user_profiles` |
| reviewed_at | instant | N | |
| decision_note | text | N | |

- **Foreign keys:** `employee_id`, `leave_type_id`, `reviewed_by`.
- **CHECK:** `end_date >= start_date`.
- **Indexes:** `(employee_id, start_date)`; `(status)`.
- **History/audit:** Requests are never deleted; cancellation is a status. Status
  transitions are audited.
- OPEN DECISION (OD-13): the approval chain (the Employee, Manager, Owner chain
  is approved only for CA/Vale, not for leave), status values, and a single reviewer
  versus multiple reviewers.

### 5.12 leave_transactions

- **Purpose:** Ledger of leave-balance movements.
- **Primary key:** `id`. **Standard columns:** STD-L.

| Column | Type | Null | Notes |
|---|---|---|---|
| employee_id | uuid | R | FK to `employees` |
| leave_type_id | uuid | R | FK to `leave_types` |
| leave_request_id | uuid | N | FK to `leave_requests` |
| transaction_type | text | R | Values: OPEN DECISION (OD-13) |
| quantity | OPEN DECISION (OD-13) | R | Signed quantity. Unit (days or minutes) depends on the leave rules |
| effective_date | date | R | |
| reason | text | N | |
| reverses_transaction_id | uuid | N | FK to `leave_transactions` |

- **Foreign keys:** `employee_id`, `leave_type_id`, `leave_request_id`, `reverses_transaction_id`.
- **Indexes:** `(employee_id, leave_type_id, effective_date)`; `(leave_request_id)`.
- **History/audit:** Append-only. A balance is the sum of transactions and is never edited
  directly. Mistakes are corrected with a reversing row.
- OPEN DECISION (OD-13): whether leave balances exist at all, and the transaction types.

### 5.13 holidays

- **Purpose:** Calendar of holidays.
- **Primary key:** `id`. **Standard columns:** STD-M.

| Column | Type | Null | Notes |
|---|---|---|---|
| holiday_date | date | R | |
| name | text | R | |
| holiday_type | text | N | Values: OPEN DECISION (OD-14) |
| is_active | bool | R | |

- **Foreign keys:** none. **Unique:** `(holiday_date, name)`.
- **Indexes:** `(holiday_date)`.
- **History/audit:** Deactivated, not deleted. Payroll snapshots reference the holiday
  that applied. Changes are audited.
- OPEN DECISION (OD-14): holiday types and any pay effect of a holiday (no pay multiplier
  is approved, so none is modeled), and whether holidays recur yearly.

### 5.14 overtime_records

- **Purpose:** Overtime hours worked by an employee and their approval.
- **Primary key:** `id`. **Standard columns:** STD-M.

| Column | Type | Null | Notes |
|---|---|---|---|
| employee_id | uuid | R | FK to `employees` |
| attendance_record_id | uuid | N | FK to `attendance_records` |
| work_date | date | R | |
| overtime_minutes | duration | R | Integer minutes. Must be greater than 0 |
| reason | text | N | |
| status | text | R | Values: OPEN DECISION (OD-15) |
| requested_by | uuid | R | FK to `user_profiles` |
| reviewed_by | uuid | N | FK to `user_profiles` |
| reviewed_at | instant | N | |
| voided_at | instant | N | |
| voided_by | uuid | N | FK to `user_profiles` |
| void_reason | text | N | |

- **Foreign keys:** `employee_id`, `attendance_record_id`, `requested_by`, `reviewed_by`, `voided_by`.
- **Indexes:** `(employee_id, work_date)`; `(status)`.
- **History/audit:** Approved records are not edited; a change is a voided row plus a new
  row (void columns above). Status changes are audited.
- OPEN DECISION (OD-15): what counts as overtime relative to the 12-hour shift, whether
  hours are entered or derived from attendance, the approval chain, and any pay multiplier
  (none is approved, so none is modeled).

### 5.15 cash_advances

- **Purpose:** Header for each cash advance / vale and its current workflow status.
- **Primary key:** `id`. **Standard columns:** STD-M.

| Column | Type | Null | Notes |
|---|---|---|---|
| employee_id | uuid | R | FK to `employees` |
| amount_requested | money | R | Must be greater than 0 |
| amount_approved | money | N | Set when approved |
| reason | text | N | |
| status | text | R | Projection of the latest transaction. Values: OPEN DECISION (OD-16) |
| requested_at | instant | R | |

- **Foreign keys:** `employee_id` to `employees.id`.
- **Approved workflow the status must support:** Employee request, Manager approval,
  Owner approval, Release, Payroll deduction. Rejection and cancellation states are undecided (OD-16).
- **Server authorization (RESOLVED, OD-19):** Owner approval and release of CA/Vale require online
  server authorization and cannot be finalized offline. Non-final steps (such as the request and
  Manager approval) may continue offline.
- **Source of truth:** `advance_transactions`. The `status` column is a convenience copy,
  written in the same database transaction as the transaction row that changes it.
- **CHECK:** `amount_approved IS NULL OR amount_approved >= 0`.
- **Indexes:** `(employee_id, status)`; `(status)`.
- **History/audit:** Never deleted. Every approval, release, and deduction is a row in
  `advance_transactions`. Header status changes are audited.
- OPEN DECISION (OD-16): whether CA and Vale are distinct types, partial release, installment
  amounts per payroll period, and whether a cached outstanding balance column is wanted.

### 5.16 advance_transactions

- **Purpose:** Append-only trail of every step and balance change of a cash advance.
- **Primary key:** `id`. **Standard columns:** STD-L.

| Column | Type | Null | Notes |
|---|---|---|---|
| cash_advance_id | uuid | R | FK to `cash_advances` |
| transaction_type | text | R | Includes at least request, manager approval, owner approval, release, payroll deduction. Full set: OPEN DECISION (OD-16) |
| amount | money | N | The amount involved in the step, where one applies |
| balance_effect | money | R | Signed change to the outstanding balance (zero for approval steps) |
| actor_user_id | uuid | R | FK to `user_profiles` |
| occurred_at | instant | R | |
| payroll_deduction_id | uuid | N | FK to `payroll_deductions`; set on payroll-deduction rows |
| reverses_transaction_id | uuid | N | FK to `advance_transactions` |
| note | text | N | |

- **Foreign keys:** `cash_advance_id`, `actor_user_id`, `payroll_deduction_id`, `reverses_transaction_id`.
- **Balance rule:** the outstanding balance is the sum of `balance_effect` for one advance.
- **Server authorization (RESOLVED, OD-19):** rows of type owner approval and release are recorded
  only after online server authorization. How that authorization is evidenced in the row is
  OPEN DECISION (OD-19, remaining).
- **Indexes:** `(cash_advance_id, occurred_at)`; `(payroll_deduction_id)`.
- **History/audit:** Append-only. Corrections are reversing rows. This table, together with
  the header, makes the full chain request, approvals, release, deductions, and balance
  changes traceable.
- OPEN DECISION (OD-16): when the payroll-deduction transaction is written (at draft
  calculation or only at payroll finalization), and the full set of transaction types.

### 5.17 deduction_categories

- **Purpose:** Catalogue of deduction types used by payroll.
- **Primary key:** `id`. **Standard columns:** STD-M.

| Column | Type | Null | Notes |
|---|---|---|---|
| code | text | R | |
| name | text | R | |
| description | text | N | |
| is_system | bool | R | True for categories required by approved rules |
| is_active | bool | R | |

- **Foreign keys:** none. **Unique:** `code`. **Indexes:** unique on `code`.
- **System categories required by the approved rules:** lateness, CA/Vale repayment, and
  owner-approved remittance shortage. Seed data creates them.
- **History/audit:** Deactivated, not deleted. Payroll deductions keep their category link.
- OPEN DECISION (OD-17): any other categories (the approved requirements name none).

### 5.18 deduction_rules

- **Purpose:** The configurable parameters of a deduction rule, owned by one rule version.
- **Primary key:** `id`. **Standard columns:** STD-L (rules belong to a version; change the version instead of editing).

| Column | Type | Null | Notes |
|---|---|---|---|
| business_rule_version_id | uuid | R | FK to `business_rule_versions` |
| deduction_category_id | uuid | R | FK to `deduction_categories` |
| rule_key | text | R | Stable key within the version |
| sequence | int | R | Evaluation order |
| parameters | json | R | Rule parameters. Representation: OPEN DECISION (OD-17) |

- **Foreign keys:** `business_rule_version_id`, `deduction_category_id`.
- **Unique:** `(business_rule_version_id, rule_key)`.
- **Indexes:** `(business_rule_version_id, sequence)`.
- **History/audit:** Rows belonging to an approved or used version are immutable.
- **Late-deduction brackets (RESOLVED, OD-17; values live in data, never in code):** 6:15 AM is the
  beginning of the 1-hour deduction bracket. With a standard time-in of 6:00 AM:

| Arrival time | Deduction |
|---|---|
| 6:00 | none |
| 6:01 to 6:14 | 0.5 hour |
| 6:15 to 6:59 | 1 hour |
| 7:00 to 7:59 | 2 hours |
| 8:00 to 8:59 | 3 hours |
| 9:00 to 9:59 | 4 hours |
| and so on | same hourly progression |

- The standard time-in is configurable, so the stored rule data defines the brackets relative to
  it. Hourly rate = daily rate / 12, where 12 is the configured standard shift length.
- OPEN DECISION (OD-17, remaining): JSON parameters or a normalized tier structure (no extra table
  is approved), how seconds within a minute are treated, whether the progression has a cap (for
  example as lateness approaches the shift length), and how the active version is selected.

### 5.19 remittance_records

- **Purpose:** One remittance with its expected and actual amounts.
- **Primary key:** `id`. **Standard columns:** STD-M (until reviewed).

| Column | Type | Null | Notes |
|---|---|---|---|
| remittance_date | date | R | |
| expected_amount | money | R | Must be 0 or greater |
| actual_amount | money | R | Must be 0 or greater |
| shortage_amount | money | R | `max(expected - actual, 0)` |
| overage_amount | money | R | `max(actual - expected, 0)` |
| shift_assignment_id | uuid | N | FK to `shift_assignments` |
| recorded_by | uuid | R | FK to `user_profiles` |
| recorded_at | instant | R | |
| status | text | R | Values: OPEN DECISION (OD-18) |
| voided_at | instant | N | |
| voided_by | uuid | N | FK to `user_profiles` |
| void_reason | text | N | |

- **Foreign keys:** `shift_assignment_id`, `recorded_by`, `voided_by`.
- **CHECK constraints:** the two derived amounts must equal the formulas above;
  at most one of `shortage_amount` and `overage_amount` is greater than 0.
- **Traceability:** expected, actual, shortage, and overage are all stored explicitly so each
  can be traced without recalculation.
- **Indexes:** `(remittance_date)`; `(status)`; `(shift_assignment_id)`.
- **History/audit:** Amounts are not edited after recording. A wrong record is voided and
  replaced. Shortage never creates a payroll deduction on its own; the only path is the
  review chain in section 5.21 and the constraint in section 5.25.
- OPEN DECISION (OD-18): where the expected amount comes from (manual entry or an
  external sales source), and the status values.

### 5.20 remittance_assignments

- **Purpose:** Records which employee(s) a remittance is attributed to.
- **Primary key:** `id`. **Standard columns:** STD-L.

| Column | Type | Null | Notes |
|---|---|---|---|
| remittance_record_id | uuid | R | FK to `remittance_records` |
| employee_id | uuid | R | FK to `employees` |
| assigned_by | uuid | R | FK to `user_profiles` |
| assigned_at | instant | R | |
| assigned_amount | money | N | Only if shortage is split. See OD-18 |
| note | text | N | |

- **Foreign keys:** `remittance_record_id`, `employee_id`, `assigned_by`.
- **Unique:** `(remittance_record_id, employee_id)`.
- **Indexes:** `(employee_id)`; `(remittance_record_id)`.
- **History/audit:** Append-only. Reassignment adds a new row and voids nothing; the latest
  assignment set is determined by `assigned_at`, and the mechanism is part of OD-18.
- OPEN DECISION (OD-18): whether responsibility can be shared by several employees and
  how a shortage is split.

### 5.21 remittance_reviews

- **Purpose:** The review, verification, and Owner approval trail for a remittance shortage.
- **Primary key:** `id`. **Standard columns:** STD-L.

| Column | Type | Null | Notes |
|---|---|---|---|
| remittance_record_id | uuid | R | FK to `remittance_records` |
| remittance_assignment_id | uuid | N | FK to `remittance_assignments` |
| review_stage | text | R | Must cover review, verification, and owner approval. Exact values: OPEN DECISION (OD-18) |
| outcome | text | R | Values: OPEN DECISION (OD-18) |
| reviewer_user_id | uuid | R | FK to `user_profiles` |
| reviewed_at | instant | R | |
| approved_deduction_amount | money | N | Only on an owner-approval row that approves a deduction |
| note | text | N | |

- **Foreign keys:** `remittance_record_id`, `remittance_assignment_id`, `reviewer_user_id`.
- **Indexes:** `(remittance_record_id, reviewed_at)`; `(review_stage, outcome)`.
- **History/audit:** Append-only. Only an owner-approval row with an approving outcome may
  authorize a payroll deduction. Owner approval of a shortage that will become a payroll
  deduction requires online server authorization (RESOLVED, OD-19).

### 5.22 payroll_periods

- **Purpose:** A 14-day payroll period, its approval state, and its lock.
- **Primary key:** `id`. **Standard columns:** STD-M (until finalized).

| Column | Type | Null | Notes |
|---|---|---|---|
| period_start | date | R | |
| period_end | date | R | Last day of the period |
| status | text | R | Must represent draft, awaiting approval, Owner-approved, finalized/locked. Values: OPEN DECISION (OD-20) |
| business_rule_version_id | uuid | N | FK to `business_rule_versions`; set when payroll is calculated |
| calculated_at | instant | N | |
| approved_by | uuid | N | FK to `user_profiles`; the Owner |
| approved_at | instant | N | |
| finalized_at | instant | N | |
| locked_at | instant | N | Set when the period becomes immutable |

- **Foreign keys:** `business_rule_version_id`, `approved_by`.
- **Unique:** `period_start`.
- **Non-overlap rule:** periods must not overlap (cloud exclusion constraint on the date range;
  the repository checks it locally).
- **CHECK:** `period_end >= period_start`. Whether the database also forces a 14-day
  length is OPEN DECISION (OD-20); until decided, the 14-day length is validated in the
  domain layer against configuration.
- **Indexes:** unique on `period_start`; `(status)`.
- **Server authorization (RESOLVED, OD-19):** Owner final payroll approval and Owner payroll
  finalization/locking require online server authorization and cannot be completed offline.
  Preparation and review may continue offline.
- **History/audit:** After finalization the period and all child rows are immutable.
  The cloud enforces this with triggers and policies; locally, the repository refuses
  writes. Official payroll export is allowed only after Owner approval.
- OPEN DECISION (OD-20): the anchor date of the first period, payday, whether finalized payroll
  can ever be reopened, and how errors found after finalization are corrected.

### 5.23 payroll_records

- **Purpose:** One employee's payroll result for one period, stored as a snapshot.
- **Primary key:** `id`. **Standard columns:** STD-M (until finalized).

| Column | Type | Null | Notes |
|---|---|---|---|
| payroll_period_id | uuid | R | FK to `payroll_periods` |
| employee_id | uuid | R | FK to `employees` |
| employee_pay_rate_id | uuid | R | FK to `employee_pay_rates`; the rate row used |
| daily_rate_snapshot | money | R | Copied at calculation |
| hourly_rate_snapshot | money | R | Daily rate / the configured shift length at calculation time |
| employee_name_snapshot | text | R | |
| position_name_snapshot | text | N | |
| business_rule_version_id | uuid | R | FK to `business_rule_versions` |
| total_earnings | money | R | |
| total_deductions | money | R | |
| total_adjustments | money | R | Signed |
| net_pay | money | R | |
| attendance_summary | json | N | Frozen summary. Content: OPEN DECISION (OD-20) |
| calculated_at | instant | R | |

- **Foreign keys:** `payroll_period_id`, `employee_id`, `employee_pay_rate_id`, `business_rule_version_id`.
- **Unique:** `(payroll_period_id, employee_id)`.
- **CHECK:** `net_pay = total_earnings - total_deductions + total_adjustments`.
- **Rounding (RESOLVED, OD-30):** `total_earnings`, `total_deductions` and `total_adjustments` are
  sums of already-rounded integer-centavo line amounts, and `net_pay` is computed from those
  integer totals. Totals are never rounded from unrounded intermediate values.
- **Indexes:** unique `(payroll_period_id, employee_id)`; `(employee_id)`.
- **History/audit:** The snapshot columns make the result reproducible regardless of later
  changes to rates, names, positions, or rules. Frozen when the parent period is locked.
- OPEN DECISION (OD-20): whether draft recalculation keeps earlier calculations or replaces
  them, and whether approval status also exists per record.

### 5.24 payroll_earnings

- **Purpose:** Itemized earnings lines belonging to a payroll record.
- **Primary key:** `id`. **Standard columns:** STD-L.

| Column | Type | Null | Notes |
|---|---|---|---|
| payroll_record_id | uuid | R | FK to `payroll_records` |
| earning_type | text | R | Values: OPEN DECISION (OD-20) |
| description | text | N | |
| quantity | int | N | Minutes for time-based lines. Units for other line types: OPEN DECISION (OD-20) |
| rate_applied | money | N | |
| amount | money | R | |
| attendance_record_id | uuid | N | FK to `attendance_records` |
| overtime_record_id | uuid | N | FK to `overtime_records` |
| leave_request_id | uuid | N | FK to `leave_requests` |
| holiday_id | uuid | N | FK to `holidays` |

- **Foreign keys:** as listed.
- **Indexes:** `(payroll_record_id)`; each source FK.
- **History/audit:** Frozen when the period is locked. Source links keep each line traceable.
- OPEN DECISION (OD-20): line granularity (per day or aggregated) and the earning types.

### 5.25 payroll_deductions

- **Purpose:** Itemized deduction lines belonging to a payroll record.
- **Primary key:** `id`. **Standard columns:** STD-L.

| Column | Type | Null | Notes |
|---|---|---|---|
| payroll_record_id | uuid | R | FK to `payroll_records` |
| deduction_category_id | uuid | R | FK to `deduction_categories` |
| description | text | N | |
| deduction_minutes | duration | N | Integer minutes. For lateness lines (for example 0.5 hour = 30) |
| rate_applied | money | N | |
| amount | money | R | |
| deduction_rule_id | uuid | N | FK to `deduction_rules`; the rule applied |
| attendance_record_id | uuid | N | FK to `attendance_records` |
| cash_advance_id | uuid | N | FK to `cash_advances` |
| remittance_review_id | uuid | N | FK to `remittance_reviews` |

- **Foreign keys:** as listed.
- **Mandatory integrity rules:**
  1. A line in the remittance-shortage category must have `remittance_review_id` set, and that
     review must be an owner-approval row with an approving outcome. Enforce with a trigger
     or a composite foreign key in the cloud, and in the domain layer locally.
  2. A line in the CA/Vale category must have `cash_advance_id` set, and the advance must
     have been released.
  3. Rules 1 and 2 mean shortage can never become a deduction automatically.
- **Indexes:** `(payroll_record_id)`; `(cash_advance_id)`; `(remittance_review_id)`.
- **History/audit:** Frozen when the period is locked.

### 5.26 payroll_adjustments

- **Purpose:** Manual additions or subtractions applied to a payroll record, kept separate from calculated lines.
- **Primary key:** `id`. **Standard columns:** STD-L.

| Column | Type | Null | Notes |
|---|---|---|---|
| payroll_record_id | uuid | R | FK to `payroll_records` |
| amount | money | R | Signed; positive adds to net pay, negative reduces it |
| reason | text | R | |
| requested_by | uuid | R | FK to `user_profiles` |
| approved_by | uuid | N | FK to `user_profiles` |
| approved_at | instant | N | |
| corrects_earning_id | uuid | N | FK to `payroll_earnings` |
| corrects_deduction_id | uuid | N | FK to `payroll_deductions` |

- **Foreign keys:** as listed.
- **Indexes:** `(payroll_record_id)`.
- **History/audit:** Append-only. An adjustment is never edited; it is reversed by another adjustment.
  Adjustments cannot be added to a locked record.
- OPEN DECISION (OD-20): who may request and approve adjustments, and how an adjustment for an
  already finalized period is applied (for example in a later period).
### 5.27 payroll_settings

- **Purpose:** Operational settings for payroll that are not versioned rule values.
- **Primary key:** `id`. **Standard columns:** STD-M.

| Column | Type | Null | Notes |
|---|---|---|---|
| setting_key | text | R | |
| setting_value | text | R | |
| value_type | text | R | For example text, integer, decimal, time, boolean |
| description | text | N | |

- **Foreign keys:** none. **Unique:** `setting_key`. **Indexes:** unique on `setting_key`.
- **History/audit:** Every change is audited with the old and new value. Settings that affect
  calculation of past or future pay must live in `business_rule_versions`, not here.
- **Candidate contents (not yet decided):** first-period anchor (OD-20). The business time zone is
  fixed as Asia/Manila by OD-03.
- OPEN DECISION (OD-17): the exact boundary between `payroll_settings` and `business_rule_versions`.

### 5.28 business_rule_versions

- **Purpose:** Versioned, effective-dated sets of configurable business rules. Payroll
  references the version it used.
- **Primary key:** `id`. **Standard columns:** STD-M (until approved, then immutable).

| Column | Type | Null | Notes |
|---|---|---|---|
| version_number | int | R | Increases with each new version |
| name | text | N | |
| effective_from | date | R | |
| effective_to | date | N | Null means current |
| status | text | R | For example draft or approved. Values: OPEN DECISION (OD-17) |
| rules | json | R | The configurable values for this version. Structure: OPEN DECISION (OD-17) |
| approved_by | uuid | N | FK to `user_profiles` |
| approved_at | instant | N | |

- **Foreign keys:** `approved_by`.
- **Configurable values that must live here and never in code (all from the approved rules):**
  payroll period length, standard time-in, standard shift length, lateness tiers,
  and the divisor used to derive the hourly rate. Rates themselves live in `employee_pay_rates`.
- **Unique:** `version_number`.
- **Non-overlap rule:** approved versions must not overlap in effective period (same approach as 5.5).
- **Indexes:** unique on `version_number`; `(effective_from)`.
- **History/audit:** An approved version, or any version referenced by payroll, is immutable.
  A change creates a new version. Approval is audited.
- OPEN DECISION (OD-17): who approves a rule version and how a new version becomes effective.

### 5.29 audit_logs

- **Purpose:** Append-only record of sensitive actions and changes.
- **Primary key:** `id`. **Standard columns:** `id` only. This table has its own time and actor columns.

| Column | Type | Null | Notes |
|---|---|---|---|
| occurred_at | instant | R | When the action happened (device time) |
| recorded_at | instant | R | When this row was written |
| actor_user_id | uuid | N | Null for system actions |
| actor_role_code | text | N | Role at the time of the action |
| action | text | R | Action names: OPEN DECISION (OD-22) |
| entity_table | text | R | |
| entity_id | uuid | R | |
| old_values | json | N | |
| new_values | json | N | |
| reason | text | N | |
| device_id | uuid | N | See OD-24 |
| correlation_id | uuid | N | Groups rows from one operation |

- **Foreign keys:** `actor_user_id` to `user_profiles.id`. `entity_id` is deliberately not a foreign key because it points to many tables.
- **Indexes:** `(entity_table, entity_id, occurred_at)`; `(actor_user_id, occurred_at)`; `(action, occurred_at)`.
- **History/audit:** Append-only. Update and delete are blocked (cloud triggers and policies; locally by the repository).
- **Minimum audited events proposed (needs Project Manager confirmation):** role and account
  changes, pay-rate changes, attendance corrections, CA/Vale approvals and releases, remittance
  reviews, payroll status changes, finalization, rule-version and setting changes, backup and restore.
- OPEN DECISION (OD-22): the confirmed list of audited events, tamper evidence (such as a hash chain),
  retention period, and how personal data in `old_values`/`new_values` is handled.

### 5.30 notifications

- **Purpose:** In-app messages to users.
- **Primary key:** `id`. **Standard columns:** `id`, `created_at`.

| Column | Type | Null | Notes |
|---|---|---|---|
| recipient_user_id | uuid | R | FK to `user_profiles` |
| notification_type | text | R | |
| title | text | R | |
| body | text | N | |
| related_entity_table | text | N | |
| related_entity_id | uuid | N | |
| read_at | instant | N | The only column expected to change |

- **Foreign keys:** `recipient_user_id`.
- **Indexes:** `(recipient_user_id, read_at)`; `(recipient_user_id, created_at)`.
- **History/audit:** Not an audit source. Notifications may be purged by a retention policy.
- OPEN DECISION (OD-23): delivery channels beyond in-app, whether notifications are created
  locally or by the server, whether they sync, and retention.

### 5.31 biometric_records

- **Purpose:** Biometric attendance event/reference metadata only (RESOLVED, OD-21).
- **Primary key:** `id`. **Standard columns:** STD-L (provisional).
- **Prohibited content (RESOLVED, OD-21):** raw fingerprint data, fingerprint images, biometric
  templates, and equivalent sensitive biometric data are never stored in the application database.
- **Provisional columns.** The exact fields depend on the client's biometric device/API (OD-21,
  remaining), so the list and the nullability below are provisional:

| Column | Type | Null | Notes |
|---|---|---|---|
| employee_id | uuid | R | FK to `employees` |
| device_id | uuid or text | R | Identifies the biometric device. No FK (OD-24). Type depends on the device |
| biometric_event_id | text | R | Event identifier as supplied by the device/API |
| event_timestamp | instant | R | When the event occurred |
| event_type | text | R | Values: OPEN DECISION (OD-21) |
| source | text | R | |
| sync_status | text | R | Values: OPEN DECISION (OD-25) |

- **Foreign keys:** `employee_id` to `employees.id`.
- **Unique (proposed, provisional):** `(device_id, biometric_event_id)`, so a repeated import of the same event is idempotent.
- **Indexes (proposed):** `(employee_id, event_timestamp)`; `(device_id, event_timestamp)`.
- **Integration:** biometric integration goes through an adapter/integration layer when it is
  implemented. Business logic does not depend on a device vendor API.
- **History/audit:** The event facts are not edited after capture; `sync_status` is the only
  column expected to change (provisional).
- OPEN DECISION (OD-21, remaining): the actual biometric device brand, model, and API have not
  been provided by the client. The exact fields, and how events become or relate to
  `attendance_records` (see OD-11), stay open until they are.

### 5.32 sync_queue

- **Purpose:** Local outbox of changes waiting to be sent to the cloud. Specified here only so the
  schema can reserve the idea; no sync is implemented.
- **Primary key:** `id`. **Standard columns:** `id`, `created_at`.

| Column | Type | Null | Notes |
|---|---|---|---|
| idempotency_key | uuid | R | Stable per operation so retries are safe |
| entity_table | text | R | |
| entity_id | uuid | R | |
| operation | text | R | Insert, update, or void. No physical delete operation |
| payload | json | R | |
| status | text | R | Pending, in progress, failed, done. Final values set in the sync phase |
| attempt_count | int | R | Starts at 0 |
| last_error | text | N | |
| next_attempt_at | instant | N | |
| device_id | uuid | N | See OD-24 |

- **Foreign keys:** none (polymorphic reference).
- **Unique:** `idempotency_key`.
- **Indexes:** `(status, next_attempt_at)`; `(entity_table, entity_id)`.
- **History/audit:** Local-only. Not replicated. Completed rows may be pruned.
- OPEN DECISION (OD-25): the final structure, which belongs to the sync phase.

### 5.33 sync_conflicts

- **Purpose:** Records conflicts detected between local and cloud versions of a row.
- **Primary key:** `id`. **Standard columns:** `id`, `created_at`.

| Column | Type | Null | Notes |
|---|---|---|---|
| entity_table | text | R | |
| entity_id | uuid | R | |
| local_payload | json | R | |
| remote_payload | json | R | |
| detected_at | instant | R | |
| status | text | R | Values: OPEN DECISION (OD-25) |
| resolution | text | N | |
| resolved_by | uuid | N | FK to `user_profiles` |
| resolved_at | instant | N | |
| resolution_note | text | N | |

- **Foreign keys:** `resolved_by`.
- **Indexes:** `(status)`; `(entity_table, entity_id)`.
- **History/audit:** Resolved conflicts are retained. A resolution that changes business data is audited.
- OPEN DECISION (OD-25): the conflict policy for each table, and who may resolve conflicts.

### 5.34 backup_records

- **Purpose:** Log of backups and restores.
- **Primary key:** `id`. **Standard columns:** STD-L.

| Column | Type | Null | Notes |
|---|---|---|---|
| operation | text | R | Backup or restore |
| backup_type | text | N | For example manual or scheduled. Values: OPEN DECISION (OD-26) |
| file_name | text | R | |
| storage_location | text | N | |
| size_bytes | int | N | |
| checksum | text | N | |
| app_version | text | R | From `pubspec.yaml` |
| schema_version | int | R | The local schema version at the time |
| status | text | R | Values: OPEN DECISION (OD-26) |
| started_at | instant | R | |
| completed_at | instant | N | |
| note | text | N | |

- **Foreign keys:** none beyond `created_by`.
- **Indexes:** `(started_at)`; `(operation, status)`.
- **History/audit:** Append-only. Restore is a sensitive action and is audited.
- OPEN DECISION (OD-26): backup scope, encryption, location, who may run a restore, and
  how a restored database is reconciled with the cloud.

## 6. Relationship overview

Parent-to-child relationships, grouped by area:

- Identity: `roles` has many `user_profiles`. `user_profiles` is referenced by
  `created_by` / `updated_by` and by actor columns on most tables.
- Workforce: `positions` has many `employees`. `user_profiles` has zero or one `employees`
  (OD-06). `employees` has many `employee_pay_rates`, non-overlapping in time.
- Scheduling: `schedules` has many `shift_assignments`. `employees` has many `shift_assignments`.
- Attendance: `employees` has many `attendance_records`. `attendance_records` has many
  `attendance_corrections`. `shift_assignments` optionally links to `attendance_records`.
- Leave: `leave_types` has many `leave_requests` and `leave_transactions`.
  `leave_requests` has many `leave_transactions`.
- Overtime: `employees` has many `overtime_records`; each may link to an `attendance_records` row.
- CA/Vale: `employees` has many `cash_advances`. `cash_advances` has many `advance_transactions`.
  `advance_transactions.payroll_deduction_id` points to `payroll_deductions`.
- Deductions and rules: `business_rule_versions` has many `deduction_rules`.
  `deduction_categories` has many `deduction_rules` and `payroll_deductions`.
- Remittance: `remittance_records` has many `remittance_assignments` and `remittance_reviews`.
  `employees` has many `remittance_assignments`.
- Payroll: `payroll_periods` has many `payroll_records`, one per employee. `payroll_records`
  has many `payroll_earnings`, `payroll_deductions` and `payroll_adjustments`.
  `payroll_deductions` can source from `attendance_records`, `cash_advances`,
  `remittance_reviews` and `deduction_rules`. `payroll_earnings` can source from
  `attendance_records`, `overtime_records`, `leave_requests` and `holidays`.
- Reference-only tables: `audit_logs`, `notifications`, `sync_queue`, `sync_conflicts`
  and `backup_records` reference users and entities by id and hold no business-row dependencies.

Key cardinalities:

| Parent | Child | Cardinality |
|---|---|---|
| roles | user_profiles | one to many |
| user_profiles | employees | one to zero-or-one (OD-06) |
| employees | employee_pay_rates | one to many, non-overlapping in time |
| schedules | shift_assignments | one to many |
| employees | attendance_records | one to many |
| attendance_records | attendance_corrections | one to many |
| leave_requests | leave_transactions | one to many |
| cash_advances | advance_transactions | one to many |
| remittance_records | remittance_assignments and remittance_reviews | one to many |
| payroll_periods | payroll_records | one to many, one per employee |
| payroll_records | earnings, deductions, adjustments | one to many |
| business_rule_versions | deduction_rules | one to many |

## 7. Index and constraint strategy

| Concern | Strategy |
|---|---|
| Primary keys | UUID `id` on every table |
| Foreign keys | Declared everywhere except audit and sync polymorphic references; all `RESTRICT`. In PostgreSQL, foreign-key columns are indexed explicitly because PostgreSQL does not do it automatically |
| Uniqueness | Business codes and natural keys listed per table; partial unique indexes where "at most one active" is required |
| Non-overlap | Cloud: exclusion constraints (`btree_gist`) on `employee_pay_rates`, `payroll_periods`, `business_rule_versions`. Local: transactional repository checks, because SQLite cannot express them |
| CHECK constraints | Used for date order, positive amounts, and derived-amount consistency (net pay, shortage and overage). SQLite supports CHECK |
| Immutability | Cloud triggers and policies reject update/delete on append-only and locked rows. Local repositories refuse the same writes |
| Authorization | Row-level security in the cloud (policy design is a later phase); never a client-only check |
| Query indexes | Indexes listed per table are the minimum. Further indexes are added only after real query needs appear |
| Local portability | Use only constraint features available in both engines, or document the cloud-only extras as above |

## 8. Historical data strategy

| Pattern | Used for | Rule |
|---|---|---|
| Effective-dated versions | `employee_pay_rates`, `business_rule_versions` | Close the old row, insert a new one. Never edit values in place |
| Append-only ledger | `*_transactions`, `attendance_corrections`, `remittance_reviews`, `remittance_assignments`, `payroll_adjustments`, `audit_logs`, `backup_records` | No update or delete. Mistakes are fixed with reversing rows |
| Void instead of delete | Transactional rows (rates, remittances, overtime) | Set `voided_at`, `voided_by`, `void_reason` |
| Deactivate instead of delete | Master data | `is_active = false`; rows and links remain |
| Snapshot at calculation | `payroll_*` | Copy rates, names, positions, and rule version into the payroll row. Later master-data changes cannot alter it |
| Lock on finalization | `payroll_periods` and all children | Immutable after finalization; reopening is OPEN DECISION (OD-20) |

Specific guarantees required by the approved rules:

- **Pay rates:** history with effective dates, no overlapping periods (section 5.5).
- **Attendance:** original and corrected values both preserved (sections 5.8 and 5.9).
- **Remittance:** expected, actual, shortage, and overage stay explicit and traceable; shortage
  becomes a deduction only through a review chain ending in Owner approval (sections 5.19 to 5.21, 5.25).
- **CA/Vale:** request, approvals, release, deduction, and balance changes are traceable through
  `advance_transactions` (section 5.16).
- **Payroll:** 14-day periods, snapshots, approval status, finalized and locked records,
  earnings, deductions, adjustments (sections 5.22 to 5.26).
- **Audit:** sensitive changes are written to `audit_logs`, which cannot be altered (section 5.29).

## 9. Sync-related database considerations

Nothing here is implemented. It is recorded so the schema does not block a later sync design.

- Client-generated UUIDs mean rows created offline on different devices cannot collide.
- Sync must be retry-safe and idempotent; `sync_queue.idempotency_key` is the planned mechanism.
- Sync metadata that will likely be needed on synchronized tables, to be added by a later approved
  migration (not now): a row version or server timestamp, the originating device, a sync state,
  and a tombstone or void indicator. Hard deletes are not used, so deletions travel as voids.
- Proposed sync scope (to be confirmed in the sync phase):
  - Synchronized: all business, configuration, and audit tables (1 to 29 except as noted).
  - Local-only: `sync_queue`.
  - Undecided: `notifications` (OD-23), `sync_conflicts` and `backup_records` (OD-25, OD-26),
    `biometric_records` (OD-21).
- Conflict-sensitive tables, where two offline devices can legitimately collide:
  `employee_pay_rates`, `shift_assignments`, `attendance_records`, `payroll_periods`,
  `cash_advances`.
- The actions listed in section 2.1 (RESOLVED, OD-19) must be authorized by the server and cannot
  be finalized offline. Preparation and other non-final workflows continue offline.
- OPEN DECISION (OD-25): per-table conflict policy, tombstone handling, and server-time authority.

## 10. Migration and versioning considerations

- Local schema: tracked by an integer schema version (Drift's schema version, later). Each
  local migration must be non-destructive and tested on a copy of a populated database.
- Cloud schema: SQL migrations kept in version control and applied in order. Tooling:
  OPEN DECISION (OD-27).
- Local and cloud schema versions must stay compatible. The app must know the minimum
  compatible cloud version and refuse to sync if it is behind. Exact policy: OD-27.
- A backup is taken before any local migration runs.
- Migrations never drop or rewrite historical columns. A column is retired by deprecating it, not
  by deleting data.
- Seed data (versioned and idempotent): the four roles, the system deduction categories,
  and the initial business rule version.
- `backup_records.schema_version` and `app_version` record which versions produced each backup.
- Changing a confirmed business rule is never done through a migration alone; it needs
  Project Manager approval first.

## 11. Decisions: resolved and open

### 11.1 Resolved decisions

Resolved by the Project Manager on 2026-10-06. OD-01 to OD-04, OD-28, OD-29 and OD-30 are fully resolved. For OD-17,
OD-19, and OD-21, only the part shown here is resolved; the remainder stays open in 11.2.

| ID | Resolved decision | Applied in |
|---|---|---|
| OD-01 | UUID v4 for all primary identifiers | 3.1 |
| OD-02 | ISO 8601 representation; instants are UTC ISO 8601; business dates and displayed times are interpreted in Asia/Manila | 3.2, 3.4 |
| OD-03 | Asia/Manila is the official business time zone; no dependence on the device time zone | 3.2 |
| OD-04 | Money stored as integer centavos (PHP 480.00 = 48000); no floating point | 3.4, section 5 intro |
| OD-17 (late-hour boundary only) | 6:15 AM starts the 1-hour bracket; 7:00 to 7:59 = 2 hours, continuing hourly; hourly rate = daily rate / 12 | 5.18 |
| OD-19 (action list only) | Five Owner/final actions require online server authorization | 2.1, 5.15, 5.16, 5.21, 5.22, 9 |
| OD-21 (storage decision only) | No raw biometric data; event/reference metadata only; adapter layer | 5.31 |
| OD-28 | Durations stored as integer minutes (30 = 30, 1 hour = 60, 12-hour shift = 720); hours derived from minutes; no floating-point hours | 3.4, 5.14, 5.24, 5.25 |
| OD-29 | Integer centavos with centavo-safe arithmetic; fractions rounded to the nearest centavo, half-up (PHP 10.004 = 10.00, PHP 10.005 = 10.01) | 3.4, 5.5 |
| OD-30 | Each independently calculated line is rounded half-up to the centavo before being summed into totals; net pay is computed from integer totals; half-up is symmetric around zero for negatives (-10.005 = -10.01) | 3.4, 5.5, 5.23 |

### 11.2 Remaining open decisions

| ID | Decision needed | Affects |
|---|---|---|
| OD-05 | Single or multiple roles per user; where the permission matrix lives | roles, user_profiles |
| OD-06 | Employee-to-user relationship rules; whether an email copy is stored | employees, user_profiles |
| OD-07 | Employment status values; personal and identification fields to collect; rehire | employees |
| OD-08 | Position history; any link between position and pay | positions, employees |
| OD-09 | Inclusive/exclusive end date for rates; rate-change approval; back-dating | employee_pay_rates |
| OD-10 | Shift model: several shifts per day, rest days, overnight, schedule status, alignment with payroll periods | schedules, shift_assignments |
| OD-11 | Attendance sources, statuses, uniqueness per day, missed punches, trusted time | attendance_records |
| OD-12 | Attendance correction approval and statuses; corrections affecting locked payroll | attendance_corrections |
| OD-13 | Leave rules: paid or unpaid, balances, half-days, approval chain, transaction types | leave_* tables |
| OD-14 | Holiday types and pay effects; yearly recurrence | holidays |
| OD-15 | Overtime definition, source, approval chain, multiplier | overtime_records |
| OD-16 | CA/Vale: types, extra states, installments, partial release, when the deduction transaction is written, cached balance | cash_advances, advance_transactions |
| OD-17 | Remaining: deduction categories beyond the approved ones; rule representation; seconds handling and any cap on the late progression; split between rule versions and settings; rule approval; how the active version is selected | deduction_categories, deduction_rules, business_rule_versions, payroll_settings |
| OD-18 | Remittance: source of expected amount, amount corrections, shared responsibility, stages, outcomes, statuses | remittance_* tables |
| OD-19 | Remaining: enumerate the specific actions under "other irreversible Owner-only financial actions"; how server authorization is evidenced in stored rows | Authorization design |
| OD-20 | Payroll: first-period anchor, payday, statuses, DB-level 14-day check, recalculation retention, earning granularity and types, adjustments, reopening, post-finalization corrections | payroll_* tables |
| OD-21 | Remaining: biometric device brand/model/API (not yet provided by the client); exact event fields; how events relate to attendance records | biometric_records |
| OD-22 | Audited events, tamper evidence, retention, personal data in audit values | audit_logs |
| OD-23 | Notification channels, origin, sync, and retention | notifications |
| OD-24 | Whether a devices table is needed and how devices are identified | audit_logs, sync_queue |
| OD-25 | Sync scope, per-table conflict policy, tombstones, server-time authority | sync_* tables |
| OD-26 | Backup scope, encryption, location, restore authority, cloud reconciliation | backup_records |
| OD-27 | Cloud migration tooling; local/cloud compatibility policy | Migrations |

Resolution of any open decision requires Project Manager approval. This document is then updated
in the same change that records the decision.
