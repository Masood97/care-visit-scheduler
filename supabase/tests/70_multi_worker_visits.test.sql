-- Part B (v1.1.0): visits with one or two workers.
begin;
create extension if not exists pgtap with schema extensions;

select plan(20);

insert into auth.users (id, email) values
  ('70000000-0000-0000-0000-0000000000c1', 'coord-p@test.example'),
  ('70000000-0000-0000-0000-0000000000a1', 'w1-p@test.example'),
  ('70000000-0000-0000-0000-0000000000a2', 'w2-p@test.example'),
  ('70000000-0000-0000-0000-0000000000a3', 'w3-p@test.example');

insert into public.organizations (id, name, time_zone) values ('77000000-0000-0000-0000-000000000000', 'Org P', 'UTC');

insert into public.organization_members (organization_id, user_id, role, full_name) values
  ('77000000-0000-0000-0000-000000000000', '70000000-0000-0000-0000-0000000000c1', 'coordinator', 'Coord P'),
  ('77000000-0000-0000-0000-000000000000', '70000000-0000-0000-0000-0000000000a1', 'worker', 'Worker P1'),
  ('77000000-0000-0000-0000-000000000000', '70000000-0000-0000-0000-0000000000a2', 'worker', 'Worker P2'),
  ('77000000-0000-0000-0000-000000000000', '70000000-0000-0000-0000-0000000000a3', 'worker', 'Worker P3');

insert into public.clients (id, organization_id, full_name, address, latitude, longitude) values
  ('77c00000-0000-0000-0000-000000000001', '77000000-0000-0000-0000-000000000000', 'Lift Client', '1 P St', 51.5000, -0.1200);

-- Coordinator books a 2:1 visit that is open for check-in now ----------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub": "70000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

select lives_ok(
  $$ insert into ids values ('lift', public.book_visit(
       '77000000-0000-0000-0000-000000000000', '77c00000-0000-0000-0000-000000000001',
       array['70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-0000000000a2']::uuid[],
       now() + interval '10 minutes', now() + interval '70 minutes', 'Safe lift')) $$,
  'Part B 1: a coordinator books a visit with two workers'
);

select is(
  (select count(*)::int from public.visit_workers where visit_id = (select id from ids where name = 'lift')), 2,
  'Part B 1: the visit has two assigned workers'
);

select throws_ok(
  $$ insert into public.visit_workers (organization_id, visit_id, worker_id)
     values ('77000000-0000-0000-0000-000000000000', (select id from ids where name = 'lift'), '70000000-0000-0000-0000-0000000000a3') $$,
  'CV050', null,
  'Part B 1: a third worker is rejected'
);

select throws_ok(
  $$ select public.book_visit('77000000-0000-0000-0000-000000000000', '77c00000-0000-0000-0000-000000000001',
       array['70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-0000000000a2', '70000000-0000-0000-0000-0000000000a3']::uuid[],
       '2030-06-03 09:00+00', '2030-06-03 10:00+00') $$,
  'CV050', null,
  'Part B 1: booking with three workers is rejected'
);

select throws_ok(
  $$ select public.book_visit('77000000-0000-0000-0000-000000000000', '77c00000-0000-0000-0000-000000000001',
       '{}'::uuid[], '2030-06-03 09:00+00', '2030-06-03 10:00+00') $$,
  'CV050', null,
  'Part B 1: booking with no worker is rejected'
);

select throws_ok(
  $$ select public.book_visit('77000000-0000-0000-0000-000000000000', '77c00000-0000-0000-0000-000000000001',
       array['70000000-0000-0000-0000-0000000000a1', '70000000-0000-0000-0000-0000000000a1']::uuid[],
       '2030-06-03 09:00+00', '2030-06-03 10:00+00') $$,
  'CV053', null,
  'Part B 1: the same worker twice is rejected'
);

-- Part B 3: worker 2 is the SECOND worker on the lift visit; booking them elsewhere at that time fails.
select throws_like(
  $$ select public.book_visit('77000000-0000-0000-0000-000000000000', '77c00000-0000-0000-0000-000000000001',
       array['70000000-0000-0000-0000-0000000000a3', '70000000-0000-0000-0000-0000000000a2']::uuid[],
       now() + interval '20 minutes', now() + interval '50 minutes') $$,
  '%visit_workers_no_overlap%',
  'Part B 3: double booking is rejected for a worker across all their assignments'
);

-- Part B 1: never zero workers (the deferred check, forced to run now).
reset role;
set constraints all immediate;
select throws_ok(
  $$ delete from public.visit_workers where visit_id = (select id from ids where name = 'lift') $$,
  'CV051', null,
  'Part B 1: a visit cannot be left without workers'
);
set constraints all deferred;

-- Part B 5: a worker sees a visit if they are any of its workers -----------------------
set local role authenticated;
set local request.jwt.claims = '{"sub": "70000000-0000-0000-0000-0000000000a2", "role": "authenticated"}';

select is(
  (select count(*)::int from public.visits where id = (select id from ids where name = 'lift')), 1,
  'Part B 5: the second worker sees the visit'
);

select is(
  (select count(*)::int from public.visit_workers where visit_id = (select id from ids where name = 'lift')), 2,
  'Part B 6: the second worker sees both workers on the visit'
);

set local request.jwt.claims = '{"sub": "70000000-0000-0000-0000-0000000000a3", "role": "authenticated"}';
select is_empty(
  $$ select 1 from public.visits where id = (select id from ids where name = 'lift') $$,
  'Part B 5: a worker not on the visit does not see it'
);

-- Part B 4: separate check-ins and check-outs ---------------------------------------------
set local request.jwt.claims = '{"sub": "70000000-0000-0000-0000-0000000000a1", "role": "authenticated"}';
select public.check_in((select id from ids where name = 'lift'), 51.5000, -0.1200);
select is(
  (select status::text from public.visits where id = (select id from ids where name = 'lift')), 'in_progress',
  'Part B 4: the first check-in sets the visit in_progress'
);

set local request.jwt.claims = '{"sub": "70000000-0000-0000-0000-0000000000a2", "role": "authenticated"}';
select lives_ok(
  $$ select public.check_in((select id from ids where name = 'lift'), 51.5001, -0.1200) $$,
  'Part B 4: the second worker checks in separately'
);

set local request.jwt.claims = '{"sub": "70000000-0000-0000-0000-0000000000a1", "role": "authenticated"}';
select public.check_out((select id from ids where name = 'lift'), 51.5000, -0.1200);
select is(
  (select status::text from public.visits where id = (select id from ids where name = 'lift')), 'in_progress',
  'Part B 4: the visit stays in_progress while one worker is still there'
);

set local request.jwt.claims = '{"sub": "70000000-0000-0000-0000-0000000000a2", "role": "authenticated"}';
select public.check_out((select id from ids where name = 'lift'), 51.5000, -0.1200);
select is(
  (select status::text from public.visits where id = (select id from ids where name = 'lift')), 'completed',
  'Part B 4: the last worker''s check-out completes the visit'
);

-- Part B 6: the hours report counts every worker on the visit
set local request.jwt.claims = '{"sub": "70000000-0000-0000-0000-0000000000c1", "role": "authenticated"}';
select is(
  (select count(distinct worker_id)::int from public.worker_weekly_hours
   where organization_id = '77000000-0000-0000-0000-000000000000'),
  2,
  'Part B 6: hours are counted for both workers on the visit'
);

-- Part B 7: the legacy visits.worker_id keeps working --------------------------------------
select lives_ok(
  $$ insert into public.visits (id, organization_id, client_id, worker_id, starts_at, ends_at)
     values ('77d00000-0000-0000-0000-000000000009', '77000000-0000-0000-0000-000000000000',
             '77c00000-0000-0000-0000-000000000001', '70000000-0000-0000-0000-0000000000a3',
             '2030-06-04 09:00+00', '2030-06-04 10:00+00') $$,
  'Part B 7: a legacy insert with only visits.worker_id still works'
);

select results_eq(
  $$ select worker_id from public.visit_workers where visit_id = '77d00000-0000-0000-0000-000000000009' $$,
  $$ values ('70000000-0000-0000-0000-0000000000a3'::uuid) $$,
  'Part B 7: ... and its worker is assigned in visit_workers'
);

update public.visits set worker_id = '70000000-0000-0000-0000-0000000000a1' where id = '77d00000-0000-0000-0000-000000000009';
select results_eq(
  $$ select worker_id from public.visit_workers where visit_id = '77d00000-0000-0000-0000-000000000009' $$,
  $$ values ('70000000-0000-0000-0000-0000000000a1'::uuid) $$,
  'Part B 7: a legacy reassignment through visits.worker_id moves the assignment'
);

-- Removing the primary from a 2:1 visit hands visits.worker_id to the other worker.
insert into public.visit_workers (organization_id, visit_id, worker_id)
values ('77000000-0000-0000-0000-000000000000', '77d00000-0000-0000-0000-000000000009', '70000000-0000-0000-0000-0000000000a2');
delete from public.visit_workers
where visit_id = '77d00000-0000-0000-0000-000000000009' and worker_id = '70000000-0000-0000-0000-0000000000a1';
select is(
  (select worker_id from public.visits where id = '77d00000-0000-0000-0000-000000000009'),
  '70000000-0000-0000-0000-0000000000a2'::uuid,
  'Part B 7: removing the primary worker makes the remaining worker primary in visits.worker_id'
);

select * from finish();
rollback;
