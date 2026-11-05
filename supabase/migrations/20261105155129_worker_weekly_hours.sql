-- Hours report (rule 10): completed hours per worker per week, weeks counted in the
-- organization's time zone (ISO weeks, starting Monday 00:00 local time).
--
-- Hours are actual worked time: check-out minus check-in for the same worker on the
-- same visit. A visit counts in the week its check-in happened.
--
-- security_invoker = true: the view runs with the caller's privileges, so the RLS on
-- visit_events decides what each person sees. Owners and coordinators see every event
-- in their organization; workers see only their own, so they only get their own hours.

create view public.worker_weekly_hours
with (security_invoker = true)
as
select
  ci.organization_id,
  ci.worker_id,
  m.full_name                                                          as worker_name,
  (date_trunc('week', ci.occurred_at at time zone o.time_zone))::date as week_start,
  count(*)::int                                                        as visits_completed,
  round((sum(extract(epoch from co.occurred_at - ci.occurred_at)) / 3600)::numeric, 2) as hours
from public.visit_events ci
join public.visit_events co
  on co.visit_id = ci.visit_id
 and co.worker_id = ci.worker_id
 and co.event_type = 'check_out'
join public.organizations o
  on o.id = ci.organization_id
join public.organization_members m
  on m.organization_id = ci.organization_id
 and m.user_id = ci.worker_id
where ci.event_type = 'check_in'
group by ci.organization_id, ci.worker_id, m.full_name, week_start;

comment on view public.worker_weekly_hours is 'Rule 10: completed hours per worker per week (weeks start Monday in the organization''s time zone). Visibility follows RLS on visit_events.';
comment on column public.worker_weekly_hours.week_start is 'Monday of the week, as a local date in the organization''s time zone.';
comment on column public.worker_weekly_hours.hours is 'Sum of check-out minus check-in, in hours (2 decimals).';

revoke all on table public.worker_weekly_hours from anon, authenticated;
grant select on table public.worker_weekly_hours to authenticated;
