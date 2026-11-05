-- EXPLAIN ANALYZE evidence for the indexes behind the three most common queries.
-- Generates realistic volume inside a transaction and ROLLS BACK at the end, so the
-- database is left exactly as it was. Local only:
--   docker exec -i supabase_db_care-visit-scheduler psql -U postgres -X < scripts/explain-indexes.sql
--
-- Volume: 10 organizations x (20 workers + 50 clients) and 20,000 visits
-- (100 per worker, one every 6 hours, from 12 days ago to 13 days ahead), check-in/out
-- events for past visits, and 100 more small agencies (20 members each) so
-- organization_members is realistic in size (~2,200 rows).
\set ON_ERROR_STOP on
\pset pager off
begin;

do $$
declare
  o int; w int;
  v_org uuid; v_user uuid;
begin
  for o in 1..10 loop
    insert into public.organizations (name, time_zone) values ('Perf Org ' || o, 'Australia/Sydney') returning id into v_org;
    for w in 1..20 loop
      insert into auth.users (id, email) values (gen_random_uuid(), format('perf-%s-%s@test.example', o, w)) returning id into v_user;
      insert into public.organization_members (organization_id, user_id, role, full_name)
      values (v_org, v_user, 'worker', format('Worker %s-%s', o, w));
    end loop;
    insert into public.clients (organization_id, full_name, address, latitude, longitude)
    select v_org, 'Client ' || o || '-' || c, c || ' Perf Street', -33.86 + c * 0.001, 151.2 + c * 0.001
    from generate_series(1, 50) c;
  end loop;

  -- Other tenants: members only.
  for o in 1..100 loop
    insert into public.organizations (name, time_zone) values ('Other Org ' || o, 'Europe/London') returning id into v_org;
    for w in 1..20 loop
      insert into auth.users (id, email) values (gen_random_uuid(), format('other-%s-%s@test.example', o, w)) returning id into v_user;
      insert into public.organization_members (organization_id, user_id, role, full_name)
      values (v_org, v_user, case when w = 1 then 'owner' when w = 2 then 'coordinator' else 'worker' end::public.member_role,
              format('Member %s-%s', o, w));
    end loop;
  end loop;
end;
$$;

-- 100 visits per worker, 2 hours long, every 6 hours from 12 days ago.
insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
select m.organization_id,
       (select c.id from public.clients c where c.organization_id = m.organization_id order by c.id offset (n % 50) limit 1),
       m.user_id,
       date_trunc('hour', now()) - interval '12 days' + n * interval '6 hours',
       date_trunc('hour', now()) - interval '12 days' + n * interval '6 hours' + interval '2 hours'
from public.organization_members m
cross join generate_series(0, 99) n
where m.full_name like 'Worker %-%';

-- Check-in/out events for the visits that are already over (for the hours report).
insert into public.visit_events (organization_id, visit_id, worker_id, event_type, occurred_at, latitude, longitude, distance_m)
select v.organization_id, v.id, v.worker_id, e.t, case e.t when 'check_in' then v.starts_at else v.ends_at end, -33.86, 151.2, 10
from public.visits v
cross join (values ('check_in'::public.visit_event_type), ('check_out')) e(t)
where v.ends_at < now() and v.notes is null and exists (select 1 from public.organizations o where o.id = v.organization_id and o.name like 'Perf Org %');

analyze public.organization_members, public.clients, public.visits, public.visit_workers, public.visit_events;

select (select count(*) from public.visits) as visits,
       (select count(*) from public.visit_workers) as assignments,
       (select count(*) from public.visit_events) as events,
       (select count(*) from public.organization_members) as members;

-- Pick one organization, one of its workers, and the current week (Monday 00:00 Sydney).
select o.id as org_id, (select m.user_id from public.organization_members m where m.organization_id = o.id limit 1) as worker_id
from public.organizations o where o.name = 'Perf Org 3' \gset
-- A coordinator of another tenant, for the RLS membership check.
select m.organization_id as member_org_id, m.user_id as member_user_id
from public.organization_members m join public.organizations o on o.id = m.organization_id
where o.name = 'Other Org 42' and m.role = 'coordinator' \gset
select (date_trunc('week', now() at time zone 'Australia/Sydney') at time zone 'Australia/Sydney') as week_start \gset

\echo
\echo '=== Query 1: coordinator week view (visits of one organization in a week)'
explain (analyze, buffers, costs off, timing on, summary on)
select id, client_id, worker_id, starts_at, ends_at, status
from public.visits
where organization_id = :'org_id'
  and starts_at >= :'week_start'::timestamptz
  and starts_at <  :'week_start'::timestamptz + interval '7 days'
order by starts_at;

\echo
\echo '=== Query 2: a worker''s visits in a date range (My visits; v1.1.0 assignments)'
explain (analyze, buffers, costs off, timing on, summary on)
select visit_id, starts_at, ends_at, visit_status
from public.visit_workers
where worker_id = :'worker_id'
  and starts_at >= now() - interval '1 day'
  and starts_at <  now() + interval '8 days'
order by starts_at;

\echo
\echo '=== Query 3: membership check run by every RLS policy (private.has_role / is_member)'
explain (analyze, buffers, costs off, timing on, summary on)
select exists (
  select 1 from public.organization_members m
  where m.organization_id = :'member_org_id' and m.user_id = :'member_user_id' and m.role = any (array['owner', 'coordinator']::public.member_role[])
);

rollback;
