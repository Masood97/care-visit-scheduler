-- Part B (v1.1.0), step 1 of 6: visits can have one or two workers (2:1 support).
--
-- Expand phase of an expand/contract change (see docs/adr/0002): the assignment moves to
-- this table, while visits.worker_id stays as the "primary worker" so the mobile app that
-- still reads and writes it keeps working.
--
-- The no-double-booking rule must hold for each worker across all their assignments, so
-- the GiST exclusion constraint moves here too. Constraints can't span tables, so each row
-- carries a copy of its visit's time range and status, kept in sync by triggers.

create table public.visit_workers (
  organization_id uuid not null,
  visit_id        uuid not null,
  worker_id       uuid not null,
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  visit_status    public.visit_status not null,
  created_at      timestamptz not null default now(),
  primary key (visit_id, worker_id),

  constraint visit_workers_visit_fk
    foreign key (organization_id, visit_id)
    references public.visits (organization_id, id) on delete cascade,
  constraint visit_workers_worker_fk
    foreign key (organization_id, worker_id)
    references public.organization_members (organization_id, user_id) on delete restrict,

  -- Rule 3 per worker, across every visit they are assigned to.
  constraint visit_workers_no_overlap
    exclude using gist (worker_id with =, tstzrange(starts_at, ends_at, '[)') with &&)
    where (visit_status <> 'cancelled')
);

comment on table public.visit_workers is 'Workers assigned to a visit: 1 or 2 per visit (v1.1.0). visits.worker_id mirrors one of them (the primary) for older clients.';
comment on column public.visit_workers.starts_at is 'Copy of visits.starts_at (kept in sync by trigger) so the exclusion constraint can see it.';
comment on column public.visit_workers.ends_at is 'Copy of visits.ends_at (kept in sync by trigger).';
comment on column public.visit_workers.visit_status is 'Copy of visits.status (kept in sync by trigger); cancelled assignments do not block a worker''s time.';
comment on constraint visit_workers_no_overlap on public.visit_workers is 'Rule 3 for 2:1 visits: a worker cannot be on two non-cancelled visits that overlap in time.';

-- "My visits" for a worker; (visit_id) is covered by the primary key.
create index visit_workers_worker_id_starts_at_idx on public.visit_workers (worker_id, starts_at);

alter table public.visit_workers enable row level security;
revoke all on table public.visit_workers from anon;
grant select, insert, delete on table public.visit_workers to authenticated;
grant select, insert, delete on table public.visit_workers to service_role;
