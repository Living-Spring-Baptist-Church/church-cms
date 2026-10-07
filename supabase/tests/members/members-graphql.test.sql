-- LBC-26 (AC 3, 4, 7): the GraphQL surface of the congregation tables. Every field of each type is listed so a
-- duplicated relationship name cannot slip in (the LBC-17 pitfall), each relationship is shown to resolve to the
-- right rows, and inserts and updates work as the secretary and fail as the usher and anon. Fixture and actors:
-- see the preamble.

begin;

select plan(35);

-- Fixture: start from an empty congregation and identity model so the demo seed cannot influence the results.
set local session_replication_role = replica;
delete from public.visitor_followups;
delete from public.member_departments;
delete from public.members;
delete from public.households;
delete from public.staff_roles;
delete from public.staff;
delete from public.departments;
set local session_replication_role = origin;

-- Runs one statement as a real database role with the JWT claims set, so RLS and grants are exercised.
-- The label picks the staff member; 'anon' is the signed-out role.
create temp table actors (label text primary key, staff_id uuid, is_active boolean not null default true);
create temp table actor_roles (label text not null, role public.app_role not null, department_id uuid);

create function pg_temp.run_as(p_label text, p_statement text)
returns bigint
language plpgsql
as $$
declare
  v_original name := current_user;
  v_db_role name := case p_label when 'anon' then 'anon' else 'authenticated' end;
  v_rows bigint;
begin
  perform set_config('request.jwt.claims', json_build_object('role', v_db_role, 'sub', (select staff_id from actors where label = p_label))::text, true);
  perform set_config('role', v_db_role::text, true);
  execute p_statement;
  get diagnostics v_rows = row_count;
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_rows;
end;
$$;

create function pg_temp.attempt(p_label text, p_statement text)
returns text
language sql
as $$
  select format('select pg_temp.run_as(%L, %L)', p_label, p_statement);
$$;

-- The values of one column the actor can read from a table or view, sorted and comma separated.
create function pg_temp.seen_as(p_label text, p_relation text, p_column text)
returns text
language plpgsql
as $$
declare
  v_original name := current_user;
  v_db_role name := case p_label when 'anon' then 'anon' else 'authenticated' end;
  v_seen text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', v_db_role, 'sub', (select staff_id from actors where label = p_label))::text, true);
  perform set_config('role', v_db_role::text, true);
  execute format('select coalesce(string_agg(%1$I::text, %2$L order by %1$I::text), %3$L) from %4$s', p_column, ',', '', p_relation) into v_seen;
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_seen;
end;
$$;

create function pg_temp.graphql_as(p_label text, p_query text)
returns jsonb
language plpgsql
as $$
declare
  v_original name := current_user;
  v_db_role name := case p_label when 'anon' then 'anon' else 'authenticated' end;
  v_result jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('role', v_db_role, 'sub', (select staff_id from actors where label = p_label))::text, true);
  perform set_config('role', v_db_role::text, true);
  v_result := graphql.resolve(p_query);
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_result;
end;
$$;

-- Departments: 40...01 Choir, 40...02 Youth, 40...03 Children's Ministry (the only children's ministry).
insert into public.departments (id, name, is_childrens_ministry)
values
  ('40000000-0000-4000-8000-000000000001', 'Choir', false),
  ('40000000-0000-4000-8000-000000000002', 'Youth', false),
  ('40000000-0000-4000-8000-000000000003', 'Children''s Ministry', true);

-- One active actor per role, department heads of each department, two staff holding two roles, staff with no
-- role, an inactive staff member for most roles, and anon.
insert into actors (label)
values
  ('super_admin'), ('pastor'), ('treasurer'), ('secretary'), ('usher'), ('content_editor'),
  ('head_choir'), ('head_youth'), ('head_children'),
  ('head_choir_and_children'), ('usher_and_pastor'), ('usher_and_head_children'), ('no_role');

insert into actor_roles (label, role, department_id)
values
  ('super_admin', 'super_admin', null),
  ('pastor', 'pastor', null),
  ('treasurer', 'treasurer', null),
  ('secretary', 'secretary', null),
  ('usher', 'usher', null),
  ('content_editor', 'content_editor', null),
  ('head_choir', 'department_head', '40000000-0000-4000-8000-000000000001'),
  ('head_youth', 'department_head', '40000000-0000-4000-8000-000000000002'),
  ('head_children', 'department_head', '40000000-0000-4000-8000-000000000003'),
  ('head_choir_and_children', 'department_head', '40000000-0000-4000-8000-000000000001'),
  ('head_choir_and_children', 'department_head', '40000000-0000-4000-8000-000000000003'),
  ('usher_and_pastor', 'usher', null),
  ('usher_and_pastor', 'pastor', null),
  ('usher_and_head_children', 'usher', null),
  ('usher_and_head_children', 'department_head', '40000000-0000-4000-8000-000000000003');

insert into actors (label, is_active)
select 'inactive_' || label, false
from actors
where label in ('super_admin', 'pastor', 'treasurer', 'secretary', 'usher', 'content_editor', 'head_choir', 'head_children');

insert into actor_roles (label, role, department_id)
select 'inactive_' || label, role, department_id
from actor_roles
where 'inactive_' || label in (select label from actors);

insert into actors (label, is_active) values ('anon', true);

update actors
set staff_id = ('50000000-0000-4000-8000-' || lpad(numbered.position::text, 12, '0'))::uuid
from (select label, row_number() over (order by label) as position from actors where label <> 'anon') as numbered
where actors.label = numbered.label;

insert into auth.users (id, aud, role, email)
select staff_id, 'authenticated', 'authenticated', label || '@test.invalid' from actors where label <> 'anon';

insert into public.staff (id, full_name, is_active)
select staff_id, label, is_active from actors where label <> 'anon';

insert into public.staff_roles (staff_id, role, department_id)
select actors.staff_id, actor_roles.role, actor_roles.department_id
from actor_roles
join actors using (label);

-- Households: 30...01 and 30...02 active, 30...03 archived.
insert into public.households (id, name, address, archived_at)
values
  ('30000000-0000-4000-8000-000000000001', 'Alpha Household', '1 Test Lane', null),
  ('30000000-0000-4000-8000-000000000002', 'Beta Household', '2 Test Lane', null),
  ('30000000-0000-4000-8000-000000000003', 'Gamma Household', '3 Test Lane', now());

-- Members, keyed by first name (60...01 to 60...09). Ten years old is a minor, 1980 an adult.
insert into public.members (id, household_id, first_name, last_name, phone, email, date_of_birth, status, archived_at)
values
  ('60000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 'AdultChoir', 'Test', '+233200000201', 'a1@example.org', '1980-01-01', 'active', null),
  ('60000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', 'AdultYouth', 'Test', '+233200000202', 'a2@example.org', '1980-01-01', 'active', null),
  ('60000000-0000-4000-8000-000000000003', null, 'AdultNone', 'Test', '+233200000203', 'a3@example.org', '1980-01-01', 'visitor', null),
  ('60000000-0000-4000-8000-000000000004', null, 'AdultArchived', 'Test', '+233200000204', 'a4@example.org', '1980-01-01', 'transferred', now()),
  ('60000000-0000-4000-8000-000000000005', '30000000-0000-4000-8000-000000000002', 'MinorChildren', 'Test', null, null, current_date - interval '10 years', 'active', null),
  ('60000000-0000-4000-8000-000000000006', '30000000-0000-4000-8000-000000000002', 'MinorChoir', 'Test', null, null, current_date - interval '10 years', 'active', null),
  ('60000000-0000-4000-8000-000000000007', null, 'MinorArchived', 'Test', null, null, current_date - interval '10 years', 'inactive', now()),
  ('60000000-0000-4000-8000-000000000008', null, 'UnknownDob', 'Test', '+233200000208', null, null, 'visitor', null),
  ('60000000-0000-4000-8000-000000000009', null, 'AdultBoth', 'Test', '+233200000209', 'a9@example.org', '1980-01-01', 'active', null);

insert into public.member_departments (member_id, department_id)
values
  ('60000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000002'),
  ('60000000-0000-4000-8000-000000000004', '40000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000005', '40000000-0000-4000-8000-000000000003'),
  ('60000000-0000-4000-8000-000000000006', '40000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000007', '40000000-0000-4000-8000-000000000003'),
  ('60000000-0000-4000-8000-000000000008', '40000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000009', '40000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000009', '40000000-0000-4000-8000-000000000002');

-- Follow-ups, keyed by notes: on an adult visitor, on a minor, on an archived adult.
insert into public.visitor_followups (id, member_id, assigned_to, status, notes)
select ids.id, ids.member_id, (select staff_id from actors where label = 'secretary'), 'pending', ids.notes
from (values
  ('70000000-0000-4000-8000-000000000001'::uuid, '60000000-0000-4000-8000-000000000003'::uuid, 'FollowAdult'),
  ('70000000-0000-4000-8000-000000000002'::uuid, '60000000-0000-4000-8000-000000000005'::uuid, 'FollowMinor'),
  ('70000000-0000-4000-8000-000000000003'::uuid, '60000000-0000-4000-8000-000000000004'::uuid, 'FollowArchived')
) as ids (id, member_id, notes);

-- Who may see which members: first names, sorted. Everyone not listed sees none.
create temp table expected_members (label text primary key, seen text not null);
insert into expected_members
values
  ('super_admin', 'AdultArchived,AdultBoth,AdultChoir,AdultNone,AdultYouth,MinorArchived,MinorChildren,MinorChoir,UnknownDob'),
  ('pastor', 'AdultBoth,AdultChoir,AdultNone,AdultYouth,MinorChildren,MinorChoir,UnknownDob'),
  ('usher_and_pastor', 'AdultBoth,AdultChoir,AdultNone,AdultYouth,MinorChildren,MinorChoir,UnknownDob'),
  ('secretary', 'AdultArchived,AdultBoth,AdultChoir,AdultNone,AdultYouth'),
  ('head_choir', 'AdultBoth,AdultChoir'),
  ('head_youth', 'AdultBoth,AdultYouth'),
  ('head_children', 'MinorChildren'),
  ('usher_and_head_children', 'MinorChildren'),
  ('head_choir_and_children', 'AdultBoth,AdultChoir,MinorChildren');

-- pg_graphql answers introspection only when the schema comment turns it on (as scripts/export-graphql-schema.mjs
-- does). Switched on here for this rolled-back transaction only.
do $enable_introspection$
begin
  execute format(
    'comment on schema public is %L',
    regexp_replace(obj_description('public'::regnamespace, 'pg_namespace'), '^@graphql[(][{]', '@graphql({"introspection": true, ')
  );
end
$enable_introspection$;

create function pg_temp.type_fields(p_type text)
returns jsonb
language sql
as $$
  select jsonb_agg(field ->> 'name' order by field ->> 'name')
  from jsonb_array_elements(
    pg_temp.graphql_as('super_admin', format('{ __type(name: "%s") { fields { name } } }', p_type)) #> '{data,__type,fields}'
  ) as field;
$$;

create function pg_temp.mutation_names()
returns jsonb
language sql
as $$
  select jsonb_agg(field ->> 'name' order by field ->> 'name')
  from jsonb_array_elements(
    pg_temp.graphql_as('super_admin', '{ __type(name: "Mutation") { fields { name } } }') #> '{data,__type,fields}'
  ) as field;
$$;

-- Every field on each type, so a duplicated or renamed relationship shows up as a diff (two fields with the same
-- name would make one relationship silently resolve to the wrong table)

select is(pg_temp.type_fields('Members'),
  '["archivedAt", "consentRecordedAt", "createdAt", "dateOfBirth", "email", "firstName", "firstVisitOn", "gender", "household", "householdId", "id", "joinedOn", "lastName", "maritalStatus", "memberDepartmentsCollection", "nodeId", "phone", "smsOptOut", "staffCollection", "status", "updatedAt", "visitorFollowupsCollection"]'::jsonb,
  'should list exactly these fields on Members');
select is(pg_temp.type_fields('Households'),
  '["address", "archivedAt", "createdAt", "id", "membersCollection", "name", "nodeId", "updatedAt"]'::jsonb,
  'should list exactly these fields on Households');
select is(pg_temp.type_fields('MemberDepartments'),
  '["department", "departmentId", "id", "member", "memberId", "nodeId"]'::jsonb,
  'should list exactly these fields on MemberDepartments');
select is(pg_temp.type_fields('VisitorFollowups'),
  '["assignedStaff", "assignedTo", "createdAt", "dueOn", "id", "member", "memberId", "nodeId", "notes", "status", "updatedAt"]'::jsonb,
  'should list exactly these fields on VisitorFollowups, with the assigned staff member apart from the assignedTo id');
select is(pg_temp.type_fields('MemberNames'),
  '["firstName", "id", "lastName", "nodeId", "status"]'::jsonb,
  'should list exactly these fields on MemberNames');
select is(pg_temp.type_fields('Staff'),
  '["assignedVisitorFollowupsCollection", "createdAt", "fullName", "grantedRolesCollection", "id", "isActive", "member", "memberId", "nodeId", "phone", "staffRolesCollection", "updatedAt"]'::jsonb,
  'should list exactly these fields on Staff, now that it links to a member');
select is(pg_temp.type_fields('Departments'),
  '["archivedAt", "id", "isChildrensMinistry", "memberDepartmentsCollection", "name", "nodeId", "staffRolesCollection"]'::jsonb,
  'should list exactly these fields on Departments');

select is(
  pg_temp.mutation_names() @> '["insertIntoMembersCollection", "updateMembersCollection", "insertIntoHouseholdsCollection", "updateHouseholdsCollection", "insertIntoMemberDepartmentsCollection", "deleteFromMemberDepartmentsCollection", "insertIntoVisitorFollowupsCollection", "updateVisitorFollowupsCollection"]'::jsonb,
  true,
  'should offer the generated inserts and updates, and the delete of department links'
);

select is(
  (select jsonb_agg(name order by name) from jsonb_array_elements_text(pg_temp.mutation_names()) as names (name) where name ~ '^deleteFrom(Members|Households|VisitorFollowups)Collection$'),
  null,
  'should offer no delete mutation for members, households or follow-ups'
);

-- Relationships resolve to the right rows

select is(
  pg_temp.graphql_as('super_admin', $$query { visitorFollowupsCollection(filter: { notes: { eq: "FollowAdult" } }) { edges { node { member { firstName } assignedStaff { fullName } } } } }$$) #>> '{data,visitorFollowupsCollection,edges,0,node,member,firstName}',
  'AdultNone',
  'should resolve VisitorFollowups.member to the visitor being followed up'
);

select is(
  pg_temp.graphql_as('super_admin', $$query { visitorFollowupsCollection(filter: { notes: { eq: "FollowAdult" } }) { edges { node { assignedStaff { fullName } } } } }$$) #>> '{data,visitorFollowupsCollection,edges,0,node,assignedStaff,fullName}',
  'secretary',
  'should resolve VisitorFollowups.assignedStaff to the staff member who does the follow-up'
);

select is(
  pg_temp.graphql_as('super_admin', $$query { staffCollection(filter: { fullName: { eq: "secretary" } }) { edges { node { assignedVisitorFollowupsCollection { edges { node { notes } } } } } } }$$) #>> '{data,staffCollection,edges,0,node,assignedVisitorFollowupsCollection,edges,0,node,notes}',
  'FollowAdult',
  'should list on Staff.assignedVisitorFollowupsCollection the follow-ups assigned to them'
);

select is(
  jsonb_array_length(pg_temp.graphql_as('super_admin', $$query { membersCollection(filter: { firstName: { eq: "AdultNone" } }) { edges { node { visitorFollowupsCollection { edges { node { id } } } } } } }$$) #> '{data,membersCollection,edges,0,node,visitorFollowupsCollection,edges}'),
  1,
  'should list on Members.visitorFollowupsCollection the follow-ups of that visitor'
);

select is(
  pg_temp.graphql_as('super_admin', $$query { membersCollection(filter: { firstName: { eq: "AdultChoir" } }) { edges { node { household { name } } } } }$$) #>> '{data,membersCollection,edges,0,node,household,name}',
  'Alpha Household',
  'should resolve Members.household to the household of the member'
);

select is(
  jsonb_array_length(pg_temp.graphql_as('super_admin', $$query { householdsCollection(filter: { name: { eq: "Alpha Household" } }) { edges { node { membersCollection { edges { node { id } } } } } } }$$) #> '{data,householdsCollection,edges,0,node,membersCollection,edges}'),
  2,
  'should list on Households.membersCollection the two members of that household'
);

select is(
  pg_temp.graphql_as('super_admin', $$query { membersCollection(filter: { firstName: { eq: "AdultBoth" } }) { edges { node { memberDepartmentsCollection(orderBy: [{ departmentId: AscNullsLast }]) { edges { node { department { name } } } } } } } }$$) #>> '{data,membersCollection,edges,0,node,memberDepartmentsCollection,edges}',
  '[{"node": {"department": {"name": "Choir"}}}, {"node": {"department": {"name": "Youth"}}}]',
  'should resolve MemberDepartments.department to both departments of a member'
);

select is(
  pg_temp.graphql_as('super_admin', $$query { memberDepartmentsCollection(filter: { memberId: { eq: "60000000-0000-4000-8000-000000000005" } }) { edges { node { member { firstName } department { name } } } } }$$) #>> '{data,memberDepartmentsCollection,edges}',
  '[{"node": {"member": {"firstName": "MinorChildren"}, "department": {"name": "Children''s Ministry"}}}]',
  'should resolve MemberDepartments.member and department to the member and department of the link'
);

select is(
  jsonb_array_length(pg_temp.graphql_as('super_admin', $$query { departmentsCollection(filter: { name: { eq: "Choir" } }) { edges { node { memberDepartmentsCollection { edges { node { id } } } } } } }$$) #> '{data,departmentsCollection,edges,0,node,memberDepartmentsCollection,edges}'),
  5,
  'should list on Departments.memberDepartmentsCollection the five links to Choir'
);

update public.staff set member_id = '60000000-0000-4000-8000-000000000003' where id = (select staff_id from actors where label = 'usher');

select is(
  pg_temp.graphql_as('super_admin', $$query { membersCollection(filter: { firstName: { eq: "AdultNone" } }) { edges { node { staffCollection { edges { node { fullName } } } } } } }$$) #>> '{data,membersCollection,edges,0,node,staffCollection,edges,0,node,fullName}',
  'usher',
  'should list on Members.staffCollection the staff account of that person'
);

select is(
  pg_temp.graphql_as('super_admin', $$query { staffCollection(filter: { fullName: { eq: "usher" } }) { edges { node { member { firstName } } } } }$$) #>> '{data,staffCollection,edges,0,node,member,firstName}',
  'AdultNone',
  'should resolve Staff.member to the member record of the staff account'
);

select is(
  pg_temp.graphql_as('head_choir', $$query { staffCollection { edges { node { member { firstName } } } } }$$) #>> '{data,staffCollection,edges,0,node,member}',
  null,
  'should not reveal a member through a staff link the reader cannot see on members'
);

-- Mutations through GraphQL

select is(
  pg_temp.graphql_as('secretary', $$mutation { insertIntoMembersCollection(objects: [{ firstName: "Gql", lastName: "Adult", dateOfBirth: "1991-02-03", status: active }]) { affectedCount records { firstName status } } }$$) #> '{data,insertIntoMembersCollection}',
  '{"records": [{"status": "active", "firstName": "Gql"}], "affectedCount": 1}'::jsonb,
  'should let the secretary create a member through insertIntoMembersCollection'
);

select isnt(
  pg_temp.graphql_as('usher', $$mutation { insertIntoMembersCollection(objects: [{ firstName: "Gql", lastName: "Usher", dateOfBirth: "1991-02-03" }]) { affectedCount } }$$) -> 'errors',
  null,
  'should refuse the usher creating a member through GraphQL'
);

select is((select count(*) from public.members where last_name = 'Usher'), 0::bigint, 'should leave no member behind after the usher''s refused insert');

select isnt(
  pg_temp.graphql_as('secretary', format($$mutation { insertIntoMembersCollection(objects: [{ firstName: "Gql", lastName: "Minor", dateOfBirth: "%s" }]) { affectedCount } }$$, current_date - 100)) -> 'errors',
  null,
  'should refuse the secretary creating a minor through GraphQL'
);

select is(
  pg_temp.graphql_as('secretary', $$mutation { updateMembersCollection(set: { phone: "+233200000555" }, filter: { firstName: { eq: "AdultNone" } }) { affectedCount } }$$) #>> '{data,updateMembersCollection,affectedCount}',
  '1',
  'should let the secretary update a member through updateMembersCollection'
);

select is(
  pg_temp.graphql_as('usher', $$mutation { updateMembersCollection(set: { phone: "+233200000556" }, filter: { firstName: { eq: "AdultNone" } }) { affectedCount } }$$) #>> '{data,updateMembersCollection,affectedCount}',
  '0',
  'should update nothing when the usher tries updateMembersCollection'
);

select is(
  pg_temp.graphql_as('secretary', $$mutation { updateMembersCollection(set: { archivedAt: "2026-10-01T00:00:00Z" }, filter: { firstName: { eq: "Gql" } }) { affectedCount } }$$) #>> '{data,updateMembersCollection,affectedCount}',
  '1',
  'should let the secretary archive a member through GraphQL'
);

select is(
  pg_temp.graphql_as('secretary', $$mutation { updateMembersCollection(set: { phone: "+233200000557" }, filter: { firstName: { eq: "MinorChildren" } }) { affectedCount } }$$) #>> '{data,updateMembersCollection,affectedCount}',
  '0',
  'should update nothing when the secretary tries to change a minor'
);

select is(
  jsonb_array_length(pg_temp.graphql_as('secretary', $$query { membersCollection(filter: { firstName: { in: ["MinorChildren", "MinorChoir", "AdultNone"] } }) { edges { node { id } } } }$$) #> '{data,membersCollection,edges}'),
  1,
  'should show the secretary only the adult through membersCollection'
);

select isnt(pg_temp.graphql_as('secretary', $$mutation { deleteFromMembersCollection(filter: { firstName: { eq: "AdultNone" } }) { affectedCount } }$$) -> 'errors', null, 'should offer no deleteFromMembersCollection mutation');
select isnt(pg_temp.graphql_as('anon', $$mutation { insertIntoMembersCollection(objects: [{ firstName: "Anon", lastName: "Test" }]) { affectedCount } }$$) -> 'errors', null, 'should offer no member mutation to anon');
select isnt(pg_temp.graphql_as('anon', $$query { householdsCollection { edges { node { id } } } }$$) -> 'errors', null, 'should offer no households query to anon');
select isnt(pg_temp.graphql_as('anon', $$query { visitorFollowupsCollection { edges { node { id } } } }$$) -> 'errors', null, 'should offer no visitor follow-ups query to anon');
select isnt(pg_temp.graphql_as('anon', $$query { memberDepartmentsCollection { edges { node { id } } } }$$) -> 'errors', null, 'should offer no member departments query to anon');

select * from finish();

rollback;
