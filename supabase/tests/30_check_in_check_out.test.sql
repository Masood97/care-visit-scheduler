-- Rules 7 and 8: check_in and check_out, called as the signed-in worker.
begin;
create extension if not exists pgtap with schema extensions;

select plan(18);

-- Fixtures: client's home at 51.5000, -0.1200. 0.0045 degrees of latitude is about 500 m,
-- 0.00045 is about 50 m.
insert into auth.users (id, email) values
  ('c0000000-0000-0000-0000-000000000001', 'w1@test.example'),
  ('c0000000-0000-0000-0000-000000000002', 'w2@test.example');

insert into public.organizations (id, name, time_zone) values ('cc000000-0000-0000-0000-000000000000', 'Org C', 'Europe/London');

insert into public.organization_members (organization_id, user_id, role, full_name) values
  ('cc000000-0000-0000-0000-000000000000', 'c0000000-0000-0000-0000-000000000001', 'worker', 'Worker 1'),
  ('cc000000-0000-0000-0000-000000000000', 'c0000000-0000-0000-0000-000000000002', 'worker', 'Worker 2');

insert into public.clients (id, organization_id, full_name, address, latitude, longitude) values
  ('cc100000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000000', 'Client C', '1 C St', 51.5000, -0.1200);

insert into public.visits (id, organization_id, client_id, worker_id, starts_at, ends_at) values
  -- open now: starts in 10 minutes (inside the 30-minute early window)
  ('cd000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000000', 'cc100000-0000-0000-0000-000000000001',
   'c0000000-0000-0000-0000-000000000001', now() + interval '10 minutes', now() + interval '70 minutes'),
  -- too early: starts in 2 hours
  ('cd000000-0000-0000-0000-000000000002', 'cc000000-0000-0000-0000-000000000000', 'cc100000-0000-0000-0000-000000000001',
   'c0000000-0000-0000-0000-000000000001', now() + interval '2 hours', now() + interval '3 hours'),
  -- too late: ended 10 minutes ago
  ('cd000000-0000-0000-0000-000000000003', 'cc000000-0000-0000-0000-000000000000', 'cc100000-0000-0000-0000-000000000001',
   'c0000000-0000-0000-0000-000000000001', now() - interval '70 minutes', now() - interval '10 minutes');

set local role authenticated;

-- Worker 2 tries worker 1's visit ------------------------------------------------------
set local request.jwt.claims = '{"sub": "c0000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select throws_ok(
  $$ select public.check_in('cd000000-0000-0000-0000-000000000001', 51.5000, -0.1200) $$,
  'CV010', null,
  'rule 7: only the assigned worker can check in'
);

-- Worker 1 ----------------------------------------------------------------------------
set local request.jwt.claims = '{"sub": "c0000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select throws_ok(
  $$ select public.check_in('cd000000-0000-0000-0000-000000000001', 51.5045, -0.1200) $$,
  'CV014', null,
  'rule 7: a check-in from 500 m away is rejected'
);

select throws_like(
  $$ select public.check_in('cd000000-0000-0000-0000-000000000001', 51.5045, -0.1200) $$,
  'You are 500 m from the client''s home%',
  'rule 7: the too-far error tells the worker how far away they are'
);

select throws_ok(
  $$ select public.check_in('cd000000-0000-0000-0000-000000000002', 51.5000, -0.1200) $$,
  'CV012', null,
  'rule 7: check-in more than 30 minutes before the start is rejected'
);

select throws_ok(
  $$ select public.check_in('cd000000-0000-0000-0000-000000000003', 51.5000, -0.1200) $$,
  'CV013', null,
  'rule 7: check-in after the scheduled end is rejected'
);

select throws_ok(
  $$ select public.check_in('cd000000-0000-0000-0000-000000000001', null, -0.1200) $$,
  'CV015', null,
  'rule 7: a check-in without a valid location is rejected'
);

select throws_ok(
  $$ select public.check_out('cd000000-0000-0000-0000-000000000001', 51.5000, -0.1200) $$,
  'CV020', null,
  'rule 8: you cannot check out before checking in'
);

select lives_ok(
  $$ select public.check_in('cd000000-0000-0000-0000-000000000001', 51.50045, -0.1200) $$,
  'rule 7: the assigned worker checks in from 50 m away, inside the window'
);

select is(
  (select status::text from public.visits where id = 'cd000000-0000-0000-0000-000000000001'), 'in_progress',
  'rule 7: check-in sets the visit to in_progress'
);

select ok(
  (select distance_m between 45 and 55 from public.visit_events
   where visit_id = 'cd000000-0000-0000-0000-000000000001' and event_type = 'check_in'),
  'rule 7: the check-in event records the distance from the client''s home (~50 m)'
);

select throws_ok(
  $$ select public.check_in('cd000000-0000-0000-0000-000000000001', 51.5000, -0.1200) $$,
  'CV011', null,
  'rule 7: a visit cannot be checked in to twice'
);

-- Worker 2 tries to check out of worker 1's visit
set local request.jwt.claims = '{"sub": "c0000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select throws_ok(
  $$ select public.check_out('cd000000-0000-0000-0000-000000000001', 51.5000, -0.1200) $$,
  'CV020', null,
  'rule 8: only the worker who checked in can check out'
);

set local request.jwt.claims = '{"sub": "c0000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$ select public.check_out('cd000000-0000-0000-0000-000000000001', 51.5003, -0.1201) $$,
  'rule 8: the worker who checked in checks out'
);

select is(
  (select status::text from public.visits where id = 'cd000000-0000-0000-0000-000000000001'), 'completed',
  'rule 8: check-out sets the visit to completed'
);

select is(
  (select count(*)::int from public.visit_events where visit_id = 'cd000000-0000-0000-0000-000000000001'), 2,
  'rules 7-8: one check-in and one check-out event were recorded'
);

select throws_ok(
  $$ select public.check_out('cd000000-0000-0000-0000-000000000001', 51.5000, -0.1200) $$,
  'CV021', null,
  'rule 8: a completed visit cannot be checked out of again'
);

reset role;
update public.visits set status = 'cancelled' where id = 'cd000000-0000-0000-0000-000000000002';
set local role authenticated;

select throws_ok(
  $$ select public.check_in('cd000000-0000-0000-0000-000000000002', 51.5000, -0.1200) $$,
  'CV011', null,
  'rule 7: a cancelled visit cannot be checked in to'
);

select throws_ok(
  $$ select public.check_in('00000000-0000-0000-0000-00000000dead', 51.5000, -0.1200) $$,
  'CV010', null,
  'rule 7: an unknown visit id gives the same error as someone else''s visit (no id probing)'
);

select * from finish();
rollback;
