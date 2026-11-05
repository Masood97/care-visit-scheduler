-- Helper functions used by the RLS policies.
--
-- They are SECURITY DEFINER so a policy on table X can look at organization_members or
-- visits without triggering those tables' own policies (which would recurse or hide the
-- rows the check needs). Each one only answers a yes/no question about the *current*
-- user, taken from auth.uid() (the verified JWT), never from an argument the client
-- controls. search_path is empty and every name is schema-qualified.

-- Is the current user a member of the organization (any role)?
create or replace function private.is_member(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_members m
    where m.organization_id = p_organization_id
      and m.user_id = (select auth.uid())
  );
$$;

-- Does the current user hold one of these roles in the organization?
create or replace function private.has_role(p_organization_id uuid, p_roles public.member_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.organization_members m
    where m.organization_id = p_organization_id
      and m.user_id = (select auth.uid())
      and m.role = any (p_roles)
  );
$$;

-- Is the current user the assigned worker on at least one (non-cancelled) visit to this client?
-- Lets workers read the clients on their own visits and nobody else's; a cancelled booking
-- does not keep giving access to the client's address.
create or replace function private.is_worker_of_client(p_client_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.visits v
    where v.client_id = p_client_id
      and v.worker_id = (select auth.uid())
      and v.status <> 'cancelled'
  );
$$;

comment on function private.is_member(uuid) is 'RLS helper: current user belongs to the organization.';
comment on function private.has_role(uuid, public.member_role[]) is 'RLS helper: current user has one of the roles in the organization.';
comment on function private.is_worker_of_client(uuid) is 'RLS helper: current user is the assigned worker on a visit to the client.';

revoke all on function private.is_member(uuid) from public;
revoke all on function private.has_role(uuid, public.member_role[]) from public;
revoke all on function private.is_worker_of_client(uuid) from public;
grant execute on function private.is_member(uuid) to authenticated;
grant execute on function private.has_role(uuid, public.member_role[]) to authenticated;
grant execute on function private.is_worker_of_client(uuid) to authenticated;
