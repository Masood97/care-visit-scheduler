-- clients: people who receive care at home.

create table public.clients (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  full_name       text not null
                  constraint clients_full_name_not_blank check (btrim(full_name) <> ''),
  address         text not null
                  constraint clients_address_not_blank check (btrim(address) <> ''),
  latitude        double precision not null
                  constraint clients_latitude_range check (latitude between -90 and 90),
  longitude       double precision not null
                  constraint clients_longitude_range check (longitude between -180 and 180),
  status          public.client_status not null default 'active',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  -- Target of the composite foreign key from visits: a visit's client must be in the visit's organization.
  constraint clients_organization_id_id_key unique (organization_id, id)
);

comment on table public.clients is 'A person who receives care. Clients with visits cannot be deleted (visits FK is ON DELETE RESTRICT); archive them instead.';
comment on column public.clients.latitude is 'Latitude of the home address in degrees (WGS 84). Check-in distance is measured from here.';
comment on column public.clients.longitude is 'Longitude of the home address in degrees (WGS 84).';
comment on column public.clients.status is 'archived clients keep their history but cannot get new visits.';

create trigger clients_set_updated_at
  before update on public.clients
  for each row execute function private.set_updated_at();

alter table public.clients enable row level security;
revoke all on table public.clients from anon;
-- TRUNCATE would bypass RLS and row triggers; REFERENCES/TRIGGER aren't needed by app users.
revoke truncate, references, trigger on table public.clients from authenticated;
