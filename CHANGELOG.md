# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-11-06

Bonus items and polish. No migrations.

### Added

- **End-to-end tests** (Playwright, `e2e/`) run in CI as the required `E2E` check against a seeded local stack. They cover:
  - coordinator: booking 2:1 and 1:1 visits, the double-booking message, the cancel dialog, archive and restore
  - worker at phone size with faked location: check-in refused from ~530 m, accepted at the door, then check-out
  - owner: the hours report
- **Index evidence:** `scripts/explain-indexes.sql` and the *Indexes for the three most common queries* section of `docs/schema.md`. It has EXPLAIN ANALYZE plans for the week view, a worker's visits and the RLS membership check, on ~20k visits.

### Changed

- The week view is grouped by local day and marks 2:1 visits. Cancelling a visit asks for confirmation in an accessible dialog instead of `window.confirm`.

## [1.1.1] - 2026-11-06

Docs only, no migrations.

### Added

- `docs/deployments.md`: the pipeline's `supabase migration list` for staging and production after v1.1.0. Both show 22/22 migrations matching the repo.

## [1.1.0] - 2026-11-06

Part B: visits with one or two workers (2:1 support). Forward-only: 6 new migrations.

### Added

- `visit_workers`: 1–2 workers per visit.
  - At most 2 is checked with the visit row locked; at least 1 is checked by deferred constraint triggers at commit.
  - Double booking is enforced per worker across all their assignments, by a GiST exclusion constraint on a trigger-synced copy of the visit's time range and status.
  - Adding and removing workers is audited.
- Each assigned worker checks in and out separately. The first check-in sets `in_progress`, and the last assigned worker's check-out sets `completed`.
- A worker sees a visit, its client and their colleague if they are any of its workers. The hours report counts every worker on a visit.
- `book_visit` / `update_visit` RPCs write a visit and its workers in one transaction (`security invoker`).
- Web app: optional second worker when booking or editing, every worker shown on the week view, and per-worker check-in/out on *My visits*.
- Tests: 20 new pgTAP assertions (122 total), plus `scripts/test-part-b-backfill.sh` in CI. It applies Part B to a seeded v1.0.1 database and proves no visit lost its worker.
- ADR 0002: plan for retiring `visits.worker_id` (expand now, measure, contract in a later major release).
- Deploys print `supabase migration list` after pushing, which is the source for `docs/deployments.md`.

### Changed

- `visits.worker_id` is kept and synced both ways as the "primary worker", so the production mobile app keeps working.
- `db push` / `migration list` in the deploy workflow pass `--linked` explicitly.

## [1.0.1] - 2026-11-05

Hotfix for v1.0.0, shipped forward-only.

### Fixed

- **Every API request in production failed with `permission denied`.** The hosted projects don't auto-grant new `public` tables to the Data API roles, while the local stack did. The new migration `20261105174258_explicit_api_grants.sql` grants `authenticated` exactly what the RLS policies allow. It grants `service_role` read/write on core tables and read-only on events and the audit log. `anon` gets nothing.
- Local stack now has `auto_expose_new_tables = false`, so a missing grant fails the pgTAP tests instead of reaching production.

### Changed

- CI also runs on every push to `main`, so release merge commits get their own green run.

## [1.0.0] - 2026-11-05

First production release: Part A (database) and the web app.

### Added

- **Database** (15 forward-only migrations):
  - Tables: organizations, members, clients, visits, visit events and audit log.
  - Row-level security on every table.
  - No double booking, enforced by a GiST exclusion constraint that holds under concurrent bookings.
  - Valid times (end after start, at most 12 hours).
  - Archived clients can't get new visits, and clients with visits can't be deleted.
  - Status flow backed by check-in/check-out evidence.
  - `check_in` / `check_out` functions: assigned worker only, 30-minute early window up to the scheduled end, 200 m radius.
  - Append-only audit log for clients, visits and memberships.
  - `worker_weekly_hours` report in each organization's time zone.
  - Guards that keep open visits on workers, an owner in every organization, and rows in their organization.
- **Tests:** 102 pgTAP assertions, a two-session concurrent double-booking test, and a role-based smoke test of the app.
- **Web app:**
  - Coordinator: week view with book/edit/cancel, client management with archiving.
  - Worker: phone-first screen with location-based check-in and check-out.
  - Owner: weekly hours report.
  - Database errors are shown as plain messages.
- **CI/CD:**
  - PR checks: migration-history guard, reset with seed, schema lint, pgTAP, concurrency test, generated-types check, web type-check/lint/build, PR title and secret scan.
  - Deploys: staging on `develop`; production on `main` after manual approval, followed by the Vercel deploy.
- **Docs:** README, `docs/schema.md`, `docs/migrations-runbook.md`, ADR 0001 (double booking).
- `scripts/create-demo-accounts.mjs` creates demo sign-ins on a hosted project, where seed data is never loaded.

[1.2.0]: https://github.com/Masood97/care-visit-scheduler/releases/tag/v1.2.0
[1.1.1]: https://github.com/Masood97/care-visit-scheduler/releases/tag/v1.1.1
[1.1.0]: https://github.com/Masood97/care-visit-scheduler/releases/tag/v1.1.0
[1.0.1]: https://github.com/Masood97/care-visit-scheduler/releases/tag/v1.0.1
[1.0.0]: https://github.com/Masood97/care-visit-scheduler/releases/tag/v1.0.0
