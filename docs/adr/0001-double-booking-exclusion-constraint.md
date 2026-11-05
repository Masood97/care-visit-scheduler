# ADR 0001: Enforce "no double booking" with a GiST exclusion constraint

- **Status:** Accepted
- **Date:** 2026-11-05

## Context

Business rule 3: a worker can't have two visits that overlap in time, unless one is cancelled. The rule must still hold when two coordinators book at the same moment.

Options considered:

1. **Check in the web app** (query for overlaps, then insert). This has a race: two requests both see "no overlap" and both insert. It also fails to protect writes that bypass the app, such as the mobile app, scripts or SQL.
2. **BEFORE INSERT trigger that queries for overlaps.** It has the same race under READ COMMITTED, because each transaction can't see the other's uncommitted row. Fixing it needs an explicit lock per worker (`pg_advisory_xact_lock` or `SELECT … FOR UPDATE` on the member row), which every write path has to remember to take.
3. **SERIALIZABLE isolation.** It works, but needs retry logic on serialization failures, and it applies to every transaction, not just this rule.
4. **Exclusion constraint.** Postgres guarantees that no two rows satisfy all the operators at once. It is checked through the constraint's GiST index, which makes concurrent inserters wait on each other.

## Decision

Use a GiST exclusion constraint on `visits`:

```sql
constraint visits_no_overlap
  exclude using gist (worker_id with =, tstzrange(starts_at, ends_at, '[)') with &&)
  where (status <> 'cancelled')
```

- `btree_gist` provides `=` for `uuid` inside a GiST index.
- `'[)'` makes the range start-inclusive and end-exclusive, so back-to-back visits (10:00–11:00 then 11:00–12:00) are allowed.
- The partial `WHERE status <> 'cancelled'` means cancelled visits don't block a slot. Cancelling a visit frees it, and un-cancelling is impossible anyway (the status-flow trigger forbids leaving `cancelled`).

## Consequences

- **Concurrency-safe by construction.** If transaction A has inserted a visit and not committed, transaction B inserting an overlapping visit for the same worker waits on A. When A commits, B fails with `23P01 exclusion_violation`. If A rolls back, B succeeds. No application locking and no retries are needed. `scripts/test-concurrent-booking.sh` proves this in CI with two real sessions. The pgTAP test `10_visit_constraints.test.sql` covers the single-session cases (overlap, back-to-back, cancelled, moving a visit onto another).
- **Holds for every writer:** the web app, the legacy mobile app, functions and SQL.
- **Clear error for the UI:** the app maps SQLSTATE `23P01` with constraint `visits_no_overlap` to "This worker already has a visit at that time."
- **Cost:** a GiST index on `(worker_id, range)` is maintained on every insert and update. That is negligible at this scale, and the index also speeds up "is this worker free?" lookups.
- **Part B (2 workers per visit):** the rule must hold per worker across all their assignments, so a single `worker_id` column is no longer enough. The plan is to move the same exclusion constraint onto a `visit_workers (visit_id, worker_id, starts_at, ends_at, status)` table. The visit's time and status are copied onto it by trigger, because exclusion constraints can't span tables. See the Part B ADR.
