# ADR 0002: Two workers per visit, and retiring `visits.worker_id`

- **Status:** Accepted (expand phase shipped in v1.1.0; contract phase planned)
- **Date:** 2026-11-06

## Context

Some clients need two workers at the same time (2:1 support, for example for a safe lift). A visit must now have 1 or 2 workers. The double-booking rule must hold for each worker across all their assignments. Each worker checks in and out separately. The hours report counts every worker.

A mobile app in production still reads and writes `visits.worker_id`. We can't force every phone to update on the day we ship, so the column must keep working in this release. It also has to be removed safely later.

Options considered:

1. **A second column `visits.second_worker_id`.** Rejected. The overlap rule would need two exclusion constraints plus a cross-column check (A's first slot against B's second slot). It's asymmetric, it can't grow beyond two, and check-in/out would branch on which column the worker is in.
2. **An array column `worker_ids uuid[]`.** Rejected. Array elements can't have foreign keys, and an exclusion constraint can't compare individual elements.
3. **A join table `visit_workers`, with `visits.worker_id` kept and synchronised (expand/contract).** Chosen.

## Decision

**Expand (v1.1.0, shipped).** New migrations only; no merged migration was changed.

- `visit_workers (visit_id, worker_id, …)` is the source of truth for who is on a visit.
  - Composite foreign keys keep the visit and the worker in the same organization.
  - At most 2 workers is checked on insert while the visit row is locked.
  - At least 1 worker is checked by deferred constraint triggers at commit.
- The GiST exclusion constraint moves to `visit_workers`: `visit_workers_no_overlap`. Constraints can't span tables, so each assignment carries a trigger-maintained copy of its visit's `starts_at`, `ends_at` and `status`.
- **`visits.worker_id` stays and means "the primary worker"**, kept in sync in both directions by triggers:
  - legacy **insert** with `worker_id` → that worker is assigned;
  - legacy **update** of `worker_id` → the old primary assignment is replaced by the new worker;
  - removing the primary from a 2:1 visit → the remaining worker becomes `worker_id`.
- Backfill: every existing visit gets one assignment with its current worker. The sync triggers are created **before** the backfill, so visits written during the deploy aren't missed (`ON CONFLICT DO NOTHING`).
- Check-in/out:
  - any assigned worker checks in once; the first check-in sets `in_progress`;
  - each worker who checked in checks out once; the visit becomes `completed` when **every** assigned worker has checked out. For a safe lift both carers are needed.
- RLS: a worker sees a visit, and its client, if they are **any** of its workers.
- The hours report already pairs check-in and check-out per worker, so it counts every worker without changes.
- The web app books and edits through `book_visit` / `update_visit` RPCs. They write the visit and its 1–2 workers in one transaction, as the caller, so RLS applies.
- Proof on real data: `scripts/test-part-b-backfill.sh` (in CI) builds the v1.0.1 schema, loads the 32-visit seed, applies Part B, and checks that visit counts, statuses and every (visit, worker) pair are unchanged.

**Contract (planned, a later major release such as v2.0.0).** Remove `visits.worker_id` once nothing writes it.

| Step | When | How |
| --- | --- | --- |
| 1. Ship mobile app N+1 | after v1.1.0 | Reads `visit_workers`, books through `book_visit` / `update_visit`, never touches `worker_id` |
| 2. Measure legacy use | from v1.2.0 | A new migration adds a statement-level trigger that counts INSERT/UPDATEs setting `visits.worker_id` from outside the RPCs, using a `set_config` flag that the RPCs set. Release v1.2.0 also sets a minimum supported mobile version. |
| 3. Decide | when legacy writes are **zero for 30 days** and the minimum app version is ≥ N+1 | ADR update, then a release PR that names the contract migrations |
| 4. Contract migration A | v2.0.0 | Replace `private.sync_visit_workers()` and `private.enforce_visit_rules()` with versions that don't reference `worker_id`. Drop `visits_no_overlap` and the primary-reassignment trigger. |
| 5. Contract migration B | v2.0.0 | `set lock_timeout = '5s'; alter table public.visits drop column worker_id;`. Dropping a column is a quick catalog change with no table rewrite. Then regenerate the types. |

Each contract step is its own forward-only migration, run through staging first. If an old client appears after step 5, it gets a clear API error, which is acceptable once the minimum version is enforced. We don't roll back; we fix forward.

## Consequences

- Older clients keep working unchanged. They see and set the primary worker, and their writes keep `visit_workers` correct.
- Two sources describe the primary worker until the contract phase. The triggers keep them consistent, and `70_multi_worker_visits.test.sql` covers legacy insert, legacy reassignment and primary hand-over.
- `visits_no_overlap` is now redundant, because `visit_workers_no_overlap` is stricter. It stays until the contract phase because it costs little, and dropping it is part of the planned cleanup.
- Assignments can only change while a visit is `scheduled`. That keeps the worked-hours history stable, the same rule as re-timing a visit.
- A 2:1 visit where one worker never turns up stays `in_progress`. That is deliberate: the visit didn't happen as booked. A coordinator workflow for it (for example "complete with one worker") is out of scope for v1.1.0.
