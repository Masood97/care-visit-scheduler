-- Rule 2 (only owners manage members) and the tenant guards:
-- open visits stay on workers, an organization keeps an owner, rows never change
-- organization, membership changes are audited, anon can't reach the RPCs or the report.
begin;
create extension if not exists pgtap with schema extensions;

select plan(13);

insert into auth.users (id, email) values
  ('90000000-0000-0000-0000-000000000001', 'owner-g@test.example'),
  ('90000000-0000-0000-0000-000000000002', 'coord-g@test.example'),
  ('90000000-0000-0000-0000-000000000003', 'worker-g@test.example'),
  ('90000000-0000-0000-0000-000000000004', 'idle-worker-g@test.example');

insert into public.organizations (id, name, time_zone) values
  ('99000000-0000-0000-0000-00000000000a', 'Org G', 'UTC'),
  ('99000000-0000-0000-0000-00000000000b', 'Org H', 'UTC');

insert into public.organization_members (organization_id, user_id, role, full_name) values
  ('99000000-0000-0000-0000-00000000000a', '90000000-0000-0000-0000-000000000001', 'owner', 'Owner G'),
  ('99000000-0000-0000-0000-00000000000a', '90000000-0000-0000-0000-000000000002', 'coordinator', 'Coord G'),
  ('99000000-0000-0000-0000-00000000000a', '90000000-0000-0000-0000-000000000003', 'worker', 'Worker G'),
  ('99000000-0000-0000-0000-00000000000a', '90000000-0000-0000-0000-000000000004', 'worker', 'Idle Worker G');

insert into public.clients (id, organization_id, full_name, address, latitude, longitude) values
  ('99c00000-0000-0000-0000-000000000001', '99000000-0000-0000-0000-00000000000a', 'Client G', '1 G St', 10, 10);

insert into public.visits (id, organization_id, client_id, worker_id, starts_at, ends_at) values
  ('99d00000-0000-0000-0000-000000000001', '99000000-0000-0000-0000-00000000000a', '99c00000-0000-0000-0000-000000000001',
   '90000000-0000-0000-0000-000000000003', '2030-04-01 09:00+00', '2030-04-01 10:00+00');

-- Coordinator: cannot change or remove members ---------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub": "90000000-0000-0000-0000-000000000002", "role": "authenticated"}';

select results_eq(
  $$ with u as (update public.organization_members set role = 'owner'
                where user_id = '90000000-0000-0000-0000-000000000002' returning 1)
     select count(*)::int from u $$,
  $$ values (0) $$,
  'rule 2: a coordinator cannot promote themselves'
);

select results_eq(
  $$ with d as (delete from public.organization_members
                where user_id = '90000000-0000-0000-0000-000000000004' returning 1)
     select count(*)::int from d $$,
  $$ values (0) $$,
  'rule 2: a coordinator cannot remove members'
);

-- Owner: manages members, within the guards ---------------------------------------------------
set local request.jwt.claims = '{"sub": "90000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select throws_ok(
  $$ update public.organization_members set role = 'coordinator'
     where user_id = '90000000-0000-0000-0000-000000000003' $$,
  'CV040', null,
  'a worker with open visits cannot be demoted'
);

select throws_ok(
  $$ delete from public.organization_members where user_id = '90000000-0000-0000-0000-000000000003' $$,
  'CV040', null,
  'a worker with open visits cannot be removed'
);

select lives_ok(
  $$ update public.organization_members set role = 'coordinator'
     where user_id = '90000000-0000-0000-0000-000000000004' $$,
  'rule 2: an owner can change the role of a worker without open visits'
);

select throws_ok(
  $$ update public.organization_members set role = 'coordinator'
     where user_id = '90000000-0000-0000-0000-000000000001' $$,
  'CV041', null,
  'the last owner cannot demote themselves'
);

select throws_ok(
  $$ delete from public.organization_members where user_id = '90000000-0000-0000-0000-000000000001' $$,
  'CV041', null,
  'the last owner cannot be removed'
);

select throws_ok(
  $$ update public.organization_members set organization_id = '99000000-0000-0000-0000-00000000000b'
     where user_id = '90000000-0000-0000-0000-000000000004' $$,
  'CV042', null,
  'rule 1: an owner cannot move a member into another organization'
);

-- Rows never change organization (even for the database owner) ------------------------------
reset role;

select throws_ok(
  $$ update public.visits set organization_id = '99000000-0000-0000-0000-00000000000b'
     where id = '99d00000-0000-0000-0000-000000000001' $$,
  'CV043', null,
  'a visit cannot be moved to another organization'
);

select throws_ok(
  $$ update public.clients set organization_id = '99000000-0000-0000-0000-00000000000b'
     where id = '99c00000-0000-0000-0000-000000000001' $$,
  'CV043', null,
  'a client cannot be moved to another organization'
);

select results_eq(
  $$ select action::text, new_data ->> 'role' from public.audit_log
     where table_name = 'organization_members' and row_id = '90000000-0000-0000-0000-000000000004'
     order by id $$,
  $$ values ('insert', 'worker'), ('update', 'coordinator') $$,
  'rule 9: membership changes are audited'
);

-- Anonymous -------------------------------------------------------------------------------------
set local role anon;
set local request.jwt.claims = '{"role": "anon"}';

select throws_ok(
  $$ select public.check_out('99d00000-0000-0000-0000-000000000001', 10, 10) $$,
  '42501', null,
  'anon cannot call check_out'
);

select throws_ok(
  'select * from public.worker_weekly_hours',
  '42501', null,
  'anon cannot read the hours report'
);

select * from finish();
rollback;
