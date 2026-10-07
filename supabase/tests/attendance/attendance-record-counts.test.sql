-- LBC-31 (AC 3, 5, 6): public.record_attendance_counts. One row per service (a second call overwrites rather than
-- duplicates), counts are whole numbers from 0 to private.max_headcount(), recorded_by is always the caller, who
-- may record is decided by role, and every write leaves exact audit rows. Denied calls leave no row and no audit
-- entry. Fixture and actors: see the preamble.

begin;

select plan(78);

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

create function pg_temp.record_as(p_label text, p_service uuid, p_men integer, p_women integer, p_children integer, p_visitors integer)
returns text
language sql
as $$
  select format('select pg_temp.run_as(%L, %L)', p_label,
    format('select * from public.record_attendance_counts(%L, %s, %s, %s, %s)', p_service, coalesce(p_men::text, 'null'), coalesce(p_women::text, 'null'), coalesce(p_children::text, 'null'), coalesce(p_visitors::text, 'null')));
$$;

create function pg_temp.audit_rows(p_record_id uuid, p_action text)
returns bigint
language sql
as $$
  select count(*) from audit.log where record_id = p_record_id and action = p_action;
$$;

-- Who may record: super admin, secretary, usher (also when they hold a second role). SundayNext has no count yet.

select is(
  pg_temp.run_as(label, format($$select * from public.record_attendance_counts('bb200000-0000-4000-8000-000000000002', %s, 2, 3, 4)$$, position)),
  1::bigint,
  format('should let %s record attendance', label))
from (values ('super_admin', 1), ('secretary', 2), ('usher', 3), ('usher_and_pastor', 4), ('usher_and_head_children', 5)) as allowed (label, position)
order by label;

select is(
  (select count(*) from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000002'),
  1::bigint,
  'should hold one count for the service however many people recorded it');

select throws_ok(
  pg_temp.record_as(label, 'bb200000-0000-4000-8000-000000000002', 1, 1, 1, 1),
  'P0001', 'AUTH_FORBIDDEN',
  format('should refuse %s recording attendance', label))
from actors
where label in ('pastor', 'treasurer', 'content_editor', 'head_choir', 'head_children', 'no_role', 'no_staff',
  'inactive_super_admin', 'inactive_secretary', 'inactive_usher')
order by label;

select throws_ok(pg_temp.record_as('anon', 'bb200000-0000-4000-8000-000000000002', 1, 1, 1, 1), '42501', null, 'should deny anon calling record_attendance_counts');

select throws_ok(
  pg_temp.record_as('pastor', gen_random_uuid(), 1, 1, 1, 1), 'P0001', 'AUTH_FORBIDDEN',
  'should check the role before looking for the service, so a refused caller learns nothing about ids');

-- Upsert semantics on SundayPast, which has a count of 10, 20, 30, 4 recorded by the usher

select is(
  pg_temp.run_as('secretary', $$select * from public.record_attendance_counts('bb200000-0000-4000-8000-000000000001', 11, 21, 31, 5)$$),
  1::bigint, 'should let a second recorder overwrite the count');

select is((select count(*) from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000001'), 1::bigint, 'should update the count rather than add a second one');
select is(
  (select (men, women, children, visitors)::text from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000001'),
  '(11,21,31,5)', 'should store the new counts exactly');
select is(
  (select recorded_by from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000001'),
  (select staff_id from actors where label = 'secretary'),
  'should set recorded_by to whoever made the latest count');
select is(
  (select id from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000001'),
  'bb300000-0000-4000-8000-000000000001'::uuid, 'should keep the id of the count when it is overwritten');

-- Zero is a valid count, the bounds are exact

select is(pg_temp.run_as('usher', $$select * from public.record_attendance_counts('bb200000-0000-4000-8000-000000000001', 0, 0, 0, 0)$$), 1::bigint, 'should accept all zero counts');
select is(
  (select (men, women, children, visitors)::text from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000001'),
  '(0,0,0,0)', 'should store zero counts as zero');
select is(pg_temp.run_as('usher', $$select * from public.record_attendance_counts('bb200000-0000-4000-8000-000000000001', 100000, 100000, 100000, 100000)$$), 1::bigint, 'should accept the largest allowed counts');
select is(
  (select (men, women, children, visitors)::text from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000001'),
  '(100000,100000,100000,100000)', 'should store the largest counts exactly');

-- Validation: every failure leaves the stored count as it was

select throws_ok(
  pg_temp.record_as('usher', 'bb200000-0000-4000-8000-000000000001', men, women, children, visitors),
  'P0001', 'VALIDATION_FAILED', format('should reject the counts %s', counts))
from (values
  ('-1,1,1,1', -1, 1, 1, 1), ('1,-1,1,1', 1, -1, 1, 1), ('1,1,-1,1', 1, 1, -1, 1), ('1,1,1,-1', 1, 1, 1, -1),
  ('100001,1,1,1', 100001, 1, 1, 1), ('1,1,1,2147483647', 1, 1, 1, 2147483647), ('-2147483648,1,1,1', -2147483648, 1, 1, 1),
  ('null men', null, 1, 1, 1), ('null women', 1, null, 1, 1), ('null children', 1, 1, null, 1), ('null visitors', 1, 1, 1, null)
) as bad (counts, men, women, children, visitors);

select throws_ok(pg_temp.record_as('usher', null, 1, 1, 1, 1), 'P0001', 'VALIDATION_FAILED', 'should reject a missing service id');
select throws_ok(pg_temp.record_as('usher', gen_random_uuid(), 1, 1, 1, 1), 'P0001', 'NOT_FOUND', 'should reject a service that does not exist');
select throws_ok(pg_temp.record_as('usher', 'bb200000-0000-4000-8000-000000000003', 1, 1, 1, 1), 'P0001', 'VALIDATION_FAILED', 'should reject recording for an archived service');
select throws_ok(pg_temp.record_as('secretary', 'bb200000-0000-4000-8000-000000000003', 1, 1, 1, 1), 'P0001', 'VALIDATION_FAILED', 'should reject recording for an archived service as the office too');
select is((select count(*) from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000003'), 0::bigint, 'should leave no count behind for the archived service');
select is(
  (select (men, women, children, visitors)::text from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000001'),
  '(100000,100000,100000,100000)', 'should leave the count untouched after every rejected call');

-- The table itself refuses what the function would refuse, even for the owner

select throws_ok($$insert into public.attendance_counts (service_id, men, recorded_by) values ('bb200000-0000-4000-8000-000000000006', -1, (select staff_id from actors where label = 'usher'))$$, '23514', null, 'should reject a negative count at the table');
select throws_ok($$insert into public.attendance_counts (service_id, women, recorded_by) values ('bb200000-0000-4000-8000-000000000006', 100001, (select staff_id from actors where label = 'usher'))$$, '23514', null, 'should reject a count above the limit at the table');
select throws_ok($$insert into public.attendance_counts (service_id, recorded_by) values ('bb200000-0000-4000-8000-000000000006', gen_random_uuid())$$, '23503', null, 'should reject a recorder that is not a staff member');
select throws_ok($$insert into public.attendance_counts (service_id, recorded_by) values (gen_random_uuid(), (select staff_id from actors where label = 'usher'))$$, '23503', null, 'should reject a count for a service that does not exist');
select throws_ok($$insert into public.attendance_counts (service_id, recorded_by) values ('bb200000-0000-4000-8000-000000000001', (select staff_id from actors where label = 'usher'))$$, '23505', null, 'should reject a second count row for the same service at the table');

-- Injection through text-like inputs cannot reach SQL: the function takes uuid and integers only

select throws_ok(
  $$select pg_temp.run_as('usher', 'select * from public.record_attendance_counts(''bb200000-0000-4000-8000-000000000001''; drop table public.services; --'', 1, 1, 1, 1)')$$,
  '42601', null, 'should not run a statement smuggled in through the service id');
select throws_ok(
  $$select pg_temp.run_as('usher', 'select * from public.record_attendance_counts(''x'', 1, 1, 1, 1)')$$,
  '22P02', null, 'should reject a service id that is not a uuid');
select throws_ok(
  $$select pg_temp.run_as('usher', 'select * from public.record_attendance_counts(''bb200000-0000-4000-8000-000000000001'', 1.5, 1, 1, 1)')$$,
  '42883', null, 'should not accept a fractional count');
select has_table('public', 'services', 'should still have the services table after the injection attempt');

-- Audit: INSERT then UPDATE rows with the exact changed fields and the right actor

select pg_temp.run_as('usher', $$select * from public.record_attendance_counts('bb200000-0000-4000-8000-000000000006', 5, 6, 7, 8)$$);
select pg_temp.run_as('secretary', $$select * from public.record_attendance_counts('bb200000-0000-4000-8000-000000000006', 5, 6, 9, 8)$$);

create temp table youth_count as select id from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000006';

select is(pg_temp.audit_rows((select id from youth_count), 'INSERT'), 1::bigint, 'should write one INSERT audit row for the first count');
select is(pg_temp.audit_rows((select id from youth_count), 'UPDATE'), 1::bigint, 'should write one UPDATE audit row for the overwrite');
select is(
  (select actor_id from audit.log where record_id = (select id from youth_count) and action = 'INSERT'),
  (select staff_id from actors where label = 'usher'), 'should record the usher as the actor of the first count');
select is(
  (select actor_id from audit.log where record_id = (select id from youth_count) and action = 'UPDATE'),
  (select staff_id from actors where label = 'secretary'), 'should record the secretary as the actor of the overwrite');
select is(
  (select changed_fields from audit.log where record_id = (select id from youth_count) and action = 'UPDATE'),
  array['children', 'recorded_by'], 'should list exactly the changed fields of the overwrite (updated_at is the same inside one transaction)');
select is(
  (select (old_data ->> 'children')::int || '>' || (new_data ->> 'children')::int from audit.log where record_id = (select id from youth_count) and action = 'UPDATE'),
  '7>9', 'should keep the old and the new value in the audit row');
select is(
  (select table_name from audit.log where record_id = (select id from youth_count) and action = 'INSERT'),
  'attendance_counts', 'should name the table in the audit row');

select throws_ok(pg_temp.record_as('pastor', 'bb200000-0000-4000-8000-000000000006', 99, 99, 99, 99), 'P0001', 'AUTH_FORBIDDEN', 'should refuse the pastor overwriting the count');
select throws_ok(pg_temp.record_as('usher', 'bb200000-0000-4000-8000-000000000006', -5, 1, 1, 1), 'P0001', 'VALIDATION_FAILED', 'should refuse a negative overwrite');
select is(pg_temp.audit_rows((select id from youth_count), 'UPDATE'), 1::bigint, 'should leave no audit row for denied or rejected calls');
select is(
  (select (men, women, children, visitors)::text from public.attendance_counts where id = (select id from youth_count)),
  '(5,6,9,8)', 'should keep the last valid count after denied calls');

-- The usher can record but cannot read finances, people or the audit log (finance tables arrive in a later ticket and
-- must be added to this denial: ledger_entries, cash_counts, deposits, pledges, expenses, accounts)

select is(pg_temp.run_as('usher', 'select * from public.attendance_counts'), 5::bigint, 'should let the usher read the counts');
select is(pg_temp.run_as('usher', 'select * from public.members'), 0::bigint, 'should show the usher no members');
select is(pg_temp.run_as('usher', 'select * from public.staff'), 1::bigint, 'should show the usher only their own staff profile');
select is(pg_temp.run_as('usher', 'select * from public.staff_roles'), 1::bigint, 'should show the usher only their own role');
select is(pg_temp.run_as('usher', 'select * from public.households'), 0::bigint, 'should show the usher no households');
select is(pg_temp.run_as('usher', 'select * from public.visitor_followups'), 0::bigint, 'should show the usher no follow-ups');
select is(pg_temp.run_as('usher', 'select * from public.programs'), 0::bigint, 'should show the usher no programs');
select is(pg_temp.run_as('usher', 'select * from public.program_participants'), 0::bigint, 'should show the usher no program participants');
select throws_ok(pg_temp.attempt('usher', 'select * from audit.log'), '42501', null, 'should deny the usher reading the audit log');
select throws_ok(pg_temp.attempt('usher', 'select private.has_role(''usher'')'), '42501', null, 'should deny the usher calling a private helper through the schema');

-- A future edge function writes with the service role: the CHECK limits must not need an owner-only function

create function pg_temp.as_service_role(p_statement text)
returns bigint
language plpgsql
as $$
declare
  v_original name := current_user;
  v_rows bigint;
begin
  perform set_config('role', 'service_role', true);
  execute p_statement;
  get diagnostics v_rows = row_count;
  perform set_config('role', v_original::text, true);
  return v_rows;
end;
$$;

insert into public.services (id, name, type, starts_at) values ('bb200000-0000-4000-8000-0000000000b1', 'ServiceRoleService', 'special', '2027-05-01 09:00:00+00');

select is(
  pg_temp.as_service_role(format($$insert into public.attendance_counts (service_id, men, women, children, visitors, recorded_by) values ('bb200000-0000-4000-8000-0000000000b1', 1, 2, 3, 100000, %L)$$, (select staff_id from actors where label = 'usher'))),
  1::bigint, 'should let the service role insert a valid count directly');
select is(
  (select (men, women, children, visitors)::text from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-0000000000b1'),
  '(1,2,3,100000)', 'should store the service role count exactly');
select throws_ok(
  format($$select pg_temp.as_service_role(%L)$$, format($$insert into public.attendance_counts (service_id, men, recorded_by) values ('bb200000-0000-4000-8000-000000000006', 100001, %L)$$, (select staff_id from actors where label = 'usher'))),
  '23514', null, 'should reject a count of 100001 inserted by the service role');
select throws_ok(
  format($$select pg_temp.as_service_role(%L)$$, format($$insert into public.attendance_counts (service_id, women, recorded_by) values ('bb200000-0000-4000-8000-000000000006', -1, %L)$$, (select staff_id from actors where label = 'usher'))),
  '23514', null, 'should reject a negative count inserted by the service role');

select * from finish();

rollback;
