-- LBC-31 (AC 4, 5, 6): row level security and grants on programs, services, attendance_counts,
-- attendance_checkins and program_participants for every role, table and action: super admin, pastor, treasurer,
-- secretary, usher, department head (own program and others), content editor, inactive staff, a signed-in user with
-- no staff profile, and anon. Fixture and actors: see the preamble. The finance tables do not exist yet; when they
-- do, the treasurer, content editor and usher denials below extend to them.

begin;

select plan(290);

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
-- MinorChildren at SundayPast, c4 super admin checked in MinorChildren at the children's event, c5 super admin
-- checked in MinorChoir (a minor outside the children's ministry) at SundayPast.
insert into public.attendance_checkins (id, service_id, member_id, checked_in_by)
select ids.id, ids.service_id, ids.member_id, (select staff_id from actors where label = ids.actor)
from (values
  ('bb400000-0000-4000-8000-000000000001'::uuid, 'bb200000-0000-4000-8000-000000000001'::uuid, '60000000-0000-4000-8000-000000000001'::uuid, 'usher'),
  ('bb400000-0000-4000-8000-000000000002'::uuid, 'bb200000-0000-4000-8000-000000000001'::uuid, '60000000-0000-4000-8000-000000000003'::uuid, 'secretary'),
  ('bb400000-0000-4000-8000-000000000003'::uuid, 'bb200000-0000-4000-8000-000000000001'::uuid, '60000000-0000-4000-8000-000000000005'::uuid, 'super_admin'),
  ('bb400000-0000-4000-8000-000000000004'::uuid, 'bb200000-0000-4000-8000-000000000005'::uuid, '60000000-0000-4000-8000-000000000005'::uuid, 'super_admin'),
  ('bb400000-0000-4000-8000-000000000005'::uuid, 'bb200000-0000-4000-8000-000000000001'::uuid, '60000000-0000-4000-8000-000000000006'::uuid, 'super_admin')
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

-- Who sees which rows. Expected row counts per actor; every actor not listed sees none.

create temp table expected_rows (label text not null, relation text not null, row_count bigint not null);
insert into expected_rows
values
  -- programs: super admin, secretary, pastor all 4; a department head the programs of the departments they head
  ('super_admin', 'programs', 4), ('secretary', 'programs', 4), ('pastor', 'programs', 4), ('usher_and_pastor', 'programs', 4),
  ('head_choir', 'programs', 1), ('head_youth', 'programs', 1), ('head_children', 'programs', 1),
  ('head_choir_and_children', 'programs', 2), ('usher_and_head_children', 'programs', 1),
  -- services: 6 including the archived one. Ushers see the 5 current ones. Heads see the services of their programs.
  ('super_admin', 'services', 6), ('secretary', 'services', 6), ('pastor', 'services', 6), ('usher_and_pastor', 'services', 6),
  ('usher', 'services', 5), ('usher_and_head_children', 'services', 5),
  ('head_choir', 'services', 1), ('head_youth', 'services', 1), ('head_children', 'services', 1), ('head_choir_and_children', 'services', 2),
  -- attendance_counts: 3 rows
  ('super_admin', 'attendance_counts', 3), ('secretary', 'attendance_counts', 3), ('pastor', 'attendance_counts', 3),
  ('usher', 'attendance_counts', 3), ('usher_and_pastor', 'attendance_counts', 3), ('usher_and_head_children', 'attendance_counts', 3),
  ('head_choir', 'attendance_counts', 1), ('head_youth', 'attendance_counts', 0), ('head_children', 'attendance_counts', 1),
  ('head_choir_and_children', 'attendance_counts', 2),
  -- attendance_checkins: 5 rows, each visible only together with its member (the secretary sees the child of the children's ministry)
  ('super_admin', 'attendance_checkins', 5), ('pastor', 'attendance_checkins', 5), ('usher_and_pastor', 'attendance_checkins', 5),
  ('secretary', 'attendance_checkins', 4),
  ('usher', 'attendance_checkins', 1), ('usher_and_head_children', 'attendance_checkins', 1),
  ('head_children', 'attendance_checkins', 1), ('head_choir_and_children', 'attendance_checkins', 1),
  -- program_participants: 5 rows, each visible only together with its member
  ('super_admin', 'program_participants', 5), ('pastor', 'program_participants', 5), ('usher_and_pastor', 'program_participants', 5),
  ('secretary', 'program_participants', 4),
  ('head_choir', 'program_participants', 1), ('head_youth', 'program_participants', 1), ('head_children', 'program_participants', 1),
  ('head_choir_and_children', 'program_participants', 3), ('usher_and_head_children', 'program_participants', 1);

select is(
  pg_temp.run_as(actors.label, format('select * from public.%I', relations.relation)),
  coalesce((select row_count from expected_rows where expected_rows.label = actors.label and expected_rows.relation = relations.relation), 0),
  format('should show %s %s of the %s rows', actors.label,
    coalesce((select row_count from expected_rows where expected_rows.label = actors.label and expected_rows.relation = relations.relation), 0), relations.relation)
)
from actors
cross join (values ('programs'), ('services'), ('attendance_counts'), ('attendance_checkins'), ('program_participants')) as relations (relation)
where actors.label <> 'anon'
order by relations.relation, actors.label;

select throws_ok(pg_temp.attempt('anon', format('select * from public.%I', relation)), '42501', null, format('should deny anon reading %s', relation))
from unnest(array['programs', 'services', 'attendance_counts', 'attendance_checkins', 'program_participants']) as relations (relation);

select is(
  pg_temp.seen_as('head_choir', 'public.programs', 'name'), 'ChoirProgram', 'should show a department head only the program of their own department');
select is(
  pg_temp.seen_as('usher', 'public.services', 'name'), 'ChildrenEvent,ChoirEvent,SundayNext,SundayPast,YouthEvent', 'should hide the archived service from an usher');
select is(
  pg_temp.seen_as('head_choir', 'public.attendance_counts', 'men'), '10', 'should show a department head only the count of a service of their program');

-- services: super admin and secretary create and edit; nobody deletes

select is(
  pg_temp.run_as(label, $$insert into public.services (name, type, starts_at) values ('NewService ' || gen_random_uuid(), 'special', now() + interval '400 days')$$),
  1::bigint, format('should let %s create a service', label))
from actors where label in ('super_admin', 'secretary') order by label;

select throws_ok(
  pg_temp.attempt(label, $$insert into public.services (name, type, starts_at) values ('DeniedService', 'special', '2027-01-02 09:00:00+00')$$),
  '42501', null, format('should reject %s creating a service', label))
from actors where label not in ('super_admin', 'secretary') order by label;

select is(
  pg_temp.run_as(label, $$update public.services set name = name where name = 'SundayNext'$$),
  case when label in ('super_admin', 'secretary') then 1 else 0 end::bigint,
  format('should let %s edit a service only if super admin or secretary', label))
from actors where label <> 'anon' order by label;

select throws_ok(pg_temp.attempt('anon', $$update public.services set name = 'AnonRename'$$), '42501', null, 'should deny anon updating services');

select throws_ok(
  pg_temp.attempt(label, $$delete from public.services where name = 'SundayPast'$$),
  '42501', null, format('should not let %s delete a service', label))
from actors where label in ('super_admin', 'secretary', 'usher', 'pastor', 'anon') order by label;

select throws_ok(
  pg_temp.attempt('super_admin', $$update public.services set id = gen_random_uuid() where name = 'SundayPast'$$),
  '42501', null, 'should not let anyone change a service id');

select is(
  pg_temp.run_as('secretary', $$update public.services set archived_at = now() where name = 'YouthEvent'$$),
  1::bigint, 'should let the secretary archive a service');

-- attendance_counts: no direct write for anybody, the function is the only path

select throws_ok(
  pg_temp.attempt(label, $$insert into public.attendance_counts (service_id, recorded_by) values ('bb200000-0000-4000-8000-000000000002', (select id from public.staff limit 1))$$),
  '42501', null, format('should not let %s insert a count directly', label))
from actors where label in ('super_admin', 'secretary', 'usher', 'pastor', 'head_choir', 'anon') order by label;

select throws_ok(
  pg_temp.attempt(label, $$update public.attendance_counts set men = 99$$),
  '42501', null, format('should not let %s update a count directly', label))
from actors where label in ('super_admin', 'secretary', 'usher', 'pastor', 'head_choir', 'anon') order by label;

select throws_ok(
  pg_temp.attempt(label, $$delete from public.attendance_counts$$),
  '42501', null, format('should not let %s delete a count directly', label))
from actors where label in ('super_admin', 'secretary', 'usher', 'pastor', 'head_choir', 'anon') order by label;

-- programs: super admin and secretary create and edit all; a head creates and edits only for their department

select is(
  pg_temp.run_as(label, $$insert into public.programs (name, department_id) values ('OfficeProgram', '40000000-0000-4000-8000-000000000002')$$),
  1::bigint, format('should let %s create a program for any department', label))
from actors where label in ('super_admin', 'secretary') order by label;

select is(
  pg_temp.run_as('head_choir', $$insert into public.programs (name, department_id) values ('HeadProgram', '40000000-0000-4000-8000-000000000001')$$),
  1::bigint, 'should let a department head create a program for their own department');

select throws_ok(
  pg_temp.attempt('head_choir', $$insert into public.programs (name, department_id) values ('Stolen', '40000000-0000-4000-8000-000000000002')$$),
  '42501', null, 'should reject a department head creating a program for another department');

select throws_ok(
  pg_temp.attempt('head_choir', $$insert into public.programs (name, department_id) values ('NoDept', null)$$),
  '42501', null, 'should reject a department head creating a program with no department');

select throws_ok(
  pg_temp.attempt(label, $$insert into public.programs (name, department_id) values ('Denied', '40000000-0000-4000-8000-000000000001')$$),
  '42501', null, format('should reject %s creating a program', label))
from actors where label in ('pastor', 'treasurer', 'usher', 'content_editor', 'no_role', 'no_staff', 'anon', 'inactive_super_admin', 'inactive_secretary', 'inactive_head_choir', 'head_youth') order by label;

select is(
  pg_temp.run_as('head_choir', $$update public.programs set description = 'Edited' where name = 'ChoirProgram'$$),
  1::bigint, 'should let a department head edit a program of their department');

select is(
  pg_temp.run_as('head_youth', $$update public.programs set description = 'Edited' where name = 'ChoirProgram'$$),
  0::bigint, 'should not let a department head edit the program of another department');

select throws_ok(
  pg_temp.attempt('head_choir', $$update public.programs set department_id = '40000000-0000-4000-8000-000000000002' where name = 'ChoirProgram'$$),
  '42501', null, 'should not let a department head move a program into a department they do not head');

select throws_ok(
  pg_temp.attempt('head_choir', $$update public.programs set department_id = null where name = 'ChoirProgram'$$),
  '42501', null, 'should not let a department head remove the department from a program');

select is(
  pg_temp.run_as('head_choir', $$update public.programs set archived_at = now() where name = 'ChoirProgram'$$),
  1::bigint, 'should let a department head archive a program of their department');

select is(
  pg_temp.run_as(label, $$update public.programs set description = 'Edited' where name = 'NoDeptProgram'$$),
  case when label in ('super_admin', 'secretary') then 1 else 0 end::bigint,
  format('should let %s edit a program with no department only if super admin or secretary', label))
from actors where label <> 'anon' order by label;

select throws_ok(pg_temp.attempt('anon', $$update public.programs set name = 'x'$$), '42501', null, 'should deny anon updating programs');

select throws_ok(
  pg_temp.attempt(label, $$delete from public.programs$$),
  '42501', null, format('should not let %s delete a program', label))
from actors where label in ('super_admin', 'secretary', 'head_choir', 'anon') order by label;

select throws_ok(
  pg_temp.attempt('super_admin', $$insert into public.programs (name, starts_on, ends_on) values ('Backwards', '2026-02-02', '2026-02-01')$$),
  '23514', null, 'should reject a program that ends before it starts');

select throws_ok(
  pg_temp.attempt('super_admin', $$insert into public.programs (name) values ('   ')$$),
  '23514', null, 'should reject a program with a blank name');

select throws_ok(
  pg_temp.attempt('super_admin', $$insert into public.services (name, type, starts_at) values ('SundayPast', 'sunday', '2026-09-27 08:00:00+00')$$),
  '23505', null, 'should reject listing the same service twice');

-- attendance_checkins: ushers act on adults listed in member_names, the office on members it can see

select is(
  pg_temp.run_as('usher', format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('bb200000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000002', %L)$$, (select staff_id from actors where label = 'usher'))),
  1::bigint, 'should let an usher check in an adult');

select throws_ok(
  pg_temp.attempt('usher', format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('bb200000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000005', %L)$$, (select staff_id from actors where label = 'usher'))),
  '42501', null, 'should not let an usher check in a child');

select throws_ok(
  pg_temp.attempt('usher', format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('bb200000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000008', %L)$$, (select staff_id from actors where label = 'usher'))),
  '42501', null, 'should not let an usher check in a person with no date of birth');

select throws_ok(
  pg_temp.attempt('usher', format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('bb200000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000003', %L)$$, (select staff_id from actors where label = 'secretary'))),
  '42501', null, 'should not let an usher check in someone as another staff member');

select throws_ok(
  pg_temp.attempt('usher', format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('bb200000-0000-4000-8000-000000000003', '60000000-0000-4000-8000-000000000003', %L)$$, (select staff_id from actors where label = 'usher'))),
  '42501', null, 'should not let an usher check in to an archived service');

select throws_ok(
  pg_temp.attempt('usher', format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values (gen_random_uuid(), '60000000-0000-4000-8000-000000000003', %L)$$, (select staff_id from actors where label = 'usher'))),
  '42501', null, 'should answer the same for an unknown service as for an archived one');

select throws_ok(
  pg_temp.attempt('usher', format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('bb200000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000001', %L)$$, (select staff_id from actors where label = 'usher'))),
  '23505', null, 'should reject checking in the same person to the same service twice');

select is(
  pg_temp.run_as('secretary', format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('bb200000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000003', %L)$$, (select staff_id from actors where label = 'secretary'))),
  1::bigint, 'should let the secretary check in an adult');

select is(
  pg_temp.run_as('secretary', format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('bb200000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000005', %L)$$, (select staff_id from actors where label = 'secretary'))),
  1::bigint, 'should let the secretary check in a child of the children''s ministry');

select throws_ok(
  pg_temp.attempt('secretary', format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('bb200000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000006', %L)$$, (select staff_id from actors where label = 'secretary'))),
  '42501', null, 'should not let the secretary check in a minor outside the children''s ministry');

select is(
  pg_temp.run_as('super_admin', format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('bb200000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000006', %L)$$, (select staff_id from actors where label = 'super_admin'))),
  1::bigint, 'should let the super admin check in a child');

select throws_ok(
  pg_temp.attempt(label, format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('bb200000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000002', %L)$$, (select staff_id from actors where actors.label = a.label))),
  '42501', null, format('should reject %s checking someone in', label))
from (select label from actors where label in ('pastor', 'treasurer', 'content_editor', 'head_choir', 'head_children', 'no_role', 'no_staff', 'anon', 'inactive_usher', 'inactive_super_admin', 'inactive_secretary')) as a
order by label;

select throws_ok(
  pg_temp.attempt('super_admin', $$update public.attendance_checkins set member_id = '60000000-0000-4000-8000-000000000002'$$),
  '42501', null, 'should not let anyone update a check-in');

select is(pg_temp.run_as('usher', $$delete from public.attendance_checkins where id = 'bb400000-0000-4000-8000-000000000001'$$), 1::bigint, 'should let an usher remove their own check-in of an adult');
select is(pg_temp.run_as('usher', $$delete from public.attendance_checkins where id = 'bb400000-0000-4000-8000-000000000002'$$), 0::bigint, 'should not let an usher remove a check-in made by someone else');
select is(pg_temp.run_as('usher', $$delete from public.attendance_checkins where id = 'bb400000-0000-4000-8000-000000000003'$$), 0::bigint, 'should not let an usher remove the check-in of a child');
select is(pg_temp.run_as('secretary', $$delete from public.attendance_checkins where id = 'bb400000-0000-4000-8000-000000000002'$$), 1::bigint, 'should let the secretary remove the check-in of an adult');
select is(pg_temp.run_as('secretary', $$delete from public.attendance_checkins where id = 'bb400000-0000-4000-8000-000000000005'$$), 0::bigint, 'should not let the secretary remove the check-in of a minor outside the children''s ministry');
select is(pg_temp.run_as('secretary', $$delete from public.attendance_checkins where id = 'bb400000-0000-4000-8000-000000000003'$$), 1::bigint, 'should let the secretary remove the check-in of a child of the children''s ministry');
select is(pg_temp.run_as('super_admin', $$delete from public.attendance_checkins where id = 'bb400000-0000-4000-8000-000000000005'$$), 1::bigint, 'should let the super admin remove the check-in of a child');
select is(pg_temp.run_as(label, $$delete from public.attendance_checkins$$), 0::bigint, format('should not let %s remove check-ins', label))
from actors where label in ('pastor', 'head_children', 'treasurer', 'no_role', 'no_staff') order by label;
select throws_ok(pg_temp.attempt('anon', $$delete from public.attendance_checkins$$), '42501', null, 'should deny anon removing check-ins');

-- program_participants: office for members they can see, a head for their own programs

select is(
  pg_temp.run_as(label, $$insert into public.program_participants (program_id, member_id) values ('bb100000-0000-4000-8000-000000000004', '60000000-0000-4000-8000-000000000003')$$),
  1::bigint, format('should let %s register an adult for any program', label))
from actors where label = 'super_admin' union all
select is(
  pg_temp.run_as(label, $$insert into public.program_participants (program_id, member_id) values ('bb100000-0000-4000-8000-000000000004', '60000000-0000-4000-8000-000000000002')$$),
  1::bigint, format('should let %s register an adult for any program', label))
from actors where label = 'secretary';

select throws_ok(
  pg_temp.attempt('secretary', $$insert into public.program_participants (program_id, member_id) values ('bb100000-0000-4000-8000-000000000004', '60000000-0000-4000-8000-000000000006')$$),
  '42501', null, 'should not let the secretary register a minor outside the children''s ministry');

select is(
  pg_temp.run_as('secretary', $$insert into public.program_participants (program_id, member_id) values ('bb100000-0000-4000-8000-000000000004', '60000000-0000-4000-8000-000000000005')$$),
  1::bigint, 'should let the secretary register a child of the children''s ministry');

select throws_ok(
  pg_temp.attempt('secretary', $$insert into public.program_participants (program_id, member_id) values ('bb100000-0000-4000-8000-000000000004', gen_random_uuid())$$),
  '42501', null, 'should answer the same for an unknown member as for a child, so ids cannot be probed');

select throws_ok(
  pg_temp.attempt('head_children', $$insert into public.program_participants (program_id, member_id) values ('bb100000-0000-4000-8000-000000000003', '60000000-0000-4000-8000-000000000005')$$),
  '23505', null, 'should reject registering the same child for the same program twice');

select throws_ok(
  pg_temp.attempt('head_children', $$insert into public.program_participants (program_id, member_id) values ('bb100000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000005')$$),
  '42501', null, 'should not let a department head register someone for the program of another department');

select throws_ok(
  pg_temp.attempt('head_choir', $$insert into public.program_participants (program_id, member_id) values ('bb100000-0000-4000-8000-000000000001', '60000000-0000-4000-8000-000000000003')$$),
  '42501', null, 'should not let a department head register a member they cannot see');

select throws_ok(
  pg_temp.attempt(label, $$insert into public.program_participants (program_id, member_id) values ('bb100000-0000-4000-8000-000000000004', '60000000-0000-4000-8000-000000000002')$$),
  '42501', null, format('should reject %s registering a participant', label))
from actors where label in ('pastor', 'treasurer', 'usher', 'content_editor', 'no_role', 'no_staff', 'anon', 'inactive_super_admin', 'inactive_secretary', 'inactive_head_children') order by label;

select throws_ok(
  pg_temp.attempt('super_admin', $$update public.program_participants set member_id = '60000000-0000-4000-8000-000000000002'$$),
  '42501', null, 'should not let anyone update a registration');

select is(pg_temp.run_as('head_children', $$delete from public.program_participants where id = 'bb500000-0000-4000-8000-000000000003'$$), 1::bigint, 'should let a department head remove a child from their program');
select is(pg_temp.run_as('head_choir', $$delete from public.program_participants where id = 'bb500000-0000-4000-8000-000000000002'$$), 0::bigint, 'should not let a head remove a minor they cannot see');
select is(pg_temp.run_as('secretary', $$delete from public.program_participants where id = 'bb500000-0000-4000-8000-000000000004'$$), 1::bigint, 'should let the secretary remove an adult from a program');
select is(pg_temp.run_as('secretary', $$delete from public.program_participants where id = 'bb500000-0000-4000-8000-000000000002'$$), 0::bigint, 'should not let the secretary remove a minor from a program');
select is(pg_temp.run_as('super_admin', $$delete from public.program_participants where id = 'bb500000-0000-4000-8000-000000000002'$$), 1::bigint, 'should let the super admin remove a minor from a program');
select is(pg_temp.run_as(label, $$delete from public.program_participants$$), 0::bigint, format('should not let %s remove registrations', label))
from actors where label in ('pastor', 'usher', 'treasurer', 'content_editor', 'no_role') order by label;
select throws_ok(pg_temp.attempt('anon', $$delete from public.program_participants$$), '42501', null, 'should deny anon removing registrations');

select * from finish();

rollback;
