# Migrations runbook

How a schema change travels from a laptop to production, and what to do when it goes wrong.

**The one rule:** schema changes reach a hosted project only through a migration file and the pipeline. Nobody runs DDL in the Supabase dashboard, the SQL editor, `psql` against a hosted database, or `supabase db push` from a laptop.

## The path of a migration

```mermaid
flowchart LR
  A[Laptop: write migration + tests] --> B[PR into develop]
  B --> C{CI: 8 checks}
  C -- fail --> A
  C -- pass --> D[Squash merge]
  D --> E[deploy.yml: push to staging]
  E --> F[Release PR develop to main]
  F --> G{CI again}
  G -- pass --> H[Merge commit]
  H --> I[Manual approval]
  I --> J[push to production]
  J --> K[Deploy web app to Vercel]
```

1. **Branch** from `develop`: `git switch develop && git pull && git switch -c feature/<short-kebab>`.
2. **Create the file** with the CLI, which stamps the current UTC time:
   ```bash
   npx supabase migration new add_visit_notes
   # -> supabase/migrations/20261105143012_add_visit_notes.sql
   ```
3. **Write the SQL**, then the pgTAP tests in `supabase/tests/` (a positive and a negative case for each rule).
4. **Prove it locally:**
   ```bash
   npm run db:reset    # every migration + seed on an empty database
   npm run db:lint     # schema lint, fails on errors
   npm run db:test     # pgTAP
   npm run db:types    # regenerate lib/database.types.ts, then commit it
   npm run db:check-migrations
   ```
5. **Open a PR into `develop`.** CI (`.github/workflows/ci.yml`) runs on every push:

   | Check | Fails when |
   | --- | --- |
   | Migration history | a merged migration was edited, renamed or deleted, or a new file's timestamp is not newer than the newest one on the target branch, or the name isn't `<YYYYMMDDHHMMSS>_<snake_case>.sql` |
   | Local stack | `supabase db start` can't start Postgres |
   | Reset | any migration or the seed fails on an empty database |
   | Lint | `supabase db lint` reports an error |
   | Tests | any pgTAP test fails |
   | Types | committed `lib/database.types.ts` differs from the generated types |
   | Web app | type-check, lint or build fails |
   | PR title / Secret scan | title isn't a Conventional Commit; gitleaks finds a secret |

6. **Squash merge.** `deploy.yml` links the **staging** project, prints the pending migrations (`supabase db push --dry-run`) and applies them (`supabase db push`).
7. **Release.** A PR from `develop` into `main` titled `Release vX.Y.Z` runs the same CI. After the merge commit, the production job waits for a reviewer to approve it (Actions → the run → *Review deployments*). It then pushes the migrations to **production** and, only if that succeeded, deploys the web app to Vercel.

Each environment allows one deploy at a time (`concurrency`), and a queued deploy waits rather than cancelling a running one. Seed data is never pushed to a hosted project.

## Naming rules

- File: `<YYYYMMDDHHMMSS>_<snake_case_description>.sql`, created with `npx supabase migration new`. Never hand-pick a timestamp.
- One concern per file (one table, one function, one policy set). Small files make a failed deploy easy to locate.
- A header comment states what the migration does and why.
- Objects: tables plural `snake_case`; constraints `<table>_<column>_<kind>` (e.g. `visits_time_range_check`); policies say who and what (`"coordinators manage visits"`).

## Fix forward, never edit

Once a migration is merged into `develop` it may already be applied to staging, and after a release to production. Editing it would make the file in git disagree with what the database actually ran. Supabase tracks applied versions in `supabase_migrations.schema_migrations`, so it would never re-run the edited file.

So every correction is a **new** migration:

| Problem after merge | Fix-forward migration |
| --- | --- |
| Wrong default / constraint | `alter table ... alter column ... set default ...` / drop and re-add the constraint |
| Bad function | `create or replace function ...` with the corrected body |
| Missing index | `create index ...` |
| A column that should not exist | expand/contract: stop using it in the app first, drop it in a later release |

CI enforces this: the *Migration history* check fails any PR that modifies, renames or deletes an existing migration.

## When a deploy fails halfway

`supabase db push` runs each pending migration in its own transaction and records it in `supabase_migrations.schema_migrations` only on success. If migration 3 of 5 fails, 1–2 are applied and recorded, 3 rolled back, 4–5 not attempted.

1. **Read the failed job log.** The dry-run step lists what was pending, and the push step shows the failing statement.
2. **Don't touch the database by hand.** Nothing in the dashboard, and no manual `schema_migrations` edits.
3. **Find the cause.** It is usually data that staging didn't have, such as a `not null` or `unique` that existing production rows violate, or a lock timeout on a busy table.
4. **Fix forward.** A deploy only runs after a merge, so the failed file is already merged and must not be edited. Add a new migration that makes the change safe, for example by backfilling first and then adding the constraint, and ship it through the normal flow. The pipeline resumes from the first unapplied migration.
5. **Production failed but staging passed?** Reproduce with production-like data. Staging may lack the rows that triggered it. Restore a recent production backup into a branch or local database, apply, and fix.
6. **Web app:** in production the Vercel deploy runs only after migrations succeed, so a failed migration never ships app code that expects the new schema.

## Changing a large table without long locks

Most `ALTER TABLE` forms take an `ACCESS EXCLUSIVE` lock, which blocks reads and writes for as long as the statement runs. On a big, busy table:

- **Keep lock waits short:** start the migration with `set lock_timeout = '5s';` so it fails fast instead of queueing every other query behind it. Retry off-peak.
- **Add columns as nullable, or with a constant default.** Both are metadata-only in Postgres 11+, so there's no table rewrite.
- **Add constraints in two steps:**
  ```sql
  alter table visits add constraint visits_x_check check (...) not valid; -- instant, checks new rows only
  alter table visits validate constraint visits_x_check;                  -- scans with a weaker lock
  ```
- **Indexes:** `create index concurrently ...` doesn't block writes. It can't run inside a transaction, so put it alone in its own migration file.
- **Backfills:** update in batches (for example 5–10k rows per statement keyed by id), not in one huge `UPDATE`. Then set `not null` once every row is filled. A `check (col is not null) not valid` + `validate` first makes the final `set not null` skip the full scan.
- **Renames and drops** use expand/contract across releases: add the new column, write both, backfill, switch reads, and drop the old one in a later release. This is how `visits.worker_id` is retired in Part B (see `docs/adr/`).

## Local commands

| Command | Does |
| --- | --- |
| `npm run db:start` / `db:stop` | start or stop the local stack (Docker) |
| `npm run db:reset` | rebuild the local database from migrations + seed |
| `npm run db:lint` | lint the local schema |
| `npm run db:test` | run pgTAP tests |
| `npm run db:types` | regenerate `lib/database.types.ts` |
| `npm run db:check-migrations` | run CI's migration-history check against `origin/develop` |
