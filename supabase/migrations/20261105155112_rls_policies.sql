-- Row-level security policies (rules 1 and 2).
--
--   * Tenant isolation: every policy is scoped to organizations the current user belongs to.
--   * Owners and coordinators manage clients and visits in their organization.
--   * Workers read only their own visits and the clients on those visits; they change a
--     visit only through check_in / check_out (there is no worker UPDATE policy).
--   * Only owners manage members.
--   * visit_events are written only by the check-in/out functions; audit_log only by triggers.
-- All policies target the `authenticated` role; `anon` has no privileges at all.

-- organizations ---------------------------------------------------------------
create policy "members read their organizations"
  on public.organizations for select to authenticated
  using (private.is_member(id));

-- organization_members ----------------------------------------------------------
create policy "members read colleagues"
  on public.organization_members for select to authenticated
  using (private.is_member(organization_id));

create policy "owners add members"
  on public.organization_members for insert to authenticated
  with check (private.has_role(organization_id, array['owner']::public.member_role[]));

create policy "owners update members"
  on public.organization_members for update to authenticated
  using (private.has_role(organization_id, array['owner']::public.member_role[]))
  with check (private.has_role(organization_id, array['owner']::public.member_role[]));

create policy "owners remove members"
  on public.organization_members for delete to authenticated
  using (private.has_role(organization_id, array['owner']::public.member_role[]));

-- clients -----------------------------------------------------------------------
create policy "staff read clients, workers read their visits' clients"
  on public.clients for select to authenticated
  using (
    private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[])
    or private.is_worker_of_client(id)
  );

create policy "staff add clients"
  on public.clients for insert to authenticated
  with check (private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[]));

create policy "staff update clients"
  on public.clients for update to authenticated
  using (private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[]))
  with check (private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[]));

create policy "staff delete clients"
  on public.clients for delete to authenticated
  using (private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[]));

-- visits ------------------------------------------------------------------------
create policy "staff read visits, workers read their own"
  on public.visits for select to authenticated
  using (
    private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[])
    or worker_id = (select auth.uid())
  );

create policy "staff book visits"
  on public.visits for insert to authenticated
  with check (private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[]));

create policy "staff update visits"
  on public.visits for update to authenticated
  using (private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[]))
  with check (private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[]));

create policy "staff delete visits"
  on public.visits for delete to authenticated
  using (private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[]));

-- visit_events (insert only through check_in / check_out) ------------------------
create policy "staff read events, workers read their own"
  on public.visit_events for select to authenticated
  using (
    private.has_role(organization_id, array['owner', 'coordinator']::public.member_role[])
    or worker_id = (select auth.uid())
  );

revoke insert, update, delete on table public.visit_events from authenticated;

-- audit_log (written only by triggers; append-only guards in the audit_trail migration) --
create policy "owners read the audit log"
  on public.audit_log for select to authenticated
  using (private.has_role(organization_id, array['owner']::public.member_role[]));

revoke insert, update, delete on table public.audit_log from authenticated;
