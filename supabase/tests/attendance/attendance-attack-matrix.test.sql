-- LBC-31: an attacker's view of services, attendance and programs. Each test tries something a hostile or careless
-- signed-in user, or anon, could try: reading or changing rows by guessing ids, probing for hidden members, nested
-- GraphQL reads, search_path tricks, calling private helpers, escalating privileges through recorded_by,
-- checked_in_by or the department, switching off the audit trigger, and oversized or malicious input. A passing
-- test means the attack failed. Fixture and actors: see the preamble.

begin;

select plan(63);

-- Fixture: start from an empty congregation, events and identity model so the demo seed cannot influence the results.
set local session_replication_role = replica;
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

-- One active actor per role, department heads of each department, staff holding two roles, a user with no staff
-- profile, an inactive staff member for most roles, and anon.
insert into actors (label)
values
  ('super_admin'), ('pastor'), ('treasurer'), ('secretary'), ('usher'), ('content_editor'),
  ('head_choir'), ('head_youth'), ('head_children'),
  ('head_choir_and_children'), ('usher_and_pastor'), ('usher_and_head_children'), ('no_role'), ('no_staff');

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
where label in ('super_admin', 'pastor', 'secretary', 'usher', 'head_choir', 'head_children');

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
select staff_id, label, is_active from actors where label not in ('anon', 'no_staff');

insert into public.staff_roles (staff_id, role, department_id)
select actors.staff_id, actor_roles.role, actor_roles.department_id
from actor_roles
join actors using (label);

-- Members (60...01 to 60...08). Ten years old is a minor, 1980 an adult. The names tell which department.
insert into public.members (id, first_name, last_name, date_of_birth, status)
values
  ('60000000-0000-4000-8000-000000000001', 'AdultChoir', 'Test', '1980-01-01', 'active'),
  ('60000000-0000-4000-8000-000000000002', 'AdultYouth', 'Test', '1980-01-01', 'active'),
  ('60000000-0000-4000-8000-000000000003', 'AdultNone', 'Test', '1980-01-01', 'visitor'),
  ('60000000-0000-4000-8000-000000000005', 'MinorChildren', 'Test', current_date - interval '10 years', 'active'),
  ('60000000-0000-4000-8000-000000000006', 'MinorChoir', 'Test', current_date - interval '10 years', 'active'),
  ('60000000-0000-4000-8000-000000000008', 'UnknownDob', 'Test', null, 'visitor');

insert into public.member_departments (member_id, department_id)
values
  ('60000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000002'),
  ('60000000-0000-4000-8000-000000000005', '40000000-0000-4000-8000-000000000003'),
  ('60000000-0000-4000-8000-000000000006', '40000000-0000-4000-8000-000000000001');

-- Programs, keyed by name (bb1...01 to 04): one per department and one with no department.
insert into public.programs (id, name, department_id)
values
  ('bb100000-0000-4000-8000-000000000001', 'ChoirProgram', '40000000-0000-4000-8000-000000000001'),
  ('bb100000-0000-4000-8000-000000000002', 'YouthProgram', '40000000-0000-4000-8000-000000000002'),
  ('bb100000-0000-4000-8000-000000000003', 'ChildrenProgram', '40000000-0000-4000-8000-000000000003'),
  ('bb100000-0000-4000-8000-000000000004', 'NoDeptProgram', null);

-- Services, keyed by name (bb2...01 to 06): two Sundays, a cancelled (archived) special service, and one event
-- for each of the choir, children's and youth programs.
insert into public.services (id, name, type, starts_at, program_id, archived_at)
values
  ('bb200000-0000-4000-8000-000000000001', 'SundayPast', 'sunday', '2026-09-27 08:00:00+00', null, null),
  ('bb200000-0000-4000-8000-000000000002', 'SundayNext', 'sunday', '2026-10-11 08:00:00+00', null, null),
  ('bb200000-0000-4000-8000-000000000003', 'ArchivedSpecial', 'special', '2026-10-18 08:00:00+00', null, '2026-10-01 00:00:00+00'),
  ('bb200000-0000-4000-8000-000000000004', 'ChoirEvent', 'program', '2026-11-14 17:00:00+00', 'bb100000-0000-4000-8000-000000000001', null),
  ('bb200000-0000-4000-8000-000000000005', 'ChildrenEvent', 'program', '2026-12-19 09:00:00+00', 'bb100000-0000-4000-8000-000000000003', null),
  ('bb200000-0000-4000-8000-000000000006', 'YouthEvent', 'program', '2026-12-20 09:00:00+00', 'bb100000-0000-4000-8000-000000000002', null);

-- Headcounts: SundayPast, ChoirEvent and ChildrenEvent, all recorded by the usher.
insert into public.attendance_counts (id, service_id, men, women, children, visitors, recorded_by)
select ids.id, ids.service_id, 10, 20, 30, 4, (select staff_id from actors where label = 'usher')
from (values
  ('bb300000-0000-4000-8000-000000000001'::uuid, 'bb200000-0000-4000-8000-000000000001'::uuid),
  ('bb300000-0000-4000-8000-000000000002'::uuid, 'bb200000-0000-4000-8000-000000000004'::uuid),
  ('bb300000-0000-4000-8000-000000000003'::uuid, 'bb200000-0000-4000-8000-000000000005'::uuid)
) as ids (id, service_id);

-- Check-ins: c1 usher checked in AdultChoir, c2 secretary checked in AdultNone, c3 super admin checked in
-- MinorChildren at SundayPast, c4 super admin checked in MinorChildren at the children's event.
insert into public.attendance_checkins (id, service_id, member_id, checked_in_by)
select ids.id, ids.service_id, ids.member_id, (select staff_id from actors where label = ids.actor)
from (values
  ('bb400000-0000-4000-8000-000000000001'::uuid, 'bb200000-0000-4000-8000-000000000001'::uuid, '60000000-0000-4000-8000-000000000001'::uuid, 'usher'),
  ('bb400000-0000-4000-8000-000000000002'::uuid, 'bb200000-0000-4000-8000-000000000001'::uuid, '60000000-0000-4000-8000-000000000003'::uuid, 'secretary'),
  ('bb400000-0000-4000-8000-000000000003'::uuid, 'bb200000-0000-4000-8000-000000000001'::uuid, '60000000-0000-4000-8000-000000000005'::uuid, 'super_admin'),
  ('bb400000-0000-4000-8000-000000000004'::uuid, 'bb200000-0000-4000-8000-000000000005'::uuid, '60000000-0000-4000-8000-000000000005'::uuid, 'super_admin')
) as ids (id, service_id, member_id, actor);

-- Participants: ChoirProgram has AdultChoir and MinorChoir, ChildrenProgram has MinorChildren and AdultChoir,
-- YouthProgram has AdultYouth.
insert into public.program_participants (id, program_id, member_id)
values
  ('bb500000-0000-4000-8000-000000000001', 'bb100000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000001'),
  ('bb500000-0000-4000-8000-000000000002', 'bb100000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000006'),
  ('bb500000-0000-4000-8000-000000000003', 'bb100000-0000-4000-8000-000000000003', '60000000-0000-4000-8000-000000000005'),
  ('bb500000-0000-4000-8000-000000000004', 'bb100000-0000-4000-8000-000000000003', '60000000-0000-4000-8000-000000000001'),
  ('bb500000-0000-4000-8000-000000000005', 'bb100000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000002');

create function pg_temp.try_as(p_label text, p_statement text)
returns text
language plpgsql
as $$
begin
  perform pg_temp.run_as(p_label, p_statement);
  return 'ok';
exception when others then
  return sqlstate || ':' || sqlerrm;
end;
$$;

-- 1. Guessing ids (IDOR): rows a role cannot see do not answer to their id either

select is(pg_temp.run_as('head_choir', $$select * from public.attendance_counts where id = 'bb300000-0000-4000-8000-000000000003'$$), 0::bigint, 'should not show a department head the count of another department''s event by its id');
select is(pg_temp.run_as('head_choir', $$select * from public.services where id = 'bb200000-0000-4000-8000-000000000005'$$), 0::bigint, 'should not show a department head another department''s service by its id');
select is(pg_temp.run_as('head_choir', $$select * from public.programs where id = 'bb100000-0000-4000-8000-000000000003'$$), 0::bigint, 'should not show a department head another department''s program by its id');
select is(pg_temp.run_as('secretary', $$select * from public.program_participants where id = 'bb500000-0000-4000-8000-000000000003'$$), 0::bigint, 'should not show the secretary a child''s registration by its id');
select is(pg_temp.run_as('secretary', $$select * from public.attendance_checkins where id = 'bb400000-0000-4000-8000-000000000003'$$), 0::bigint, 'should not show the secretary a child''s check-in by its id');
select is(pg_temp.run_as('usher', $$select * from public.attendance_checkins where id = 'bb400000-0000-4000-8000-000000000002'$$), 0::bigint, 'should not show an usher a check-in someone else made');
select is(pg_temp.run_as('usher', $$select * from public.services where id = 'bb200000-0000-4000-8000-000000000003'$$), 0::bigint, 'should not show an usher an archived service by its id');
select is(pg_temp.run_as('usher', $$update public.services set name = 'Pwned' where id = 'bb200000-0000-4000-8000-000000000001'$$), 0::bigint, 'should not let an usher rename a service by its id');
select is(pg_temp.run_as('head_children', $$update public.programs set name = 'Pwned' where id = 'bb100000-0000-4000-8000-000000000001'$$), 0::bigint, 'should not let a department head rename another department''s program by its id');
select is(pg_temp.run_as('head_children', $$delete from public.program_participants where id = 'bb500000-0000-4000-8000-000000000001'$$), 0::bigint, 'should not let a department head remove a registration of another program by its id');
select is((select count(*) from public.services where name = 'Pwned') + (select count(*) from public.programs where name = 'Pwned'), 0::bigint, 'should have changed nothing');

-- 2. Probing for hidden members through check-ins and registrations: a child, an unknown date of birth, a member that
-- does not exist and an archived member all answer the same way

select is(
  (select count(distinct sqlstate_and_message) from (
     select pg_temp.try_as('secretary', format($$insert into public.program_participants (program_id, member_id) values ('bb100000-0000-4000-8000-000000000004', %L)$$, member_id)) as sqlstate_and_message
     from (values ('60000000-0000-4000-8000-000000000005'::uuid), ('60000000-0000-4000-8000-000000000008'), ('00000000-0000-4000-8000-0000000000aa')) as probes (member_id)
   ) as answers),
  1::bigint, 'should answer a child, an unknown date of birth and a missing member identically when the secretary registers them');

select is(
  (select count(distinct answer) from (
     select pg_temp.try_as('usher', format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('bb200000-0000-4000-8000-000000000002', %L, %L)$$, member_id, (select staff_id from actors where label = 'usher'))) as answer
     from (values ('60000000-0000-4000-8000-000000000005'::uuid), ('60000000-0000-4000-8000-000000000008'), ('00000000-0000-4000-8000-0000000000aa')) as probes (member_id)
   ) as answers),
  1::bigint, 'should answer a child, an unknown date of birth and a missing member identically when an usher checks them in');

select is(pg_temp.seen_as('usher', 'public.member_names', 'first_name'), 'AdultChoir,AdultNone,AdultYouth', 'should list only adults with a known date of birth to an usher, the names the usher may act on');

-- 3. Nested GraphQL reads cannot reach a child through another path

select is(
  pg_temp.graphql_as('secretary', $$query { servicesCollection { edges { node { attendanceCheckinsCollection { edges { node { member { firstName dateOfBirth } } } } } } } }$$)::text ~ 'Minor',
  false, 'should not name a child anywhere in a nested read from services as the secretary');
select is(
  pg_temp.graphql_as('secretary', $$query { programsCollection { edges { node { programParticipantsCollection { edges { node { member { firstName } } } } } } } }$$)::text ~ 'Minor',
  false, 'should not name a child anywhere in a nested read from programs as the secretary');
select is(
  pg_temp.graphql_as('usher', $$query { servicesCollection { edges { node { attendanceCheckinsCollection { edges { node { member { firstName } } } } } } } }$$)::text ~ '(Adult|Minor)',
  false, 'should not name any member in a nested read as an usher');
select is(
  pg_temp.graphql_as('usher', $$query { servicesCollection { edges { node { program { name } } } } }$$)::text ~ 'Program',
  false, 'should not let an usher read programs through the service they are attached to');
select is(
  pg_temp.graphql_as('head_choir', $$query { programsCollection { edges { node { servicesCollection { edges { node { attendanceCheckinsCollection { edges { node { member { firstName } } } } } } } } } } }$$)::text ~ 'Minor',
  false, 'should not name a child in a nested read as a department head of another department');
select is(
  pg_temp.graphql_as('treasurer', $$query { servicesCollection { edges { node { id } } } }$$) #>> '{data,servicesCollection,edges}',
  '[]', 'should show the treasurer no services');
select is(
  pg_temp.graphql_as('content_editor', $$query { attendanceCountsCollection { edges { node { men } } } }$$) #>> '{data,attendanceCountsCollection,edges}',
  '[]', 'should show the content editor no counts');
select is(
  pg_temp.graphql_as('no_staff', $$query { programsCollection { edges { node { id } } } }$$) #>> '{data,programsCollection,edges}',
  '[]', 'should show a signed-in user with no staff profile no programs');
select is(
  pg_temp.graphql_as('inactive_usher', $$query { servicesCollection { edges { node { id } } } }$$) #>> '{data,servicesCollection,edges}',
  '[]', 'should show a deactivated usher no services');
select is(
  jsonb_array_length(pg_temp.graphql_as('usher', $$query { attendanceCheckinsCollection(first: 100) { edges { node { id } } } }$$) #> '{data,attendanceCheckinsCollection,edges}'),
  1, 'should show an usher only their own check-in however many they ask for');

-- 4. search_path tricks: a shadowing temp table or schema changes nothing

create function pg_temp.shadow_attack()
returns text
language plpgsql
as $$
declare
  v_original name := current_user;
  v_path text;
  v_result text;
begin
  perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', 'authenticated', 'sub', (select staff_id from actors where label = 'usher'))::text, true);
  perform set_config('role', 'authenticated', true);
  v_path := current_setting('search_path');
  perform set_config('search_path', 'pg_temp, public', true);
  create temp table services (id uuid, archived_at timestamptz);
  create temp table attendance_counts (id uuid);
  insert into pg_temp.services values ('bb200000-0000-4000-8000-000000000002', null);
  select (public.record_attendance_counts('bb200000-0000-4000-8000-000000000002', 7, 7, 7, 7)).men::text into v_result;
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  perform set_config('search_path', v_path, true);
  return v_result;
end;
$$;

select is(pg_temp.shadow_attack(), '7', 'should record into the real table whatever temp tables shadow its name');
select is((select count(*) from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000002' and men = 7), 1::bigint, 'should have written the count to public.attendance_counts');

-- 5. Private helpers and internals are not reachable

select throws_ok(pg_temp.attempt(label, 'select private.max_headcount()'), '42501', null, format('should deny %s calling a private rule value', label))
from actors where label in ('usher', 'secretary', 'super_admin', 'anon') order by label;
select throws_ok(pg_temp.attempt(label, $$select private.parse_service_templates('[]'::jsonb)$$), '42501', null, format('should deny %s calling the private template parser', label))
from actors where label in ('usher', 'secretary', 'super_admin', 'anon') order by label;
select throws_ok(pg_temp.attempt('super_admin', $$select audit.record_change()$$), '42501', null, 'should deny calling the audit trigger function directly');
select throws_ok(pg_temp.attempt('anon', $$select private.is_office_staff()$$), '42501', null, 'should deny anon calling a policy helper');
select throws_ok(pg_temp.attempt('usher', $$create table public.evil (id int)$$), '42501', null, 'should deny creating a table in public');
select throws_ok(pg_temp.attempt('usher', $$create function public.record_attendance_counts(uuid, integer, integer, integer, integer, integer) returns int language sql as 'select 1'$$), '42501', null, 'should deny planting a function in public');

-- 6. Switching the safety nets off

select throws_ok(pg_temp.attempt(label, 'set session_replication_role = replica'), '42501', null, format('should deny %s switching off triggers with session_replication_role', label))
from actors where label in ('usher', 'secretary', 'super_admin') order by label;
select throws_ok(pg_temp.attempt('super_admin', 'alter table public.services disable trigger audit_services'), '42501', null, 'should deny disabling the audit trigger');
select throws_ok(pg_temp.attempt('super_admin', 'alter table public.services disable row level security'), '42501', null, 'should deny disabling row level security');
select throws_ok(pg_temp.attempt('super_admin', 'truncate public.attendance_counts'), '42501', null, 'should deny truncating the counts');
select throws_ok(pg_temp.attempt('super_admin', 'truncate public.services cascade'), '42501', null, 'should deny truncating services');
select throws_ok(pg_temp.attempt('super_admin', 'drop table public.attendance_counts'), '42501', null, 'should deny dropping a table');

-- 7. Privilege escalation through the columns the caller controls

select throws_ok(
  pg_temp.attempt('usher', format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('bb200000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000002', %L)$$, (select staff_id from actors where label = 'secretary'))),
  '42501', null, 'should not let an usher check someone in as the secretary');
select throws_ok(
  pg_temp.attempt('usher', $$update public.attendance_counts set recorded_by = (select id from public.staff limit 1)$$),
  '42501', null, 'should not let an usher change recorded_by directly');
select throws_ok(
  pg_temp.attempt('secretary', $$update public.attendance_counts set men = 0$$),
  '42501', null, 'should not let the secretary edit a count outside the function');
select throws_ok(
  pg_temp.attempt('head_choir', $$update public.programs set department_id = '40000000-0000-4000-8000-000000000003' where name = 'ChoirProgram'$$),
  '42501', null, 'should not let a department head hand their program to a department they do not head');
select is(
  pg_temp.run_as('head_choir', $$update public.programs set department_id = '40000000-0000-4000-8000-000000000001' where name = 'ChildrenProgram'$$),
  0::bigint, 'should not let a department head pull another department''s program into theirs');
select throws_ok(
  pg_temp.attempt('usher', $$insert into public.staff_roles (staff_id, role, granted_by) values ((select staff_id from actors where label = 'usher'), 'super_admin', (select staff_id from actors where label = 'usher'))$$),
  '42501', null, 'should not let an usher grant themselves a role to reach more attendance data');
select is(
  pg_temp.run_as('usher', $$update public.services set archived_at = null where id = 'bb200000-0000-4000-8000-000000000003'$$),
  0::bigint, 'should not let an usher un-archive a service');
select throws_ok(
  pg_temp.attempt('super_admin', $$update public.attendance_checkins set checked_in_at = now() - interval '1 year'$$),
  '42501', null, 'should not let anyone backdate a check-in');
select throws_ok(
  pg_temp.attempt('secretary', $$insert into public.services (name, type, starts_at, created_at) values ('Back', 'special', now(), '2000-01-01')$$),
  '42501', null, 'should not let anyone set created_at on a service');

-- 8. Hostile input

select throws_ok(pg_temp.attempt('usher', $$select * from public.record_attendance_counts('bb200000-0000-4000-8000-000000000002', 2147483647, 0, 0, 0)$$), 'P0001', 'VALIDATION_FAILED', 'should reject the largest integer as a count');
select throws_ok(pg_temp.attempt('usher', $$select * from public.record_attendance_counts('bb200000-0000-4000-8000-000000000002', -2147483648, 0, 0, 0)$$), 'P0001', 'VALIDATION_FAILED', 'should reject the smallest integer as a count');
select throws_ok(pg_temp.attempt('usher', $$select * from public.record_attendance_counts('bb200000-0000-4000-8000-000000000002', 2147483648, 0, 0, 0)$$), '42883', null, 'should reject a count that does not fit an integer');
select throws_ok(pg_temp.attempt('usher', $$select * from public.record_attendance_counts('bb200000-0000-4000-8000-000000000002', 'ten', 0, 0, 0)$$), '22P02', null, 'should reject a count that is text');
select is(
  (select (men, women, children, visitors)::text from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000002'),
  '(7,7,7,7)', 'should keep the last valid count after every hostile call');
select lives_ok(
  $$select pg_temp.run_as('secretary', $q$insert into public.services (name, type, starts_at) values ('Bobby''); drop table public.services;--', 'special', now() + interval '500 days')$q$)$$,
  'should store a service name with SQL in it as plain text');
select is((select count(*) from public.services where name like 'Bobby%'), 1::bigint, 'should hold the odd service name as data');
select has_table('public', 'services', 'should still have the services table');

select * from finish();

rollback;
