#!/usr/bin/env bash
# Proves rule 3 holds under concurrency: two sessions book the same worker for
# overlapping times at the same moment. Exactly one booking must survive.
#
# Session A inserts a visit and holds its transaction open. Session B inserts an
# overlapping visit meanwhile: the exclusion constraint makes B wait for A, and when
# A commits, B fails with exclusion_violation (23P01). No application locking involved.
#
# Usage: scripts/test-concurrent-booking.sh   (needs the local Supabase database running)
set -euo pipefail

DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
if command -v psql >/dev/null 2>&1; then
  PSQL=(psql "${DB_URL}")
else
  # Windows laptops without a psql client: use the one inside the database container.
  PSQL=(docker exec -i "supabase_db_care-visit-scheduler" psql -U postgres)
fi
run() { "${PSQL[@]}" -X -q -v ON_ERROR_STOP=1 "$@"; }

ORG=40000000-0000-0000-0000-00000000000c
WORKER=40000000-0000-0000-0000-0000000000c2
CLIENT=40000000-0000-0000-0000-0000000000c3

cleanup() {
  run -c "delete from public.visits where organization_id = '${ORG}';
          delete from public.clients where organization_id = '${ORG}';
          delete from public.organization_members where organization_id = '${ORG}';
          delete from public.organizations where id = '${ORG}';
          delete from auth.users where id = '${WORKER}';" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

run <<SQL
insert into auth.users (id, email) values ('${WORKER}', 'concurrency-worker@test.example');
insert into public.organizations (id, name, time_zone) values ('${ORG}', 'Concurrency Test Org', 'UTC');
insert into public.organization_members (organization_id, user_id, role, full_name)
  values ('${ORG}', '${WORKER}', 'worker', 'Concurrency Worker');
insert into public.clients (id, organization_id, full_name, address, latitude, longitude)
  values ('${CLIENT}', '${ORG}', 'Concurrency Client', '1 Race Street', 51.5, -0.12);
SQL

book() { # $1 = start, $2 = end, $3 = seconds to keep the transaction open
  run <<SQL
begin;
insert into public.visits (organization_id, client_id, worker_id, starts_at, ends_at)
values ('${ORG}', '${CLIENT}', '${WORKER}', '$1', '$2');
select pg_sleep($3);
commit;
SQL
}

out_a="$(mktemp)"; out_b="$(mktemp)"
book '2031-03-03 09:00+00' '2031-03-03 11:00+00' 6 >"${out_a}" 2>&1 & pid_a=$!
sleep 2   # A has inserted and is still holding its transaction (6 s) while B starts
book '2031-03-03 10:00+00' '2031-03-03 12:00+00' 0 >"${out_b}" 2>&1 & pid_b=$!

status_a=0; wait "${pid_a}" || status_a=$?
status_b=0; wait "${pid_b}" || status_b=$?

booked="$(run -tA -c "select count(*) from public.visits where organization_id = '${ORG}';")"

echo "session A exit=${status_a}: $(tr '\n' ' ' <"${out_a}")"
echo "session B exit=${status_b}: $(tr '\n' ' ' <"${out_b}")"
echo "visits stored: ${booked}"

if [[ "${status_a}" -eq 0 && "${status_b}" -ne 0 && "${booked}" -eq 1 ]] \
   && grep -q 'visits_no_overlap' "${out_b}"; then
  echo "PASS: concurrent overlapping bookings -> exactly one stored, the other rejected by visits_no_overlap."
else
  echo "FAIL: expected A to succeed, B to fail on visits_no_overlap, and 1 stored visit."
  exit 1
fi
