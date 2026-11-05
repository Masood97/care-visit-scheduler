-- Local / CI seed data. FAKE people, places and addresses only.
-- Loaded by `supabase db reset`; never pushed to a hosted project.
--
-- 2 organizations, each with 1 owner, 1 coordinator, 2 workers, 5 clients and 16 visits
-- spread over two weeks around today (at local times in each agency's zone), so the demo
-- always has past, current and future visits:
--   completed (with check-in + check-out events), cancelled, in_progress (checked in), scheduled.
--
-- Sign-in for every seeded user: password `Password123!`, emails like
-- owner@harbour.example, coordinator@harbour.example, worker1@harbour.example, worker2@harbour.example
-- (and the same with @pennine.example).
--
-- Visits are inserted as `scheduled` and then moved through the allowed status flow,
-- so the status-flow trigger is exercised by the seed itself.

-- Creates a confirmed email/password user in Supabase Auth and returns its id.
create or replace function pg_temp.seed_user(p_email text)
returns uuid
language plpgsql
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    -- GoTrue reads these as strings; NULL makes sign-in fail.
    confirmation_token, recovery_token, email_change_token_new, email_change
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', p_email,
    extensions.crypt('Password123!', extensions.gen_salt('bf')), now(),
    '{"provider": "email", "providers": ["email"]}', '{}', now(), now(),
    '', '', '', ''
  );

  insert into auth.identities (user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
  values (
    v_id, v_id::text, 'email',
    jsonb_build_object('sub', v_id::text, 'email', p_email, 'email_verified', true),
    now(), now(), now()
  );

  return v_id;
end;
$$;

do $$
declare
  org        record;
  spec       record;
  v_org      uuid;
  v_workers  uuid[];
  v_clients  uuid[];
  v_lat      double precision[];
  v_lng      double precision[];
  v_visit    uuid;
  v_start    timestamptz;
  v_end      timestamptz;
  v_worker   uuid;
  v_today    timestamp;  -- today's local midnight in the organization's time zone
  i          int;
begin
  for org in
    select *
    from (values
      ('Harbour Home Care', 'Australia/Sydney', 'harbour', -33.8650, 151.2094,
       array['Helen Marsh', 'Callum Reid', 'Wei Chen', 'Sofia Alvarez'],
       array['Margaret Ellis', 'Tomasz Nowak', 'Aiyana Brooks', 'Desmond Hale', 'Priya Raman'],
       array['14 Gullwing Street, Harbourside', '3/22 Pelican Parade, Harbourside', '87 Saltbush Road, Harbourside',
             '5 Lantern Court, Harbourside', '41 Moreton Bay Avenue, Harbourside']),
      ('Pennine Community Care', 'Europe/London', 'pennine', 53.7996, -1.5491,
       array['Robert Lister', 'Fiona Brady', 'Kwame Mensah', 'Ellie Ward'],
       array['Eileen Thornton', 'Gareth Pryce', 'Nadia Haddad', 'Wilfred Ashby', 'Sunita Patel'],
       array['9 Millstone Row, Fellside', '27 Heather Close, Fellside', '2 Weaver''s Yard, Fellside',
             '63 Beck Lane, Fellside', '18 Gritstone Terrace, Fellside'])
    ) as t(name, tz, slug, lat, lng, staff, client_names, addresses)
  loop
    insert into public.organizations (name, time_zone)
    values (org.name, org.tz)
    returning id into v_org;

    -- Staff: owner, coordinator, worker1, worker2.
    insert into public.organization_members (organization_id, user_id, role, full_name)
    values
      (v_org, pg_temp.seed_user('owner@' || org.slug || '.example'),       'owner',       org.staff[1]),
      (v_org, pg_temp.seed_user('coordinator@' || org.slug || '.example'), 'coordinator', org.staff[2]);

    v_workers := array[
      pg_temp.seed_user('worker1@' || org.slug || '.example'),
      pg_temp.seed_user('worker2@' || org.slug || '.example')
    ];
    insert into public.organization_members (organization_id, user_id, role, full_name)
    values
      (v_org, v_workers[1], 'worker', org.staff[3]),
      (v_org, v_workers[2], 'worker', org.staff[4]);

    -- Five clients spread around the agency's area (about 1 km apart).
    v_clients := '{}'; v_lat := '{}'; v_lng := '{}';
    for i in 1..5 loop
      v_lat := v_lat || (org.lat + i * 0.009);
      v_lng := v_lng || (org.lng + i * 0.006);
      insert into public.clients (organization_id, full_name, address, latitude, longitude)
      values (v_org, org.client_names[i], org.addresses[i], v_lat[i], v_lng[i])
      returning id into v_visit;  -- reuse the uuid variable as a temporary holder
      v_clients := v_clients || v_visit;
    end loop;

    v_today := date_trunc('day', now() at time zone org.tz);

    -- 16 visits: worker no., client no., day offset from today, local start hour, length,
    -- final status, notes. A null day offset means "started 30 minutes ago" (the visit
    -- that is checked in right now).
    for spec in
      select *
      from (values
        (1, 1,   -8,    9, interval '2 hours',    'completed',   'Morning personal care'),
        (1, 2,   -7,   13, interval '2 hours',    'completed',   'Shopping and meal prep'),
        (1, 3,   -6,    9, interval '90 minutes', 'completed',   'Medication prompt'),
        (1, 1,   -3,    9, interval '2 hours',    'completed',   'Morning personal care'),
        (1, 4,   -2,   10, interval '2 hours',    'cancelled',   'Client in hospital'),
        (1, 2,   -1,   13, interval '2 hours',    'completed',   'Shopping and meal prep'),
        (1, 5, null, null, interval '2 hours',    'in_progress', 'Companionship visit'),
        (1, 1,    1,    9, interval '2 hours',    'scheduled',   'Morning personal care'),
        (1, 3,    3,    9, interval '90 minutes', 'scheduled',   'Medication prompt'),
        (2, 4,   -7,    8, interval '3 hours',    'completed',   'Safe lift and bathing'),
        (2, 5,   -5,   14, interval '2 hours',    'completed',   'Physio exercises'),
        (2, 2,   -4,   10, interval '2 hours',    'cancelled',   'Rescheduled by family'),
        (2, 3,   -2,   11, interval '2 hours',    'completed',   'Cleaning and laundry'),
        (2, 4,    1,    8, interval '2 hours',    'scheduled',   'Safe lift and bathing'),
        (2, 5,    2,   14, interval '2 hours',    'scheduled',   'Physio exercises'),
        (2, 1,    4,   18, interval '1 hour',     'scheduled',   'Evening check')
      ) as s(worker_no, client_no, day_offset, local_hour, duration, final_status, notes)
    loop
      v_worker := v_workers[spec.worker_no];
      if spec.day_offset is null then
        v_start := date_trunc('minute', now()) - interval '30 minutes';
      else
        -- local wall-clock time -> timestamptz, so 09:00 means 09:00 in the agency's zone
        v_start := (v_today + spec.day_offset * interval '1 day' + spec.local_hour * interval '1 hour')
                   at time zone org.tz;
      end if;
      v_end := v_start + spec.duration;

      insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at, notes)
      values (v_org, v_clients[spec.client_no], v_worker, v_start, v_end, spec.notes)
      returning id into v_visit;

      if spec.final_status in ('in_progress', 'completed') then
        -- Checked in 3 minutes after the start, about 11 m from the client's front door.
        insert into public.visit_events (organization_id, visit_id, worker_id, event_type, occurred_at, latitude, longitude, distance_m)
        values (v_org, v_visit, v_worker, 'check_in', v_start + interval '3 minutes',
                v_lat[spec.client_no] + 0.0001, v_lng[spec.client_no], 11.1);
        update public.visits set status = 'in_progress' where id = v_visit;
      end if;

      if spec.final_status = 'completed' then
        insert into public.visit_events (organization_id, visit_id, worker_id, event_type, occurred_at, latitude, longitude, distance_m)
        values (v_org, v_visit, v_worker, 'check_out', v_end - interval '4 minutes',
                v_lat[spec.client_no] - 0.0001, v_lng[spec.client_no], 11.1);
        update public.visits set status = 'completed' where id = v_visit;
      elsif spec.final_status = 'cancelled' then
        update public.visits set status = 'cancelled' where id = v_visit;
      end if;
    end loop;
  end loop;
end;
$$;
