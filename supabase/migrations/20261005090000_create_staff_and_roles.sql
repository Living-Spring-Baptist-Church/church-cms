-- Identity and access (LBC-17): app_role, departments, staff, staff_roles, the private RLS helpers,
-- the policies that use them and the grant_role / revoke_role functions.
-- Source: docs/system-design.md, sections "Identity & access" and "Permissions (row-level security)".
--
-- Rule note: backend.md section 5 says a function should be the only path for a business rule. For the last
-- super admin invariant that is met through triggers instead, which also protect direct DML and the table owner.
--
-- Two things are deliberately NOT here yet:
--   * The audit trigger (audit.record_change()) is attached to these tables by LBC-21, which creates
--     the audit schema objects. The structural test already requires it as soon as the function exists.
--   * The foreign key staff.member_id -> members(id). The members table does not exist yet, so the
--     members migration adds the constraint (system design: "or the foreign key is added in a later migration").

create type public.app_role as enum (
  'super_admin',
  'pastor',
  'treasurer',
  'secretary',
  'usher',
  'department_head',
  'content_editor'
);

comment on type public.app_role is 'Role a staff member can hold. A staff member can hold several. department_head is scoped to one department.';

create table public.departments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_childrens_ministry boolean not null default false,
  archived_at timestamptz
);

comment on table public.departments is 'Church departments such as Choir or Youth. Archived instead of deleted so history and links survive.';
comment on column public.departments.name is 'Unique display name of the department.';
comment on column public.departments.is_childrens_ministry is 'True when heads of this department may see the records of minors.';
comment on column public.departments.archived_at is 'Set when the department is retired. Null while active.';

create table public.staff (
  id uuid primary key references auth.users (id),
  full_name text not null,
  phone text,
  member_id uuid,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.staff is 'Profile and status of a person who can sign in to the dashboard. Keyed to the Supabase Auth user; credentials never live here. Deactivated, never deleted.';
comment on column public.staff.id is 'The Supabase Auth user id.';
comment on column public.staff.full_name is 'Name shown in the dashboard.';
comment on column public.staff.phone is 'Optional contact number.';
comment on column public.staff.member_id is 'Optional link to the member record of the same person.';
comment on column public.staff.is_active is 'False once the account is deactivated. Inactive staff are treated as holding no roles and see nothing; their rows remain.';

create index staff_member_id_idx on public.staff (member_id);

create trigger staff_updated_at
  before update on public.staff
  for each row execute function private.set_updated_at();

create table public.staff_roles (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff (id),
  role public.app_role not null,
  department_id uuid references public.departments (id),
  granted_by uuid references public.staff (id),
  granted_at timestamptz not null default now(),
  constraint staff_roles_staff_role_department_key unique nulls not distinct (staff_id, role, department_id),
  constraint staff_roles_department_matches_role_check check ((role = 'department_head') = (department_id is not null))
);

comment on table public.staff_roles is 'Roles held by staff. Granted and revoked through grant_role and revoke_role, which a super admin calls; a super admin may also insert and delete rows directly. The last active super admin can never be removed on any path.';
comment on column public.staff_roles.staff_id is 'The staff member who holds the role.';
comment on column public.staff_roles.role is 'The role held.';
comment on column public.staff_roles.department_id is 'The department headed. Required for department_head and forbidden for every other role.';
comment on column public.staff_roles.granted_by is 'The super admin who granted the role. Null for the first super admin created at setup.';
comment on column public.staff_roles.granted_at is 'When the role was granted.';

create index staff_roles_department_id_idx on public.staff_roles (department_id);
create index staff_roles_granted_by_idx on public.staff_roles (granted_by);

-- Two foreign keys point at staff, so name the GraphQL relationships explicitly. Without this both fields are
-- called staff on StaffRoles and the API silently resolves the wrong one.
comment on constraint staff_roles_staff_id_fkey on public.staff_roles is
  e'@graphql({"foreign_name": "staff", "local_name": "staffRolesCollection"})';
comment on constraint staff_roles_granted_by_fkey on public.staff_roles is
  e'@graphql({"foreign_name": "grantedByStaff", "local_name": "grantedRolesCollection"})';

-- Helpers. They are SECURITY DEFINER because they must read staff_roles and staff whatever the caller may
-- see, and policies on those same tables call them (reading them with RLS on would recurse).

create function private.has_any_role(p_roles public.app_role[])
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.staff_roles as staff_role
    join public.staff on staff.id = staff_role.staff_id
    where staff_role.staff_id = (select auth.uid())
      and staff_role.role = any (p_roles)
      and staff.is_active
  );
$$;

create function private.has_role(p_role public.app_role)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_any_role(array[p_role]);
$$;

create function private.heads_department(p_department_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.staff_roles as staff_role
    join public.staff on staff.id = staff_role.staff_id
    where staff_role.staff_id = (select auth.uid())
      and staff_role.role = 'department_head'
      and staff_role.department_id = p_department_id
      and staff.is_active
  );
$$;

create function private.is_active_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.staff
    where staff.id = (select auth.uid())
      and staff.is_active
  );
$$;

comment on function private.has_any_role(public.app_role[]) is 'True when the signed-in user is active staff holding at least one of the roles. Inactive staff hold none.';
comment on function private.has_role(public.app_role) is 'True when the signed-in user is active staff holding the role.';
comment on function private.heads_department(uuid) is 'True when the signed-in user is active staff and head of the department.';
comment on function private.is_active_staff() is 'True when the signed-in user has an active staff profile, whatever roles they hold.';

-- Last super admin protection. Lives in triggers so it holds on every path (the functions below, direct DML
-- by a super admin, the service role). The advisory lock serialises concurrent attempts: the second waits,
-- then re-reads the committed state and fails, so two parallel removals cannot both succeed.

create function private.super_admin_lock_key()
returns bigint
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.hashtextextended('lbc.last_super_admin', 0);
$$;

comment on function private.super_admin_lock_key() is 'Advisory lock key that serialises every change which could remove an active super admin.';

create function private.assert_super_admin_remains(p_departing_staff_id uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(private.super_admin_lock_key());

  if exists (
       select 1
       from public.staff_roles as staff_role
       join public.staff on staff.id = staff_role.staff_id
       where staff_role.role = 'super_admin' and staff.is_active and staff_role.staff_id = p_departing_staff_id
     )
     and not exists (
       select 1
       from public.staff_roles as staff_role
       join public.staff on staff.id = staff_role.staff_id
       where staff_role.role = 'super_admin' and staff.is_active and staff_role.staff_id <> p_departing_staff_id
     )
  then
    raise exception using
      errcode = 'P0001',
      message = 'STAFF_LAST_SUPER_ADMIN',
      detail = format('Staff %s is the last active super admin', p_departing_staff_id),
      hint = 'Make another active staff member a super admin first';
  end if;
end;
$$;

comment on function private.assert_super_admin_remains(uuid) is 'Raises STAFF_LAST_SUPER_ADMIN when the staff member is the only active super admin. Takes the advisory lock first so concurrent removals queue up.';

create function private.guard_super_admin_role_change()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform private.assert_super_admin_remains(old.staff_id);
  return case tg_op when 'DELETE' then old else new end;
end;
$$;

create function private.guard_super_admin_deactivation()
returns trigger
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  perform private.assert_super_admin_remains(old.id);
  return new;
end;
$$;

comment on function private.guard_super_admin_role_change() is 'Trigger on staff_roles: a super_admin row may not be deleted or moved away while it is the last one.';
comment on function private.guard_super_admin_deactivation() is 'Trigger on staff: the last active super admin may not be deactivated.';

create trigger staff_roles_protect_last_super_admin_delete
  before delete on public.staff_roles
  for each row
  when (old.role = 'super_admin')
  execute function private.guard_super_admin_role_change();

create trigger staff_roles_protect_last_super_admin_update
  before update of role, staff_id on public.staff_roles
  for each row
  when (old.role = 'super_admin' and (new.role <> old.role or new.staff_id <> old.staff_id))
  execute function private.guard_super_admin_role_change();

create trigger staff_protect_last_super_admin
  before update of is_active on public.staff
  for each row
  when (old.is_active and not new.is_active)
  execute function private.guard_super_admin_deactivation();

-- Function privileges: nothing is callable by default. Only the helpers that policies and public functions
-- evaluate as the signed-in user are granted to authenticated. Schema USAGE is not granted: policies are
-- stored with resolved function ids, so execute is the only privilege checked.

revoke execute on function
  private.has_any_role(public.app_role[]),
  private.has_role(public.app_role),
  private.heads_department(uuid),
  private.is_active_staff(),
  private.super_admin_lock_key(),
  private.assert_super_admin_remains(uuid),
  private.guard_super_admin_role_change(),
  private.guard_super_admin_deactivation()
from public, anon, authenticated;

grant execute on function
  private.has_any_role(public.app_role[]),
  private.has_role(public.app_role),
  private.heads_department(uuid),
  private.is_active_staff()
to authenticated;

-- Table privileges: Supabase grants new public tables to anon and authenticated by default. Start from nothing.

alter table public.departments enable row level security;
alter table public.staff enable row level security;
alter table public.staff_roles enable row level security;

revoke all on table public.departments, public.staff, public.staff_roles from public, anon, authenticated;

grant select on public.departments to authenticated;
grant insert (name, is_childrens_ministry), update (name, is_childrens_ministry, archived_at) on public.departments to authenticated;

grant select on public.staff to authenticated;
grant update (full_name, phone, member_id, is_active) on public.staff to authenticated;

grant select, insert, delete on public.staff_roles to authenticated;

-- Policies (PRD matrix: "Settings & users" is edited by super admin only; the pastor has no access to users).

create policy departments_select_staff on public.departments for select to authenticated
  using ((select private.has_any_role(enum_range(null::public.app_role))));

create policy departments_insert_super_admin on public.departments for insert to authenticated
  with check ((select private.has_role('super_admin')));

create policy departments_update_super_admin on public.departments for update to authenticated
  using ((select private.has_role('super_admin')))
  with check ((select private.has_role('super_admin')));

create policy staff_select_self on public.staff for select to authenticated
  using (id = (select auth.uid()) and (select private.is_active_staff()));

create policy staff_select_super_admin on public.staff for select to authenticated
  using ((select private.has_role('super_admin')));

create policy staff_update_super_admin on public.staff for update to authenticated
  using ((select private.has_role('super_admin')))
  with check ((select private.has_role('super_admin')));

create policy staff_roles_select_self on public.staff_roles for select to authenticated
  using (staff_id = (select auth.uid()) and (select private.is_active_staff()));

create policy staff_roles_select_super_admin on public.staff_roles for select to authenticated
  using ((select private.has_role('super_admin')));

create policy staff_roles_insert_super_admin on public.staff_roles for insert to authenticated
  with check (
    (select private.has_role('super_admin'))
    and granted_by = (select auth.uid())
    and exists (select 1 from public.staff where staff.id = staff_roles.staff_id and staff.is_active)
  );

create policy staff_roles_delete_super_admin on public.staff_roles for delete to authenticated
  using ((select private.has_role('super_admin')));

-- grant_role / revoke_role: SECURITY DEFINER because the private schema is closed to app roles (no USAGE),
-- so an invoker function could not call private.has_role. The explicit super admin check below is therefore
-- the gate, and it runs before anything else. Volatile, so pg_graphql exposes them as mutations.
-- The role arrives as text, not app_role: pg_graphql 1.6 leaves out any function with an enum argument,
-- so an app_role parameter would hide both mutations from the API. private.parse_app_role casts it safely.

create function private.parse_app_role(p_role text)
returns public.app_role
language plpgsql
stable
set search_path = ''
as $$
begin
  if p_role is null or not (p_role = any (enum_range(null::public.app_role)::text[])) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = 'role must be one of the app_role values';
  end if;
  return p_role::public.app_role;
end;
$$;

comment on function private.parse_app_role(text) is 'Casts text to app_role, raising VALIDATION_FAILED instead of a raw cast error.';

revoke execute on function private.parse_app_role(text) from public, anon, authenticated;

create function public.grant_role(p_staff_id uuid, p_role text, p_department_id uuid default null)
returns public.staff_roles
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_role public.app_role;
  v_staff public.staff;
  v_department public.departments;
  v_granted public.staff_roles;
begin
  if not private.has_role('super_admin') then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN',
      detail = 'Only a super admin can grant roles';
  end if;

  v_role := private.parse_app_role(p_role);

  if (v_role = 'department_head') is distinct from (p_department_id is not null) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = 'department_id is required for department_head and must be empty for every other role';
  end if;

  select * into v_staff from public.staff where id = p_staff_id;
  if not found then
    raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'No staff member with that id';
  end if;
  if not v_staff.is_active then
    raise exception using errcode = 'P0001', message = 'STAFF_INACTIVE',
      detail = 'Roles cannot be granted to a deactivated staff member';
  end if;

  if p_department_id is not null then
    select * into v_department from public.departments where id = p_department_id;
    if not found then
      raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'No department with that id';
    end if;
    if v_department.archived_at is not null then
      raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
        detail = 'department_id names an archived department';
    end if;
  end if;

  insert into public.staff_roles (staff_id, role, department_id, granted_by)
  values (p_staff_id, v_role, p_department_id, (select auth.uid()))
  on conflict on constraint staff_roles_staff_role_department_key do nothing
  returning * into v_granted;

  if not found then
    raise exception using errcode = 'P0001', message = 'STAFF_ROLE_ALREADY_GRANTED',
      detail = 'The staff member already holds this role';
  end if;

  return v_granted;
end;
$$;

create function public.revoke_role(p_staff_id uuid, p_role text, p_department_id uuid default null)
returns public.staff_roles
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_role public.app_role;
  v_revoked public.staff_roles;
begin
  if not private.has_role('super_admin') then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN',
      detail = 'Only a super admin can revoke roles';
  end if;

  v_role := private.parse_app_role(p_role);

  -- The staff_roles delete trigger raises STAFF_LAST_SUPER_ADMIN when this would remove the last one.
  delete from public.staff_roles
  where staff_id = p_staff_id
    and role = v_role
    and department_id is not distinct from p_department_id
  returning * into v_revoked;

  if not found then
    raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'The staff member does not hold this role';
  end if;

  return v_revoked;
end;
$$;

comment on function public.grant_role(uuid, text, uuid) is 'Grants a role (an app_role value as text) to an active staff member and returns the new row. Super admin only. department_head needs an active department; other roles must not have one. Errors: AUTH_FORBIDDEN, VALIDATION_FAILED, NOT_FOUND, STAFF_INACTIVE, STAFF_ROLE_ALREADY_GRANTED.';
comment on function public.revoke_role(uuid, text, uuid) is 'Removes a role (an app_role value as text) from a staff member and returns the removed row. Super admin only. Refuses to remove the last active super admin. Errors: AUTH_FORBIDDEN, VALIDATION_FAILED, NOT_FOUND, STAFF_LAST_SUPER_ADMIN.';

revoke execute on function public.grant_role(uuid, text, uuid), public.revoke_role(uuid, text, uuid)
  from public, anon;
grant execute on function public.grant_role(uuid, text, uuid), public.revoke_role(uuid, text, uuid)
  to authenticated;
