-- LBC-17: shape of the identity tables, the department_head check constraint, grants,
-- and the behaviour of the private role helpers (including inactive staff and wrong departments).

begin;

select plan(47);

-- Fixture: start from an empty identity model so the demo seed cannot influence the results.
set local session_replication_role = replica;
delete from public.staff_roles;
delete from public.staff;
delete from public.departments;
set local session_replication_role = origin;

create function pg_temp.claim_as(p_staff_id uuid)
returns text
language sql
as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_staff_id, 'role', 'authenticated')::text, true);
$$;

insert into auth.users (id, aud, role, email)
values
  ('30000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'admin@test.invalid'),
  ('30000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'office@test.invalid'),
  ('30000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'head@test.invalid'),
  ('30000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'former@test.invalid');

insert into public.departments (id, name)
values
  ('40000000-0000-4000-8000-000000000001', 'Choir'),
  ('40000000-0000-4000-8000-000000000002', 'Youth');

insert into public.staff (id, full_name, is_active)
values
  ('30000000-0000-4000-8000-000000000001', 'Test Admin', true),
  ('30000000-0000-4000-8000-000000000002', 'Test Office', true),
  ('30000000-0000-4000-8000-000000000003', 'Test Head', true),
  ('30000000-0000-4000-8000-000000000004', 'Test Former', false);

insert into public.staff_roles (staff_id, role, department_id)
values
  ('30000000-0000-4000-8000-000000000001', 'super_admin', null),
  ('30000000-0000-4000-8000-000000000002', 'pastor', null),
  ('30000000-0000-4000-8000-000000000002', 'secretary', null),
  ('30000000-0000-4000-8000-000000000003', 'department_head', '40000000-0000-4000-8000-000000000001'),
  ('30000000-0000-4000-8000-000000000004', 'pastor', null),
  ('30000000-0000-4000-8000-000000000004', 'department_head', '40000000-0000-4000-8000-000000000001');

-- Shape (AC 1)

select is(
  (select array_agg(enumlabel::text order by enumsortorder) from pg_enum where enumtypid = 'public.app_role'::regtype),
  array['super_admin', 'pastor', 'treasurer', 'secretary', 'usher', 'department_head', 'content_editor'],
  'should define app_role with the seven roles of the permission matrix'
);

select columns_are('public', 'departments', array['id', 'name', 'is_childrens_ministry', 'archived_at'], 'should give departments exactly the system design columns');
select columns_are('public', 'staff', array['id', 'full_name', 'phone', 'member_id', 'is_active', 'created_at', 'updated_at'], 'should give staff exactly the system design columns');
select columns_are('public', 'staff_roles', array['id', 'staff_id', 'role', 'department_id', 'granted_by', 'granted_at'], 'should give staff_roles exactly the system design columns');

select fk_ok('public', 'staff', 'id', 'auth', 'users', 'id', 'should key staff to auth.users');
select fk_ok('public', 'staff_roles', 'staff_id', 'public', 'staff', 'id', 'should link staff_roles to the staff member');
select fk_ok('public', 'staff_roles', 'department_id', 'public', 'departments', 'id', 'should link staff_roles to the department');
select fk_ok('public', 'staff_roles', 'granted_by', 'public', 'staff', 'id', 'should link staff_roles to the granting staff member');

select is(
  (select count(*) from pg_class where oid in ('public.departments'::regclass, 'public.staff'::regclass, 'public.staff_roles'::regclass) and relrowsecurity),
  3::bigint,
  'should enable row level security on departments, staff and staff_roles'
);

select has_trigger('public', 'staff', 'staff_updated_at', 'should stamp staff.updated_at with the shared trigger');

-- Grants: nothing for anon, the minimum for authenticated.

select table_privs_are('public', 'departments', 'anon', array[]::text[], 'should deny anon every privilege on departments');
select table_privs_are('public', 'staff', 'anon', array[]::text[], 'should deny anon every privilege on staff');
select table_privs_are('public', 'staff_roles', 'anon', array[]::text[], 'should deny anon every privilege on staff_roles');
select table_privs_are('public', 'departments', 'authenticated', array['SELECT'], 'should let authenticated select departments and nothing at table level');
select table_privs_are('public', 'staff', 'authenticated', array['SELECT'], 'should let authenticated select staff and nothing at table level');
select table_privs_are('public', 'staff_roles', 'authenticated', array['DELETE', 'INSERT', 'SELECT'], 'should let authenticated select, insert and delete staff_roles but never update');

select function_privs_are('public', 'grant_role', array['uuid', 'text', 'uuid'], 'anon', array[]::text[], 'should deny anon grant_role');
select function_privs_are('public', 'revoke_role', array['uuid', 'text', 'uuid'], 'anon', array[]::text[], 'should deny anon revoke_role');
select function_privs_are('public', 'grant_role', array['uuid', 'text', 'uuid'], 'authenticated', array['EXECUTE'], 'should let authenticated execute grant_role');
select function_privs_are('public', 'revoke_role', array['uuid', 'text', 'uuid'], 'authenticated', array['EXECUTE'], 'should let authenticated execute revoke_role');

select is(
  (select count(*) from pg_proc where pronamespace = 'private'::regnamespace
     and proname in ('has_role', 'has_any_role', 'heads_department', 'is_active_staff')
     and has_function_privilege('authenticated', oid, 'EXECUTE')
     and not has_function_privilege('anon', oid, 'EXECUTE')),
  4::bigint,
  'should let authenticated but not anon execute the four role helpers'
);

select is(
  (select count(*) from pg_proc where pronamespace = 'private'::regnamespace
     and proname in ('super_admin_lock_key', 'parse_app_role', 'assert_super_admin_remains', 'guard_super_admin_role_change', 'guard_super_admin_deactivation')
     and (has_function_privilege('authenticated', oid, 'EXECUTE') or has_function_privilege('anon', oid, 'EXECUTE'))),
  0::bigint,
  'should keep the last super admin internals away from anon and authenticated'
);

select schema_privs_are('private', 'authenticated', array[]::text[], 'should still deny authenticated any access to the private schema');

select is(
  (select count(*) from pg_proc where pronamespace = 'private'::regnamespace
     and proname in ('has_role', 'has_any_role', 'heads_department', 'is_active_staff')
     and prosecdef and provolatile = 's' and proconfig = array['search_path=""']),
  4::bigint,
  'should define the role helpers as stable security definer functions with an empty search_path'
);

-- department_head check constraint (AC 2)

select throws_ok(
  $$ insert into public.staff_roles (staff_id, role) values ('30000000-0000-4000-8000-000000000001', 'department_head') $$,
  '23514', null,
  'should reject a department_head role that names no department'
);

select throws_ok(
  $$ insert into public.staff_roles (staff_id, role, department_id) values ('30000000-0000-4000-8000-000000000001', 'treasurer', '40000000-0000-4000-8000-000000000001') $$,
  '23514', null,
  'should reject a role other than department_head that names a department'
);

select lives_ok(
  $$ insert into public.staff_roles (staff_id, role, department_id) values ('30000000-0000-4000-8000-000000000001', 'department_head', '40000000-0000-4000-8000-000000000002') $$,
  'should accept a department_head role that names a department'
);

select lives_ok(
  $$ insert into public.staff_roles (staff_id, role) values ('30000000-0000-4000-8000-000000000001', 'treasurer') $$,
  'should accept a role other than department_head without a department'
);

select throws_ok(
  $$ insert into public.staff_roles (staff_id, role) values ('30000000-0000-4000-8000-000000000001', 'treasurer') $$,
  '23505', null,
  'should reject the same role twice for one staff member even without a department'
);

select throws_ok(
  $$ insert into public.departments (name) values ('Choir') $$,
  '23505', null,
  'should reject two departments with the same name'
);

-- Helpers (AC 3). Run as the table owner with the JWT claim set: the helpers only read the claim.

select pg_temp.claim_as('30000000-0000-4000-8000-000000000002');

select is(
  (select array_agg(held_role::text order by held_role)
   from unnest(enum_range(null::public.app_role)) as held_role
   where private.has_role(held_role)),
  array['pastor', 'secretary'],
  'should report has_role only for the roles the signed-in staff member holds'
);

select is(private.has_any_role(array['usher', 'secretary']::public.app_role[]), true, 'should report has_any_role when one of several roles is held');
select is(private.has_any_role(array['usher', 'treasurer']::public.app_role[]), false, 'should report no has_any_role when none of the roles is held');
select is(private.has_any_role(array[]::public.app_role[]), false, 'should report no has_any_role for an empty list');
select is(private.has_any_role(null), false, 'should report no has_any_role for a null list');
select is(private.is_active_staff(), true, 'should report active staff as active');
select is(private.heads_department('40000000-0000-4000-8000-000000000001'), false, 'should deny heads_department to staff who hold no department_head role');

select pg_temp.claim_as('30000000-0000-4000-8000-000000000003');
select is(private.heads_department('40000000-0000-4000-8000-000000000001'), true, 'should report heads_department for the department the head leads');
select is(private.heads_department('40000000-0000-4000-8000-000000000002'), false, 'should deny heads_department for a different department');
select is(private.has_role('department_head'), true, 'should report has_role department_head for a department head');
select is(private.has_role('super_admin'), false, 'should deny has_role super_admin to a department head');

select pg_temp.claim_as('30000000-0000-4000-8000-000000000004');
select is(private.has_role('pastor'), false, 'should treat inactive staff as holding no role');
select is(private.has_any_role(enum_range(null::public.app_role)), false, 'should treat inactive staff as holding none of any roles');
select is(private.heads_department('40000000-0000-4000-8000-000000000001'), false, 'should deny heads_department to inactive staff');
select is(private.is_active_staff(), false, 'should report inactive staff as not active');

select pg_temp.claim_as('30000000-0000-4000-8000-0000000000ff');
select is(private.has_any_role(enum_range(null::public.app_role)), false, 'should give an unknown user no roles');

select set_config('request.jwt.claims', '', true);
select is(private.has_any_role(enum_range(null::public.app_role)), false, 'should give a request without a signed-in user no roles');

select * from finish();

rollback;
