-- Audit trail (rule 9): every insert, update and delete on clients and visits writes an
-- audit_log row. The log is append-only for everyone, owners and service_role included:
-- UPDATE/DELETE/TRUNCATE privileges are revoked AND triggers reject them, so it holds even
-- for roles that bypass RLS. (service_role's INSERT/TRIGGER are revoked in the
-- member_and_tenant_guards migration.)

-- Writes one audit row per changed row. SECURITY DEFINER because app users have no
-- INSERT privilege on audit_log; it records auth.uid() of the user who made the change.
create or replace function private.audit_row_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.audit_log (organization_id, table_name, row_id, action, old_data, new_data, changed_by)
  values (
    case when tg_op = 'DELETE' then old.organization_id else new.organization_id end,
    tg_table_name,
    case when tg_op = 'DELETE' then old.id else new.id end,
    lower(tg_op)::public.audit_action,
    case when tg_op = 'INSERT' then null else to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end,
    (select auth.uid())
  );
  return null; -- AFTER trigger: return value is ignored
end;
$$;

comment on function private.audit_row_change() is 'Trigger: appends an audit_log row for each insert/update/delete on clients and visits.';
revoke all on function private.audit_row_change() from public;

create trigger clients_audit
  after insert or update or delete on public.clients
  for each row execute function private.audit_row_change();

create trigger visits_audit
  after insert or update or delete on public.visits
  for each row execute function private.audit_row_change();

-- Append-only guard: rejects any UPDATE, DELETE or TRUNCATE on audit_log.
create or replace function private.reject_audit_log_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'audit_log is append-only: % is not allowed.', tg_op
    using errcode = 'CV030';
end;
$$;

comment on function private.reject_audit_log_change() is 'Trigger: makes audit_log append-only for every role.';
revoke all on function private.reject_audit_log_change() from public;

create trigger audit_log_no_update_or_delete
  before update or delete on public.audit_log
  for each row execute function private.reject_audit_log_change();

create trigger audit_log_no_truncate
  before truncate on public.audit_log
  for each statement execute function private.reject_audit_log_change();

-- Belt and braces: no role used by the app or the API can even attempt it.
revoke update, delete, truncate on table public.audit_log from authenticated, service_role;
