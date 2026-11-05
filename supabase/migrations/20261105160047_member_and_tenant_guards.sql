-- Guards found in security review of the RLS work:
--   * A worker can't be demoted or removed while they still have open visits
--     (otherwise a non-worker would hold scheduled visits).          -> CV040
--   * An organization always keeps at least one owner.               -> CV041
--   * Membership keys never change in place (remove + add instead).  -> CV042
--   * Clients and visits never move between organizations, which would also split
--     their audit trail across two tenants.                          -> CV043
--   * Membership changes are audited, like clients and visits.
--   * service_role can't write or tamper with audit_log, and can't TRUNCATE the audited
--     tables (TRUNCATE skips row-level audit triggers).

-- Members ------------------------------------------------------------------------------
create or replace function private.guard_member_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and (new.organization_id <> old.organization_id or new.user_id <> old.user_id) then
    raise exception 'A membership cannot be moved; remove it and add a new one.'
      using errcode = 'CV042';
  end if;

  -- Leaving the worker role (demotion or removal) with open visits.
  if old.role = 'worker' and (tg_op = 'DELETE' or new.role <> 'worker') and exists (
    select 1 from public.visits v
    where v.organization_id = old.organization_id
      and v.worker_id = old.user_id
      and v.status in ('scheduled', 'in_progress')
  ) then
    raise exception 'This worker still has open visits. Reassign or cancel them first.'
      using errcode = 'CV040';
  end if;

  -- Leaving the owner role: someone else must still be an owner. The organization row is
  -- locked so two owners can't demote each other at the same moment.
  if old.role = 'owner' and (tg_op = 'DELETE' or new.role <> 'owner') then
    perform 1 from public.organizations o where o.id = old.organization_id for update;
    if not exists (
      select 1 from public.organization_members m
      where m.organization_id = old.organization_id
        and m.role = 'owner'
        and m.user_id <> old.user_id
    ) then
      raise exception 'An organization needs at least one owner.'
        using errcode = 'CV041';
    end if;
  end if;

  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

comment on function private.guard_member_change() is 'Trigger: keeps open visits on workers, keeps one owner, and makes membership keys immutable.';
revoke all on function private.guard_member_change() from public;

create trigger organization_members_guard
  before update or delete on public.organization_members
  for each row execute function private.guard_member_change();

-- Audit membership changes (row_id = the member's user id).
create or replace function private.audit_member_change()
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
    case when tg_op = 'DELETE' then old.user_id else new.user_id end,
    lower(tg_op)::public.audit_action,
    case when tg_op = 'INSERT' then null else to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end,
    (select auth.uid())
  );
  return null;
end;
$$;

comment on function private.audit_member_change() is 'Trigger: appends an audit_log row for each membership insert/update/delete (row_id = user_id).';
revoke all on function private.audit_member_change() from public;

create trigger organization_members_audit
  after insert or update or delete on public.organization_members
  for each row execute function private.audit_member_change();

-- Clients and visits stay in their organization ------------------------------------------
create or replace function private.prevent_organization_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.organization_id <> old.organization_id then
    raise exception 'Records cannot be moved to another organization.'
      using errcode = 'CV043';
  end if;
  return new;
end;
$$;

comment on function private.prevent_organization_change() is 'Trigger: organization_id is immutable on tenant-owned rows.';
revoke all on function private.prevent_organization_change() from public;

-- Triggers on a table fire in name order; "block_..." sorts before "enforce_rules" so this
-- clearer error wins over the worker-role check when someone tries to move a visit.
create trigger clients_block_organization_change
  before update of organization_id on public.clients
  for each row execute function private.prevent_organization_change();

create trigger visits_block_organization_change
  before update of organization_id on public.visits
  for each row execute function private.prevent_organization_change();

-- service_role: no tampering with the audit trail ----------------------------------------
revoke insert, trigger on table public.audit_log from service_role;
revoke truncate on table public.clients, public.visits, public.organization_members from service_role;
