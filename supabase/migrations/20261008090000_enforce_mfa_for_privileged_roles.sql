-- Two-factor enforcement in the database (LBC-41).
-- PRD NFR Authentication: super admin, pastor and treasurer need two-factor. Until now only the dashboard
-- enforced it, so a password-only (aal1) access token could call the GraphQL API directly and read data.
-- From here the role helpers treat those roles as NOT held unless the JWT claim aal is exactly 'aal2'.
-- Every policy and every function already goes through the helpers, so changing them covers all of them.
-- The same list lives in apps/dashboard/src/core/auth/roles.ts (MFA_REQUIRED_ROLES): change both together.
--
-- Own profile exception: private.is_active_staff() deliberately ignores aal. The staff_select_self and
-- staff_roles_select_self policies use it, so a signed-in user at aal1 can still read their own staff row and
-- their own roles. The login flow needs that read to decide whether to enrol or challenge for a code.

-- The one definition of which roles need two-factor. A role added here is enforced everywhere at once.
create function private.mfa_required_roles()
returns public.app_role[]
language sql
immutable
set search_path = ''
as $$
  select array['super_admin', 'pastor', 'treasurer']::public.app_role[];
$$;

comment on function private.mfa_required_roles() is 'Roles that count as held only in a session at assurance level aal2 (PRD: super admin, pastor, treasurer). Must equal MFA_REQUIRED_ROLES in apps/dashboard/src/core/auth/roles.ts.';

-- The JWT claim value Supabase Auth sets once a second factor has been verified.
create function private.required_assurance_level()
returns text
language sql
immutable
set search_path = ''
as $$
  select 'aal2'::text;
$$;

comment on function private.required_assurance_level() is 'Value of the JWT aal claim that proves a verified second factor.';

-- Fails closed: missing, empty, malformed or non-object claims, a missing aal claim and every value other than
-- exactly aal2 all give false. pg_input_is_valid stops a malformed claims string from raising, and CASE keeps the
-- cast from running before that check.
create function private.is_aal2()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce(
    case
      when pg_catalog.pg_input_is_valid(nullif(pg_catalog.current_setting('request.jwt.claims', true), ''), 'jsonb')
        then (nullif(pg_catalog.current_setting('request.jwt.claims', true), '')::jsonb ->> 'aal')
    end = private.required_assurance_level(),
    false
  );
$$;

comment on function private.is_aal2() is 'True only when the request JWT claims carry aal exactly aal2. False for missing, malformed or unexpected claims.';

create function private.is_role_usable(p_role public.app_role)
returns boolean
language sql
stable
set search_path = ''
as $$
  select not (p_role = any (private.mfa_required_roles())) or private.is_aal2();
$$;

comment on function private.is_role_usable(public.app_role) is 'True when a held role may be used in this session: roles outside mfa_required_roles always, the others only at aal2.';

-- Same shape as before, plus the aal rule. A user holding a two-factor role and another role at aal1 keeps
-- only the other role, because the check is per role row.
create or replace function private.has_any_role(p_roles public.app_role[])
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
      and private.is_role_usable(staff_role.role)
  );
$$;

create or replace function private.heads_department(p_department_id uuid)
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
      and private.is_role_usable(staff_role.role)
  );
$$;

comment on function private.has_any_role(public.app_role[]) is 'True when the signed-in user is active staff holding at least one of the roles in a usable form: roles in mfa_required_roles count only at aal2. Inactive staff hold none.';
comment on function private.has_role(public.app_role) is 'True when the signed-in user is active staff holding the role in a usable form (see has_any_role).';
comment on function private.heads_department(uuid) is 'True when the signed-in user is active staff and head of the department in a usable form (see has_any_role).';
comment on function private.is_active_staff() is 'True when the signed-in user has an active staff profile, whatever roles they hold and whatever the aal. Gates only the own-profile reads that the login flow needs before two-factor is complete; never use it to grant business data.';

-- For the audit event writer: an active staff member whose session satisfies their own two-factor requirement.
-- Unlike has_any_role this does not need a role, so active staff with no role (and non two-factor staff at aal1)
-- keep the behaviour they had, while anyone holding a two-factor role is refused until the session is aal2.
create function private.has_dashboard_session()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.is_active_staff()
    and (
      private.is_aal2()
      or not exists (
        select 1
        from public.staff_roles as staff_role
        where staff_role.staff_id = (select auth.uid())
          and staff_role.role = any (private.mfa_required_roles())
      )
    );
$$;

comment on function private.has_dashboard_session() is 'True when the signed-in user is active staff and, if they hold any role in mfa_required_roles, the session is aal2.';

revoke execute on function
  private.mfa_required_roles(),
  private.required_assurance_level(),
  private.is_aal2(),
  private.is_role_usable(public.app_role),
  private.has_dashboard_session()
from public, anon, authenticated;

-- audit.log_event used is_active_staff, which would let a pastor at aal1 write audit rows. Only the guard changes.
create or replace function audit.log_event(
  p_action text,
  p_table_name text,
  p_record_id uuid default null,
  p_details jsonb default null
)
returns uuid
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_record_id uuid;
begin
  if v_actor_id is null or not private.has_dashboard_session() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN',
      detail = 'Only signed-in active staff can log an event';
  end if;

  if p_action is null or not (p_action = any (audit.event_actions())) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = 'action must be LOGIN or EXPORT';
  end if;

  if p_table_name is null
     or not exists (select 1 from pg_catalog.pg_tables where schemaname = 'public' and tablename = p_table_name)
  then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = 'table_name must name a table in the public schema';
  end if;

  if p_details is not null
     and (jsonb_typeof(p_details) <> 'object' or octet_length(p_details::text) > audit.max_event_details_bytes())
  then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = format('details must be a JSON object of at most %s bytes', audit.max_event_details_bytes());
  end if;

  if p_action = audit.login_action() then
    if p_record_id is not null and p_record_id <> v_actor_id then
      raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
        detail = 'A login can only be logged for the signed-in user';
    end if;
    v_record_id := v_actor_id;
  else
    v_record_id := coalesce(p_record_id, gen_random_uuid());
  end if;

  insert into audit.log (actor_id, table_name, record_id, action, new_data)
  values (v_actor_id, p_table_name, v_record_id, p_action, p_details);

  return v_record_id;
end;
$$;

comment on function audit.log_event(text, text, uuid, jsonb) is 'Records a LOGIN or EXPORT event for the signed-in active staff member (actor is always auth.uid(), never a parameter) and returns the record id. Staff holding a two-factor role must be at aal2. LOGIN is always about the caller; EXPORT gets a new export id unless one is given. Errors: AUTH_FORBIDDEN, VALIDATION_FAILED.';
