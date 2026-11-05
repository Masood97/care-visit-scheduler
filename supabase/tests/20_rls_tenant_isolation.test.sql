-- Rules 1 and 2: tenant isolation and roles, tested as real API users.
-- Each block switches to the `authenticated` role with a JWT `sub`, exactly as
-- PostgREST does for a signed-in request, so RLS is in force.
begin;
create extension if not exists pgtap with schema extensions;

select plan(24);

-- Fixtures (as the database owner) -------------------------------------------------
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000001', 'owner-a@test.example'),
  ('a0000000-0000-0000-0000-000000000002', 'coord-a@test.example'),
  ('a0000000-0000-0000-0000-000000000003', 'worker1-a@test.example'),
  ('a0000000-0000-0000-0000-000000000004', 'worker2-a@test.example'),
  ('a0000000-0000-0000-0000-000000000005', 'new-hire@test.example'),
  ('b0000000-0000-0000-0000-000000000001', 'owner-b@test.example'),
  ('b0000000-0000-0000-0000-000000000003', 'worker-b@test.example');

insert into public.organizations (id, name, time_zone) values
  ('aa000000-0000-0000-0000-000000000000', 'Org A', 'Australia/Sydney'),
  ('bb000000-0000-0000-0000-000000000000', 'Org B', 'Europe/London');

insert into public.organization_members (organization_id, user_id, role, full_name) values
  ('aa000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000001', 'owner', 'Owner A'),
  ('aa000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000002', 'coordinator', 'Coord A'),
  ('aa000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000003', 'worker', 'Worker A1'),
  ('aa000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000004', 'worker', 'Worker A2'),
  ('bb000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-000000000001', 'owner', 'Owner B'),
  ('bb000000-0000-0000-0000-000000000000', 'b0000000-0000-0000-0000-000000000003', 'worker', 'Worker B');

insert into public.clients (id, organization_id, full_name, address, latitude, longitude) values
  ('ac000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000000', 'Client A1', '1 A St', -33.86, 151.20),
  ('ac000000-0000-0000-0000-000000000002', 'aa000000-0000-0000-0000-000000000000', 'Client A2', '2 A St', -33.87, 151.21),
  ('ac000000-0000-0000-0000-000000000003', 'aa000000-0000-0000-0000-000000000000', 'Client A3', '3 A St', -33.88, 151.22),
  ('bc000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000000', 'Client B1', '1 B St',  53.80,  -1.55);

insert into public.visits (id, organization_id, client_id, worker_id, starts_at, ends_at) values
  ('ad000000-0000-0000-0000-000000000001', 'aa000000-0000-0000-0000-000000000000', 'ac000000-0000-0000-0000-000000000001',
   'a0000000-0000-0000-0000-000000000003', '2030-02-04 09:00+00', '2030-02-04 10:00+00'),
  ('ad000000-0000-0000-0000-000000000002', 'aa000000-0000-0000-0000-000000000000', 'ac000000-0000-0000-0000-000000000002',
   'a0000000-0000-0000-0000-000000000004', '2030-02-04 09:00+00', '2030-02-04 10:00+00'),
  ('bd000000-0000-0000-0000-000000000001', 'bb000000-0000-0000-0000-000000000000', 'bc000000-0000-0000-0000-000000000001',
   'b0000000-0000-0000-0000-000000000003', '2030-02-04 09:00+00', '2030-02-04 10:00+00');

-- Coordinator of org A ------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select results_eq(
  'select name from public.organizations',
  $$ values ('Org A') $$,
  'rule 1: a coordinator sees only their own organization'
);

select is(
  (select count(*)::int from public.clients), 3,
  'rule 2: a coordinator sees every client of their organization (and none of org B)'
);

select is(
  (select count(*)::int from public.visits), 2,
  'rule 2: a coordinator sees every visit of their organization (and none of org B)'
);

select is_empty(
  $$ select 1 from public.organization_members where organization_id = 'bb000000-0000-0000-0000-000000000000' $$,
  'rule 1: org B''s members are invisible to org A'
);

select throws_ok(
  $$ insert into public.clients (organization_id, full_name, address, latitude, longitude)
     values ('bb000000-0000-0000-0000-000000000000', 'Sneaky', '9 B St', 53.8, -1.5) $$,
  '42501', null,
  'rule 1: a coordinator cannot create a client in another organization'
);

select results_eq(
  $$ with u as (update public.visits set notes = 'hijacked' where organization_id = 'bb000000-0000-0000-0000-000000000000' returning 1)
     select count(*)::int from u $$,
  $$ values (0) $$,
  'rule 1: a coordinator cannot change another organization''s visits'
);

select throws_ok(
  $$ update public.clients set organization_id = 'bb000000-0000-0000-0000-000000000000'
     where id = 'ac000000-0000-0000-0000-000000000003' $$,
  'CV043', null,
  'rule 1: a coordinator cannot move a client into another organization'
);

select lives_ok(
  $$ insert into public.clients (organization_id, full_name, address, latitude, longitude)
     values ('aa000000-0000-0000-0000-000000000000', 'New Client', '4 A St', -33.89, 151.23) $$,
  'rule 2: a coordinator can add a client to their organization'
);

select throws_ok(
  $$ insert into public.organization_members (organization_id, user_id, role, full_name)
     values ('aa000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000005', 'worker', 'New Hire') $$,
  '42501', null,
  'rule 2: a coordinator cannot manage members'
);

select is_empty(
  'select 1 from public.audit_log',
  'rule 9: a coordinator cannot read the audit log'
);

-- Worker 1 of org A ---------------------------------------------------------------------
set local request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select results_eq(
  'select id from public.visits',
  $$ values ('ad000000-0000-0000-0000-000000000001'::uuid) $$,
  'rule 2: a worker sees only their own visits'
);

select is_empty(
  $$ select 1 from public.visits where id = 'ad000000-0000-0000-0000-000000000002' $$,
  'rule 2: a worker cannot see another worker''s visit'
);

select results_eq(
  'select id from public.clients',
  $$ values ('ac000000-0000-0000-0000-000000000001'::uuid) $$,
  'rule 2: a worker sees only the clients on their own visits'
);

select results_eq(
  $$ with u as (update public.visits set notes = 'edited', status = 'cancelled'
                where id = 'ad000000-0000-0000-0000-000000000001' returning 1)
     select count(*)::int from u $$,
  $$ values (0) $$,
  'rule 2: a worker cannot update a visit directly (only through check_in / check_out)'
);

select throws_ok(
  $$ insert into public.visit_events (organization_id, visit_id, worker_id, event_type, latitude, longitude, distance_m)
     values ('aa000000-0000-0000-0000-000000000000', 'ad000000-0000-0000-0000-000000000001',
             'a0000000-0000-0000-0000-000000000003', 'check_in', -33.86, 151.20, 0) $$,
  '42501', null,
  'rule 2: a worker cannot write visit events directly'
);

select throws_ok(
  $$ insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
     values ('aa000000-0000-0000-0000-000000000000', 'ac000000-0000-0000-0000-000000000001',
             'a0000000-0000-0000-0000-000000000003', '2030-02-05 09:00+00', '2030-02-05 10:00+00') $$,
  '42501', null,
  'rule 2: a worker cannot book visits'
);

select is(
  (select count(*)::int from public.organization_members), 4,
  'a worker can see their colleagues'' names in their own organization only'
);

-- Owner of org A --------------------------------------------------------------------------
set local request.jwt.claims = '{"sub": "a0000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select lives_ok(
  $$ insert into public.organization_members (organization_id, user_id, role, full_name)
     values ('aa000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000005', 'worker', 'New Hire') $$,
  'rule 2: an owner can add members'
);

select throws_ok(
  $$ insert into public.organization_members (organization_id, user_id, role, full_name)
     values ('bb000000-0000-0000-0000-000000000000', 'a0000000-0000-0000-0000-000000000005', 'worker', 'Infiltrator') $$,
  '42501', null,
  'rule 1: an owner cannot add members to another organization'
);

select isnt_empty(
  $$ select 1 from public.audit_log where organization_id = 'aa000000-0000-0000-0000-000000000000' $$,
  'rule 9: an owner can read their organization''s audit log'
);

select is_empty(
  $$ select 1 from public.audit_log where organization_id = 'bb000000-0000-0000-0000-000000000000' $$,
  'rule 1: an owner cannot read another organization''s audit log'
);

-- Worker of org B: nothing of org A, on every table ---------------------------------------
set local request.jwt.claims = '{"sub": "b0000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select is_empty(
  $$ select 'organizations' from public.organizations where id = 'aa000000-0000-0000-0000-000000000000'
     union all select 'members' from public.organization_members where organization_id = 'aa000000-0000-0000-0000-000000000000'
     union all select 'clients' from public.clients where organization_id = 'aa000000-0000-0000-0000-000000000000'
     union all select 'visits' from public.visits where organization_id = 'aa000000-0000-0000-0000-000000000000'
     union all select 'events' from public.visit_events where organization_id = 'aa000000-0000-0000-0000-000000000000'
     union all select 'audit' from public.audit_log where organization_id = 'aa000000-0000-0000-0000-000000000000' $$,
  'rule 1: a user of org B cannot read any org A row in any table'
);

-- Anonymous (no sign-in) --------------------------------------------------------------------
reset role;
set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select throws_ok(
  'select * from public.visits',
  '42501', null,
  'anon has no access to tenant data'
);

select throws_ok(
  $$ select public.check_in('ad000000-0000-0000-0000-000000000001', -33.86, 151.20) $$,
  '42501', null,
  'anon cannot call check_in'
);

select * from finish();
rollback;
