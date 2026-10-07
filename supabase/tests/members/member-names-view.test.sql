-- LBC-26 (AC 4, 7): the member_names view gives ushers and the treasurer names and status only, checks the
-- caller's role itself, hides minors from everyone but super admin and pastor, and is reachable through GraphQL.
-- Fixture and actors: see the preamble.

begin;

select plan(47);

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

-- member_names: names only, for ushers and the treasurer, who have no policy on members.

select columns_are('public', 'member_names', array['id', 'first_name', 'last_name', 'status'], 'should expose only id, first_name, last_name and status');

select is(
  (select reloptions from pg_class where oid = 'public.member_names'::regclass),
  array['security_invoker=false', 'security_barrier=true'],
  'should run the view with its owner rights, as a security barrier, and check the role inside it'
);

select is(has_table_privilege('authenticated', 'public.member_names', 'SELECT'), true, 'should let signed-in users select from the view');
select is(has_table_privilege('anon', 'public.member_names', 'SELECT'), false, 'should not let anon select from the view');
select is(has_table_privilege('authenticated', 'public.member_names', 'INSERT, UPDATE, DELETE'), false, 'should not let signed-in users write through the view');

select is(
  pg_temp.seen_as(label, 'public.member_names', 'first_name'),
  case when label in ('usher', 'treasurer', 'usher_and_head_children') then 'AdultBoth,AdultChoir,AdultNone,AdultYouth'
       when label = 'usher_and_pastor' then 'AdultBoth,AdultChoir,AdultNone,AdultYouth,MinorChildren,MinorChoir,UnknownDob'
       else '' end,
  format('should list for %s only the names they may see', label)
) from actors where label <> 'anon' order by label;

select is(pg_temp.seen_as('usher', 'public.member_names', 'status'), 'active,active,active,visitor', 'should show the usher the status of each person');
select is(pg_temp.seen_as('treasurer', 'public.member_names', 'last_name'), 'Test,Test,Test,Test', 'should show the treasurer last names');

select throws_ok(pg_temp.attempt('anon', 'select * from public.member_names'), '42501', null, 'should deny anon reading member_names');
select throws_ok(pg_temp.attempt('usher', 'select phone from public.member_names'), '42703', null, 'should not give the usher a phone column in the view');
select throws_ok(pg_temp.attempt('usher', 'select date_of_birth from public.member_names'), '42703', null, 'should not give the usher a date of birth column in the view');

select is(pg_temp.seen_as(label, 'public.members', 'phone'), '', format('should show %s no phone numbers from members', label))
from actors where label in ('usher', 'treasurer', 'usher_and_head_children') order by label;

select is(pg_temp.run_as(label, 'select * from public.members'), 0::bigint, format('should show %s no rows of members', label))
from actors where label in ('usher', 'treasurer') order by label;

select throws_ok(pg_temp.attempt('usher', $$insert into public.member_names (id, first_name, last_name, status) values (gen_random_uuid(), 'X', 'Y', 'active')$$), '42501', null, 'should reject an insert through the view');
select throws_ok(pg_temp.attempt('usher', $$update public.member_names set first_name = 'X'$$), '42501', null, 'should reject an update through the view');
select throws_ok(pg_temp.attempt('usher', 'delete from public.member_names'), '42501', null, 'should reject a delete through the view');

-- The view follows the caller's current role and the member's current state

update public.members set archived_at = now() where first_name = 'AdultYouth';
select is(pg_temp.seen_as('usher', 'public.member_names', 'first_name'), 'AdultBoth,AdultChoir,AdultNone', 'should drop an archived member from the view');

update public.staff_roles set role = 'content_editor'
where staff_id = (select staff_id from actors where label = 'usher');
select is(pg_temp.seen_as('usher', 'public.member_names', 'first_name'), '', 'should show nothing once the usher role is taken away');

-- GraphQL: the view is queryable because of its primary key directive

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

select is(
  jsonb_array_length(pg_temp.graphql_as('treasurer', $$query { memberNamesCollection { edges { node { id firstName lastName status } } } }$$) #> '{data,memberNamesCollection,edges}'),
  3,
  'should serve member_names to the treasurer through GraphQL'
);

select is(
  (select jsonb_agg(field ->> 'name' order by field ->> 'name')
   from jsonb_array_elements(pg_temp.graphql_as('treasurer', $$query { __type(name: "MemberNames") { fields { name } } }$$) #> '{data,__type,fields}') as field),
  '["firstName", "id", "lastName", "nodeId", "status"]'::jsonb,
  'should expose only the four columns, plus nodeId, on the MemberNames type'
);

select is(
  jsonb_array_length(pg_temp.graphql_as('super_admin', $$query { memberNamesCollection { edges { node { id } } } }$$) #> '{data,memberNamesCollection,edges}'),
  0,
  'should show the super admin nothing through the view'
);

select isnt(pg_temp.graphql_as('anon', $$query { memberNamesCollection { edges { node { id } } } }$$) -> 'errors', null, 'should not offer member_names to anon in GraphQL');
select isnt(pg_temp.graphql_as('anon', $$query { membersCollection { edges { node { id } } } }$$) -> 'errors', null, 'should not offer members to anon in GraphQL');
select is(
  jsonb_array_length(pg_temp.graphql_as('treasurer', $$query { membersCollection { edges { node { phone } } } }$$) #> '{data,membersCollection,edges}'),
  0,
  'should return the treasurer no members through the members collection'
);

select * from finish();

rollback;
