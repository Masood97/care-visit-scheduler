-- organizations: one row per home-care agency (the tenant).

create table public.organizations (
  id         uuid primary key default gen_random_uuid(),
  name       text not null
             constraint organizations_name_not_blank check (btrim(name) <> ''),
  time_zone  text not null
             constraint organizations_time_zone_valid check (private.is_valid_time_zone(time_zone)),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.organizations is 'A home-care agency. Every tenant-owned row references one organization.';
comment on column public.organizations.time_zone is 'IANA time zone (e.g. Australia/Sydney). Weeks in the hours report are counted in this zone.';

create trigger organizations_set_updated_at
  before update on public.organizations
  for each row execute function private.set_updated_at();

-- Deny by default: policies are added in the RLS migration. anon never needs access.
alter table public.organizations enable row level security;
revoke all on table public.organizations from anon;
-- TRUNCATE would bypass RLS and row triggers; REFERENCES/TRIGGER aren't needed by app users.
revoke truncate, references, trigger on table public.organizations from authenticated;
