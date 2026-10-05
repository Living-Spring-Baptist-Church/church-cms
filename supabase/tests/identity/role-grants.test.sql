-- LBC-17: grant_role and revoke_role, the last-super-admin rule on every path, and inactive staff.
-- Actors run as the real `authenticated` database role with JWT claims set (see staff-access-policies.test.sql).
-- Fixture ids: 50...01 is the only active super admin, 51...01 an inactive super admin, 50...02 an active pastor,
-- 52...01 active staff with no role, 51...02 an inactive pastor.

begin;

select plan(80);

-- Fixture: start from an empty identity model so the demo seed cannot influence the results.
set local session_replication_role = replica;
delete from public.staff_roles;
delete from public.staff;
delete from public.departments;
set local session_replication_role = origin;

create function pg_temp.as_actor(p_db_role name, p_staff_id uuid, p_statement text)
returns bigint
language plpgsql
as $$
declare
  v_original name := current_user;
  v_rows bigint;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_db_role, 'sub', p_staff_id)::text, true);
  perform set_config('role', p_db_role::text, true);
  execute p_statement;
  get diagnostics v_rows = row_count;
  perform set_config('role', v_original::text, true);
  return v_rows;
end;
$$;

create function pg_temp.fails_as(p_staff_id uuid, p_statement text)
returns text
language sql
as $$
  select format('select pg_temp.as_actor(%L, %L, %L)', 'authenticated', p_staff_id, p_statement);
$$;

create function pg_temp.grant_sql(p_staff_id uuid, p_role text, p_department_id uuid default null)
returns text
language sql
as $$
  select format('select public.grant_role(%L, %L, %L)', p_staff_id, p_role, p_department_id);
$$;

create function pg_temp.revoke_sql(p_staff_id uuid, p_role text, p_department_id uuid default null)
returns text
language sql
as $$
  select format('select public.revoke_role(%L, %L, %L)', p_staff_id, p_role, p_department_id);
$$;

create function pg_temp.roles_of(p_staff_id uuid)
returns text
language sql
as $$
  select coalesce(string_agg(role::text, ',' order by role), '') from public.staff_roles where staff_id = p_staff_id;
$$;

create temp table actors as
  select role::text as label, role, true as is_active,
         ('50000000-0000-4000-8000-0000000000' || lpad(position::text, 2, '0'))::uuid as staff_id
  from unnest(enum_range(null::public.app_role)) with ordinality as roles (role, position)
  union all
  select 'inactive_' || role::text, role, false,
         ('51000000-0000-4000-8000-0000000000' || lpad(position::text, 2, '0'))::uuid
  from unnest(enum_range(null::public.app_role)) with ordinality as roles (role, position)
  union all
  select 'no_role', null, true, '52000000-0000-4000-8000-000000000001'::uuid;

insert into auth.users (id, aud, role, email)
select staff_id, 'authenticated', 'authenticated', label || '@test.invalid' from actors;

insert into public.departments (id, name, archived_at)
values
  ('40000000-0000-4000-8000-000000000001', 'Choir', null),
  ('40000000-0000-4000-8000-000000000002', 'Youth', null),
  ('40000000-0000-4000-8000-000000000003', 'Retired', now());

insert into public.staff (id, full_name, is_active)
select staff_id, label, is_active from actors;

insert into public.staff_roles (staff_id, role, department_id)
select staff_id, role, case role when 'department_head' then '40000000-0000-4000-8000-000000000001'::uuid end
from actors
where role is not null;

-- Only an active super admin may call either function (AC 4, AC 6)

select throws_ok(
  pg_temp.fails_as(staff_id, pg_temp.grant_sql('52000000-0000-4000-8000-000000000001', 'treasurer')),
  'P0001', 'AUTH_FORBIDDEN',
  format('should reject %s calling grant_role', label)
) from actors where not (is_active and role = 'super_admin') order by label;

select throws_ok(
  pg_temp.fails_as(staff_id, pg_temp.revoke_sql('50000000-0000-4000-8000-000000000002', 'pastor')),
  'P0001', 'AUTH_FORBIDDEN',
  format('should reject %s calling revoke_role', label)
) from actors where not (is_active and role = 'super_admin') order by label;

select is(pg_temp.roles_of('50000000-0000-4000-8000-000000000002'), 'pastor', 'should leave the pastor role in place after every rejected call');

-- The functions are mutations in the GraphQL API (pg_graphql runs them as the signed-in user)

create function pg_temp.graphql_as(p_db_role name, p_staff_id uuid, p_query text)
returns jsonb
language plpgsql
as $$
declare
  v_original name := current_user;
  v_result jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_db_role, 'sub', p_staff_id)::text, true);
  perform set_config('role', p_db_role::text, true);
  v_result := graphql.resolve(p_query);
  perform set_config('role', v_original::text, true);
  return v_result;
end;
$$;

select is(
  pg_temp.graphql_as('authenticated', '50000000-0000-4000-8000-000000000001', $$mutation { grantRole(pStaffId: "52000000-0000-4000-8000-000000000001", pRole: "content_editor") { role grantedBy } }$$) -> 'data' -> 'grantRole' ->> 'role',
  'content_editor',
  'should expose grant_role as the grantRole mutation'
);

-- Two foreign keys point at staff: the holder is `staff`, the granter is `grantedByStaff` (constraint comments)

select is(
  pg_temp.graphql_as('authenticated', '50000000-0000-4000-8000-000000000001', $$query { staffRolesCollection(filter: { staffId: { eq: "52000000-0000-4000-8000-000000000001" }, role: { eq: content_editor } }) { edges { node { staff { fullName } } } } }$$) #>> '{data,staffRolesCollection,edges,0,node,staff,fullName}',
  'no_role',
  'should resolve StaffRoles.staff to the staff member who holds the role'
);

select is(
  pg_temp.graphql_as('authenticated', '50000000-0000-4000-8000-000000000001', $$query { staffRolesCollection(filter: { staffId: { eq: "52000000-0000-4000-8000-000000000001" }, role: { eq: content_editor } }) { edges { node { grantedByStaff { fullName } } } } }$$) #>> '{data,staffRolesCollection,edges,0,node,grantedByStaff,fullName}',
  'super_admin',
  'should resolve StaffRoles.grantedByStaff to the super admin who granted the role'
);

select is(
  jsonb_array_length(pg_temp.graphql_as('authenticated', '50000000-0000-4000-8000-000000000001', $$query { staffCollection(filter: { id: { eq: "52000000-0000-4000-8000-000000000001" } }) { edges { node { staffRolesCollection { edges { node { id } } } } } } }$$) #> '{data,staffCollection,edges,0,node,staffRolesCollection,edges}'),
  1,
  'should list on Staff.staffRolesCollection the roles the staff member holds'
);

select is(
  jsonb_array_length(pg_temp.graphql_as('authenticated', '50000000-0000-4000-8000-000000000001', $$query { staffCollection(filter: { id: { eq: "50000000-0000-4000-8000-000000000001" } }) { edges { node { grantedRolesCollection { edges { node { id } } } } } } }$$) #> '{data,staffCollection,edges,0,node,grantedRolesCollection,edges}'),
  1,
  'should list on Staff.grantedRolesCollection the roles the staff member granted'
);

select is(
  pg_temp.graphql_as('authenticated', '50000000-0000-4000-8000-000000000001', $$mutation { revokeRole(pStaffId: "52000000-0000-4000-8000-000000000001", pRole: "content_editor") { role } }$$) -> 'data' -> 'revokeRole' ->> 'role',
  'content_editor',
  'should expose revoke_role as the revokeRole mutation'
);

select is(
  pg_temp.graphql_as('authenticated', '50000000-0000-4000-8000-000000000001', $$mutation { grantRole(pStaffId: "52000000-0000-4000-8000-000000000001", pRole: "wizard") { role } }$$) -> 'errors' -> 0 ->> 'message',
  'VALIDATION_FAILED',
  'should return the error code through GraphQL when the role is not an app_role value'
);

select isnt(
  pg_temp.graphql_as('anon', null, $$mutation { grantRole(pStaffId: "52000000-0000-4000-8000-000000000001", pRole: "pastor") { role } }$$) -> 'errors',
  null,
  'should not offer the grantRole mutation to anon'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('52000000-0000-4000-8000-000000000001', 'wizard')),
  'P0001', 'VALIDATION_FAILED',
  'should reject grant_role with a role that does not exist'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('52000000-0000-4000-8000-000000000001', null)),
  'P0001', 'VALIDATION_FAILED',
  'should reject grant_role with no role'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.revoke_sql('52000000-0000-4000-8000-000000000001', 'wizard')),
  'P0001', 'VALIDATION_FAILED',
  'should reject revoke_role with a role that does not exist'
);

-- grant_role by the super admin

select is(
  pg_temp.as_actor('authenticated', '50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('52000000-0000-4000-8000-000000000001', 'treasurer')),
  1::bigint,
  'should let the super admin grant a role and return the new row'
);

select is(
  (select granted_by from public.staff_roles where staff_id = '52000000-0000-4000-8000-000000000001' and role = 'treasurer'),
  '50000000-0000-4000-8000-000000000001'::uuid,
  'should record the super admin as the granter'
);

select is(
  pg_temp.as_actor('authenticated', '50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('52000000-0000-4000-8000-000000000001', 'department_head', '40000000-0000-4000-8000-000000000001')),
  1::bigint,
  'should let the super admin grant department_head for an active department'
);

select is(
  pg_temp.as_actor('authenticated', '50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('52000000-0000-4000-8000-000000000001', 'department_head', '40000000-0000-4000-8000-000000000002')),
  1::bigint,
  'should let one staff member head two departments'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('52000000-0000-4000-8000-000000000001', 'department_head')),
  'P0001', 'VALIDATION_FAILED',
  'should reject department_head without a department'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('52000000-0000-4000-8000-000000000001', 'usher', '40000000-0000-4000-8000-000000000001')),
  'P0001', 'VALIDATION_FAILED',
  'should reject a role other than department_head that names a department'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('52000000-0000-4000-8000-000000000001', 'department_head', '40000000-0000-4000-8000-000000000003')),
  'P0001', 'VALIDATION_FAILED',
  'should reject department_head for an archived department'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('52000000-0000-4000-8000-000000000001', 'department_head', gen_random_uuid())),
  'P0001', 'NOT_FOUND',
  'should reject department_head for an unknown department'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.grant_sql(gen_random_uuid(), 'usher')),
  'P0001', 'NOT_FOUND',
  'should reject granting a role to an unknown staff member'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('51000000-0000-4000-8000-000000000002', 'usher')),
  'P0001', 'STAFF_INACTIVE',
  'should reject granting a role to a deactivated staff member'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('52000000-0000-4000-8000-000000000001', 'treasurer')),
  'P0001', 'STAFF_ROLE_ALREADY_GRANTED',
  'should reject granting a role the staff member already holds'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('52000000-0000-4000-8000-000000000001', 'department_head', '40000000-0000-4000-8000-000000000001')),
  'P0001', 'STAFF_ROLE_ALREADY_GRANTED',
  'should reject granting department_head for a department already headed by that person'
);

select is(pg_temp.roles_of('52000000-0000-4000-8000-000000000001'), 'treasurer,department_head,department_head', 'should hold exactly the roles granted so far');

-- revoke_role by the super admin

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.revoke_sql('52000000-0000-4000-8000-000000000001', 'department_head', '40000000-0000-4000-8000-000000000003')),
  'P0001', 'NOT_FOUND',
  'should reject revoking department_head for a department the staff member does not head'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.revoke_sql('52000000-0000-4000-8000-000000000001', 'usher')),
  'P0001', 'NOT_FOUND',
  'should reject revoking a role the staff member does not hold'
);

select is(
  pg_temp.as_actor('authenticated', '50000000-0000-4000-8000-000000000001', pg_temp.revoke_sql('52000000-0000-4000-8000-000000000001', 'department_head', '40000000-0000-4000-8000-000000000002')),
  1::bigint,
  'should let the super admin revoke one department_head assignment'
);

select is(pg_temp.roles_of('52000000-0000-4000-8000-000000000001'), 'treasurer,department_head', 'should keep the other department_head assignment');

select is(
  pg_temp.as_actor('authenticated', '50000000-0000-4000-8000-000000000001', pg_temp.revoke_sql('52000000-0000-4000-8000-000000000001', 'treasurer')),
  1::bigint,
  'should let the super admin revoke a role that is not super_admin'
);

-- Last super admin rule (AC 5). 50...01 is the only active super admin; 51...01 is an inactive one and must not count.

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.revoke_sql('50000000-0000-4000-8000-000000000001', 'super_admin')),
  'P0001', 'STAFF_LAST_SUPER_ADMIN',
  'should refuse revoke_role on the last active super admin even when an inactive super admin exists'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', $$delete from public.staff_roles where role = 'super_admin' and staff_id = '50000000-0000-4000-8000-000000000001'$$),
  'P0001', 'STAFF_LAST_SUPER_ADMIN',
  'should refuse a direct DELETE of the last super admin row by a super admin'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', $$delete from public.staff_roles where role = 'super_admin'$$),
  'P0001', 'STAFF_LAST_SUPER_ADMIN',
  'should refuse a bulk DELETE that would leave no active super admin'
);

select throws_ok(
  $$ delete from public.staff_roles where role = 'super_admin' and staff_id = '50000000-0000-4000-8000-000000000001' $$,
  'P0001', 'STAFF_LAST_SUPER_ADMIN',
  'should refuse a DELETE of the last super admin row even by the table owner'
);

select throws_ok(
  $$ update public.staff_roles set role = 'pastor' where role = 'super_admin' and staff_id = '50000000-0000-4000-8000-000000000001' $$,
  'P0001', 'STAFF_LAST_SUPER_ADMIN',
  'should refuse an UPDATE that turns the last super admin into another role'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', $$update public.staff set is_active = false where id = '50000000-0000-4000-8000-000000000001'$$),
  'P0001', 'STAFF_LAST_SUPER_ADMIN',
  'should refuse deactivating the last active super admin'
);

select throws_ok(
  $$ update public.staff set is_active = false where id = '50000000-0000-4000-8000-000000000001' $$,
  'P0001', 'STAFF_LAST_SUPER_ADMIN',
  'should refuse deactivating the last active super admin even by the table owner'
);

select is(
  pg_temp.as_actor('authenticated', '50000000-0000-4000-8000-000000000002', $$delete from public.staff_roles where role = 'super_admin'$$),
  0::bigint,
  'should let a non-super-admin delete nothing from staff_roles'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('51000000-0000-4000-8000-000000000001', 'super_admin')),
  'P0001', 'STAFF_INACTIVE',
  'should not let a deactivated super admin be counted again by granting to them'
);

select is(pg_temp.roles_of('50000000-0000-4000-8000-000000000001'), 'super_admin', 'should still hold the super_admin role after every refused removal');
select is((select is_active from public.staff where id = '50000000-0000-4000-8000-000000000001'), true, 'should still be active after every refused deactivation');

-- With a second active super admin the first may step down, and removing a non-super-admin is never blocked.

select is(
  pg_temp.as_actor('authenticated', '50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('50000000-0000-4000-8000-000000000002', 'super_admin')),
  1::bigint,
  'should let the super admin grant super_admin to a second active staff member'
);

select lives_ok(
  $$ update public.staff set is_active = false where id = '50000000-0000-4000-8000-000000000002' $$,
  'should let the table owner deactivate a super admin while another active super admin remains'
);

select lives_ok(
  $$ update public.staff set is_active = true where id = '50000000-0000-4000-8000-000000000002' $$,
  'should let the table owner reactivate that super admin'
);

select is(
  pg_temp.as_actor('authenticated', '50000000-0000-4000-8000-000000000001', $$update public.staff set is_active = false where id = '50000000-0000-4000-8000-000000000003'$$),
  1::bigint,
  'should let the super admin deactivate staff who are not super admins'
);

select is(
  pg_temp.as_actor('authenticated', '50000000-0000-4000-8000-000000000002', pg_temp.revoke_sql('50000000-0000-4000-8000-000000000001', 'super_admin')),
  1::bigint,
  'should let a super admin revoke another super admin while a second active one remains'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000002', pg_temp.revoke_sql('50000000-0000-4000-8000-000000000002', 'super_admin')),
  'P0001', 'STAFF_LAST_SUPER_ADMIN',
  'should refuse the remaining super admin revoking their own role'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.grant_sql('50000000-0000-4000-8000-000000000001', 'pastor')),
  'P0001', 'AUTH_FORBIDDEN',
  'should treat a former super admin as having no super admin access'
);

-- Concurrency: removals queue on one advisory lock, so two parallel removals cannot both pass the check.

select is(
  exists (
    select 1 from pg_locks
    where locktype = 'advisory' and pid = pg_backend_pid() and granted
      and ((classid::bigint << 32) | objid::bigint) = private.super_admin_lock_key()
  ),
  true,
  'should hold the advisory lock that serialises super admin removals for the rest of the transaction'
);

-- Inactive staff: deactivating the second super admin leaves the first as the only active one

select is(
  pg_temp.as_actor('authenticated', '50000000-0000-4000-8000-000000000002', pg_temp.grant_sql('50000000-0000-4000-8000-000000000001', 'super_admin')),
  1::bigint,
  'should let the super admin restore the first super admin'
);

select is(
  pg_temp.as_actor('authenticated', '50000000-0000-4000-8000-000000000001', $$update public.staff set is_active = false where id = '50000000-0000-4000-8000-000000000002'$$),
  1::bigint,
  'should let a super admin deactivate another while one active super admin remains'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000002', pg_temp.grant_sql('52000000-0000-4000-8000-000000000001', 'usher')),
  'P0001', 'AUTH_FORBIDDEN',
  'should lose all super admin access once deactivated'
);

select throws_ok(
  pg_temp.fails_as('50000000-0000-4000-8000-000000000001', pg_temp.revoke_sql('50000000-0000-4000-8000-000000000001', 'super_admin')),
  'P0001', 'STAFF_LAST_SUPER_ADMIN',
  'should not count a deactivated super admin as a remaining one'
);

select is(
  pg_temp.as_actor('authenticated', '50000000-0000-4000-8000-000000000002', 'select * from public.staff'),
  0::bigint,
  'should show a staff member nothing after they are deactivated mid-session'
);

select * from finish();

rollback;
