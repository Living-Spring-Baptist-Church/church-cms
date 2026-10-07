-- Services and attendance (LBC-31): service_type, programs, services, attendance_counts, attendance_checkins,
-- program_participants, the recurring service generator and the recordAttendanceCounts mutation.
-- Source: docs/system-design.md, section "Congregation"; PRD ATT-01, ATT-02, PRG-01 and the permission matrix.
--
-- Deviations from the design sketch, all needing a human decision (see the ticket hand-off):
--   * attendance_counts, attendance_checkins and program_participants get a surrogate id plus a unique constraint on
--     the natural key (service_id; service_id and member_id; program_id and member_id). audit.record_change() reads
--     the row's id column, so a table without id cannot be audited (the LBC-26 member_departments precedent).
--   * services and programs get created_at and updated_at, and services gets archived_at (a cancelled service is
--     archived, never deleted). attendance_counts gets created_at and updated_at. backend.md section 4 requires
--     them and the sketch omits them.
--   * services is unique on (name, starts_at), so the generator is idempotent and a service is never listed twice.
--   * Service times are not defined anywhere yet: the settings table (LBC-23, LBC-24) has no service times column.
--     generate_recurring_services therefore takes the service time templates as a parameter. When settings holds
--     them, a wrapper can read them and call it with no change to the generator.
--
-- Who sees and does what (PRD matrix, AC 4):
--   services: super admin and secretary create, edit and see all; pastor sees all; ushers see non-archived
--     services so they can pick the right one; department heads see services linked to their own programs.
--   attendance_counts: written only by record_attendance_counts (super admin, secretary, usher). Read by super
--     admin, pastor, secretary, ushers, and department heads for the services of their own programs.
--   attendance_checkins: follow the visibility of the member, so children are never exposed to a role that cannot
--     see them. Ushers check in and remove only adults listed in member_names, and see only their own check-ins.
--   programs: super admin and secretary create and edit all; pastor sees all; a department head creates, edits and
--     sees the programs of the departments they head.
--   program_participants: follow the visibility of the member, as member_departments does.
--   Nobody can DELETE services or programs: archiving is an UPDATE. The treasurer and content editor see nothing
--   here. Finance tables will extend that denial when they are created (LBC-31 creates none).

create type public.service_type as enum ('sunday', 'midweek', 'special', 'program');

comment on type public.service_type is 'Kind of service or event: sunday, midweek, special, or program (an event belonging to a program).';

-- Rule values and helpers. Same convention as LBC-26: fixed rule values are immutable functions in private, and
-- helpers used by policies are SECURITY DEFINER because the private schema is closed to app roles.

create function private.church_time_zone()
returns text
language sql
immutable
set search_path = ''
as $$
  select 'Africa/Accra';
$$;

create function private.days_per_week()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 7;
$$;

create function private.sunday_iso_weekday()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 7;
$$;

create function private.default_generation_weeks()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 8;
$$;

create function private.max_generation_weeks()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 26;
$$;

create function private.max_service_templates()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 20;
$$;

create function private.max_headcount()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 100000;
$$;

create function private.max_name_length()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 200;
$$;

create function private.recurring_service_types()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['sunday', 'midweek'];
$$;

create function private.service_template_keys()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['name', 'type', 'weekday', 'time'];
$$;

comment on function private.church_time_zone() is 'Time zone in which service times are written. Africa/Accra has no daylight saving. The settings table (LBC-23) will hold it later.';
comment on function private.days_per_week() is 'Number of days in a week, also the highest ISO weekday number.';
comment on function private.sunday_iso_weekday() is 'ISO weekday number of Sunday (Monday is 1).';
comment on function private.default_generation_weeks() is 'How many weeks of services generate_recurring_services creates when no number is given.';
comment on function private.max_generation_weeks() is 'Largest number of weeks generate_recurring_services accepts, so one call cannot flood the services list.';
comment on function private.max_service_templates() is 'Largest number of service time templates one generate_recurring_services call accepts.';
comment on function private.max_name_length() is 'Longest service name accepted, in characters. Keeps unique (name, starts_at) well inside the btree row limit.';
comment on function private.max_headcount() is 'Largest count accepted for one attendance group at one service. A sanity limit that catches typos such as an extra digit.';
comment on function private.recurring_service_types() is 'The service types that repeat weekly and so can be generated. special and program events are created by hand.';
comment on function private.service_template_keys() is 'The keys a service time template may carry.';

create function private.is_office_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_any_role(array['super_admin', 'secretary']::public.app_role[]);
$$;

create function private.can_record_attendance()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_any_role(array['super_admin', 'secretary', 'usher']::public.app_role[]);
$$;

comment on function private.is_office_staff() is 'True when the signed-in user is an active super admin or secretary, the roles that manage services and programs.';
comment on function private.can_record_attendance() is 'True when the signed-in user is an active super admin, secretary or usher, the roles that record attendance.';

-- Tables. programs first, because services refers to it.

create table public.programs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  department_id uuid references public.departments (id),
  lead_staff_id uuid references public.staff (id),
  starts_on date,
  ends_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  constraint programs_name_check check (btrim(name) <> ''),
  constraint programs_dates_check check (starts_on is null or ends_on is null or ends_on >= starts_on)
);

comment on table public.programs is 'A program such as a retreat or youth week, run by a department (PRG-01). Archived instead of deleted.';
comment on column public.programs.id is 'Unique id of the program.';
comment on column public.programs.name is 'Display name of the program.';
comment on column public.programs.description is 'What the program is about.';
comment on column public.programs.department_id is 'The department that runs the program. Its heads can see and edit the program.';
comment on column public.programs.lead_staff_id is 'The staff member who leads the program.';
comment on column public.programs.starts_on is 'First day of the program.';
comment on column public.programs.ends_on is 'Last day of the program. Never before starts_on.';
comment on column public.programs.created_at is 'When the program was created.';
comment on column public.programs.updated_at is 'When the program was last changed. Maintained by a trigger.';
comment on column public.programs.archived_at is 'Set when the program is archived. Null while active.';

create index programs_department_id_idx on public.programs (department_id);
create index programs_lead_staff_id_idx on public.programs (lead_staff_id);

create table public.services (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type public.service_type not null,
  starts_at timestamptz not null,
  program_id uuid references public.programs (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  constraint services_name_check check (btrim(name) <> ''),
  constraint services_name_length_check check (char_length(name) <= private.max_name_length()),
  constraint services_name_starts_at_key unique (name, starts_at)
);

comment on table public.services is 'A service or event that attendance is recorded for (ATT-01), such as Sunday First Service. Archived instead of deleted: an archived service is a cancelled one.';
comment on column public.services.id is 'Unique id of the service.';
comment on column public.services.name is 'Display name, for example Sunday First Service. Unique together with starts_at.';
comment on column public.services.type is 'sunday, midweek, special or program.';
comment on column public.services.starts_at is 'When the service starts. Stored in UTC; the church time zone is applied on display.';
comment on column public.services.program_id is 'The program this event belongs to, if any. Heads of the program''s department can see the service.';
comment on column public.services.created_at is 'When the service was created.';
comment on column public.services.updated_at is 'When the service was last changed. Maintained by a trigger.';
comment on column public.services.archived_at is 'Set when the service is cancelled or retired. Null while active. Attendance cannot be recorded for an archived service.';

create index services_starts_at_idx on public.services (starts_at);
create index services_program_id_idx on public.services (program_id);

-- Defined here because a SQL function body is checked when it is created and needs programs and services.
create function private.heads_program(p_program_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.programs
    where programs.id = p_program_id
      and private.heads_department(programs.department_id)
  );
$$;

create function private.heads_service_program(p_service_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.services
    where services.id = p_service_id
      and private.heads_program(services.program_id)
  );
$$;

comment on function private.heads_program(uuid) is 'True when the signed-in user heads the department that runs the program. Reads programs as owner so policies that use it do not recurse.';
comment on function private.heads_service_program(uuid) is 'True when the service belongs to a program run by a department the signed-in user heads.';

create table public.attendance_counts (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services (id),
  men integer not null default 0,
  women integer not null default 0,
  children integer not null default 0,
  visitors integer not null default 0,
  recorded_by uuid not null references public.staff (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint attendance_counts_service_id_key unique (service_id),
  -- A check runs as the writing role, so private.max_headcount() is executable by authenticated and service_role.
  constraint attendance_counts_men_check check (men between 0 and private.max_headcount()),
  constraint attendance_counts_women_check check (women between 0 and private.max_headcount()),
  constraint attendance_counts_children_check check (children between 0 and private.max_headcount()),
  constraint attendance_counts_visitors_check check (visitors between 0 and private.max_headcount())
);

comment on table public.attendance_counts is 'Headcount of one service (ATT-02): one row per service. Written only by record_attendance_counts, which overwrites the earlier count; the audit log keeps every earlier value.';
comment on column public.attendance_counts.id is 'Surrogate id of the count, so the audit trigger can record it.';
comment on column public.attendance_counts.service_id is 'The service that was counted. Unique: one count per service.';
comment on column public.attendance_counts.men is 'Number of men present. Zero or more.';
comment on column public.attendance_counts.women is 'Number of women present. Zero or more.';
comment on column public.attendance_counts.children is 'Number of children present. Zero or more.';
comment on column public.attendance_counts.visitors is 'Number of visitors present. Zero or more.';
comment on column public.attendance_counts.recorded_by is 'The staff member who made the latest count. Always the signed-in user, never supplied by the caller.';
comment on column public.attendance_counts.created_at is 'When the first count was recorded.';
comment on column public.attendance_counts.updated_at is 'When the count was last overwritten. Maintained by a trigger.';

create index attendance_counts_recorded_by_idx on public.attendance_counts (recorded_by);

create table public.attendance_checkins (
  id uuid primary key default gen_random_uuid(),
  service_id uuid not null references public.services (id),
  member_id uuid not null references public.members (id),
  checked_in_by uuid not null references public.staff (id),
  checked_in_at timestamptz not null default now(),
  constraint attendance_checkins_service_member_key unique (service_id, member_id)
);

comment on table public.attendance_checkins is 'Per-person attendance of one service (ATT-02). A row is visible only with its member, so children are never exposed to a role that cannot see them. A surrogate id is used so the audit trigger can record the row.';
comment on column public.attendance_checkins.id is 'Surrogate id of the check-in, so the audit trigger can record it.';
comment on column public.attendance_checkins.service_id is 'The service attended.';
comment on column public.attendance_checkins.member_id is 'The person who attended.';
comment on column public.attendance_checkins.checked_in_by is 'The staff member who checked the person in. Always the signed-in user.';
comment on column public.attendance_checkins.checked_in_at is 'When the person was checked in.';

create index attendance_checkins_member_id_idx on public.attendance_checkins (member_id);
create index attendance_checkins_checked_in_by_idx on public.attendance_checkins (checked_in_by);

create table public.program_participants (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.programs (id),
  member_id uuid not null references public.members (id),
  constraint program_participants_program_member_key unique (program_id, member_id)
);

comment on table public.program_participants is 'Who is registered for a program (PRG-01). A row is visible only with its member, so children are never exposed to a role that cannot see them. A surrogate id is used so the audit trigger can record the row.';
comment on column public.program_participants.id is 'Surrogate id of the registration, so the audit trigger can record it.';
comment on column public.program_participants.program_id is 'The program.';
comment on column public.program_participants.member_id is 'The registered person.';

create index program_participants_member_id_idx on public.program_participants (member_id);

create trigger programs_updated_at
  before update on public.programs
  for each row execute function private.set_updated_at();

create trigger services_updated_at
  before update on public.services
  for each row execute function private.set_updated_at();

create trigger attendance_counts_updated_at
  before update on public.attendance_counts
  for each row execute function private.set_updated_at();

-- Name every relationship so the GraphQL fields are stable and distinct from the foreign key column fields.
comment on constraint programs_department_id_fkey on public.programs is
  e'@graphql({"foreign_name": "department", "local_name": "programsCollection"})';
comment on constraint programs_lead_staff_id_fkey on public.programs is
  e'@graphql({"foreign_name": "leadStaff", "local_name": "ledProgramsCollection"})';
comment on constraint services_program_id_fkey on public.services is
  e'@graphql({"foreign_name": "program", "local_name": "servicesCollection"})';
comment on constraint attendance_counts_service_id_fkey on public.attendance_counts is
  e'@graphql({"foreign_name": "service", "local_name": "attendanceCount"})';
comment on constraint attendance_counts_recorded_by_fkey on public.attendance_counts is
  e'@graphql({"foreign_name": "recordedByStaff", "local_name": "recordedAttendanceCountsCollection"})';
comment on constraint attendance_checkins_service_id_fkey on public.attendance_checkins is
  e'@graphql({"foreign_name": "service", "local_name": "attendanceCheckinsCollection"})';
comment on constraint attendance_checkins_member_id_fkey on public.attendance_checkins is
  e'@graphql({"foreign_name": "member", "local_name": "attendanceCheckinsCollection"})';
comment on constraint attendance_checkins_checked_in_by_fkey on public.attendance_checkins is
  e'@graphql({"foreign_name": "checkedInByStaff", "local_name": "recordedAttendanceCheckinsCollection"})';
comment on constraint program_participants_program_id_fkey on public.program_participants is
  e'@graphql({"foreign_name": "program", "local_name": "programParticipantsCollection"})';
comment on constraint program_participants_member_id_fkey on public.program_participants is
  e'@graphql({"foreign_name": "member", "local_name": "programParticipantsCollection"})';

-- Audit triggers (AFTER, and ENABLE ALWAYS so replica mode cannot skip them), as LBC-21 did.

create trigger audit_programs
  after insert or update or delete on public.programs
  for each row execute function audit.record_change();

create trigger audit_services
  after insert or update or delete on public.services
  for each row execute function audit.record_change();

create trigger audit_attendance_counts
  after insert or update or delete on public.attendance_counts
  for each row execute function audit.record_change();

create trigger audit_attendance_checkins
  after insert or update or delete on public.attendance_checkins
  for each row execute function audit.record_change();

create trigger audit_program_participants
  after insert or update or delete on public.program_participants
  for each row execute function audit.record_change();

alter table public.programs enable always trigger audit_programs;
alter table public.services enable always trigger audit_services;
alter table public.attendance_counts enable always trigger audit_attendance_counts;
alter table public.attendance_checkins enable always trigger audit_attendance_checkins;
alter table public.program_participants enable always trigger audit_program_participants;

-- Row level security and grants. Supabase grants new public tables to anon and authenticated by default.
-- anon gets nothing: the public site shows published content only, never attendance or programs.

alter table public.programs enable row level security;
alter table public.services enable row level security;
alter table public.attendance_counts enable row level security;
alter table public.attendance_checkins enable row level security;
alter table public.program_participants enable row level security;

revoke all on table
  public.programs, public.services, public.attendance_counts, public.attendance_checkins, public.program_participants
from public, anon, authenticated;

grant select on
  public.programs, public.services, public.attendance_counts, public.attendance_checkins, public.program_participants
to authenticated;

-- attendance_counts has no insert or update grant: record_attendance_counts is the only way to write it.
grant insert (name, description, department_id, lead_staff_id, starts_on, ends_on),
  update (name, description, department_id, lead_staff_id, starts_on, ends_on, archived_at)
  on public.programs to authenticated;
grant insert (name, type, starts_at, program_id), update (name, type, starts_at, program_id, archived_at)
  on public.services to authenticated;
grant insert (service_id, member_id, checked_in_by), delete on public.attendance_checkins to authenticated;
grant insert (program_id, member_id), delete on public.program_participants to authenticated;

-- Policies are evaluated as the caller, so the helpers they use are executable by authenticated.
revoke execute on function
  private.church_time_zone(),
  private.days_per_week(),
  private.sunday_iso_weekday(),
  private.default_generation_weeks(),
  private.max_generation_weeks(),
  private.max_service_templates(),
  private.max_headcount(),
  private.max_name_length(),
  private.recurring_service_types(),
  private.service_template_keys(),
  private.is_office_staff(),
  private.can_record_attendance(),
  private.heads_program(uuid),
  private.heads_service_program(uuid)
from public, anon, authenticated;

-- The two limits are also used by CHECK constraints, which run as the writing role (an edge function uses service_role).
grant execute on function private.max_headcount(), private.max_name_length() to authenticated, service_role;

grant execute on function
  private.is_office_staff(),
  private.can_record_attendance(),
  private.heads_program(uuid),
  private.heads_service_program(uuid)
to authenticated;

-- programs

create policy programs_select_office on public.programs for select to authenticated
  using ((select private.is_office_staff()));

create policy programs_select_pastor on public.programs for select to authenticated
  using ((select private.has_role('pastor')));

create policy programs_select_department_head on public.programs for select to authenticated
  using (private.heads_department(department_id));

create policy programs_insert_office on public.programs for insert to authenticated
  with check ((select private.is_office_staff()));

create policy programs_insert_department_head on public.programs for insert to authenticated
  with check (private.heads_department(department_id));

create policy programs_update_office on public.programs for update to authenticated
  using ((select private.is_office_staff()))
  with check ((select private.is_office_staff()));

-- with check keeps a head from moving a program into a department they do not head
create policy programs_update_department_head on public.programs for update to authenticated
  using (private.heads_department(department_id))
  with check (private.heads_department(department_id));

-- services

create policy services_select_office on public.services for select to authenticated
  using ((select private.is_office_staff()));

create policy services_select_pastor on public.services for select to authenticated
  using ((select private.has_role('pastor')));

create policy services_select_usher on public.services for select to authenticated
  using ((select private.has_role('usher')) and archived_at is null);

create policy services_select_department_head on public.services for select to authenticated
  using (private.heads_program(program_id));

create policy services_insert_office on public.services for insert to authenticated
  with check ((select private.is_office_staff()));

create policy services_update_office on public.services for update to authenticated
  using ((select private.is_office_staff()))
  with check ((select private.is_office_staff()));

-- attendance_counts: read only, the function writes

create policy attendance_counts_select_viewers on public.attendance_counts for select to authenticated
  using ((select private.has_any_role(array['super_admin', 'pastor', 'secretary', 'usher']::public.app_role[])));

create policy attendance_counts_select_department_head on public.attendance_counts for select to authenticated
  using (private.heads_service_program(service_id));

-- attendance_checkins: a row is visible only with its member (the exists runs the members policies as the caller).
-- Ushers cannot read members, so they act on the adults in member_names, which never lists a minor.

create policy attendance_checkins_select_leadership on public.attendance_checkins for select to authenticated
  using (
    (select private.has_any_role(array['super_admin', 'pastor', 'secretary']::public.app_role[]))
    and exists (select 1 from public.members where members.id = attendance_checkins.member_id)
  );

create policy attendance_checkins_select_department_head on public.attendance_checkins for select to authenticated
  using (
    private.heads_service_program(service_id)
    and exists (select 1 from public.members where members.id = attendance_checkins.member_id)
  );

create policy attendance_checkins_select_usher on public.attendance_checkins for select to authenticated
  using (
    (select private.has_role('usher'))
    and checked_in_by = (select auth.uid())
    and exists (select 1 from public.member_names where member_names.id = attendance_checkins.member_id)
  );

create policy attendance_checkins_insert_office on public.attendance_checkins for insert to authenticated
  with check (
    (select private.is_office_staff())
    and checked_in_by = (select auth.uid())
    and exists (select 1 from public.members where members.id = attendance_checkins.member_id)
    and exists (select 1 from public.services where services.id = attendance_checkins.service_id and services.archived_at is null)
  );

create policy attendance_checkins_insert_usher on public.attendance_checkins for insert to authenticated
  with check (
    (select private.has_role('usher'))
    and checked_in_by = (select auth.uid())
    and exists (select 1 from public.member_names where member_names.id = attendance_checkins.member_id)
    and exists (select 1 from public.services where services.id = attendance_checkins.service_id and services.archived_at is null)
  );

create policy attendance_checkins_delete_office on public.attendance_checkins for delete to authenticated
  using (
    (select private.is_office_staff())
    and exists (select 1 from public.members where members.id = attendance_checkins.member_id)
  );

create policy attendance_checkins_delete_usher on public.attendance_checkins for delete to authenticated
  using (
    (select private.has_role('usher'))
    and checked_in_by = (select auth.uid())
    and exists (select 1 from public.member_names where member_names.id = attendance_checkins.member_id)
  );

-- program_participants: a row is visible only with its member, as for member_departments

create policy program_participants_select_leadership on public.program_participants for select to authenticated
  using (
    (select private.has_any_role(array['super_admin', 'pastor', 'secretary']::public.app_role[]))
    and exists (select 1 from public.members where members.id = program_participants.member_id)
  );

create policy program_participants_select_department_head on public.program_participants for select to authenticated
  using (
    private.heads_program(program_id)
    and exists (select 1 from public.members where members.id = program_participants.member_id)
  );

create policy program_participants_insert_office on public.program_participants for insert to authenticated
  with check (
    (select private.is_office_staff())
    and exists (select 1 from public.members where members.id = program_participants.member_id)
  );

create policy program_participants_insert_department_head on public.program_participants for insert to authenticated
  with check (
    private.heads_program(program_id)
    and exists (select 1 from public.members where members.id = program_participants.member_id)
  );

create policy program_participants_delete_office on public.program_participants for delete to authenticated
  using (
    (select private.is_office_staff())
    and exists (select 1 from public.members where members.id = program_participants.member_id)
  );

create policy program_participants_delete_department_head on public.program_participants for delete to authenticated
  using (
    private.heads_program(program_id)
    and exists (select 1 from public.members where members.id = program_participants.member_id)
  );

-- record_attendance_counts: SECURITY DEFINER because the private schema is closed to app roles and attendance_counts
-- has no write policy, so the explicit role check below is the gate. Volatile, so pg_graphql exposes it as a
-- mutation. One atomic upsert per service: two ushers submitting at once cannot create two rows, the later write
-- wins and the audit log keeps both. recorded_by is always the caller.

create function public.record_attendance_counts(
  p_service_id uuid,
  p_men integer,
  p_women integer,
  p_children integer,
  p_visitors integer
)
returns public.attendance_counts
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_service public.services;
  v_recorded public.attendance_counts;
begin
  if not private.can_record_attendance() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN',
      detail = 'Only a super admin, secretary or usher can record attendance';
  end if;

  if p_service_id is null or p_men is null or p_women is null or p_children is null or p_visitors is null
     or least(p_men, p_women, p_children, p_visitors) < 0
     or greatest(p_men, p_women, p_children, p_visitors) > private.max_headcount()
  then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = format('A service and four counts between 0 and %s are required', private.max_headcount());
  end if;

  select * into v_service from public.services where id = p_service_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'No service with that id';
  end if;
  if v_service.archived_at is not null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = 'Attendance cannot be recorded for an archived service';
  end if;

  insert into public.attendance_counts (service_id, men, women, children, visitors, recorded_by)
  values (p_service_id, p_men, p_women, p_children, p_visitors, (select auth.uid()))
  on conflict on constraint attendance_counts_service_id_key do update
    set men = excluded.men,
        women = excluded.women,
        children = excluded.children,
        visitors = excluded.visitors,
        recorded_by = excluded.recorded_by
  returning * into v_recorded;

  return v_recorded;
end;
$$;

comment on function public.record_attendance_counts(uuid, integer, integer, integer, integer) is 'Records the headcount of a service and returns the row. One row per service: a second call for the same service overwrites the counts and sets recorded_by to the caller; the audit log keeps the earlier values. Super admin, secretary and usher only. Counts are whole numbers from 0 to 100000. Errors: AUTH_FORBIDDEN, VALIDATION_FAILED, NOT_FOUND.';

-- Service time templates: input checks and parsing. They live apart from the generator so the generator stays short.

create function private.is_valid_service_template(p_template jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_weekday integer;
begin
  if jsonb_typeof(p_template) is distinct from 'object'
     or exists (select 1 from jsonb_object_keys(p_template) as key where key <> all (private.service_template_keys()))
     or jsonb_typeof(p_template -> 'name') is distinct from 'string'
     or btrim(p_template ->> 'name') = ''
     or char_length(p_template ->> 'name') > private.max_name_length()
     or jsonb_typeof(p_template -> 'type') is distinct from 'string'
     or (p_template ->> 'type') <> all (private.recurring_service_types())
     or jsonb_typeof(p_template -> 'weekday') is distinct from 'number'
     or (p_template ->> 'weekday') !~ '^[0-9]$'
     or jsonb_typeof(p_template -> 'time') is distinct from 'string'
     -- HH:MM on a 24 hour clock
     or (p_template ->> 'time') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
  then
    return false;
  end if;

  v_weekday := (p_template ->> 'weekday')::integer;
  return v_weekday between 1 and private.days_per_week()
    and ((p_template ->> 'type')::public.service_type <> 'sunday' or v_weekday = private.sunday_iso_weekday());
end;
$$;

comment on function private.is_valid_service_template(jsonb) is 'True when the value is a service time template: an object with exactly the keys name (text), type (sunday or midweek), weekday (ISO, 1 Monday to 7 Sunday, and 7 for sunday) and time (HH:MM).';

create function private.parse_service_templates(p_templates jsonb)
returns table (template_name text, template_type public.service_type, iso_weekday integer, local_time time)
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_templates is null
     or jsonb_typeof(p_templates) is distinct from 'array'
     or jsonb_array_length(p_templates) not between 1 and private.max_service_templates()
     or exists (
       select 1 from jsonb_array_elements(p_templates) as element where not private.is_valid_service_template(element)
     )
  then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = format(
        'templates must be a list of 1 to %s objects with name, type (sunday or midweek), weekday (1 to %s) and time (HH:MM)',
        private.max_service_templates(), private.days_per_week()
      );
  end if;

  return query
  select
    btrim(element ->> 'name'),
    (element ->> 'type')::public.service_type,
    (element ->> 'weekday')::integer,
    (element ->> 'time')::time
  from jsonb_array_elements(p_templates) as element;
end;
$$;

comment on function private.parse_service_templates(jsonb) is 'Validates a list of service time templates and returns one row per template, raising VALIDATION_FAILED for anything else.';

-- generate_recurring_services (AC 2): SECURITY DEFINER for the same reason as record_attendance_counts. For every
-- template it creates the next p_weeks occurrences that start after now, in the church time zone. A service is
-- skipped when one of the same type already starts at that moment, archived ones included, so running it again
-- creates nothing twice and a cancelled service stays cancelled. Returns how many it created. It returns a count, not
-- rows, because pg_graphql runs a function that returns a set more than once, which would try to insert twice.

create function public.generate_recurring_services(p_templates jsonb, p_weeks integer default null)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_weeks integer := coalesce(p_weeks, private.default_generation_weeks());
  v_created integer;
begin
  if not private.is_office_staff() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN',
      detail = 'Only a super admin or secretary can generate services';
  end if;

  if v_weeks < 1 or v_weeks > private.max_generation_weeks() then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = format('weeks must be between 1 and %s', private.max_generation_weeks());
  end if;

  with templates as (
    select * from private.parse_service_templates(p_templates)
  ),
  today as (
    select (now() at time zone private.church_time_zone())::date as church_day
  ),
  next_weekday as (
    select
      templates.*,
      today.church_day
        + ((templates.iso_weekday - extract(isodow from today.church_day)::integer + private.days_per_week())
           % private.days_per_week()) as candidate_day
    from templates
    cross join today
  ),
  first_occurrence as (
    select
      next_weekday.*,
      case
        when ((next_weekday.candidate_day + next_weekday.local_time) at time zone private.church_time_zone()) > now()
          then next_weekday.candidate_day
        else next_weekday.candidate_day + private.days_per_week()
      end as first_day
    from next_weekday
  ),
  occurrences as (
    select
      first_occurrence.template_name,
      first_occurrence.template_type,
      ((first_occurrence.first_day + week_offset * private.days_per_week() + first_occurrence.local_time)
        at time zone private.church_time_zone()) as occurrence_starts_at
    from first_occurrence
    cross join generate_series(0, v_weeks - 1) as week_offset
  ),
  created as (
    insert into public.services (name, type, starts_at)
    select occurrences.template_name, occurrences.template_type, occurrences.occurrence_starts_at
    from occurrences
    where not exists (
      select 1 from public.services as existing
      where existing.type = occurrences.template_type and existing.starts_at = occurrences.occurrence_starts_at
    )
    on conflict on constraint services_name_starts_at_key do nothing
    returning services.id
  )
  select count(*)::integer into v_created from created;

  return v_created;
end;
$$;

comment on function public.generate_recurring_services(jsonb, integer) is 'Creates the next p_weeks (default 8, at most 26) weekly services for each template and returns how many it created (0 when they all exist already), so it can be run again without duplicates. p_templates is a list of objects with name, type (sunday or midweek), weekday (ISO 1 Monday to 7 Sunday, 7 for sunday) and time (HH:MM in the church time zone). Super admin and secretary only. Errors: AUTH_FORBIDDEN, VALIDATION_FAILED.';

revoke execute on function
  private.is_valid_service_template(jsonb),
  private.parse_service_templates(jsonb)
from public, anon, authenticated;

revoke execute on function
  public.record_attendance_counts(uuid, integer, integer, integer, integer),
  public.generate_recurring_services(jsonb, integer)
from public, anon;
grant execute on function
  public.record_attendance_counts(uuid, integer, integer, integer, integer),
  public.generate_recurring_services(jsonb, integer)
to authenticated;
