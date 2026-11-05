-- Enumerated types shared by the tables. Enums keep invalid values out at the
-- type level instead of relying on free-text columns plus CHECKs.

create type public.member_role as enum ('owner', 'coordinator', 'worker');
comment on type public.member_role is 'Role of a user inside one organization.';

create type public.client_status as enum ('active', 'archived');
comment on type public.client_status is 'Archived clients keep their history but cannot get new visits.';

create type public.visit_status as enum ('scheduled', 'in_progress', 'completed', 'cancelled');
comment on type public.visit_status is 'Allowed flow: scheduled -> in_progress -> completed, or scheduled -> cancelled.';

create type public.visit_event_type as enum ('check_in', 'check_out');
comment on type public.visit_event_type is 'A worker arriving at (check_in) or leaving (check_out) a visit.';

create type public.audit_action as enum ('insert', 'update', 'delete');
comment on type public.audit_action is 'Kind of change recorded in audit_log.';
