#!/usr/bin/env bash
# Guards the migration history against the target branch of a PR.
#
#   1. Merged migrations are immutable: any change to an existing file under
#      supabase/migrations/ (modify, rename, delete, type change) fails.
#   2. New migrations must be named <14-digit timestamp>_<snake_case>.sql and be
#      newer than the newest migration already on the target branch.
#
# Usage: scripts/check-migrations.sh <base-ref>   e.g. origin/develop
set -euo pipefail

BASE_REF="${1:?usage: check-migrations.sh <base-ref>}"
DIR="supabase/migrations"
status=0

# Compare against the merge base, so commits that landed on the target branch
# after this branch was cut don't show up as changes made by this PR.
changes="$(git diff --name-status -M "${BASE_REF}...HEAD" -- "${DIR}")"

if [[ -z "${changes}" ]]; then
  echo "No migration changes in this PR."
  exit 0
fi

echo "Migration changes compared with ${BASE_REF}:"
echo "${changes}"
echo

newest_on_base="$(git ls-tree --name-only "${BASE_REF}" "${DIR}/" 2>/dev/null \
  | sed -nE 's#^.*/([0-9]{14})_.*\.sql$#\1#p' | sort | tail -n 1)"
newest_on_base="${newest_on_base:-00000000000000}"
echo "Newest migration on ${BASE_REF}: ${newest_on_base}"

while IFS=$'\t' read -r change path rest; do
  case "${change}" in
    A)
      file="$(basename "${path}")"
      if [[ ! "${file}" =~ ^([0-9]{14})_[a-z0-9_]+\.sql$ ]]; then
        echo "::error file=${path}::Migration name must be <YYYYMMDDHHMMSS>_<snake_case>.sql"
        status=1
        continue
      fi
      ts="${BASH_REMATCH[1]}"
      if [[ ! "${ts}" > "${newest_on_base}" ]]; then
        echo "::error file=${path}::Timestamp ${ts} is not newer than ${newest_on_base} on ${BASE_REF}. Create it again with 'npx supabase migration new'."
        status=1
      fi
      ;;
    *)
      echo "::error file=${path}::Merged migrations are immutable (change type '${change}'${rest:+ -> ${rest}}). Fix forward with a new migration instead."
      status=1
      ;;
  esac
done <<< "${changes}"

if [[ "${status}" -eq 0 ]]; then
  echo "Migration history OK."
fi
exit "${status}"
