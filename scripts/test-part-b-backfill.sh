#!/usr/bin/env bash
# Proof on real data for Part B (v1.1.0): the visit_workers migrations run on a database
# that already has rows, and no visit loses its worker.
#
#   1. Build the v1.0.1 schema (migrations up to LAST_V1) and load the seed: 32 visits.
#   2. Record row counts and a fingerprint of every (visit, worker) pair.
#   3. Apply the Part B migrations on top (`supabase migration up`).
#   4. Check: visits unchanged; one assignment per existing visit, with the same worker,
#      time range and status.
#
# Usage: scripts/test-part-b-backfill.sh   (local Supabase running; run in CI)
set -euo pipefail

LAST_V1="20261105174258" # explicit_api_grants, the last migration of v1.0.1
# The CLI is on PATH in CI (supabase/setup-cli); locally it's the npm dev dependency.
if [[ -z "${SUPABASE:-}" ]]; then
  if command -v supabase >/dev/null 2>&1; then SUPABASE="supabase"; else SUPABASE="npx supabase"; fi
fi
DB_URL="${DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
if command -v psql >/dev/null 2>&1; then
  PSQL=(psql "${DB_URL}")
else
  PSQL=(docker exec -i "supabase_db_care-visit-scheduler" psql -U postgres)
fi
q() { "${PSQL[@]}" -X -q -t -A -v ON_ERROR_STOP=1 -c "$1"; }

echo "== 1. v1.0.1 schema + seed"
${SUPABASE} db reset --version "${LAST_V1}" >/dev/null
[[ "$(q "select to_regclass('public.visit_workers') is null")" == "t" ]] || { echo "FAIL: visit_workers already exists"; exit 1; }

visits_before="$(q "select count(*) from public.visits")"
status_before="$(q "select string_agg(status || '=' || n, ',' order by status) from (select status::text, count(*) n from public.visits group by status) s")"
pairs_before="$(q "select md5(string_agg(id::text || ':' || worker_id::text, ',' order by id)) from public.visits")"
echo "before: visits=${visits_before} (${status_before}) pairs=${pairs_before}"
[[ "${visits_before}" -gt 0 ]] || { echo "FAIL: seed produced no visits"; exit 1; }

echo "== 2. apply Part B migrations"
${SUPABASE} migration up --local >/dev/null

visits_after="$(q "select count(*) from public.visits")"
status_after="$(q "select string_agg(status || '=' || n, ',' order by status) from (select status::text, count(*) n from public.visits group by status) s")"
assignments="$(q "select count(*) from public.visit_workers")"
pairs_after="$(q "select md5(string_agg(visit_id::text || ':' || worker_id::text, ',' order by visit_id)) from public.visit_workers")"
primary_ok="$(q "select count(*) from public.visits v where not exists (select 1 from public.visit_workers w where w.visit_id = v.id and w.worker_id = v.worker_id)")"
copies_ok="$(q "select count(*) from public.visit_workers w join public.visits v on v.id = w.visit_id where w.starts_at <> v.starts_at or w.ends_at <> v.ends_at or w.visit_status <> v.status")"
echo "after:  visits=${visits_after} (${status_after}) assignments=${assignments} pairs=${pairs_after}"
echo "        visits without their worker assigned=${primary_ok}, assignments out of sync=${copies_ok}"

if [[ "${visits_after}" == "${visits_before}" && "${status_after}" == "${status_before}" \
   && "${assignments}" == "${visits_before}" && "${pairs_after}" == "${pairs_before}" \
   && "${primary_ok}" == "0" && "${copies_ok}" == "0" ]]; then
  echo "PASS: every one of the ${visits_before} existing visits kept its worker; no data lost."
else
  echo "FAIL: backfill changed or lost data."
  exit 1
fi
