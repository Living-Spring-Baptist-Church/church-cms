-- LBC-31 (AC 5): every write to the five new tables leaves an audit.log row with the right actor, table, action and
-- exact changed fields; denied statements leave nothing; the trigger still fires when session_replication_role is
-- replica. The recordAttendanceCounts upsert audit rows are checked in attendance-record-counts.test.sql.
-- Fixture and actors: see the preamble.

begin;

select plan(30);

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

create temp table audit_start as select coalesce(max(id), 0) as max_id from audit.log;
create temp view new_audit as select * from audit.log where id > (select max_id from audit_start);

create function pg_temp.entries(p_table text, p_action text, p_actor text)
returns bigint
language sql
as $$
  select count(*) from new_audit
  where table_name = p_table and action = p_action
    and actor_id is not distinct from (select staff_id from actors where label = p_actor)
    and id > (select max_id from audit_start);
$$;


-- services (secretary): insert, update, then the denied attempt of an usher
select pg_temp.run_as('secretary', $$insert into public.services (name, type, starts_at) values ('AuditService', 'special', '2027-03-01 09:00:00+00')$$);
select is(pg_temp.entries('services', 'INSERT', 'secretary'), 1::bigint, 'should audit a service insert with the secretary as actor');
select is((select record_id from new_audit where table_name = 'services' and action = 'INSERT'), (select id from public.services where name like 'AuditService%')::uuid, 'should audit under the service id');
select is((select new_data ->> 'name' from new_audit where table_name = 'services' and action = 'INSERT'), 'AuditService', 'should keep the new row in the audit entry');

select pg_temp.run_as('secretary', $$update public.services set name = 'AuditServiceRenamed', archived_at = now() where id = (select id from public.services where name like 'AuditService%')$$);
select is(pg_temp.entries('services', 'UPDATE', 'secretary'), 1::bigint, 'should audit a service update with the secretary as actor');
select is(
  (select changed_fields from new_audit where table_name = 'services' and action = 'UPDATE'),
  array['archived_at', 'name'], 'should list exactly the changed fields of a service update');
select is(
  (select old_data ->> 'name' || '>' || (new_data ->> 'name') from new_audit where table_name = 'services' and action = 'UPDATE'),
  'AuditService>AuditServiceRenamed', 'should keep the old and new name');

create temp table audit_mark as select count(*) as total from new_audit;
select throws_ok(pg_temp.attempt('usher', $$insert into public.services (name, type, starts_at) values ('Denied', 'special', '2027-03-02 09:00:00+00')$$), '42501', null, 'should refuse the usher creating a service');
select is(pg_temp.run_as('usher', $$update public.services set name = 'Hacked' where id = (select id from public.services where name like 'AuditService%')$$), 0::bigint, 'should update nothing when the usher edits a service');
select throws_ok(pg_temp.attempt('super_admin', $$delete from public.services where id = (select id from public.services where name like 'AuditService%')$$), '42501', null, 'should refuse deleting a service');
select is((select count(*) from new_audit), (select total from audit_mark), 'should leave no audit row for a denied or empty statement');

-- programs (head_choir): insert, archive
select pg_temp.run_as('head_choir', $$insert into public.programs (name, department_id) values ('AuditProgram', '40000000-0000-4000-8000-000000000001')$$);
select is(pg_temp.entries('programs', 'INSERT', 'head_choir'), 1::bigint, 'should audit a program insert with the department head as actor');
select pg_temp.run_as('head_choir', $$update public.programs set archived_at = now() where name = 'AuditProgram'$$);
select is((select changed_fields from new_audit where table_name = 'programs' and action = 'UPDATE'), array['archived_at'], 'should list archived_at as the only changed field of an archived program');
select is(pg_temp.entries('programs', 'UPDATE', 'head_choir'), 1::bigint, 'should audit a program update with the department head as actor');

-- attendance_checkins (usher): insert, delete
select pg_temp.run_as('usher', format($$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('bb200000-0000-4000-8000-000000000002', '60000000-0000-4000-8000-000000000002', %L)$$, (select staff_id from actors where label = 'usher')));
select is(pg_temp.entries('attendance_checkins', 'INSERT', 'usher'), 1::bigint, 'should audit a check-in with the usher as actor');
select pg_temp.run_as('usher', $$delete from public.attendance_checkins where service_id = 'bb200000-0000-4000-8000-000000000002' and member_id = '60000000-0000-4000-8000-000000000002'$$);
select is(pg_temp.entries('attendance_checkins', 'DELETE', 'usher'), 1::bigint, 'should audit the removal of a check-in with the usher as actor');
select is(
  (select old_data ->> 'member_id' from new_audit where table_name = 'attendance_checkins' and action = 'DELETE'),
  '60000000-0000-4000-8000-000000000002', 'should keep the removed check-in in the audit entry');
select is((select new_data from new_audit where table_name = 'attendance_checkins' and action = 'DELETE'), null, 'should keep no new data for a delete');

-- program_participants (head_children): insert, delete
select pg_temp.run_as('head_children', $$delete from public.program_participants where id = 'bb500000-0000-4000-8000-000000000003'$$);
select is(pg_temp.entries('program_participants', 'DELETE', 'head_children'), 1::bigint, 'should audit the removal of a registration with the department head as actor');
select pg_temp.run_as('head_children', $$insert into public.program_participants (program_id, member_id) values ('bb100000-0000-4000-8000-000000000003', '60000000-0000-4000-8000-000000000005')$$);
select is(pg_temp.entries('program_participants', 'INSERT', 'head_children'), 1::bigint, 'should audit a registration with the department head as actor');

-- attendance_counts: the table itself, written as the owner (the function is tested elsewhere)
insert into public.attendance_counts (id, service_id, men, recorded_by)
values ('bb300000-0000-4000-8000-0000000000a1', 'bb200000-0000-4000-8000-000000000002', 5, (select staff_id from actors where label = 'usher'));
update public.attendance_counts set men = 6 where id = 'bb300000-0000-4000-8000-0000000000a1';
delete from public.attendance_counts where id = 'bb300000-0000-4000-8000-0000000000a1';
select is(
  (select string_agg(action, ',' order by id) from new_audit where record_id = 'bb300000-0000-4000-8000-0000000000a1'),
  'INSERT,UPDATE,DELETE', 'should audit every statement on a count, as direct database access');
select is((select actor_id from new_audit where record_id = 'bb300000-0000-4000-8000-0000000000a1' and action = 'INSERT'), null, 'should record no actor for direct database access');
select is((select changed_fields from new_audit where record_id = 'bb300000-0000-4000-8000-0000000000a1' and action = 'UPDATE'), array['men'], 'should list men as the only changed field');

-- The trigger fires in replica mode too
set local session_replication_role = replica;
insert into public.services (id, name, type, starts_at) values ('bb200000-0000-4000-8000-0000000000a2', 'ReplicaService', 'special', '2027-04-01 09:00:00+00');
set local session_replication_role = origin;
select is((select count(*) from new_audit where record_id = 'bb200000-0000-4000-8000-0000000000a2'), 1::bigint, 'should audit a service written in replica mode');

-- The log is not readable or writable by the app roles that wrote the rows
select throws_ok(pg_temp.attempt(label, 'select * from audit.log'), '42501', null, format('should deny %s reading audit.log', label))
from actors where label in ('usher', 'secretary', 'head_choir', 'super_admin', 'pastor') order by label;
select throws_ok(pg_temp.attempt('super_admin', $$delete from audit.log$$), '42501', null, 'should deny the super admin deleting audit rows');

select is(
  (select count(*) from new_audit where table_name in ('programs', 'services', 'attendance_counts', 'attendance_checkins', 'program_participants') and record_id is null),
  0::bigint, 'should give every audit row a record id');

select * from finish();

rollback;
