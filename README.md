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

_(Added in #4.)_

## Adding a migration

_(Added in #2 and #3. Full detail lives in `docs/migrations-runbook.md`.)_

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
