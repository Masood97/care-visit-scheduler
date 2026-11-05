-- Shared building blocks for the schema.
--
-- * btree_gist lets a GiST exclusion constraint compare uuid columns with `=`,
--   which the "no double booking" rule on visits needs.
-- * The `private` schema holds helper and trigger functions. It is not exposed
--   through the Data API (only `public` is), so these functions can't be called
--   as RPC endpoints from the browser.

create extension if not exists btree_gist with schema extensions;

create schema if not exists private;
comment on schema private is 'Helper and trigger functions. Not exposed through the Data API.';

revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

-- Keeps updated_at current on every UPDATE.
create or replace function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function private.set_updated_at() is 'Trigger function: sets updated_at to now() on update.';

-- True when tz is a named zone in the IANA database (e.g. Australia/Sydney).
-- Abbreviations and fixed offsets (AEST, +10, EST5EDT) are rejected because they
-- ignore daylight saving, which would shift the weeks in the hours report.
-- STABLE, because the answer depends on the server's time zone database.
create or replace function private.is_valid_time_zone(tz text)
returns boolean
language sql
stable
set search_path = ''
as $$
  select exists (
    select 1 from pg_catalog.pg_timezone_names
    where name = tz and (name like '%/%' or name = 'UTC')
  );
$$;

comment on function private.is_valid_time_zone(text) is 'True when the argument is a time zone name Postgres recognises.';

revoke all on function private.is_valid_time_zone(text) from public;
grant execute on function private.is_valid_time_zone(text) to authenticated, service_role;
