-- Business rules on visits that need to look at other rows or at the old value,
-- so they can't be plain CHECK constraints:
--   5. An archived client can't get new visits.
--   6. Status moves only scheduled -> in_progress -> completed, or scheduled -> cancelled.
--   +  The assigned worker must have the worker role in the visit's organization.
--   +  Only scheduled visits can be re-timed or reassigned (keeps worked history stable).
--   +  in_progress needs a check-in event and completed needs a check-out event, so the
--      status can't be pushed forward without the worker actually checking in and out.
--
-- Errors use custom SQLSTATEs (class CV) so the web app can show a clear message:
--   CV001 archived client, CV002 not a worker, CV003 invalid status change,
--   CV004 new visit not scheduled, CV005 visit no longer editable,
--   CV006 in_progress without check-in, CV007 completed without check-out.
--
-- The lookups take FOR SHARE locks so a concurrent archive of the client or role change
-- of the worker waits for this transaction (and vice versa) instead of racing it.

create or replace function private.enforce_visit_rules()
returns trigger
language plpgsql
security definer   -- the lookups below must see the rows regardless of the caller's RLS
set search_path = ''
as $$
declare
  v_client_status public.client_status;
  v_worker_role   public.member_role;
begin
  -- Rule 6: a new visit always starts as scheduled.
  if tg_op = 'INSERT' and new.status <> 'scheduled' then
    raise exception 'A new visit must start as scheduled (got %).', new.status
      using errcode = 'CV004';
  end if;

  -- Rule 6: allowed status transitions.
  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    if not (
         (old.status = 'scheduled'   and new.status in ('in_progress', 'cancelled'))
      or (old.status = 'in_progress' and new.status = 'completed')
    ) then
      raise exception 'A visit cannot move from % to %.', old.status, new.status
        using errcode = 'CV003';
    end if;

    if new.status = 'in_progress' and not exists (
      select 1 from public.visit_events e
      where e.visit_id = new.id and e.event_type = 'check_in'
    ) then
      raise exception 'A visit starts only when the worker checks in.'
        using errcode = 'CV006';
    end if;

    if new.status = 'completed' and not exists (
      select 1 from public.visit_events e
      where e.visit_id = new.id and e.event_type = 'check_out'
    ) then
      raise exception 'A visit completes only when the worker checks out.'
        using errcode = 'CV007';
    end if;
  end if;

  -- Only scheduled visits may change time, client or worker.
  if tg_op = 'UPDATE' and old.status <> 'scheduled' and (
       new.starts_at   is distinct from old.starts_at
    or new.ends_at     is distinct from old.ends_at
    or new.client_id   is distinct from old.client_id
    or new.worker_id   is distinct from old.worker_id
    or new.organization_id is distinct from old.organization_id
  ) then
    raise exception 'Only scheduled visits can be rescheduled or reassigned (this one is %).', old.status
      using errcode = 'CV005';
  end if;

  -- Rule 5: no new visits for archived clients (on insert, or when moving a visit to another client).
  if tg_op = 'INSERT' or new.client_id is distinct from old.client_id then
    select c.status into v_client_status
    from public.clients c
    where c.id = new.client_id
    for share;

    if v_client_status = 'archived' then
      raise exception 'This client is archived and cannot get new visits.'
        using errcode = 'CV001';
    end if;
  end if;

  -- The assignee must be a worker of the visit's organization (the FK only proves membership).
  if tg_op = 'INSERT' or new.worker_id is distinct from old.worker_id
     or new.organization_id is distinct from old.organization_id then
    select m.role into v_worker_role
    from public.organization_members m
    where m.organization_id = new.organization_id
      and m.user_id = new.worker_id
    for share;

    if v_worker_role is distinct from 'worker' then
      raise exception 'Visits can only be assigned to members with the worker role.'
        using errcode = 'CV002';
    end if;
  end if;

  return new;
end;
$$;

comment on function private.enforce_visit_rules() is 'Trigger: archived clients, worker role, status flow (with check-in/out evidence) and edit lock on visits (rules 5 and 6).';
revoke all on function private.enforce_visit_rules() from public;

create trigger visits_enforce_rules
  before insert or update on public.visits
  for each row execute function private.enforce_visit_rules();
