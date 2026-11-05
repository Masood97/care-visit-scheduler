-- Part B step 5 of 6: a worker sees a visit if they are ANY of its assigned workers.

create or replace function private.is_assigned_worker(p_visit_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.visit_workers vw
    where vw.visit_id = p_visit_id
      and vw.worker_id = (select auth.uid())
  );
$$;

comment on function private.is_assigned_worker(uuid) is 'RLS helper: current user is one of the visit''s assigned workers.';
revoke all on function private.is_assigned_worker(uuid) from public;
grant execute on function private.is_assigned_worker(uuid) to authenticated;

-- Clients on any (non-cancelled) visit the worker is assigned to.
create or replace function private.is_worker_of_client(p_client_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.visit_workers vw
    join public.visits v on v.id = vw.visit_id
    where v.client_id = p_client_id
      and vw.worker_id = (select auth.uid())
      and v.status <> 'cancelled'
  );
$$;

drop policy "staff read visits, workers read their own" on public.visits;
create policy "staff read visits, workers read visits they are assigned to"
  on public.visits for select to authenticated
  using (
    private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[])
    or private.is_assigned_worker(id)
  );

create policy "staff and the visit's workers read assignments"
  on public.visit_workers for select to authenticated
  using (
    private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[])
    or private.is_assigned_worker(visit_id)
  );

create policy "staff assign workers"
  on public.visit_workers for insert to authenticated
  with check (private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[]));

create policy "staff unassign workers"
  on public.visit_workers for delete to authenticated
  using (private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[]));
