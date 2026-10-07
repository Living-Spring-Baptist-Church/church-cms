-- Congregation (LBC-26): member_status, households, members, member_departments, visitor_followups, the
-- member_names view, the children's records rule (private.is_minor) and the staff.member_id foreign key.
-- Source: docs/system-design.md, sections "Congregation" and "Permissions (row-level security)"; PRD MEM-01..MEM-05.
--
-- Deviations from the design sketch, all needing a human decision (see the ticket hand-off):
--   * member_departments gets a surrogate id plus unique (member_id, department_id). audit.record_change() reads
--     the row's id column, so a composite primary key without id cannot be audited.
--   * households and visitor_followups get created_at and updated_at, which backend.md section 4 requires on
--     every table and the sketch omits.
--   * Unknown date of birth is treated as a minor (private.is_minor(null) is true): the safe default is to hide.
--
-- Who sees what (PRD matrix, AC 2 and 3):
--   members: super admin all; pastor all non-archived; secretary adults, archived included; department head the
--   non-archived members of the department they head (minors only when that department is a children's ministry).
--   Ushers and the treasurer read nothing here: they use the member_names view.
--   Writes: super admin (everyone) and secretary (adults only, so a secretary can neither create a child nor turn
--   an adult into a minor). Nobody can DELETE members, households or follow-ups: archiving is an UPDATE.

create type public.member_status as enum ('visitor', 'active', 'inactive', 'transferred', 'deceased');

comment on type public.member_status is 'Where a person stands with the church. A visitor becomes a member by a status change, never a copy.';

-- Rule values and helpers. SECURITY DEFINER because the private schema is closed to app roles (no USAGE), so an
-- invoker function could not call another private function; none of these reads a table the caller cannot see.

create function private.age_of_majority()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 18;
$$;

comment on function private.age_of_majority() is 'Age in years at which a person stops being a minor. Children''s records are protected until then.';

create function private.is_minor_on(p_date_of_birth date, p_on date)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  -- Unknown age is treated as a minor. A leap day birth turns 18 on 1 March, the later and so safer date.
  select p_date_of_birth is null
    or p_date_of_birth > (p_on - pg_catalog.make_interval(years => private.age_of_majority()))::date;
$$;

create function private.is_minor(p_date_of_birth date)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_minor_on(p_date_of_birth, current_date);
$$;

create function private.can_view_minors()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_any_role(array['super_admin', 'pastor']::public.app_role[]);
$$;

create function private.can_manage_members()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_any_role(array['super_admin', 'secretary']::public.app_role[]);
$$;

comment on function private.is_minor_on(date, date) is 'True when a person born on the date is under the age of majority on the given day. A null date of birth counts as a minor.';
comment on function private.is_minor(date) is 'True when a person born on the date is a minor today. A null date of birth counts as a minor, so unknown ages are hidden from everyone but super admin and pastor.';
comment on function private.can_view_minors() is 'True when the signed-in user is an active super admin or pastor, the roles that see every minor. Heads of children''s ministry see minors of their own department only, through heads_department_of_member.';
comment on function private.can_manage_members() is 'True when the signed-in user is an active super admin or secretary, the only roles that write congregation records.';
revoke execute on function
  private.age_of_majority(),
  private.is_minor_on(date, date),
  private.is_minor(date),
  private.can_view_minors(),
  private.can_manage_members()
from public, anon, authenticated;

-- Policies are evaluated as the caller, so the helpers they use are executable by authenticated.
grant execute on function
  private.is_minor(date),
  private.can_view_minors(),
  private.can_manage_members()
to authenticated;

-- Tables

create table public.households (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  address text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  constraint households_name_check check (btrim(name) <> '')
);

comment on table public.households is 'A family or home that members belong to, such as The Mensah Family. Archived instead of deleted.';
comment on column public.households.id is 'Unique id of the household.';
comment on column public.households.name is 'Display name of the household.';
comment on column public.households.address is 'Postal or home address. Visible only to super admin, pastor and secretary.';
comment on column public.households.created_at is 'When the household was created.';
comment on column public.households.updated_at is 'When the household was last changed. Maintained by a trigger.';
comment on column public.households.archived_at is 'Set when the household is archived (MEM-05). Null while active. Archived households are visible only to super admin and secretary.';

create table public.members (
  id uuid primary key default gen_random_uuid(),
  household_id uuid references public.households (id),
  first_name text not null,
  last_name text not null,
  phone text,
  email text,
  date_of_birth date,
  gender text,
  marital_status text,
  status public.member_status not null default 'visitor',
  first_visit_on date,
  joined_on date,
  sms_opt_out boolean not null default false,
  consent_recorded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  constraint members_first_name_check check (btrim(first_name) <> ''),
  constraint members_last_name_check check (btrim(last_name) <> '')
);

comment on table public.members is 'Members and visitors in one table (MEM-01, MEM-02). Records of people under the age of majority are visible only to super admin, pastor and the heads of the children''s ministry they belong to. Archived instead of deleted (MEM-05).';
comment on column public.members.id is 'Unique id of the member or visitor.';
comment on column public.members.household_id is 'The household the person belongs to, if any.';
comment on column public.members.first_name is 'Given name.';
comment on column public.members.last_name is 'Family name.';
comment on column public.members.phone is 'Contact number. Personal data: never shown to ushers or the treasurer.';
comment on column public.members.email is 'Contact email address. Personal data: never shown to ushers or the treasurer.';
comment on column public.members.date_of_birth is 'Date of birth. Decides whether the record is a minor''s (private.is_minor). Unknown counts as a minor.';
comment on column public.members.gender is 'Gender, free text as the person gives it.';
comment on column public.members.marital_status is 'Marital status, free text as the person gives it.';
comment on column public.members.status is 'visitor, active, inactive, transferred or deceased.';
comment on column public.members.first_visit_on is 'Day of the first visit, for visitors (MEM-02).';
comment on column public.members.joined_on is 'Day the person joined the church.';
comment on column public.members.sms_opt_out is 'True when the person asked not to receive SMS (MSG-04).';
comment on column public.members.consent_recorded_at is 'When the person consented to the church holding their data. Null when no consent is recorded.';
comment on column public.members.created_at is 'When the record was created.';
comment on column public.members.updated_at is 'When the record was last changed. Maintained by a trigger.';
comment on column public.members.archived_at is 'Set when the record is archived (MEM-05). Null while active. Archived records are visible only to super admin and, for adults, secretary.';

create index members_household_id_idx on public.members (household_id);
create index members_status_idx on public.members (status);
create index members_last_name_first_name_idx on public.members (last_name, first_name);
create index members_archived_at_idx on public.members (archived_at);

create table public.member_departments (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members (id),
  department_id uuid not null references public.departments (id),
  constraint member_departments_member_department_key unique (member_id, department_id)
);

comment on table public.member_departments is 'Which departments a member belongs to (MEM-03). A surrogate id is used so the audit trigger can record the row.';
comment on column public.member_departments.id is 'Surrogate id of the link, so the audit trigger can record it.';
comment on column public.member_departments.member_id is 'The member.';
comment on column public.member_departments.department_id is 'The department the member belongs to.';

create index member_departments_department_id_idx on public.member_departments (department_id);

-- Defined here because a SQL function body is checked when it is created and needs member_departments.
create function private.heads_department_of_member(p_member_id uuid, p_is_minor boolean)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.member_departments as membership
    join public.departments on departments.id = membership.department_id
    where membership.member_id = p_member_id
      and private.heads_department(membership.department_id)
      and (not p_is_minor or departments.is_childrens_ministry)
  );
$$;

comment on function private.heads_department_of_member(uuid, boolean) is 'True when the signed-in user heads a department the member belongs to. For a minor the department must be a children''s ministry. Reads member_departments as owner so the members policy does not recurse.';

revoke execute on function private.heads_department_of_member(uuid, boolean) from public, anon, authenticated;
grant execute on function private.heads_department_of_member(uuid, boolean) to authenticated;

create table public.visitor_followups (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members (id),
  assigned_to uuid references public.staff (id),
  status text not null default 'pending',
  notes text,
  due_on date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint visitor_followups_status_check check (status in ('pending', 'contacted', 'done'))
);

comment on table public.visitor_followups is 'A follow-up task for a visitor (MEM-02): who contacts them and how far it got.';
comment on column public.visitor_followups.id is 'Unique id of the follow-up.';
comment on column public.visitor_followups.member_id is 'The visitor to follow up.';
comment on column public.visitor_followups.assigned_to is 'The staff member who does the follow-up.';
comment on column public.visitor_followups.status is 'pending, contacted or done.';
comment on column public.visitor_followups.notes is 'Free-text notes about the follow-up. May be personal: keep it short.';
comment on column public.visitor_followups.due_on is 'Day the follow-up is due.';
comment on column public.visitor_followups.created_at is 'When the follow-up was created.';
comment on column public.visitor_followups.updated_at is 'When the follow-up was last changed. Maintained by a trigger.';

create index visitor_followups_member_id_idx on public.visitor_followups (member_id);
create index visitor_followups_assigned_to_idx on public.visitor_followups (assigned_to);
create index visitor_followups_status_idx on public.visitor_followups (status);

create trigger households_updated_at
  before update on public.households
  for each row execute function private.set_updated_at();

create trigger members_updated_at
  before update on public.members
  for each row execute function private.set_updated_at();

create trigger visitor_followups_updated_at
  before update on public.visitor_followups
  for each row execute function private.set_updated_at();

-- The foreign key LBC-17 left out because members did not exist yet.
alter table public.staff
  add constraint staff_member_id_fkey foreign key (member_id) references public.members (id);

-- Name every relationship so the GraphQL fields are stable (see LBC-17: duplicates resolve silently wrong).
comment on constraint members_household_id_fkey on public.members is
  e'@graphql({"foreign_name": "household", "local_name": "membersCollection"})';
comment on constraint member_departments_member_id_fkey on public.member_departments is
  e'@graphql({"foreign_name": "member", "local_name": "memberDepartmentsCollection"})';
comment on constraint member_departments_department_id_fkey on public.member_departments is
  e'@graphql({"foreign_name": "department", "local_name": "memberDepartmentsCollection"})';
comment on constraint visitor_followups_member_id_fkey on public.visitor_followups is
  e'@graphql({"foreign_name": "member", "local_name": "visitorFollowupsCollection"})';
comment on constraint visitor_followups_assigned_to_fkey on public.visitor_followups is
  e'@graphql({"foreign_name": "assignedStaff", "local_name": "assignedVisitorFollowupsCollection"})';
comment on constraint staff_member_id_fkey on public.staff is
  e'@graphql({"foreign_name": "member", "local_name": "staffCollection"})';

-- Audit triggers (AFTER, and ENABLE ALWAYS so replica mode cannot skip them), as LBC-21 did.

create trigger audit_households
  after insert or update or delete on public.households
  for each row execute function audit.record_change();

create trigger audit_members
  after insert or update or delete on public.members
  for each row execute function audit.record_change();

create trigger audit_member_departments
  after insert or update or delete on public.member_departments
  for each row execute function audit.record_change();

create trigger audit_visitor_followups
  after insert or update or delete on public.visitor_followups
  for each row execute function audit.record_change();

alter table public.households enable always trigger audit_households;
alter table public.members enable always trigger audit_members;
alter table public.member_departments enable always trigger audit_member_departments;
alter table public.visitor_followups enable always trigger audit_visitor_followups;

-- Row level security and grants. Supabase grants new public tables to anon and authenticated by default.

alter table public.households enable row level security;
alter table public.members enable row level security;
alter table public.member_departments enable row level security;
alter table public.visitor_followups enable row level security;

revoke all on table public.households, public.members, public.member_departments, public.visitor_followups
  from public, anon, authenticated;

-- No DELETE on members, households or visitor_followups for anyone. Membership rows can be removed: the link has
-- no history of its own and the audit log keeps the old row.
grant select on public.households, public.members, public.member_departments, public.visitor_followups to authenticated;
grant insert (name, address), update (name, address, archived_at) on public.households to authenticated;
grant insert (
  household_id, first_name, last_name, phone, email, date_of_birth, gender, marital_status, status,
  first_visit_on, joined_on, sms_opt_out, consent_recorded_at
), update (
  household_id, first_name, last_name, phone, email, date_of_birth, gender, marital_status, status,
  first_visit_on, joined_on, sms_opt_out, consent_recorded_at, archived_at
) on public.members to authenticated;
grant insert (member_id, department_id), delete on public.member_departments to authenticated;
grant insert (member_id, assigned_to, status, notes, due_on), update (assigned_to, status, notes, due_on)
  on public.visitor_followups to authenticated;

-- members

create policy members_select_super_admin on public.members for select to authenticated
  using ((select private.has_role('super_admin')));

create policy members_select_pastor on public.members for select to authenticated
  using ((select private.has_role('pastor')) and archived_at is null);

create policy members_select_secretary on public.members for select to authenticated
  using ((select private.has_role('secretary')) and not private.is_minor(date_of_birth));

create policy members_select_department_head on public.members for select to authenticated
  using (archived_at is null and private.heads_department_of_member(id, private.is_minor(date_of_birth)));

create policy members_insert_super_admin on public.members for insert to authenticated
  with check ((select private.has_role('super_admin')));

create policy members_insert_secretary on public.members for insert to authenticated
  with check ((select private.has_role('secretary')) and not private.is_minor(date_of_birth));

create policy members_update_super_admin on public.members for update to authenticated
  using ((select private.has_role('super_admin')))
  with check ((select private.has_role('super_admin')));

create policy members_update_secretary on public.members for update to authenticated
  using ((select private.has_role('secretary')) and not private.is_minor(date_of_birth))
  with check ((select private.has_role('secretary')) and not private.is_minor(date_of_birth));

-- households (addresses): pastor sees active ones, super admin and secretary all

create policy households_select_super_admin on public.households for select to authenticated
  using ((select private.has_role('super_admin')));

create policy households_select_pastor on public.households for select to authenticated
  using ((select private.has_role('pastor')) and archived_at is null);

create policy households_select_secretary on public.households for select to authenticated
  using ((select private.has_role('secretary')));

create policy households_insert_office on public.households for insert to authenticated
  with check ((select private.can_manage_members()));

create policy households_update_office on public.households for update to authenticated
  using ((select private.can_manage_members()))
  with check ((select private.can_manage_members()));

-- member_departments: a row is visible only with its member (the exists runs the members policies as the caller),
-- and a department head sees only the rows of the departments they head, never a member's other departments.

create policy member_departments_select_leadership on public.member_departments for select to authenticated
  using (
    (select private.has_any_role(array['super_admin', 'pastor', 'secretary']::public.app_role[]))
    and exists (select 1 from public.members where members.id = member_departments.member_id)
  );

create policy member_departments_select_department_head on public.member_departments for select to authenticated
  using (
    private.heads_department(department_id)
    and exists (select 1 from public.members where members.id = member_departments.member_id)
  );

create policy member_departments_insert_office on public.member_departments for insert to authenticated
  with check (
    (select private.can_manage_members())
    and exists (select 1 from public.members where members.id = member_departments.member_id)
  );

create policy member_departments_delete_office on public.member_departments for delete to authenticated
  using (
    (select private.can_manage_members())
    and exists (select 1 from public.members where members.id = member_departments.member_id)
  );

-- visitor_followups: follows the visibility of the member, so a secretary never touches a minor's follow-up

create policy visitor_followups_select_leadership on public.visitor_followups for select to authenticated
  using (
    (select private.has_any_role(array['super_admin', 'pastor', 'secretary']::public.app_role[]))
    and exists (select 1 from public.members where members.id = visitor_followups.member_id)
  );

create policy visitor_followups_insert_office on public.visitor_followups for insert to authenticated
  with check (
    (select private.can_manage_members())
    and exists (select 1 from public.members where members.id = visitor_followups.member_id)
  );

create policy visitor_followups_update_office on public.visitor_followups for update to authenticated
  using (
    (select private.can_manage_members())
    and exists (select 1 from public.members where members.id = visitor_followups.member_id)
  )
  with check (
    (select private.can_manage_members())
    and exists (select 1 from public.members where members.id = visitor_followups.member_id)
  );

-- member_names: RLS works on rows, not columns, so ushers and the treasurer get no policy on members. This view
-- runs with its owner's rights (it must read members past RLS) and checks the caller's role itself. It lists
-- active people only, and minors only for the roles that may see every minor. security_barrier makes the view
-- filter run before any condition the caller adds, so an error message cannot leak a name that is filtered out.
create view public.member_names
with (security_invoker = false, security_barrier = true)
as
select members.id, members.first_name, members.last_name, members.status
from public.members
where (select private.has_any_role(array['usher', 'treasurer']::public.app_role[]))
  and members.archived_at is null
  and (not private.is_minor(members.date_of_birth) or (select private.can_view_minors()));

comment on view public.member_names is
  e'@graphql({"primary_key_columns": ["id"], "description": "Names and status of active members for ushers and the treasurer. Returns nothing to any other role. Minors are listed only to roles that may see every minor, and people with no date of birth are treated as minors."})';
comment on column public.member_names.id is 'The member id.';
comment on column public.member_names.first_name is 'Given name.';
comment on column public.member_names.last_name is 'Family name.';
comment on column public.member_names.status is 'visitor, active, inactive, transferred or deceased.';

revoke all on table public.member_names from public, anon, authenticated;
grant select on public.member_names to authenticated;
