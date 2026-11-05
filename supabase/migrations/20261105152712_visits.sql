-- visits: one booked visit of a worker to a client's home.
--
-- Rules enforced here by constraints (rule numbers from the brief):
--   3. No double booking: GiST exclusion constraint per worker over the time range,
--      ignoring cancelled visits. Postgres checks it atomically on insert/update, so it
--      also holds when two coordinators book at the same moment (see docs/adr/0001).
--   4. Valid times: ends after it starts, lasts at most 12 hours.
--   5. A client with visits can't be deleted: ON DELETE RESTRICT.
-- Tenant consistency: composite foreign keys make the client and the worker belong to
-- the same organization as the visit.

create table public.visits (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  client_id       uuid not null,
  worker_id       uuid not null,
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  status          public.visit_status not null default 'scheduled',
  notes           text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint visits_client_fk
    foreign key (organization_id, client_id)
    references public.clients (organization_id, id) on delete restrict,
  constraint visits_worker_fk
    foreign key (organization_id, worker_id)
    references public.organization_members (organization_id, user_id) on delete restrict,

  constraint visits_ends_after_start check (ends_at > starts_at),
  constraint visits_max_12_hours check (ends_at - starts_at <= interval '12 hours'),

  -- '[)' = start inclusive, end exclusive, so back-to-back visits (10:00-11:00, 11:00-12:00) are allowed.
  constraint visits_no_overlap
    exclude using gist (worker_id with =, tstzrange(starts_at, ends_at, '[)') with &&)
    where (status <> 'cancelled'),

  -- Target of the composite foreign key from visit_events.
  constraint visits_organization_id_id_key unique (organization_id, id)
);

comment on table public.visits is 'A booked visit. One worker per visit in v1.0.0. Status changes are checked by trigger (see visit_rules migration).';
comment on column public.visits.worker_id is 'auth.users id of the assigned worker; must be a worker member of the same organization.';
comment on column public.visits.starts_at is 'Scheduled start. Check-in opens 30 minutes before this.';
comment on column public.visits.ends_at is 'Scheduled end (exclusive). Check-in closes at this time.';
comment on constraint visits_no_overlap on public.visits is 'Rule 3: a worker cannot have two non-cancelled visits that overlap in time. Deliberately global: a person who works for two agencies cannot be in two homes at once either.';

-- Coordinator week view: visits of one organization in a time window.
create index visits_organization_id_starts_at_idx on public.visits (organization_id, starts_at);
-- Worker "my visits" and the FK lookups on worker / client.
create index visits_worker_id_starts_at_idx on public.visits (worker_id, starts_at);
create index visits_organization_id_client_id_idx on public.visits (organization_id, client_id);

create trigger visits_set_updated_at
  before update on public.visits
  for each row execute function private.set_updated_at();

alter table public.visits enable row level security;
revoke all on table public.visits from anon;
-- TRUNCATE would bypass RLS and row triggers; REFERENCES/TRIGGER aren't needed by app users.
revoke truncate, references, trigger on table public.visits from authenticated;
