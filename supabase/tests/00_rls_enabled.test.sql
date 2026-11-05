-- Business rule 1: every table in the public schema has row-level security turned on.
-- This test guards every future table automatically: a migration that adds a table
-- without `enable row level security` fails CI.
begin;
create extension if not exists pgtap with schema extensions;

select plan(1);

select is_empty(
  $$
    select c.relname
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r', 'p')   -- ordinary and partitioned tables
      and not c.relrowsecurity
  $$,
  'every table in public has row-level security enabled'
);

select * from finish();
rollback;
