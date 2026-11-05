-- Rule 9: every insert, update and delete on clients and visits is audited, and the
-- audit log cannot be changed by anyone (owners and the database owner included).
begin;
create extension if not exists pgtap with schema extensions;

select plan(12);

insert into auth.users (id, email) values
  ('e0000000-0000-0000-0000-000000000001', 'owner-e@test.example'),
  ('e0000000-0000-0000-0000-000000000002', 'coord-e@test.example'),
  ('e0000000-0000-0000-0000-000000000003', 'worker-e@test.example');

insert into public.organizations (id, name, time_zone) values ('ee000000-0000-0000-0000-000000000000', 'Org E', 'UTC');

insert into public.organization_members (organization_id, user_id, role, full_name) values
  ('ee000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000001', 'owner', 'Owner E'),
  ('ee000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000002', 'coordinator', 'Coord E'),
  ('ee000000-0000-0000-0000-000000000000', 'e0000000-0000-0000-0000-000000000003', 'worker', 'Worker E');

-- The coordinator creates, edits and deletes a client, and books and cancels a visit.
set local role authenticated;
set local request.jwt.claims = '{"sub": "e0000000-0000-0000-0000-000000000002", "role": "authenticated"}';

insert into public.clients (id, organization_id, full_name, address, latitude, longitude) values
  ('ec000000-0000-0000-0000-000000000001', 'ee000000-0000-0000-0000-000000000000', 'Temp Client', '1 E St', 10, 10),
  ('ec000000-0000-0000-0000-000000000002', 'ee000000-0000-0000-0000-000000000000', 'Kept Client', '2 E St', 10, 10);
update public.clients set full_name = 'Temp Client (renamed)' where id = 'ec000000-0000-0000-0000-000000000001';
delete from public.clients where id = 'ec000000-0000-0000-0000-000000000001';

insert into public.visits (id, organization_id, client_id, worker_id, starts_at, ends_at) values
  ('ed000000-0000-0000-0000-000000000001', 'ee000000-0000-0000-0000-000000000000', 'ec000000-0000-0000-0000-000000000002',
   'e0000000-0000-0000-0000-000000000003', '2030-03-04 09:00+00', '2030-03-04 10:00+00');
update public.visits set status = 'cancelled' where id = 'ed000000-0000-0000-0000-000000000001';

reset role;

select results_eq(
  $$ select action::text from public.audit_log
     where row_id = 'ec000000-0000-0000-0000-000000000001' order by id $$,
  $$ values ('insert'), ('update'), ('delete') $$,
  'rule 9: insert, update and delete on clients are each audited'
);

select results_eq(
  $$ select action::text from public.audit_log
     where row_id = 'ed000000-0000-0000-0000-000000000001' order by id $$,
  $$ values ('insert'), ('update') $$,
  'rule 9: insert and update on visits are audited'
);

select is(
  (select count(distinct changed_by)::int from public.audit_log
   where organization_id = 'ee000000-0000-0000-0000-000000000000' and changed_by = 'e0000000-0000-0000-0000-000000000002'),
  1,
  'rule 9: the audit row records who made the change'
);

select ok(
  (select old_data ->> 'full_name' = 'Temp Client' and new_data ->> 'full_name' = 'Temp Client (renamed)'
   from public.audit_log where row_id = 'ec000000-0000-0000-0000-000000000001' and action = 'update'),
  'rule 9: the audit row keeps the old and new values'
);

-- Owner: can read, cannot change ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub": "e0000000-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  -- 3 for the deleted client, 1 for the kept client, 2 for the visit
  (select count(*)::int from public.audit_log where table_name in ('clients', 'visits')), 6,
  'rule 9: the owner reads their organization''s audit log'
);

select throws_ok(
  $$ update public.audit_log set changed_by = null $$,
  '42501', null,
  'rule 9: an owner cannot update the audit log'
);

select throws_ok(
  $$ delete from public.audit_log $$,
  '42501', null,
  'rule 9: an owner cannot delete from the audit log'
);

select throws_ok(
  $$ insert into public.audit_log (organization_id, table_name, row_id, action, new_data)
     values ('ee000000-0000-0000-0000-000000000000', 'clients', gen_random_uuid(), 'insert', '{}') $$,
  '42501', null,
  'rule 9: nobody can forge audit rows through the API'
);

-- Worker: cannot read ---------------------------------------------------------------------
set local request.jwt.claims = '{"sub": "e0000000-0000-0000-0000-000000000003", "role": "authenticated"}';

select is_empty(
  'select 1 from public.audit_log',
  'rule 9: a worker cannot read the audit log'
);

-- Database owner (bypasses RLS and privileges): the triggers still refuse -----------------
reset role;

select throws_ok(
  $$ update public.audit_log set changed_by = null where organization_id = 'ee000000-0000-0000-0000-000000000000' $$,
  'CV030', null,
  'rule 9: even the database owner cannot update the audit log'
);

select throws_ok(
  $$ delete from public.audit_log where organization_id = 'ee000000-0000-0000-0000-000000000000' $$,
  'CV030', null,
  'rule 9: even the database owner cannot delete from the audit log'
);

select throws_ok(
  $$ truncate public.audit_log $$,
  'CV030', null,
  'rule 9: the audit log cannot be truncated'
);

select * from finish();
rollback;
