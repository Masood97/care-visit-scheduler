# Care Visits

A multi-tenant scheduling platform for home-care agencies. Coordinators book visits, support workers check in and out on site from a phone, and owners see worked hours. Many agencies share one Postgres database, so every business rule, including tenant isolation, is enforced inside the database by constraints, row-level security and functions.

**Stack:** Next.js 16 (App Router) · TypeScript · Tailwind CSS v4 · shadcn/ui on Radix · React Hook Form + Zod · Supabase (Postgres, Auth, CLI) · Vercel · GitHub Actions.

> This README is filled in as the work lands. Sections marked _(added in #N)_ are completed by that issue's PR.

## Prerequisites

| Tool | Version | Notes |
| --- | --- | --- |
| Node.js | 22 or later | npm comes with it |
| Docker Desktop | running | The local Supabase stack runs in Docker |
| Supabase CLI | 2.122.1 | Installed by `npm ci` as a dev dependency. Run it with `npx supabase` |

## Local setup

_(Completed in #3 and #5, once there is a schema and an app to run.)_

```bash
npm ci                      # install dependencies, including the Supabase CLI
npx supabase start          # start Postgres, Auth and Studio in Docker
npx supabase db reset       # apply every migration and load supabase/seed.sql
cp .env.example .env.local  # then paste the Publishable key from `npx supabase status`
npm run dev                 # http://localhost:3000
```

## Running the tests

```bash
npm run db:test             # pgTAP tests in supabase/tests/ (needs the local stack running)
npm run db:test-concurrency # two sessions book the same slot at once; exactly one must win
```

| File | Proves |
| --- | --- |
| `00_rls_enabled.test.sql` | every table in `public` has RLS enabled |
| `10_visit_constraints.test.sql` | no double booking, valid times, archived clients, no deleting clients with visits, status flow, edit lock, same-org client, worker role, valid time zone |
| `20_rls_tenant_isolation.test.sql` | one organization can't read or write another's rows (every table); a worker can't see another worker's visits; workers can't edit visits or write events directly; only owners manage members; anon has no access |
| `30_check_in_check_out.test.sql` | check-in from 500 m is rejected; time window; only the assigned worker checks in; only the worker who checked in checks out; status becomes in_progress, then completed |
| `40_audit_log.test.sql` | insert/update/delete on clients and visits are audited with who and old/new values; owners read but can't update, delete or truncate it, and neither can the database owner |
| `50_worker_weekly_hours.test.sql` | completed hours per worker per week in the organization's time zone; workers see only their own |
| `scripts/test-concurrent-booking.sh` | no double booking under concurrent bookings (run in CI) |

The brief's required tests map to: cross-org read → `20`; worker can't see another's visits → `20`; double booking → `10` and the concurrency script; 500 m check-in → `30`; invalid status change → `10`; audit log can't be changed → `40`.

### Local sign-in

`npx supabase db reset` loads fake demo data. Every seeded user's password is `Password123!`:

| Role | Harbour Home Care (Australia/Sydney) | Pennine Community Care (Europe/London) |
| --- | --- | --- |
| Owner | `owner@harbour.example` | `owner@pennine.example` |
| Coordinator | `coordinator@harbour.example` | `coordinator@pennine.example` |
| Worker | `worker1@harbour.example`, `worker2@harbour.example` | `worker1@pennine.example`, `worker2@pennine.example` |

## Adding a migration

```bash
npx supabase migration new <snake_case_description>   # never hand-pick the timestamp
# write the SQL and its pgTAP tests, then:
npm run db:reset && npm run db:lint && npm run db:test
npm run db:types            # commit the regenerated lib/database.types.ts
```

Merged migrations are never edited: fix forward with a new file. CI blocks a PR that edits, renames or deletes an existing migration, or adds one with an older timestamp. The full path to production, failure handling and large-table techniques are in [`docs/migrations-runbook.md`](docs/migrations-runbook.md).

## CI/CD

- **`ci.yml`** runs on every PR into `develop` or `main`. The **Database** job checks the migration history, starts Postgres, resets with migrations and seed, lints, runs pgTAP and checks the generated types. The **Web app** job type-checks, lints and builds. **PR title** checks Conventional Commits, and **Secret scan** runs gitleaks.
- **`deploy.yml`** runs on every push. On `develop` it pushes migrations to staging. On `main` it waits for manual approval, pushes migrations to production, then deploys the web app to Vercel.

## Branches and releases

| Branch | Deploys to | Takes merges from | Merge method |
| --- | --- | --- | --- |
| `develop` | Staging Supabase project | `feature/`, `fix/`, `chore/` and `docs/` branches | Squash merge |
| `main` | Production Supabase project and Vercel production | `develop` only, through release PRs | Merge commit |

- Branch from `develop` and name it `<type>/<short-kebab-description>`, for example `feature/core-schema`.
- PR titles follow [Conventional Commits](https://www.conventionalcommits.org/), for example `feat(db): add visits table with overlap constraint`. The squash merge turns the title into the commit on `develop`.
- Each PR links its issue (`Closes #3`) and fills in the PR template, including the migration notes.
- To release, open a PR from `develop` into `main` titled `Release vX.Y.Z`, merge it with a merge commit, then tag `vX.Y.Z` and publish a GitHub release note.
- Both branches are protected by rulesets: no direct pushes, no force pushes, no deletion and no bypass for admins.

## Secrets and environment variables

No secret is ever committed. `.env.example` is the only env file in the repo.

**Web app** (`.env.local` locally; Vercel project settings when hosted)

| Variable | Purpose |
| --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase API URL. In Vercel, Production points to the production project and Preview points to staging |
| `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` | Publishable (anon) key. Safe in the browser because RLS protects the data |

The service-role / secret key is never used by the app and is never stored in Vercel.

**GitHub Environments** (`staging` deploys from `develop`; `production` deploys from `main` and needs a manual approval)

| Secret | Environments | Purpose |
| --- | --- | --- |
| `SUPABASE_ACCESS_TOKEN` | staging, production | Personal access token the CLI uses to link and push. Each environment has its own token |
| `SUPABASE_DB_PASSWORD` | staging, production | Database password of that environment's project |
| `SUPABASE_PROJECT_ID` | staging, production | Project ref of that environment's project |
| `VERCEL_TOKEN` | production | Deploys the web app after production migrations succeed |
| `VERCEL_ORG_ID` | production | Vercel team / account id |
| `VERCEL_PROJECT_ID` | production | Vercel project id |

## Hosted projects

| Environment | Supabase project ref | Region |
| --- | --- | --- |
| staging | `oupgsrousiqwuvnqvvsx` | ap-northeast-2 |
| production | `innzqhhynydebmkviaeg` | ap-southeast-1 |

The two projects are in different regions. That doesn't affect correctness, but staging latency won't predict production latency.

## Documentation

_(Added as each piece lands.)_

- `docs/schema.md`: ER diagram, tables, constraints and the role-by-table access matrix
- `docs/migrations-runbook.md`: how a migration travels from a laptop to production
- `docs/adr/`: decision records
- `docs/deployments.md`: `supabase migration list` output for staging and production
- `CHANGELOG.md`: release notes

## Time spent

Started 5 November 2026, 17:23 PKT. _(Total added at submission.)_

## What was cut

_(Filled in at submission.)_
