-- organization_members: which users belong to which organization, and with what role.
-- A user can belong to several organizations (one row each).

create table public.organization_members (
  organization_id uuid not null references public.organizations (id) on delete cascade,
  user_id         uuid not null references auth.users (id) on delete cascade,
  role            public.member_role not null,
  full_name       text not null
                  constraint organization_members_full_name_not_blank check (btrim(full_name) <> ''),
  created_at      timestamptz not null default now(),
  primary key (organization_id, user_id)
);

comment on table public.organization_members is 'Membership of a Supabase Auth user in an organization, with their role there.';
comment on column public.organization_members.role is 'owner manages members and sees the audit log; coordinator manages clients and visits; worker does visits.';
comment on column public.organization_members.full_name is 'Display name shown to colleagues in the same organization (auth.users is not readable by the app).';

-- "Which organizations am I in?" is asked on every request by the RLS helpers.
create index organization_members_user_id_idx on public.organization_members (user_id);

alter table public.organization_members enable row level security;
revoke all on table public.organization_members from anon;
-- TRUNCATE would bypass RLS and row triggers; REFERENCES/TRIGGER aren't needed by app users.
revoke truncate, references, trigger on table public.organization_members from authenticated;
