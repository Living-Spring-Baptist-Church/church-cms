-- LBC-26: attempts to get around the congregation policies, written as an attacker would: private helpers,
-- escalation through neighbouring tables, upserts and updates on rows the writer cannot read, probing ids,
-- error-message leaks through member_names, node ids and nested GraphQL reads, and mid-session deactivation.
-- Every test expects the attempt to fail or to show nothing. Fixture and actors: see the preamble.

begin;

select plan(46);

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
  perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', v_db_role, 'sub', (select staff_id from actors where label = p_label))::text, true);
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
  perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', v_db_role, 'sub', (select staff_id from actors where label = p_label))::text, true);
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
  perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', v_db_role, 'sub', (select staff_id from actors where label = p_label))::text, true);
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

-- Reaching private helpers, the audit log or a higher role directly

select throws_ok(pg_temp.attempt(label, format('select private.%s', helper)), '42501', null, format('should refuse %s calling private.%s directly', label, helper))
from actors
cross join (values ('is_minor(current_date)'), ('can_view_minors()'), ('can_manage_members()'), ('heads_department_of_member(gen_random_uuid(), false)'), ('age_of_majority()')) as helpers (helper)
where label in ('secretary', 'usher', 'anon')
order by label, helper;

select throws_ok(pg_temp.attempt(label, 'select * from audit.log'), '42501', null, format('should refuse %s reading the audit log', label))
from actors where label in ('super_admin', 'secretary', 'anon') order by label;

select is(has_schema_privilege('authenticated', 'public', 'CREATE'), false, 'should not let signed-in users create objects in public, so they cannot add leaky functions');
select is(has_schema_privilege('authenticated', 'private', 'USAGE'), false, 'should keep the private schema closed to signed-in users');

-- A different search_path does not change what the helpers see

create function pg_temp.count_members_with_search_path(p_label text, p_search_path text)
returns bigint
language plpgsql
as $$
declare
  v_original_path text := current_setting('search_path');
  v_count bigint;
begin
  perform set_config('search_path', p_search_path, true);
  v_count := pg_temp.run_as(p_label, 'select * from public.members');
  perform set_config('search_path', v_original_path, true);
  return v_count;
end;
$$;

select is(
  pg_temp.count_members_with_search_path('secretary', 'pg_temp, public'),
  5::bigint,
  'should show the secretary the same members whatever search_path they set'
);

-- Role escalation through the neighbouring tables

select is(pg_temp.run_as('secretary', $$update public.staff set member_id = '60000000-0000-4000-8000-000000000005'$$), 0::bigint, 'should not let the secretary link a staff account to a member');
select throws_ok(pg_temp.attempt('secretary', $$insert into public.staff_roles (staff_id, role, granted_by) select staff_id, 'super_admin', staff_id from actors where label = 'secretary'$$), '42501', null, 'should refuse the secretary granting herself super admin');
select is(pg_temp.run_as('secretary', $$update public.departments set is_childrens_ministry = true$$), 0::bigint, 'should not let the secretary turn a department into a children''s ministry to reach minors');
select is(pg_temp.run_as('head_choir', $$update public.departments set is_childrens_ministry = true where name = 'Choir'$$), 0::bigint, 'should not let a department head flag their own department as children''s ministry');
select is(pg_temp.seen_as('head_choir', 'public.members', 'first_name'), 'AdultBoth,AdultChoir', 'should still hide minors from the head of Choir after the escalation attempts');

-- Writes that would reveal or reach rows the writer cannot read

select throws_ok(pg_temp.attempt('secretary', $$insert into public.members (id, first_name, last_name, date_of_birth) values ('60000000-0000-4000-8000-000000000005', 'Take', 'Over', '1990-01-01') on conflict (id) do update set first_name = excluded.first_name$$), '42501', null, 'should refuse an upsert that targets the id of a minor');
select is(pg_temp.run_as('secretary', $$update public.members set household_id = '30000000-0000-4000-8000-000000000001' where first_name = 'MinorChoir'$$), 0::bigint, 'should not let the secretary move a minor into a household');
select is(pg_temp.run_as('secretary', $$update public.members set first_name = 'Renamed' where date_of_birth is null$$), 0::bigint, 'should not let the secretary update members with an unknown date of birth');
select is((select first_name from public.members where id = '60000000-0000-4000-8000-000000000008'), 'UnknownDob', 'should leave the unknown-age member untouched');

-- Probing ids: the answer is the same for a hidden row and a row that does not exist

select throws_ok(pg_temp.attempt('secretary', $$insert into public.visitor_followups (member_id) values ('60000000-0000-4000-8000-000000000005')$$), '42501', null, 'should refuse a follow-up for a minor the secretary cannot see');
select throws_ok(pg_temp.attempt('secretary', $$insert into public.visitor_followups (member_id) values (gen_random_uuid())$$), '42501', null, 'should refuse a follow-up for an id that does not exist with the same error');

-- A name filtered out of member_names cannot leak through an error message (the view is a security barrier)

create function pg_temp.error_text_of(p_label text, p_statement text)
returns text
language plpgsql
as $$
begin
  perform pg_temp.run_as(p_label, p_statement);
  return 'no error';
exception when others then
  return sqlerrm;
end;
$$;

select is(
  pg_temp.error_text_of('usher', 'select * from public.member_names where first_name::int > 0') ~ '(Minor|Unknown)',
  false,
  'should not leak the name of a hidden minor through a cast error on the view'
);

select is(
  pg_temp.error_text_of('usher', 'select * from public.member_names where 1 / (length(first_name) - length(first_name)) > 0') ~ '(Minor|Unknown)',
  false,
  'should not leak the existence of a hidden member through a division error on the view'
);

select is(
  pg_temp.error_text_of('usher', $$select * from public.member_names where first_name = 'MinorChildren'$$),
  'no error',
  'should answer a search for a hidden minor''s name with an empty result, not an error'
);

select is(pg_temp.run_as('usher', $$select * from public.member_names where first_name = 'MinorChildren'$$), 0::bigint, 'should find no hidden minor by name through the view');

-- Nested GraphQL reads cannot route around the policies

create function pg_temp.node_id_of(p_first_name text)
returns text
language sql
as $$
  select pg_temp.graphql_as('super_admin', format('query { membersCollection(filter: { firstName: { eq: "%s" } }) { edges { node { nodeId } } } }', p_first_name)) #>> '{data,membersCollection,edges,0,node,nodeId}';
$$;

select isnt(pg_temp.node_id_of('AdultYouth'), null, 'should give the super admin a node id to try');

select is(
  pg_temp.graphql_as('head_choir', format('query { node(nodeId: "%s") { ... on Members { firstName } } }', pg_temp.node_id_of('AdultYouth'))) #> '{data,node}',
  'null'::jsonb,
  'should return null when a department head asks for another department''s member by node id'
);

select is(
  pg_temp.graphql_as('secretary', format('query { node(nodeId: "%s") { ... on Members { firstName } } }', pg_temp.node_id_of('MinorChildren'))) #> '{data,node}',
  'null'::jsonb,
  'should return null when the secretary asks for a minor by node id'
);

select is(
  pg_temp.graphql_as('head_choir', format('query { node(nodeId: "%s") { ... on Members { firstName } } }', pg_temp.node_id_of('AdultBoth'))) #>> '{data,node,firstName}',
  'AdultBoth',
  'should return the member when a department head asks for their own department''s member by node id'
);

select is(
  jsonb_array_length(pg_temp.graphql_as('head_choir', $$query { membersCollection(filter: { firstName: { eq: "AdultBoth" } }) { edges { node { memberDepartmentsCollection { edges { node { department { name } } } } } } } }$$) #> '{data,membersCollection,edges,0,node,memberDepartmentsCollection,edges}'),
  1,
  'should show a department head only their own department among a member''s departments'
);

select is(
  jsonb_array_length(pg_temp.graphql_as('secretary', $$query { householdsCollection(filter: { name: { eq: "Beta Household" } }) { edges { node { membersCollection { edges { node { id } } } } } } }$$) #> '{data,householdsCollection,edges,0,node,membersCollection,edges}'),
  0,
  'should show the secretary no members of a household that holds only minors'
);

select is(
  jsonb_array_length(pg_temp.graphql_as('pastor', $$query { householdsCollection(filter: { name: { eq: "Beta Household" } }) { edges { node { membersCollection { edges { node { id } } } } } } }$$) #> '{data,householdsCollection,edges,0,node,membersCollection,edges}'),
  2,
  'should show the pastor the minors of a household'
);

-- A staff member who loses a role or is deactivated mid-session loses access at once

update public.staff set is_active = false where id = (select staff_id from actors where label = 'secretary');
select is(pg_temp.run_as('secretary', 'select * from public.members'), 0::bigint, 'should show a deactivated secretary no members');
select throws_ok(pg_temp.attempt('secretary', $$insert into public.members (first_name, last_name, date_of_birth) values ('Late', 'Test', '1990-01-01')$$), '42501', null, 'should refuse a deactivated secretary creating a member');
delete from public.staff_roles where staff_id = (select staff_id from actors where label = 'head_choir');
select is(pg_temp.run_as('head_choir', 'select * from public.members'), 0::bigint, 'should show a former department head no members');

select * from finish();

rollback;
