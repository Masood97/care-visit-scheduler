-- Part B step 4 of 6: rules on assignments (added after the backfill, which must be able
-- to copy assignments of completed and cancelled visits).
--
--   * 1 to 2 workers per visit:
--       - at most 2: checked on insert while the visit row is locked, so two coordinators
--         adding a second worker at the same moment can't both succeed       -> CV050
--       - at least 1: deferred constraint triggers check at COMMIT, so a worker can be
--         swapped (remove + add) inside one transaction                       -> CV051
--   * Assignments change only while the visit is scheduled                     -> CV005
--   * The assignee must have the worker role                                   -> CV002
--   * Assignment keys never change in place                                    -> CV052
--   * Removing the primary worker hands visits.worker_id to the remaining worker, so the
--     legacy column always names an assigned worker.
--   * Assignment changes are audited (rule 9: they are changes to a visit).

-- BEFORE INSERT: validate and fill the copied columns from the visit itself.
create or replace function private.before_visit_worker_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_visit public.visits;
begin
  select * into v_visit from public.visits where id = new.visit_id for update;
  if not found then
    return new; -- the foreign key reports the missing visit
  end if;

  if v_visit.status <> 'scheduled' then
    raise exception 'Workers can only be changed while the visit is scheduled.'
      using errcode = 'CV005';
  end if;

  if not exists (
    select 1 from public.organization_members m
    where m.organization_id = v_visit.organization_id and m.user_id = new.worker_id and m.role = 'worker'
    for share
  ) then
    raise exception 'Visits can only be assigned to members with the worker role.'
      using errcode = 'CV002';
  end if;

  if (select count(*) from public.visit_workers where visit_id = new.visit_id) >= 2 then
    raise exception 'A visit can have at most two workers.'
      using errcode = 'CV050';
  end if;

  -- The copies always come from the visit, never from the caller.
  new.organization_id := v_visit.organization_id;
  new.starts_at := v_visit.starts_at;
  new.ends_at := v_visit.ends_at;
  new.visit_status := v_visit.status;
  return new;
end;
$$;

-- BEFORE DELETE / UPDATE: assignments are fixed once the visit has started.
create or replace function private.before_visit_worker_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_status public.visit_status;
begin
  if tg_op = 'UPDATE' then
    if new.visit_id <> old.visit_id or new.worker_id <> old.worker_id or new.organization_id <> old.organization_id then
      raise exception 'An assignment cannot be moved; remove it and add a new one.'
        using errcode = 'CV052';
    end if;
    return new; -- only the synced copies change
  end if;

  select status into v_status from public.visits where id = old.visit_id;
  if found and v_status <> 'scheduled' then
    raise exception 'Workers can only be changed while the visit is scheduled.'
      using errcode = 'CV005';
  end if;
  return old;
end;
$$;

-- AFTER DELETE: if the primary worker was removed, the remaining worker becomes primary.
create or replace function private.after_visit_worker_delete()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.visits v
     set worker_id = (select vw.worker_id from public.visit_workers vw
                      where vw.visit_id = old.visit_id order by vw.created_at limit 1)
   where v.id = old.visit_id
     and v.worker_id = old.worker_id
     and exists (select 1 from public.visit_workers vw where vw.visit_id = old.visit_id);
  return null;
end;
$$;

-- Deferred check (at COMMIT): every visit has at least one worker.
create or replace function private.require_visit_worker()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_visit_id uuid;
begin
  -- Fires for visits (INSERT: NEW is the visit) and visit_workers (DELETE: OLD is the assignment).
  if tg_table_name = 'visits' then
    v_visit_id := new.id;
  else
    v_visit_id := old.visit_id;
  end if;

  if exists (select 1 from public.visits where id = v_visit_id)
     and not exists (select 1 from public.visit_workers where visit_id = v_visit_id) then
    raise exception 'A visit needs at least one worker.'
      using errcode = 'CV051';
  end if;
  return null;
end;
$$;

-- Audit assignment changes (row_id = the visit).
create or replace function private.audit_visit_worker_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.audit_log (organization_id, table_name, row_id, action, old_data, new_data, changed_by)
  values (
    case when tg_op = 'DELETE' then old.organization_id else new.organization_id end,
    tg_table_name,
    case when tg_op = 'DELETE' then old.visit_id else new.visit_id end,
    lower(tg_op)::public.audit_action,
    case when tg_op = 'INSERT' then null else to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end,
    (select auth.uid())
  );
  return null;
end;
$$;

comment on function private.before_visit_worker_insert() is 'Trigger: max 2 workers, worker role, scheduled-only, copies time/status from the visit.';
comment on function private.before_visit_worker_change() is 'Trigger: assignments are immutable keys and change only while the visit is scheduled.';
comment on function private.after_visit_worker_delete() is 'Trigger: keeps visits.worker_id pointing at an assigned worker.';
comment on function private.require_visit_worker() is 'Deferred constraint trigger: a visit always has at least one worker at commit.';
comment on function private.audit_visit_worker_change() is 'Trigger: audits adding and removing workers on a visit.';

revoke all on function private.before_visit_worker_insert() from public;
revoke all on function private.before_visit_worker_change() from public;
revoke all on function private.after_visit_worker_delete() from public;
revoke all on function private.require_visit_worker() from public;
revoke all on function private.audit_visit_worker_change() from public;

create trigger visit_workers_before_insert
  before insert on public.visit_workers
  for each row execute function private.before_visit_worker_insert();

create trigger visit_workers_before_change
  before update or delete on public.visit_workers
  for each row execute function private.before_visit_worker_change();

create trigger visit_workers_after_delete
  after delete on public.visit_workers
  for each row execute function private.after_visit_worker_delete();

create constraint trigger visits_require_worker
  after insert on public.visits
  deferrable initially deferred
  for each row execute function private.require_visit_worker();

create constraint trigger visit_workers_require_worker
  after delete on public.visit_workers
  deferrable initially deferred
  for each row execute function private.require_visit_worker();

create trigger visit_workers_audit
  after insert or delete on public.visit_workers
  for each row execute function private.audit_visit_worker_change();
