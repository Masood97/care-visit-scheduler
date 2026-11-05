-- Part B step 3 of 6: backfill. Every existing visit keeps its current worker.
--
-- One assignment per visit, copied from visits.worker_id with the visit's time range and
-- status. Idempotent (ON CONFLICT DO NOTHING) and safe to run while the app is live: the
-- sync trigger from the previous migration already covers visits written meanwhile.
--
-- Locks: reads visits (no lock beyond a normal SELECT) and inserts into the new table.
-- For a very large visits table this would run in batches by id range (see the runbook);
-- at our size a single statement takes milliseconds.
--
-- Proof on real data: scripts/test-part-b-backfill.sh (run in CI) applies the schema up to
-- v1.0.1, loads the seed, applies Part B, and checks counts and pairs before/after.

insert into public.visit_workers (organization_id, visit_id, worker_id, starts_at, ends_at, visit_status)
select v.organization_id, v.id, v.worker_id, v.starts_at, v.ends_at, v.status
from public.visits v
on conflict (visit_id, worker_id) do nothing;
