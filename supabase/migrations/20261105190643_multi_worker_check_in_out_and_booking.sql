-- Part B step 6 of 6: each assigned worker checks in and out separately.
--   * The visit becomes in_progress at the FIRST check-in ...
--   * ... and completed when the LAST assigned worker checks out (every assigned worker must
--     check out: for 2:1 support both carers are needed for the whole visit).
-- Plus book_visit / update_visit RPCs so a visit and its 1-2 workers are written in one
-- transaction (security invoker: the caller's RLS and privileges apply).
--
-- New error codes: CV016 already checked in, CV022 already checked out,
-- CV053 two different workers needed, CV054 visit not found / not editable.

-- Status flow: "completed" now needs a check-out from every assigned worker. ------------
create or replace function private.enforce_visit_rules()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_client_status public.client_status;
  v_worker_role   public.member_role;
begin
  if tg_op = 'INSERT' and new.status <> 'scheduled' then
    raise exception 'A new visit must start as scheduled (got %).', new.status
      using errcode = 'CV004';
  end if;

  if tg_op = 'UPDATE' and new.status is distinct from old.status then
    if not (
         (old.status = 'scheduled'   and new.status in ('in_progress', 'cancelled'))
      or (old.status = 'in_progress' and new.status = 'completed')
    ) then
      raise exception 'A visit cannot move from % to %.', old.status, new.status
        using errcode = 'CV003';
    end if;

    if new.status = 'in_progress' and not exists (
      select 1 from public.visit_events e
      where e.visit_id = new.id and e.event_type = 'check_in'
    ) then
      raise exception 'A visit starts only when a worker checks in.'
        using errcode = 'CV006';
    end if;

    if new.status = 'completed' and exists (
      select 1 from public.visit_workers vw
      where vw.visit_id = new.id
        and not exists (
          select 1 from public.visit_events e
          where e.visit_id = new.id and e.worker_id = vw.worker_id and e.event_type = 'check_out'
        )
    ) then
      raise exception 'A visit completes only when every assigned worker has checked out.'
        using errcode = 'CV007';
    end if;
  end if;

  if tg_op = 'UPDATE' and old.status <> 'scheduled' and (
       new.starts_at   is distinct from old.starts_at
    or new.ends_at     is distinct from old.ends_at
    or new.client_id   is distinct from old.client_id
    or new.worker_id   is distinct from old.worker_id
    or new.organization_id is distinct from old.organization_id
  ) then
    raise exception 'Only scheduled visits can be rescheduled or reassigned (this one is %).', old.status
      using errcode = 'CV005';
  end if;

  if tg_op = 'INSERT' or new.client_id is distinct from old.client_id then
    select c.status into v_client_status from public.clients c where c.id = new.client_id for share;
    if v_client_status = 'archived' then
      raise exception 'This client is archived and cannot get new visits.'
        using errcode = 'CV001';
    end if;
  end if;

  if tg_op = 'INSERT' or new.worker_id is distinct from old.worker_id
     or new.organization_id is distinct from old.organization_id then
    select m.role into v_worker_role
    from public.organization_members m
    where m.organization_id = new.organization_id and m.user_id = new.worker_id
    for share;
    if v_worker_role is distinct from 'worker' then
      raise exception 'Visits can only be assigned to members with the worker role.'
        using errcode = 'CV002';
    end if;
  end if;

  return new;
end;
$$;

-- check_in: any assigned worker, once each. -------------------------------------------
create or replace function public.check_in(p_visit_id uuid, p_lat double precision, p_lng double precision)
returns public.visit_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_visit    public.visits;
  v_client   public.clients;
  v_distance double precision;
  v_event    public.visit_events;
begin
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'Your location could not be read. Allow location access and try again.'
      using errcode = 'CV015';
  end if;

  -- Lock the visit so two workers checking in at once update its status one after the other.
  select * into v_visit from public.visits where id = p_visit_id for update;

  if not found or not exists (
    select 1
    from public.visit_workers vw
    join public.organization_members m
      on m.organization_id = vw.organization_id and m.user_id = vw.worker_id and m.role = 'worker'
    where vw.visit_id = p_visit_id and vw.worker_id = (select auth.uid())
  ) then
    raise exception 'Only a worker assigned to this visit can check in.'
      using errcode = 'CV010';
  end if;

  if exists (
    select 1 from public.visit_events e
    where e.visit_id = p_visit_id and e.worker_id = (select auth.uid()) and e.event_type = 'check_in'
  ) then
    raise exception 'You have already checked in to this visit.'
      using errcode = 'CV016';
  end if;

  if v_visit.status not in ('scheduled', 'in_progress') then
    raise exception 'This visit is % and can''t be checked in to.', replace(v_visit.status::text, '_', ' ')
      using errcode = 'CV011';
  end if;

  if now() < v_visit.starts_at - interval '30 minutes' then
    raise exception 'Check-in opens 30 minutes before the visit starts.'
      using errcode = 'CV012';
  end if;

  if now() > v_visit.ends_at then
    raise exception 'Check-in closed at the scheduled end of the visit.'
      using errcode = 'CV013';
  end if;

  select * into v_client from public.clients where id = v_visit.client_id;
  v_distance := private.distance_m(p_lat, p_lng, v_client.latitude, v_client.longitude);

  if v_distance > 200 then
    raise exception 'You are % m from the client''s home. Check-in works within 200 m.', round(v_distance)
      using errcode = 'CV014';
  end if;

  insert into public.visit_events (organization_id, visit_id, worker_id, event_type, latitude, longitude, distance_m)
  values (v_visit.organization_id, v_visit.id, (select auth.uid()), 'check_in', p_lat, p_lng, round(v_distance::numeric, 1))
  returning * into v_event;

  -- First check-in starts the visit.
  if v_visit.status = 'scheduled' then
    update public.visits set status = 'in_progress' where id = v_visit.id;
  end if;

  return v_event;
end;
$$;

-- check_out: each worker who checked in, once; the last one completes the visit. --------
create or replace function public.check_out(p_visit_id uuid, p_lat double precision, p_lng double precision)
returns public.visit_events
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_visit    public.visits;
  v_client   public.clients;
  v_distance double precision;
  v_event    public.visit_events;
begin
  if p_lat is null or p_lng is null or p_lat not between -90 and 90 or p_lng not between -180 and 180 then
    raise exception 'Your location could not be read. Allow location access and try again.'
      using errcode = 'CV015';
  end if;

  select * into v_visit from public.visits where id = p_visit_id for update;

  if not found or not exists (
    select 1 from public.visit_events e
    where e.visit_id = p_visit_id and e.worker_id = (select auth.uid()) and e.event_type = 'check_in'
  ) then
    raise exception 'Only a worker who checked in to this visit can check out.'
      using errcode = 'CV020';
  end if;

  if exists (
    select 1 from public.visit_events e
    where e.visit_id = p_visit_id and e.worker_id = (select auth.uid()) and e.event_type = 'check_out'
  ) then
    raise exception 'You have already checked out of this visit.'
      using errcode = 'CV022';
  end if;

  if v_visit.status <> 'in_progress' then
    raise exception 'This visit is % and can''t be checked out of.', replace(v_visit.status::text, '_', ' ')
      using errcode = 'CV021';
  end if;

  select * into v_client from public.clients where id = v_visit.client_id;
  v_distance := private.distance_m(p_lat, p_lng, v_client.latitude, v_client.longitude);

  insert into public.visit_events (organization_id, visit_id, worker_id, event_type, latitude, longitude, distance_m)
  values (v_visit.organization_id, v_visit.id, (select auth.uid()), 'check_out', p_lat, p_lng, round(v_distance::numeric, 1))
  returning * into v_event;

  -- The last assigned worker to check out completes the visit.
  if not exists (
    select 1 from public.visit_workers vw
    where vw.visit_id = v_visit.id
      and not exists (
        select 1 from public.visit_events e
        where e.visit_id = v_visit.id and e.worker_id = vw.worker_id and e.event_type = 'check_out'
      )
  ) then
    update public.visits set status = 'completed' where id = v_visit.id;
  end if;

  return v_event;
end;
$$;

comment on function public.check_in(uuid, double precision, double precision)
  is 'Rule 7 (v1.1.0): any assigned worker checks in once, within the window and 200 m; the first check-in sets in_progress.';
comment on function public.check_out(uuid, double precision, double precision)
  is 'Rule 8 (v1.1.0): each worker who checked in checks out once; the last assigned worker''s check-out sets completed.';

-- Booking with 1-2 workers in one transaction. ---------------------------------------
create or replace function public.book_visit(
  p_organization_id uuid,
  p_client_id uuid,
  p_worker_ids uuid[],
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_notes text default null
)
returns uuid
language plpgsql
security invoker   -- RLS and privileges of the caller apply to every statement
set search_path = ''
as $$
declare
  v_visit_id uuid;
begin
  if coalesce(cardinality(p_worker_ids), 0) not between 1 and 2 or array_position(p_worker_ids, null) is not null then
    raise exception 'A visit needs one or two workers.' using errcode = 'CV050';
  end if;
  if cardinality(p_worker_ids) = 2 and p_worker_ids[1] = p_worker_ids[2] then
    raise exception 'Choose two different workers.' using errcode = 'CV053';
  end if;

  -- The first worker is the primary (visits.worker_id); the sync trigger assigns them.
  insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at, notes)
  values (p_organization_id, p_client_id, p_worker_ids[1], p_starts_at, p_ends_at, p_notes)
  returning id into v_visit_id;

  if cardinality(p_worker_ids) = 2 then
    insert into public.visit_workers (organization_id, visit_id, worker_id)
    values (p_organization_id, v_visit_id, p_worker_ids[2]);
  end if;

  return v_visit_id;
end;
$$;

create or replace function public.update_visit(
  p_visit_id uuid,
  p_client_id uuid,
  p_worker_ids uuid[],
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_notes text default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_organization_id uuid;
begin
  if coalesce(cardinality(p_worker_ids), 0) not between 1 and 2 or array_position(p_worker_ids, null) is not null then
    raise exception 'A visit needs one or two workers.' using errcode = 'CV050';
  end if;
  if cardinality(p_worker_ids) = 2 and p_worker_ids[1] = p_worker_ids[2] then
    raise exception 'Choose two different workers.' using errcode = 'CV053';
  end if;

  select organization_id into v_organization_id from public.visits where id = p_visit_id;
  if not found then
    raise exception 'That visit no longer exists or you can''t edit it.' using errcode = 'CV054';
  end if;

  -- 1. drop workers who are no longer on the visit (the "at least one" check runs at commit)
  delete from public.visit_workers where visit_id = p_visit_id and worker_id <> all (p_worker_ids);

  -- 2. update the visit; the new primary is synced into visit_workers by trigger
  update public.visits
     set client_id = p_client_id, worker_id = p_worker_ids[1],
         starts_at = p_starts_at, ends_at = p_ends_at, notes = p_notes
   where id = p_visit_id;

  -- 3. add the second worker if they aren't assigned yet
  if cardinality(p_worker_ids) = 2 then
    insert into public.visit_workers (organization_id, visit_id, worker_id)
    values (v_organization_id, p_visit_id, p_worker_ids[2])
    on conflict (visit_id, worker_id) do nothing;
  end if;
end;
$$;

comment on function public.book_visit(uuid, uuid, uuid[], timestamptz, timestamptz, text)
  is 'Books a visit with 1-2 workers in one transaction (security invoker: RLS applies).';
comment on function public.update_visit(uuid, uuid, uuid[], timestamptz, timestamptz, text)
  is 'Edits a scheduled visit and its 1-2 workers in one transaction (security invoker: RLS applies).';

revoke all on function public.book_visit(uuid, uuid, uuid[], timestamptz, timestamptz, text) from public, anon;
revoke all on function public.update_visit(uuid, uuid, uuid[], timestamptz, timestamptz, text) from public, anon;
grant execute on function public.book_visit(uuid, uuid, uuid[], timestamptz, timestamptz, text) to authenticated;
grant execute on function public.update_visit(uuid, uuid, uuid[], timestamptz, timestamptz, text) to authenticated;
