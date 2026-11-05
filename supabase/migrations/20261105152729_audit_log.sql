-- audit_log: append-only history of changes to clients and visits.
-- The table is created here; the triggers that fill it and the guards that make it
-- append-only (even for owners) come with the audit-trail migration.
-- No foreign keys on purpose: history must survive the deletion of what it describes.

create table public.audit_log (
  id              bigint generated always as identity primary key,
  organization_id uuid not null,
  table_name      text not null,
  row_id          uuid not null,
  action          public.audit_action not null,
  old_data        jsonb,
  new_data        jsonb,
  changed_by      uuid,
  changed_at      timestamptz not null default now(),

  constraint audit_log_data_matches_action check (
       (action = 'insert' and old_data is null     and new_data is not null)
    or (action = 'update' and old_data is not null and new_data is not null)
    or (action = 'delete' and old_data is not null and new_data is null)
  )
);

comment on table public.audit_log is 'Append-only change history for clients and visits. Readable by owners; nobody can update or delete it.';
comment on column public.audit_log.organization_id is 'Tenant of the changed row, so owners only see their own organization''s history.';
comment on column public.audit_log.row_id is 'Primary key of the changed row in table_name.';
comment on column public.audit_log.old_data is 'Row before the change (null for insert).';
comment on column public.audit_log.new_data is 'Row after the change (null for delete).';
comment on column public.audit_log.changed_by is 'auth.uid() of the user who made the change; null for changes made outside a user session (seed, migrations).';

-- Owners browse their organization's history newest first.
create index audit_log_organization_id_changed_at_idx on public.audit_log (organization_id, changed_at desc);

alter table public.audit_log enable row level security;
revoke all on table public.audit_log from anon;
-- TRUNCATE would bypass RLS and row triggers; REFERENCES/TRIGGER aren't needed by app users.
revoke truncate, references, trigger on table public.audit_log from authenticated;
