-- LBC-41 (AC 1, 2, 4, 5): reads on staff, staff_roles, departments, members, member_names, content_items,
-- attendance_counts and services, exercised for every role at aal1 and at aal2. Super admin, pastor and treasurer
-- are denied at aal1 and allowed at aal2; every other role is unaffected by aal; a user holding a two-factor role
-- and another role at aal1 keeps only the other role; the own staff row and own roles stay readable at aal1.
-- Every actor runs through pg_temp.count_as(), which switches to the real database role with the JWT claims set,
-- so RLS and grants are exercised (never the table owner). The demo seed is cleared first.

begin;

select plan(203);

-- Fixture: start from an empty model so the demo seed cannot influence the results.
set local session_replication_role = replica;
delete from public.content_items;
delete from public.sermons;
delete from public.attendance_checkins;
delete from public.attendance_counts;
delete from public.program_participants;
delete from public.services;
delete from public.programs;
delete from public.visitor_followups;
delete from public.member_departments;
delete from public.members;
delete from public.households;
delete from public.staff_roles;
delete from public.staff;
delete from public.departments;
set local session_replication_role = origin;

create temp table actors (label text primary key, staff_id uuid, is_active boolean not null default true);
create temp table actor_roles (label text not null, role public.app_role not null, department_id uuid);

-- The claims a Supabase access token carries. A null aal leaves the claim out.
create function pg_temp.claims_for(p_label text, p_aal text)
returns text
language sql
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'role', 'authenticated',
    'sub', (select staff_id from actors where label = p_label),
    'aal', p_aal
  ))::text;
$$;

-- Counts the rows of one table or view that the actor can read at the given assurance level.
create function pg_temp.count_as(p_label text, p_aal text, p_relation text)
returns bigint
language plpgsql
as $$
declare
  v_original name := current_user;
  v_seen bigint;
begin
  perform set_config('request.jwt.claims', pg_temp.claims_for(p_label, p_aal), true);
  perform set_config('role', 'authenticated', true);
  execute format('select count(*) from public.%I', p_relation) into v_seen;
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_seen;
end;
$$;

create function pg_temp.graphql_as(p_label text, p_aal text, p_query text)
returns jsonb
language plpgsql
as $$
declare
  v_original name := current_user;
  v_result jsonb;
begin
  perform set_config('request.jwt.claims', pg_temp.claims_for(p_label, p_aal), true);
  perform set_config('role', 'authenticated', true);
  v_result := graphql.resolve(p_query);
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_result;
end;
$$;

insert into public.departments (id, name, is_childrens_ministry)
values ('d1000000-0000-4000-8000-000000000001', 'MfaTestDepartment', false);

-- One actor per role, one for each combination that mixes a two-factor role with another role, staff with no
-- role and a deactivated pastor.
insert into actors (label)
values
  ('super_admin'), ('pastor'), ('treasurer'), ('secretary'), ('usher'), ('department_head'), ('content_editor'),
  ('pastor_usher'), ('super_admin_secretary'), ('treasurer_content_editor'), ('no_role');
insert into actors (label, is_active) values ('inactive_pastor', false);

insert into actor_roles (label, role, department_id)
values
  ('super_admin', 'super_admin', null),
  ('pastor', 'pastor', null),
  ('treasurer', 'treasurer', null),
  ('secretary', 'secretary', null),
  ('usher', 'usher', null),
  ('department_head', 'department_head', 'd1000000-0000-4000-8000-000000000001'),
  ('content_editor', 'content_editor', null),
  ('pastor_usher', 'pastor', null),
  ('pastor_usher', 'usher', null),
  ('super_admin_secretary', 'super_admin', null),
  ('super_admin_secretary', 'secretary', null),
  ('treasurer_content_editor', 'treasurer', null),
  ('treasurer_content_editor', 'content_editor', null),
  ('inactive_pastor', 'pastor', null);

update actors
set staff_id = ('e1000000-0000-4000-8000-' || lpad(numbered.position::text, 12, '0'))::uuid
from (select label, row_number() over (order by label) as position from actors) as numbered
where actors.label = numbered.label;

insert into auth.users (id, aud, role, email)
select staff_id, 'authenticated', 'authenticated', label || '@test.invalid' from actors;

insert into public.staff (id, full_name, is_active)
select staff_id, label, is_active from actors;

insert into public.staff_roles (staff_id, role, department_id)
select actors.staff_id, actor_roles.role, actor_roles.department_id
from actor_roles
join actors using (label);

-- One adult member in the department, one service, one headcount, one draft written by the content editor.
insert into public.members (id, first_name, last_name, date_of_birth, status)
values ('e2000000-0000-4000-8000-000000000001', 'MfaAdult', 'Test', '1980-01-01', 'active');

insert into public.member_departments (member_id, department_id)
values ('e2000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000001');

insert into public.services (id, name, type, starts_at)
values ('e3000000-0000-4000-8000-000000000001', 'MfaTestService', 'sunday', now() + interval '1 day');

insert into public.attendance_counts (service_id, men, women, children, visitors, recorded_by)
select 'e3000000-0000-4000-8000-000000000001', 1, 1, 1, 1, staff_id from actors where label = 'usher';

insert into public.content_items (kind, title, author_id)
select 'announcement', 'MfaDraft', staff_id from actors where label = 'content_editor';

-- Expected number of rows each actor can read, per assurance level. -1 means every row of the table.
-- The last six columns are departments, members, member_names, content_items, attendance_counts, services.
create temp table expected_reads (
  label text not null,
  aal text not null,
  staff_rows integer not null,
  staff_role_rows integer not null,
  department_rows integer not null,
  member_rows integer not null,
  member_name_rows integer not null,
  content_rows integer not null,
  count_rows integer not null,
  service_rows integer not null,
  primary key (label, aal)
);

insert into expected_reads
values
  ('super_admin', 'aal1', 1, 1, 0, 0, 0, 0, 0, 0),
  ('super_admin', 'aal2', -1, -1, 1, 1, 0, 1, 1, 1),
  ('pastor', 'aal1', 1, 1, 0, 0, 0, 0, 0, 0),
  ('pastor', 'aal2', 1, 1, 1, 1, 0, 1, 1, 1),
  ('treasurer', 'aal1', 1, 1, 0, 0, 0, 0, 0, 0),
  ('treasurer', 'aal2', 1, 1, 1, 0, 1, 0, 0, 0),
  ('secretary', 'aal1', 1, 1, 1, 1, 0, 1, 1, 1),
  ('secretary', 'aal2', 1, 1, 1, 1, 0, 1, 1, 1),
  ('usher', 'aal1', 1, 1, 1, 0, 1, 0, 1, 1),
  ('usher', 'aal2', 1, 1, 1, 0, 1, 0, 1, 1),
  ('department_head', 'aal1', 1, 1, 1, 1, 0, 0, 0, 0),
  ('department_head', 'aal2', 1, 1, 1, 1, 0, 0, 0, 0),
  ('content_editor', 'aal1', 1, 1, 1, 0, 0, 1, 0, 0),
  ('content_editor', 'aal2', 1, 1, 1, 0, 0, 1, 0, 0),
  ('pastor_usher', 'aal1', 1, 2, 1, 0, 1, 0, 1, 1),
  ('pastor_usher', 'aal2', 1, 2, 1, 1, 1, 1, 1, 1),
  ('super_admin_secretary', 'aal1', 1, 2, 1, 1, 0, 1, 1, 1),
  ('super_admin_secretary', 'aal2', -1, -1, 1, 1, 0, 1, 1, 1),
  ('treasurer_content_editor', 'aal1', 1, 2, 1, 0, 0, 1, 0, 0),
  ('treasurer_content_editor', 'aal2', 1, 2, 1, 0, 1, 1, 0, 0),
  ('no_role', 'aal1', 1, 0, 0, 0, 0, 0, 0, 0),
  ('no_role', 'aal2', 1, 0, 0, 0, 0, 0, 0, 0),
  ('inactive_pastor', 'aal1', 0, 0, 0, 0, 0, 0, 0, 0),
  ('inactive_pastor', 'aal2', 0, 0, 0, 0, 0, 0, 0, 0);

select is(
  pg_temp.count_as(label, aal, 'staff'),
  case when staff_rows = -1 then (select count(*) from actors) else staff_rows end::bigint,
  format('should show %s at %s the expected staff rows', label, aal)
) from expected_reads order by label, aal;

select is(
  pg_temp.count_as(label, aal, 'staff_roles'),
  case when staff_role_rows = -1 then (select count(*) from actor_roles) else staff_role_rows end::bigint,
  format('should show %s at %s the expected staff_roles rows', label, aal)
) from expected_reads order by label, aal;

select is(
  pg_temp.count_as(label, aal, 'departments'),
  department_rows::bigint,
  format('should show %s at %s the expected departments', label, aal)
) from expected_reads order by label, aal;

select is(
  pg_temp.count_as(label, aal, 'members'),
  member_rows::bigint,
  format('should show %s at %s the expected members', label, aal)
) from expected_reads order by label, aal;

select is(
  pg_temp.count_as(label, aal, 'member_names'),
  member_name_rows::bigint,
  format('should show %s at %s the expected member names', label, aal)
) from expected_reads order by label, aal;

select is(
  pg_temp.count_as(label, aal, 'content_items'),
  content_rows::bigint,
  format('should show %s at %s the expected content items', label, aal)
) from expected_reads order by label, aal;

select is(
  pg_temp.count_as(label, aal, 'attendance_counts'),
  count_rows::bigint,
  format('should show %s at %s the expected attendance counts', label, aal)
) from expected_reads order by label, aal;

select is(
  pg_temp.count_as(label, aal, 'services'),
  service_rows::bigint,
  format('should show %s at %s the expected services', label, aal)
) from expected_reads order by label, aal;

-- Own profile at aal1: the login flow reads the own staff row and own roles through GraphQL to decide whether to
-- enrol or ask for a code, before any second factor exists. This is the exact CurrentStaff query.
create function pg_temp.current_staff_as(p_label text, p_aal text)
returns jsonb
language sql
as $$
  select pg_temp.graphql_as(p_label, p_aal, format(
    'query { staffCollection(filter: { id: { eq: "%s" } }, first: 1) { edges { node { id fullName isActive staffRolesCollection { edges { node { role } } } } } } }',
    (select staff_id from actors where label = p_label)));
$$;

select is(
  pg_temp.current_staff_as(label, 'aal1') #>> '{data,staffCollection,edges,0,node,fullName}',
  label,
  format('should let %s read the own staff row through GraphQL at aal1', label)
) from actors where label in ('super_admin', 'pastor', 'treasurer', 'pastor_usher', 'treasurer_content_editor', 'usher') order by label;

select is(
  (select array_agg(edge #>> '{node,role}' order by edge #>> '{node,role}')
   from jsonb_array_elements(pg_temp.current_staff_as('pastor_usher', 'aal1') #> '{data,staffCollection,edges,0,node,staffRolesCollection,edges}') as edge),
  array['pastor', 'usher']::text[],
  'should list both own roles of a pastor and usher at aal1, so the login flow knows two-factor is needed'
);

select is(
  jsonb_array_length(pg_temp.graphql_as('pastor', 'aal1', 'query { membersCollection { edges { node { id } } } }') #> '{data,membersCollection,edges}'),
  0,
  'should return no members to a pastor at aal1 through GraphQL'
);

select is(
  jsonb_array_length(pg_temp.graphql_as('pastor', 'aal2', 'query { membersCollection { edges { node { id } } } }') #> '{data,membersCollection,edges}'),
  1,
  'should return the member to a pastor at aal2 through GraphQL'
);

select is(
  jsonb_array_length(pg_temp.graphql_as('super_admin', 'aal1', 'query { staffCollection { edges { node { id } } } }') #> '{data,staffCollection,edges}'),
  1,
  'should show a super admin at aal1 only the own staff row through GraphQL'
);

select is(
  jsonb_array_length(pg_temp.graphql_as('pastor', 'aal1', 'query { contentItemsCollection { edges { node { id } } } }') #> '{data,contentItemsCollection,edges}'),
  0,
  'should return no content items to a pastor at aal1 through GraphQL'
);

select * from finish();

rollback;
