-- Part B step 2 of 6: keep visit_workers in step with visits.
--
-- Created BEFORE the backfill on purpose: from this moment every new or changed visit
-- maintains its own assignment, so no visit written while the backfill runs is missed
-- (the backfill uses ON CONFLICT DO NOTHING).
--
--   * INSERT on visits (e.g. the legacy mobile app, which only knows worker_id)
--       -> the worker becomes the visit's primary assignment.
--   * UPDATE of visits.worker_id (legacy reassignment)
--       -> the old primary assignment is replaced by the new worker.
--   * UPDATE of starts_at / ends_at / status
--       -> copied onto every assignment, so the exclusion constraint re-checks each worker.

create or replace function private.sync_visit_workers()
returns trigger
language plpgsql
security definer   -- app users can't UPDATE visit_workers directly
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.visit_workers (organization_id, visit_id, worker_id, starts_at, ends_at, visit_status)
    values (new.organization_id, new.id, new.worker_id, new.starts_at, new.ends_at, new.status)
    on conflict (visit_id, worker_id) do nothing;
    return null;
  end if;

  if new.worker_id is distinct from old.worker_id then
    delete from public.visit_workers where visit_id = new.id and worker_id = old.worker_id;
    insert into public.visit_workers (organization_id, visit_id, worker_id, starts_at, ends_at, visit_status)
    values (new.organization_id, new.id, new.worker_id, new.starts_at, new.ends_at, new.status)
    on conflict (visit_id, worker_id) do nothing;
  end if;

  if new.starts_at is distinct from old.starts_at
     or new.ends_at is distinct from old.ends_at
     or new.status is distinct from old.status then
    update public.visit_workers
       set starts_at = new.starts_at, ends_at = new.ends_at, visit_status = new.status
     where visit_id = new.id;
  end if;

  return null;
end;
$$;

comment on function private.sync_visit_workers() is 'Trigger: mirrors visits.worker_id, time range and status onto visit_workers (Part B compatibility).';
revoke all on function private.sync_visit_workers() from public;

create trigger visits_sync_workers
  after insert or update on public.visits
  for each row execute function private.sync_visit_workers();
