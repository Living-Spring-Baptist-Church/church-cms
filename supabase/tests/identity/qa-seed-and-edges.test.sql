-- LBC-17 QA: the demo seed accounts, anon denial through GraphQL, helper functions with edge inputs,
-- a department head over several departments, unicode department names and the grant_role result shape.
-- Unlike the other identity tests this one runs against the real demo seed on purpose.

begin;

select plan(31);

-- Seeded demo accounts: one active staff member per role.

select is(
  (select count(*) from public.staff where is_active),
  7::bigint,
  'should seed seven active staff members'
);

select is(
  (select count(*) from public.staff as staff join auth.users on auth.users.id = staff.id where auth.users.email like '%@demo.church'),
  7::bigint,
  'should key every seeded staff member to an auth user on the fake demo.church domain'
);

select is(
  (select count(*) from public.staff_roles as staff_role join public.staff on staff.id = staff_role.staff_id
   where staff_role.role = 'super_admin' and staff.is_active and staff.id = '10000000-0000-4000-8000-000000000001'),
  1::bigint,
  'should seed super-admin@demo.church as an active super admin'
);

select is(
  (select array_agg(staff_role.role order by auth.users.email) from public.staff_roles as staff_role join auth.users on auth.users.id = staff_role.staff_id),
  array['content_editor', 'department_head', 'pastor', 'secretary', 'super_admin', 'treasurer', 'usher']::public.app_role[],
  'should give each seeded demo account exactly its own role'
);

select is(
  (select department_id from public.staff_roles where role = 'department_head'),
  '20000000-0000-4000-8000-000000000001'::uuid,
  'should seed the department head over Choir'
);

select is(
  (select count(*) from public.departments where is_childrens_ministry),
  1::bigint,
  'should seed exactly one childrens ministry department'
);

-- Helper functions with edge inputs, evaluated as a signed-in super admin.

select set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', 'authenticated', 'sub', '10000000-0000-4000-8000-000000000001')::text, true);

select is(private.has_role(null), false, 'should return false, not null, when has_role gets null');
select is(private.has_any_role(null), false, 'should return false when has_any_role gets null');
select is(private.has_any_role(array[]::public.app_role[]), false, 'should return false when has_any_role gets an empty list');
select is(private.heads_department(null), false, 'should return false when heads_department gets null');
select is(private.has_any_role(array['pastor', 'super_admin']::public.app_role[]), true, 'should return true when one of several roles is held');
select is(private.has_role('pastor'), false, 'should return false for a role the user does not hold');

select set_config('request.jwt.claims', '', true);
select is(private.has_role('super_admin'), false, 'should return false when there are no claims');
select is(private.is_active_staff(), false, 'should return false for is_active_staff when there are no claims');

-- Department head over several departments.

select set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', 'authenticated', 'sub', '10000000-0000-4000-8000-000000000001')::text, true);
select set_config('role', 'authenticated', true);

select is(
  (select (public.grant_role('10000000-0000-4000-8000-000000000006', 'department_head', '20000000-0000-4000-8000-000000000003')).department_id),
  '20000000-0000-4000-8000-000000000003'::uuid,
  'should let a department head also head a second department'
);

reset role;
select set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', 'authenticated', 'sub', '10000000-0000-4000-8000-000000000006')::text, true);

select is(private.heads_department('20000000-0000-4000-8000-000000000001'), true, 'should still head the first department');
select is(private.heads_department('20000000-0000-4000-8000-000000000003'), true, 'should head the second department');
select is(private.heads_department('20000000-0000-4000-8000-000000000002'), false, 'should not head a department never granted');
select is(private.has_role('department_head'), true, 'should hold department_head when heading two departments');

-- grant_role result shape and unicode department names, as super admin.

select set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', 'authenticated', 'sub', '10000000-0000-4000-8000-000000000001')::text, true);
select set_config('role', 'authenticated', true);

create temp table granted_row as
  select * from public.grant_role('10000000-0000-4000-8000-000000000005', 'secretary');

reset role;

select is((select role from granted_row), 'secretary'::public.app_role, 'should return the granted role');
select is((select staff_id from granted_row), '10000000-0000-4000-8000-000000000005'::uuid, 'should return the staff member who received the role');
select is((select granted_by from granted_row), '10000000-0000-4000-8000-000000000001'::uuid, 'should record the calling super admin as granted_by');
select is((select department_id from granted_row), null, 'should return no department for a role that has none');
select isnt((select granted_at from granted_row), null, 'should stamp granted_at');

select set_config('role', 'authenticated', true);

select is(
  (select count(*) from (select name from public.departments where name = 'Ɛkɔ Mmɔfra ‘Kids’ ünï') as found),
  0::bigint,
  'should not have the unicode department before it is created'
);
insert into public.departments (name) values ('Ɛkɔ Mmɔfra ‘Kids’ ünï');
select is(
  (select count(*) from public.departments where name = 'Ɛkɔ Mmɔfra ‘Kids’ ünï'),
  1::bigint,
  'should store and return a department name with diacritics and curly quotes unchanged'
);
reset role;

-- A non super admin cannot change staff columns even on their own row.

select set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', 'authenticated', 'sub', '10000000-0000-4000-8000-000000000002')::text, true);
select set_config('role', 'authenticated', true);

update public.staff set full_name = 'Renamed' where id = '10000000-0000-4000-8000-000000000002';
select is(
  (select full_name from public.staff where id = '10000000-0000-4000-8000-000000000002'),
  'Demo Pastor',
  'should not let a pastor rename their own staff profile'
);
reset role;

-- GraphQL as anon: no data and no mutations.

select set_config('request.jwt.claims', json_build_object('role', 'anon')::text, true);
select set_config('role', 'anon', true);

select is(
  (graphql.resolve('{ staffCollection { edges { node { id } } } }')::jsonb) ->> 'data',
  null,
  'should return no data for a staff query as anon'
);
select ok(
  (graphql.resolve('{ staffRolesCollection { edges { node { id } } } }')::jsonb) -> 'errors' is not null,
  'should return an error for a staff_roles query as anon'
);
select ok(
  (graphql.resolve('{ departmentsCollection { edges { node { id } } } }')::jsonb) -> 'errors' is not null,
  'should return an error for a departments query as anon'
);
select ok(
  (graphql.resolve('mutation { grantRole(pStaffId: "10000000-0000-4000-8000-000000000002", pRole: "super_admin") { id } }')::jsonb) -> 'errors' is not null,
  'should reject grantRole as anon'
);
reset role;

select * from finish();

rollback;
