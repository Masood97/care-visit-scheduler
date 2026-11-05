-- check_in / check_out (rules 7 and 8). The only way a worker changes a visit.
--
-- Both are SECURITY DEFINER (workers have no UPDATE on visits and no INSERT on
-- visit_events) and re-check everything themselves against auth.uid():
--   check_in : assigned worker only; from 30 min before start until the scheduled end;
--              within 200 m of the client's home; records the event; visit -> in_progress.
--   check_out: only the worker who checked in; records the event; visit -> completed.
-- The visit row is locked FOR UPDATE so two taps of the button can't both succeed.
--
-- Error SQLSTATEs (mapped to messages by the web app):
--   CV010 not your visit, CV011 visit not open for check-in, CV012 too early, CV013 too late,
--   CV014 too far away, CV015 invalid location, CV020 you haven't checked in, CV021 not in progress.

-- Great-circle (haversine) distance in metres between two WGS 84 points.
create or replace function private.distance_m(lat1 double precision, lng1 double precision,
                                              lat2 double precision, lng2 double precision)
returns double precision
language sql
immutable
strict
set search_path = ''
as $$
  select 2 * 6371000 * asin(sqrt(
           power(sin(radians(lat2 - lat1) / 2), 2)
         + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
         ));
$$;

comment on function private.distance_m(double precision, double precision, double precision, double precision)
  is 'Haversine distance in metres (Earth radius 6371 km). Accurate to well under 1% at check-in distances.';
revoke all on function private.distance_m(double precision, double precision, double precision, double precision) from public;

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

  select * into v_visit from public.visits where id = p_visit_id for update;

  -- Same error whether the visit doesn't exist or belongs to someone else: don't leak other tenants' ids.
  -- The caller must also still hold the worker role in the visit's organization.
  if not found or v_visit.worker_id is distinct from (select auth.uid()) or not exists (
    select 1 from public.organization_members m
    where m.organization_id = v_visit.organization_id
      and m.user_id = v_visit.worker_id
      and m.role = 'worker'
  ) then
    raise exception 'Only the worker assigned to this visit can check in.'
      using errcode = 'CV010';
  end if;

  if v_visit.status <> 'scheduled' then
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
  values (v_visit.organization_id, v_visit.id, v_visit.worker_id, 'check_in', p_lat, p_lng, round(v_distance::numeric, 1))
  returning * into v_event;

  update public.visits set status = 'in_progress' where id = v_visit.id;

  return v_event;
end;
$$;

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

  -- Only the worker who checked in to this visit can check out of it.
  if not found or not exists (
    select 1 from public.visit_events e
    where e.visit_id = p_visit_id
      and e.worker_id = (select auth.uid())
      and e.event_type = 'check_in'
  ) then
    raise exception 'Only the worker who checked in to this visit can check out.'
      using errcode = 'CV020';
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

  update public.visits set status = 'completed' where id = v_visit.id;

  return v_event;
end;
$$;

comment on function public.check_in(uuid, double precision, double precision)
  is 'Rule 7: assigned worker checks in within the time window and 200 m of the client; visit becomes in_progress.';
comment on function public.check_out(uuid, double precision, double precision)
  is 'Rule 8: the worker who checked in checks out; visit becomes completed.';

revoke all on function public.check_in(uuid, double precision, double precision) from public, anon;
revoke all on function public.check_out(uuid, double precision, double precision) from public, anon;
grant execute on function public.check_in(uuid, double precision, double precision) to authenticated;
grant execute on function public.check_out(uuid, double precision, double precision) to authenticated;
