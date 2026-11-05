-- visit_events: check-in and check-out records written by the check_in / check_out functions.

create table public.visit_events (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  visit_id        uuid not null,
  worker_id       uuid not null,
  event_type      public.visit_event_type not null,
  occurred_at     timestamptz not null default now(),
  latitude        double precision not null
                  constraint visit_events_latitude_range check (latitude between -90 and 90),
  longitude       double precision not null
                  constraint visit_events_longitude_range check (longitude between -180 and 180),
  distance_m      double precision not null
                  constraint visit_events_distance_non_negative check (distance_m >= 0),

  constraint visit_events_visit_fk
    foreign key (organization_id, visit_id)
    references public.visits (organization_id, id) on delete restrict,
  constraint visit_events_worker_fk
    foreign key (organization_id, worker_id)
    references public.organization_members (organization_id, user_id) on delete restrict,

  -- One check-in and one check-out per worker per visit (also holds for 2-worker visits in v1.1.0).
  constraint visit_events_one_per_worker_and_type unique (visit_id, worker_id, event_type)
);

comment on table public.visit_events is 'Check-in / check-out records. Written only by the check_in and check_out functions; never updated.';
comment on column public.visit_events.organization_id is 'Copied from the visit so RLS can filter by tenant without a join.';
comment on column public.visit_events.occurred_at is 'Server time of the event (now() inside check_in / check_out), not the device clock.';
comment on column public.visit_events.latitude is 'Worker''s reported latitude at the event (browser geolocation).';
comment on column public.visit_events.longitude is 'Worker''s reported longitude at the event.';
comment on column public.visit_events.distance_m is 'Great-circle distance in metres from the client''s home at the time of the event.';

-- Hours report: a worker's events over time.
create index visit_events_worker_id_occurred_at_idx on public.visit_events (worker_id, occurred_at);
create index visit_events_organization_id_occurred_at_idx on public.visit_events (organization_id, occurred_at);

alter table public.visit_events enable row level security;
revoke all on table public.visit_events from anon;
-- TRUNCATE would bypass RLS and row triggers; REFERENCES/TRIGGER aren't needed by app users.
revoke truncate, references, trigger on table public.visit_events from authenticated;
