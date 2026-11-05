-- Fix forward: grant table privileges to the Data API roles explicitly.
--
-- The hosted projects don't auto-grant new tables in `public` to `authenticated` /
-- `service_role` (the local stack did, which hid this). Without these grants every API
-- request failed with "permission denied" before RLS was even evaluated.
--
-- Privileges are the outer gate, RLS policies the inner one. These grants match the
-- policies exactly; anything without a policy (worker UPDATE on visits, writes to
-- visit_events / audit_log) stays impossible for `authenticated` either way.
-- `anon` gets nothing.

-- authenticated: what the RLS policies allow, and nothing more.
grant select                         on table public.organizations        to authenticated;
grant select, insert, update, delete on table public.organization_members to authenticated;
grant select, insert, update, delete on table public.clients              to authenticated;
grant select, insert, update, delete on table public.visits               to authenticated;
grant select                         on table public.visit_events         to authenticated;
grant select                         on table public.audit_log            to authenticated;
grant select                         on table public.worker_weekly_hours  to authenticated;

-- service_role (server-side admin scripts such as scripts/create-demo-accounts.mjs; it
-- bypasses RLS). Still no way to change or forge the audit log, and no TRUNCATE, which
-- would skip the audit triggers.
grant select, insert, update, delete on table public.organizations        to service_role;
grant select, insert, update, delete on table public.organization_members to service_role;
grant select, insert, update, delete on table public.clients              to service_role;
grant select, insert, update, delete on table public.visits               to service_role;
grant select                         on table public.visit_events         to service_role;
grant select                         on table public.audit_log            to service_role;
grant select                         on table public.worker_weekly_hours  to service_role;
revoke references, trigger on all tables in schema public from service_role;
