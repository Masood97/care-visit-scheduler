-- Constraint and trigger rules on visits (rules 3, 4, 5, 6) and tenant consistency.
-- Runs as the database owner: these rules hold for every caller, RLS or not.
-- Self-contained fixtures inside a transaction that is rolled back.
begin;
create extension if not exists pgtap with schema extensions;

select plan(29);

-- Fixtures ----------------------------------------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'coord-a@test.example'),
  ('00000000-0000-0000-0000-0000000000a2', 'worker-a@test.example'),
  ('00000000-0000-0000-0000-0000000000b2', 'worker-b@test.example');

insert into public.organizations (id, name, time_zone) values
  ('10000000-0000-0000-0000-00000000000a', 'Test Org A', 'Australia/Sydney'),
  ('10000000-0000-0000-0000-00000000000b', 'Test Org B', 'Europe/London');

insert into public.organization_members (organization_id, user_id, role, full_name) values
  ('10000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a1', 'coordinator', 'Coord A'),
  ('10000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000a2', 'worker', 'Worker A'),
  ('10000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000000b2', 'worker', 'Worker B');

insert into public.clients (id, organization_id, full_name, address, latitude, longitude, status) values
  ('20000000-0000-0000-0000-0000000000a1', '10000000-0000-0000-0000-00000000000a', 'Client A1', '1 Test St', -33.86, 151.20, 'active'),
  ('20000000-0000-0000-0000-0000000000a2', '10000000-0000-0000-0000-00000000000a', 'Client A2', '2 Test St', -33.87, 151.21, 'archived'),
  ('20000000-0000-0000-0000-0000000000b1', '10000000-0000-0000-0000-00000000000b', 'Client B1', '3 Test St',  53.80,  -1.55, 'active');

-- Worker A: 09:00-11:00 on a fixed future day.
insert into public.visits (id, organization_id, client_id, worker_id, starts_at, ends_at) values
  ('30000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-00000000000a',
   '20000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2',
   '2030-01-07 09:00+00', '2030-01-07 11:00+00');

-- Inserts a check-in or check-out event for worker A (the trigger requires them before status moves).
create function pg_temp.add_event(p_visit uuid, p_type public.visit_event_type) returns void language sql as $$
  insert into public.visit_events (organization_id, visit_id, worker_id, event_type, latitude, longitude, distance_m)
  values ('10000000-0000-0000-0000-00000000000a', p_visit, '00000000-0000-0000-0000-0000000000a2', p_type, -33.86, 151.20, 5);
$$;

-- Rule 3: no double booking -----------------------------------------------
select throws_like(
  $$ insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
     values ('10000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-0000000000a1',
             '00000000-0000-0000-0000-0000000000a2', '2030-01-07 10:00+00', '2030-01-07 12:00+00') $$,
  '%visits_no_overlap%',
  'rule 3: an overlapping visit for the same worker is rejected by visits_no_overlap'
);

select lives_ok(
  $$ insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
     values ('10000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-0000000000a1',
             '00000000-0000-0000-0000-0000000000a2', '2030-01-07 11:00+00', '2030-01-07 12:00+00') $$,
  'rule 3: a back-to-back visit (starts when the previous ends) is allowed'
);

select throws_like(
  $$ update public.visits set starts_at = '2030-01-07 10:30+00', ends_at = '2030-01-07 11:30+00'
     where starts_at = '2030-01-07 11:00+00' $$,
  '%visits_no_overlap%',
  'rule 3: moving a visit onto another of the same worker''s visits is rejected'
);

select lives_ok(
  $$ update public.visits set status = 'cancelled' where id = '30000000-0000-0000-0000-000000000001' $$,
  'rule 6: scheduled -> cancelled is allowed'
);

select lives_ok(
  $$ insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
     values ('10000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-0000000000a1',
             '00000000-0000-0000-0000-0000000000a2', '2030-01-07 09:30+00', '2030-01-07 10:30+00') $$,
  'rule 3: a cancelled visit does not block the slot'
);

-- Rule 4: valid times -------------------------------------------------------
select throws_like(
  $$ insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
     values ('10000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-0000000000a1',
             '00000000-0000-0000-0000-0000000000a2', '2030-01-08 10:00+00', '2030-01-08 09:00+00') $$,
  '%visits_ends_after_start%',
  'rule 4: a visit that ends before it starts is rejected'
);

select throws_like(
  $$ insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
     values ('10000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-0000000000a1',
             '00000000-0000-0000-0000-0000000000a2', '2030-01-08 10:00+00', '2030-01-08 10:00+00') $$,
  '%visits_ends_after_start%',
  'rule 4: a zero-length visit is rejected'
);

select throws_like(
  $$ insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
     values ('10000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-0000000000a1',
             '00000000-0000-0000-0000-0000000000a2', '2030-01-08 06:00+00', '2030-01-08 18:01+00') $$,
  '%visits_max_12_hours%',
  'rule 4: a visit longer than 12 hours is rejected'
);

select lives_ok(
  $$ insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
     values ('10000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-0000000000a1',
             '00000000-0000-0000-0000-0000000000a2', '2030-01-09 06:00+00', '2030-01-09 18:00+00') $$,
  'rule 4: a visit of exactly 12 hours is allowed'
);

-- Rule 5: archived clients and deletes --------------------------------------
select throws_ok(
  $$ insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
     values ('10000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-0000000000a2',
             '00000000-0000-0000-0000-0000000000a2', '2030-01-10 09:00+00', '2030-01-10 10:00+00') $$,
  'CV001', null,
  'rule 5: an archived client cannot get a new visit'
);

insert into public.visits (id, organization_id, client_id, worker_id, starts_at, ends_at) values
  ('30000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-00000000000a',
   '20000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2',
   '2030-01-14 09:00+00', '2030-01-14 10:00+00');

select throws_ok(
  $$ update public.visits set client_id = '20000000-0000-0000-0000-0000000000a2'
     where id = '30000000-0000-0000-0000-000000000003' $$,
  'CV001', null,
  'rule 5: a visit cannot be moved to an archived client'
);

select throws_like(
  $$ delete from public.clients where id = '20000000-0000-0000-0000-0000000000a1' $$,
  '%visits_client_fk%',
  'rule 5: a client with visits cannot be deleted'
);

select lives_ok(
  $$ update public.clients set status = 'archived' where id = '20000000-0000-0000-0000-0000000000a1' $$,
  'rule 5: a client with visits can be archived instead'
);
update public.clients set status = 'active' where id = '20000000-0000-0000-0000-0000000000a1';

-- Rule 6: status flow -------------------------------------------------------
select throws_ok(
  $$ insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at, status)
     values ('10000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-0000000000a1',
             '00000000-0000-0000-0000-0000000000a2', '2030-01-11 09:00+00', '2030-01-11 10:00+00', 'completed') $$,
  'CV004', null,
  'rule 6: a new visit must start as scheduled'
);

insert into public.visits (id, organization_id, client_id, worker_id, starts_at, ends_at) values
  ('30000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-00000000000a',
   '20000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2',
   '2030-01-12 09:00+00', '2030-01-12 10:00+00');

select throws_ok(
  $$ update public.visits set status = 'completed' where id = '30000000-0000-0000-0000-000000000002' $$,
  'CV003', null,
  'rule 6: scheduled -> completed (skipping in_progress) is rejected'
);

select throws_ok(
  $$ update public.visits set status = 'in_progress' where id = '30000000-0000-0000-0000-000000000002' $$,
  'CV006', null,
  'rule 6: a visit cannot become in_progress without a check-in event'
);

select pg_temp.add_event('30000000-0000-0000-0000-000000000002', 'check_in');
select lives_ok(
  $$ update public.visits set status = 'in_progress' where id = '30000000-0000-0000-0000-000000000002' $$,
  'rule 6: scheduled -> in_progress is allowed after check-in'
);

select throws_ok(
  $$ update public.visits set status = 'cancelled' where id = '30000000-0000-0000-0000-000000000002' $$,
  'CV003', null,
  'rule 6: in_progress -> cancelled is rejected'
);

select throws_ok(
  $$ update public.visits set status = 'completed' where id = '30000000-0000-0000-0000-000000000002' $$,
  'CV007', null,
  'rule 6: a visit cannot complete without a check-out event'
);

select pg_temp.add_event('30000000-0000-0000-0000-000000000002', 'check_out');
select lives_ok(
  $$ update public.visits set status = 'completed' where id = '30000000-0000-0000-0000-000000000002' $$,
  'rule 6: in_progress -> completed is allowed after check-out'
);

select throws_ok(
  $$ update public.visits set status = 'scheduled' where id = '30000000-0000-0000-0000-000000000002' $$,
  'CV003', null,
  'rule 6: completed -> scheduled is rejected'
);

select throws_ok(
  $$ update public.visits set status = 'cancelled' where id = '30000000-0000-0000-0000-000000000002' $$,
  'CV003', null,
  'rule 6: completed -> cancelled is rejected'
);

select throws_ok(
  $$ update public.visits set status = 'scheduled' where id = '30000000-0000-0000-0000-000000000001' $$,
  'CV003', null,
  'rule 6: cancelled -> scheduled is rejected'
);

select throws_ok(
  $$ update public.visits set ends_at = '2030-01-12 11:00+00' where id = '30000000-0000-0000-0000-000000000002' $$,
  'CV005', null,
  'a completed visit cannot be re-timed'
);

-- Tenant consistency and roles ---------------------------------------------
select throws_like(
  $$ insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
     values ('10000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-0000000000b1',
             '00000000-0000-0000-0000-0000000000a2', '2030-01-13 09:00+00', '2030-01-13 10:00+00') $$,
  '%visits_client_fk%',
  'a visit cannot use a client from another organization'
);

-- The BEFORE trigger rejects this first (CV002: not a worker of this org);
-- visits_worker_fk would reject it too if the trigger were ever removed.
select throws_ok(
  $$ insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
     values ('10000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-0000000000a1',
             '00000000-0000-0000-0000-0000000000b2', '2030-01-13 09:00+00', '2030-01-13 10:00+00') $$,
  'CV002', null,
  'a visit cannot be assigned to a worker from another organization'
);

select throws_ok(
  $$ insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
     values ('10000000-0000-0000-0000-00000000000a', '20000000-0000-0000-0000-0000000000a1',
             '00000000-0000-0000-0000-0000000000a1', '2030-01-13 09:00+00', '2030-01-13 10:00+00') $$,
  'CV002', null,
  'a visit can only be assigned to a member with the worker role'
);

select throws_like(
  $$ insert into public.visit_events (organization_id, visit_id, worker_id, event_type, latitude, longitude, distance_m)
     values ('10000000-0000-0000-0000-00000000000b', '30000000-0000-0000-0000-000000000003',
             '00000000-0000-0000-0000-0000000000b2', 'check_in', 53.80, -1.55, 5) $$,
  '%visit_events_visit_fk%',
  'a visit event must belong to the same organization as its visit'
);

select throws_like(
  $$ insert into public.organizations (name, time_zone) values ('Bad TZ Org', 'AEST') $$,
  '%organizations_time_zone_valid%',
  'an organization needs an IANA time zone (abbreviations are rejected)'
);

select * from finish();
rollback;
