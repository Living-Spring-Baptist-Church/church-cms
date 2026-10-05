-- LBC-17: row level security on departments, staff and staff_roles, exercised as every role in app_role,
-- as active staff with no role, as inactive staff holding each role, and as anon.
-- Every actor runs through pg_temp.as_actor(), which switches to the real database role with the JWT claims
-- set, so RLS and grants are really exercised (never the table owner).

begin;

select plan(251);

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

create function pg_temp.attempt(p_db_role name, p_staff_id uuid, p_statement text)
returns text
language sql
as $$
  select format('select pg_temp.as_actor(%L, %L, %L)', p_db_role, p_staff_id, p_statement);
$$;

-- One active actor and one inactive actor per role, plus active staff who hold no role.
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

insert into public.departments (id, name)
values ('40000000-0000-4000-8000-000000000001', 'Choir'), ('40000000-0000-4000-8000-000000000002', 'Youth');

insert into public.staff (id, full_name, is_active)
select staff_id, label, is_active from actors;

insert into public.staff_roles (staff_id, role, department_id)
select staff_id, role, case role when 'department_head' then '40000000-0000-4000-8000-000000000001'::uuid end
from actors
where role is not null;

-- Reads: expected counts depend only on who the actor is.
-- Active staff with any role: all departments. Super admin: every staff row and role row. Everyone else: only themselves.

select is(
  pg_temp.as_actor('authenticated', staff_id, 'select * from public.departments'),
  case when is_active and role is not null then 2 else 0 end::bigint,
  format('should show departments to %s only when active staff with a role', label)
) from actors order by label;

select is(
  pg_temp.as_actor('authenticated', staff_id, 'select * from public.staff'),
  case when not is_active then 0 when role = 'super_admin' then 15 else 1 end::bigint,
  format('should show %s the staff rows they may see', label)
) from actors order by label;

select is(
  pg_temp.as_actor('authenticated', staff_id, format('select * from public.staff where id = %L', staff_id)),
  case when is_active then 1 else 0 end::bigint,
  format('should let %s read their own profile only while active', label)
) from actors order by label;

select is(
  pg_temp.as_actor('authenticated', staff_id, format('select * from public.staff where id <> %L', staff_id)),
  case when is_active and role = 'super_admin' then 14 else 0 end::bigint,
  format('should hide other staff profiles from %s unless super admin', label)
) from actors order by label;

select is(
  pg_temp.as_actor('authenticated', staff_id, 'select * from public.staff_roles'),
  case when not is_active then 0 when role = 'super_admin' then 14 when role is null then 0 else 1 end::bigint,
  format('should show %s the staff_roles rows they may see', label)
) from actors order by label;

-- anon: no access at all

select throws_ok(pg_temp.attempt('anon', null, 'select * from public.departments'), '42501', null, 'should deny anon reading departments');
select throws_ok(pg_temp.attempt('anon', null, 'select * from public.staff'), '42501', null, 'should deny anon reading staff');
select throws_ok(pg_temp.attempt('anon', null, 'select * from public.staff_roles'), '42501', null, 'should deny anon reading staff_roles');
select throws_ok(pg_temp.attempt('anon', null, $$insert into public.departments (name) values ('Anon')$$), '42501', null, 'should deny anon inserting departments');
select throws_ok(pg_temp.attempt('anon', null, 'update public.staff set phone = phone'), '42501', null, 'should deny anon updating staff');
select throws_ok(pg_temp.attempt('anon', null, 'delete from public.staff_roles'), '42501', null, 'should deny anon deleting staff_roles');
select throws_ok(pg_temp.attempt('anon', null, $$select public.grant_role('52000000-0000-4000-8000-000000000001', 'pastor')$$), '42501', null, 'should deny anon calling grant_role');
select throws_ok(pg_temp.attempt('anon', null, $$select public.revoke_role('52000000-0000-4000-8000-000000000001', 'pastor')$$), '42501', null, 'should deny anon calling revoke_role');

select throws_ok(
  pg_temp.attempt('anon', null, format('select private.%s', helper)),
  '42501', null,
  format('should deny anon calling private.%s directly', helper)
) from (values ('has_role(''super_admin'')'), ('has_any_role(array[''pastor'']::public.app_role[])'), ('heads_department(gen_random_uuid())'), ('is_active_staff()')) as helpers (helper);

select throws_ok(
  pg_temp.attempt('authenticated', staff_id, 'select private.has_role(''super_admin'')'),
  '42501', null,
  'should deny a signed-in super admin calling private helpers directly'
) from actors where is_active and role = 'super_admin';

-- departments writes: only an active super admin inserts or updates; nobody deletes

select throws_ok(
  pg_temp.attempt('authenticated', staff_id, $$insert into public.departments (name) values ('Probe')$$),
  '42501', null,
  format('should reject %s inserting a department', label)
) from actors where not (is_active and role = 'super_admin') order by label;

select is(
  pg_temp.as_actor('authenticated', staff_id, $$insert into public.departments (name, is_childrens_ministry) values ('Probe', true)$$),
  1::bigint,
  'should let the super admin insert a department'
) from actors where is_active and role = 'super_admin';

select is(
  pg_temp.as_actor('authenticated', staff_id, 'update public.departments set is_childrens_ministry = true'),
  case when is_active and role = 'super_admin' then 3 else 0 end::bigint,
  format('should let only an active super admin update departments (%s)', label)
) from actors order by label;

select throws_ok(
  pg_temp.attempt('authenticated', staff_id, 'delete from public.departments'),
  '42501', null,
  format('should reject %s deleting a department because departments are archived instead', label)
) from actors order by label;

-- staff writes: only an active super admin updates; nobody inserts or deletes through the API

select is(
  pg_temp.as_actor('authenticated', staff_id, $$update public.staff set phone = 'demo'$$),
  case when is_active and role = 'super_admin' then 15 else 0 end::bigint,
  format('should let only an active super admin update staff (%s)', label)
) from actors order by label;

select throws_ok(
  pg_temp.attempt('authenticated', staff_id, format($$insert into public.staff (id, full_name) values (%L, 'Probe')$$, gen_random_uuid())),
  '42501', null,
  format('should reject %s inserting a staff row', label)
) from actors order by label;

select throws_ok(
  pg_temp.attempt('authenticated', staff_id, 'delete from public.staff'),
  '42501', null,
  format('should reject %s deleting a staff row', label)
) from actors order by label;

select throws_ok(
  pg_temp.attempt('authenticated', staff_id, format($$update public.staff set id = %L$$, gen_random_uuid())),
  '42501', null,
  format('should reject %s changing the id of a staff row', label)
) from actors order by label;

-- staff_roles writes: only an active super admin inserts or deletes; nobody updates

select throws_ok(
  pg_temp.attempt('authenticated', staff_id, format($$insert into public.staff_roles (staff_id, role, granted_by) values (%L, 'pastor', %L)$$, '52000000-0000-4000-8000-000000000001', staff_id)),
  '42501', null,
  format('should reject %s granting a role directly', label)
) from actors where not (is_active and role = 'super_admin') order by label;

select throws_ok(
  pg_temp.attempt('authenticated', staff_id, format($$insert into public.staff_roles (staff_id, role, granted_by) values (%L, 'super_admin', %L)$$, staff_id, staff_id)),
  '42501', null,
  format('should reject %s promoting themselves to super admin', label)
) from actors where not (is_active and role = 'super_admin') order by label;

select is(
  pg_temp.as_actor('authenticated', staff_id, format($$insert into public.staff_roles (staff_id, role, granted_by) values (%L, 'pastor', %L)$$, '52000000-0000-4000-8000-000000000001', staff_id)),
  1::bigint,
  'should let the super admin grant a role directly when they are recorded as the granter'
) from actors where is_active and role = 'super_admin';

select throws_ok(
  pg_temp.attempt('authenticated', staff_id, format($$insert into public.staff_roles (staff_id, role, granted_by) values (%L, 'treasurer', %L)$$, '52000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000002')),
  '42501', null,
  'should reject a super admin recording someone else as the granter'
) from actors where is_active and role = 'super_admin';

select throws_ok(
  pg_temp.attempt('authenticated', staff_id, format($$insert into public.staff_roles (staff_id, role, granted_by) values (%L, 'treasurer', %L)$$, '51000000-0000-4000-8000-000000000001', staff_id)),
  '42501', null,
  'should reject a super admin granting a role to deactivated staff'
) from actors where is_active and role = 'super_admin';

select is(
  pg_temp.as_actor('authenticated', staff_id, $$delete from public.staff_roles where role = 'usher'$$),
  case when is_active and role = 'super_admin' then 2 else 0 end::bigint,
  format('should let only an active super admin delete staff_roles (%s)', label)
) from actors order by label;

select throws_ok(
  pg_temp.attempt('authenticated', staff_id, 'update public.staff_roles set granted_by = null'),
  '42501', null,
  format('should reject %s updating staff_roles because roles are revoked and granted instead', label)
) from actors order by label;

select * from finish();

rollback;
