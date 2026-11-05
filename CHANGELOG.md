# Changelog

All notable changes to this project. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

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

[1.0.0]: https://github.com/Masood97/care-visit-scheduler/releases/tag/v1.0.0
