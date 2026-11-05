Closes #

<!-- PR title must follow Conventional Commits, e.g. `feat(db): add visits table with overlap constraint`.
     A squash merge turns the title into the commit on develop. -->

## What changed

-

## Why

-

## How it was tested

- [ ] `npx supabase db reset` (migrations + seed apply to an empty database)
- [ ] `npx supabase test db` (pgTAP)
- [ ] `npm run typecheck && npm run lint && npm run build`
- [ ] Manual check:

## Migration notes

<!-- Write "None" for each line if this PR has no migrations. -->

- **New files:**
- **Table locks:** <!-- which statements take locks, on which tables, and for how long -->
- **Data changes:** <!-- backfills, updates, deletes; expected row counts -->
- **Fix-forward plan:** <!-- if this breaks after deploy, which new migration fixes it -->
