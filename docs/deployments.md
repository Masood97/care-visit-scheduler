# Deployments

`supabase migration list` for the hosted projects. The **Local** column is the repo's migrations and **Remote** is what the project has applied. Matching columns mean the project is exactly at the repo's state.

The deploy workflow prints this table after every `db push` (step *Migration history* in `.github/workflows/deploy.yml`), so it comes from the pipeline, not from a laptop.

_(Filled in from the v1.1.0 deploy runs.)_
