-- Rule 10: completed hours per worker per week, weeks counted in the organization's
-- time zone; staff see the whole organization, workers only themselves.
begin;
create extension if not exists pgtap with schema extensions;

select plan(5);

insert into auth.users (id, email) values
  ('f0000000-0000-0000-0000-000000000001', 'coord-f@test.example'),
  ('f0000000-0000-0000-0000-000000000002', 'w1-f@test.example'),
  ('f0000000-0000-0000-0000-000000000003', 'w2-f@test.example');

insert into public.organizations (id, name, time_zone) values ('ff000000-0000-0000-0000-000000000000', 'Org F', 'Australia/Sydney');

insert into public.organization_members (organization_id, user_id, role, full_name) values
  ('ff000000-0000-0000-0000-000000000000', 'f0000000-0000-0000-0000-000000000001', 'coordinator', 'Coord F'),
  ('ff000000-0000-0000-0000-000000000000', 'f0000000-0000-0000-0000-000000000002', 'worker', 'Worker F1'),
  ('ff000000-0000-0000-0000-000000000000', 'f0000000-0000-0000-0000-000000000003', 'worker', 'Worker F2');

insert into public.clients (id, organization_id, full_name, address, latitude, longitude) values
  ('fc000000-0000-0000-0000-000000000001', 'ff000000-0000-0000-0000-000000000000', 'Client F', '1 F St', -33.86, 151.20);

-- Builds a completed visit with real events (as the database owner, bypassing the check-in time window).
create function pg_temp.completed_visit(p_worker uuid, p_check_in timestamptz, p_check_out timestamptz)
returns void language plpgsql as $$
declare v uuid;
begin
  insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
  values ('ff000000-0000-0000-0000-000000000000', 'fc000000-0000-0000-0000-000000000001', p_worker, p_check_in, p_check_out)
  returning id into v;
  insert into public.visit_events (organization_id, visit_id, worker_id, event_type, occurred_at, latitude, longitude, distance_m)
  values ('ff000000-0000-0000-0000-000000000000', v, p_worker, 'check_in', p_check_in, -33.86, 151.20, 3);
  update public.visits set status = 'in_progress' where id = v;
  insert into public.visit_events (organization_id, visit_id, worker_id, event_type, occurred_at, latitude, longitude, distance_m)
  values ('ff000000-0000-0000-0000-000000000000', v, p_worker, 'check_out', p_check_out, -33.86, 151.20, 3);
  update public.visits set status = 'completed' where id = v;
end;
$$;

-- Worker 1: Monday 7 Jan 2030 00:30 in Sydney is still Sunday 6 Jan 13:30 in UTC.
-- Counted in UTC it would land in the previous week; in Sydney time it is week of 7 Jan.
select pg_temp.completed_visit('f0000000-0000-0000-0000-000000000002', '2030-01-07 00:30 Australia/Sydney', '2030-01-07 02:00 Australia/Sydney');
select pg_temp.completed_visit('f0000000-0000-0000-0000-000000000002', '2030-01-09 09:00 Australia/Sydney', '2030-01-09 11:00 Australia/Sydney');
-- Worker 1, previous local week (Sunday 6 Jan 23:00 Sydney)
select pg_temp.completed_visit('f0000000-0000-0000-0000-000000000002', '2030-01-06 23:00 Australia/Sydney', '2030-01-06 23:45 Australia/Sydney');
-- Worker 2
select pg_temp.completed_visit('f0000000-0000-0000-0000-000000000003', '2030-01-08 10:00 Australia/Sydney', '2030-01-08 13:00 Australia/Sydney');
-- A scheduled (not completed) visit for worker 2 counts nothing.
insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
values ('ff000000-0000-0000-0000-000000000000', 'fc000000-0000-0000-0000-000000000001',
        'f0000000-0000-0000-0000-000000000003', '2030-01-10 10:00 Australia/Sydney', '2030-01-10 12:00 Australia/Sydney');

set local role authenticated;

-- Coordinator: whole organization -------------------------------------------------------
set local request.jwt.claims = '{"sub": "f0000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select results_eq(
  $$ select worker_name, week_start, visits_completed, hours
     from public.worker_weekly_hours order by worker_name, week_start $$,
  $$ values ('Worker F1', date '2029-12-31', 1, 0.75::numeric),
            ('Worker F1', date '2030-01-07', 2, 3.50::numeric),
            ('Worker F2', date '2030-01-07', 1, 3.00::numeric) $$,
  'rule 10: the coordinator sees completed hours for every worker, per local week'
);

select is(
  (select week_start from public.worker_weekly_hours
   where worker_name = 'Worker F1' and visits_completed = 2),
  date '2030-01-07',
  'rule 10: a check-in at 00:30 Monday Sydney time counts in that Monday''s week, not the UTC week'
);

-- Worker 1: only their own hours --------------------------------------------------------
set local request.jwt.claims = '{"sub": "f0000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select results_eq(
  $$ select week_start, hours from public.worker_weekly_hours order by week_start $$,
  $$ values (date '2029-12-31', 0.75::numeric), (date '2030-01-07', 3.50::numeric) $$,
  'rule 10: a worker sees only their own hours'
);

select is_empty(
  $$ select 1 from public.worker_weekly_hours where worker_id = 'f0000000-0000-0000-0000-000000000003' $$,
  'rule 10: a worker cannot see another worker''s hours'
);

-- Another organization sees nothing --------------------------------------------------------
reset role;
insert into auth.users (id, email) values ('f0000000-0000-0000-0000-000000000009', 'outsider@test.example');
insert into public.organizations (id, name, time_zone) values ('ff900000-0000-0000-0000-000000000000', 'Org Outsider', 'UTC');
insert into public.organization_members (organization_id, user_id, role, full_name)
values ('ff900000-0000-0000-0000-000000000000', 'f0000000-0000-0000-0000-000000000009', 'owner', 'Outsider');

set local role authenticated;
set local request.jwt.claims = '{"sub": "f0000000-0000-0000-0000-000000000009", "role": "authenticated"}';

select is_empty(
  'select 1 from public.worker_weekly_hours',
  'rule 1: another organization''s owner sees none of these hours'
);

select * from finish();
rollback;
