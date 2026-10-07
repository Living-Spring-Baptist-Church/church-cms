-- LBC-31 (AC 2, 5): public.generate_recurring_services. Creates the next weeks of weekly services from service
-- time templates: right weekday and time in the church time zone, never in the past, a capped horizon, validated
-- input, only super admin and secretary, and idempotent (running it again, or after a service was renamed or
-- cancelled, creates nothing twice). The templates are a parameter because the settings table has no service
-- times yet. Fixture and actors: see the preamble.

begin;

select plan(77);

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

-- Start with no services at all, so only generated ones are counted
set local session_replication_role = replica;
delete from public.attendance_checkins;
delete from public.attendance_counts;
delete from public.services;
set local session_replication_role = origin;

create function pg_temp.generate_as(p_label text, p_templates text, p_weeks text)
returns text
language sql
as $$
  select format('select pg_temp.run_as(%L, %L)', p_label,
    format('select public.generate_recurring_services(%s, %s)', p_templates, p_weeks));
$$;

create function pg_temp.generated(p_label text, p_templates text, p_weeks text)
returns integer
language plpgsql
as $$
declare
  v_original name := current_user;
  v_count integer;
begin
  perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', 'authenticated', 'sub', (select staff_id from actors where label = p_label))::text, true);
  perform set_config('role', 'authenticated', true);
  execute format('select public.generate_recurring_services(%s, %s)', p_templates, p_weeks) into v_count;
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_count;
end;
$$;

-- Two Sunday services, so 2 x 8 services by default
select is(
  pg_temp.generated('secretary', $$'[{"name":"Sunday First Service","type":"sunday","weekday":7,"time":"08:00"},{"name":"Sunday Second Service","type":"sunday","weekday":7,"time":"10:30"}]'::jsonb$$, 'null'),
  16, 'should create eight weeks of two Sunday services by default');

select is((select count(*) from public.services), 16::bigint, 'should hold sixteen services');
select is((select count(*) from public.services where type = 'sunday'), 16::bigint, 'should type every generated service as sunday');
select is((select count(*) from public.services where name = 'Sunday First Service'), 8::bigint, 'should create eight first services');
select is(
  (select count(*) from public.services where extract(isodow from starts_at at time zone private.church_time_zone()) <> 7),
  0::bigint, 'should put every service on a Sunday in the church time zone');
select is(
  (select string_agg(distinct (starts_at at time zone private.church_time_zone())::time::text, ',') from public.services where name = 'Sunday First Service'),
  '08:00:00', 'should start every first service at 08:00 church time');
select is(
  (select string_agg(distinct (starts_at at time zone private.church_time_zone())::time::text, ',') from public.services where name = 'Sunday Second Service'),
  '10:30:00', 'should start every second service at 10:30 church time');
select is((select count(*) from public.services where starts_at <= now()), 0::bigint, 'should create no service in the past');
select is(
  (select count(*) from public.services where name = 'Sunday First Service' and starts_at <= now() + interval '7 days'),
  1::bigint, 'should make the first occurrence the next upcoming one, within a week');
select is(
  (select count(*) from (
     select starts_at - lag(starts_at) over (order by starts_at) as gap from public.services where name = 'Sunday First Service'
   ) as gaps where gap is not null and gap <> interval '7 days'),
  0::bigint, 'should space the services exactly one week apart');
select is(
  (select count(*) from public.services where archived_at is not null or program_id is not null),
  0::bigint, 'should create plain active services');

-- Audit: one INSERT row per service with the caller as actor
select is(
  (select count(*) from audit.log where table_name = 'services' and action = 'INSERT' and actor_id = (select staff_id from actors where label = 'secretary')),
  16::bigint, 'should audit every generated service with the secretary as actor');

-- Idempotent
select is(
  pg_temp.generated('secretary', $$'[{"name":"Sunday First Service","type":"sunday","weekday":7,"time":"08:00"},{"name":"Sunday Second Service","type":"sunday","weekday":7,"time":"10:30"}]'::jsonb$$, 'null'),
  0, 'should create nothing the second time');
select is((select count(*) from public.services), 16::bigint, 'should still hold sixteen services after a second run');
select is(
  pg_temp.generated('super_admin', $$'[{"name":"Sunday First Service","type":"sunday","weekday":7,"time":"08:00"}]'::jsonb$$, '3'),
  0, 'should create nothing for services that exist already, whoever runs it');
select is(
  pg_temp.generated('super_admin', $$'[{"name":"Sunday First Service","type":"sunday","weekday":7,"time":"08:00"},{"name":"Sunday First Service","type":"sunday","weekday":7,"time":"08:00"}]'::jsonb$$, '2'),
  0, 'should cope with the same template listed twice');

-- A longer horizon adds only the new weeks
select is(
  pg_temp.generated('super_admin', $$'[{"name":"Sunday First Service","type":"sunday","weekday":7,"time":"08:00"}]'::jsonb$$, '10'),
  2, 'should add only the two new weeks when the horizon grows from eight to ten');

-- Cancelled and renamed services are not brought back
update public.services set archived_at = now()
where id = (select id from public.services where name = 'Sunday Second Service' order by starts_at limit 1);
update public.services set name = 'Renamed Service'
where id = (select id from public.services where name = 'Sunday Second Service' order by starts_at desc limit 1);

select is(
  pg_temp.generated('secretary', $$'[{"name":"Sunday Second Service","type":"sunday","weekday":7,"time":"10:30"}]'::jsonb$$, 'null'),
  0, 'should not recreate a cancelled or renamed service');
select is((select count(*) from public.services where name = 'Sunday Second Service'), 7::bigint, 'should leave seven Sunday Second Services');

-- Midweek, other weekday and time
select is(
  pg_temp.generated('secretary', $$'[{"name":"Midweek Prayer","type":"midweek","weekday":3,"time":"18:30"}]'::jsonb$$, '4'),
  4, 'should create four midweek services');
select is(
  (select count(*) from public.services where name = 'Midweek Prayer' and type = 'midweek' and extract(isodow from starts_at at time zone private.church_time_zone()) = 3 and (starts_at at time zone private.church_time_zone())::time = '18:30'),
  4::bigint, 'should put the midweek services on Wednesday at 18:30 church time');

-- Horizon: 1 to 26 weeks
select is(pg_temp.generated('secretary', $$'[{"name":"One Week","type":"midweek","weekday":1,"time":"19:00"}]'::jsonb$$, '1'), 1, 'should accept a horizon of one week');
select is(pg_temp.generated('secretary', $$'[{"name":"Long Run","type":"midweek","weekday":2,"time":"19:00"}]'::jsonb$$, '26'), 26, 'should accept a horizon of 26 weeks');
select throws_ok(pg_temp.generate_as('secretary', $$'[{"name":"X","type":"midweek","weekday":2,"time":"19:00"}]'::jsonb$$, weeks), 'P0001', 'VALIDATION_FAILED', format('should reject a horizon of %s weeks', weeks))
from unnest(array['0', '27', '-1', '2147483647', '-2147483648']) as horizons (weeks);
select is((select count(*) from public.services where name = 'X'), 0::bigint, 'should create nothing for a rejected horizon');

-- Templates are validated
select throws_ok(pg_temp.generate_as('secretary', template, '1'), 'P0001', 'VALIDATION_FAILED', format('should reject the template: %s', label))
from (values
  ('null', 'null::jsonb'),
  ('not a list', $$'{"name":"A"}'::jsonb$$),
  ('empty list', $$'[]'::jsonb$$),
  ('a string', $$'"text"'::jsonb$$),
  ('a number element', $$'[1]'::jsonb$$),
  ('missing name', $$'[{"type":"sunday","weekday":7,"time":"08:00"}]'::jsonb$$),
  ('blank name', $$'[{"name":"  ","type":"sunday","weekday":7,"time":"08:00"}]'::jsonb$$),
  ('numeric name', $$'[{"name":5,"type":"sunday","weekday":7,"time":"08:00"}]'::jsonb$$),
  ('special type', $$'[{"name":"A","type":"special","weekday":7,"time":"08:00"}]'::jsonb$$),
  ('unknown type', $$'[{"name":"A","type":"party","weekday":7,"time":"08:00"}]'::jsonb$$),
  ('sunday on Monday', $$'[{"name":"A","type":"sunday","weekday":1,"time":"08:00"}]'::jsonb$$),
  ('weekday 0', $$'[{"name":"A","type":"midweek","weekday":0,"time":"08:00"}]'::jsonb$$),
  ('weekday 8', $$'[{"name":"A","type":"midweek","weekday":8,"time":"08:00"}]'::jsonb$$),
  ('weekday as text', $$'[{"name":"A","type":"midweek","weekday":"3","time":"08:00"}]'::jsonb$$),
  ('weekday fraction', $$'[{"name":"A","type":"midweek","weekday":3.5,"time":"08:00"}]'::jsonb$$),
  ('time 25:00', $$'[{"name":"A","type":"midweek","weekday":3,"time":"25:00"}]'::jsonb$$),
  ('time 8:00', $$'[{"name":"A","type":"midweek","weekday":3,"time":"8:00"}]'::jsonb$$),
  ('time with seconds', $$'[{"name":"A","type":"midweek","weekday":3,"time":"08:00:00"}]'::jsonb$$),
  ('time number', $$'[{"name":"A","type":"midweek","weekday":3,"time":800}]'::jsonb$$),
  ('extra key', $$'[{"name":"A","type":"midweek","weekday":3,"time":"08:00","note":"x"}]'::jsonb$$),
  ('missing time', $$'[{"name":"A","type":"midweek","weekday":3}]'::jsonb$$)
) as bad (label, template);

select throws_ok(
  pg_temp.generate_as('secretary', $$(select jsonb_agg(jsonb_build_object('name', 'T' || n, 'type', 'midweek', 'weekday', 3, 'time', '08:00')) from generate_series(1, 21) as n)$$, '1'),
  'P0001', 'VALIDATION_FAILED', 'should reject more than twenty templates');

select is(
  pg_temp.generated('secretary', $$'[{"name":"x''); drop table public.services; --","type":"midweek","weekday":4,"time":"07:00"}]'::jsonb$$, '1'),
  1, 'should treat a service name with SQL in it as plain text');
select is((select count(*) from public.services where name like 'x%drop table%'), 1::bigint, 'should store the odd name as it was given');

-- Permissions
select is(
  pg_temp.generated('super_admin', $$'[{"name":"Perm Test","type":"midweek","weekday":5,"time":"20:00"}]'::jsonb$$, '1'),
  1, 'should let the super admin generate services');
select is(
  pg_temp.generated('secretary', $$'[{"name":"Perm Test","type":"midweek","weekday":5,"time":"20:00"}]'::jsonb$$, '1'),
  0, 'should let the secretary generate services');

select throws_ok(pg_temp.generate_as(label, $$'[{"name":"Denied","type":"midweek","weekday":5,"time":"20:00"}]'::jsonb$$, '1'), 'P0001', 'AUTH_FORBIDDEN', format('should refuse %s generating services', label))
from actors
where label in ('pastor', 'treasurer', 'usher', 'content_editor', 'head_choir', 'no_role', 'no_staff', 'inactive_super_admin', 'inactive_secretary', 'usher_and_pastor')
order by label;
select throws_ok(pg_temp.generate_as('anon', $$'[{"name":"Denied","type":"midweek","weekday":5,"time":"20:00"}]'::jsonb$$, '1'), '42501', null, 'should deny anon generating services');
select is((select count(*) from public.services where name = 'Denied'), 0::bigint, 'should create nothing for refused callers');
select throws_ok(pg_temp.generate_as('pastor', 'null::jsonb', '0'), 'P0001', 'AUTH_FORBIDDEN', 'should check the role before the input, so a refused caller learns nothing');

-- Name length: 200 characters are accepted, 201 are not, through the generator and through a direct insert
select is(
  pg_temp.generated('secretary', $$jsonb_build_array(jsonb_build_object('name', repeat('n', 200), 'type', 'midweek', 'weekday', 6, 'time', '06:00'))$$, '1'),
  1, 'should accept a template name of 200 characters');
select throws_ok(
  pg_temp.generate_as('secretary', $$jsonb_build_array(jsonb_build_object('name', repeat('n', 201), 'type', 'midweek', 'weekday', 6, 'time', '06:30'))$$, '1'),
  'P0001', 'VALIDATION_FAILED', 'should reject a template name of 201 characters');
select is(
  pg_temp.run_as('secretary', $$insert into public.services (name, type, starts_at) values (repeat('d', 200), 'special', now() + interval '600 days')$$),
  1::bigint, 'should accept a direct service insert with a name of 200 characters');
select throws_ok(
  pg_temp.attempt('secretary', $$insert into public.services (name, type, starts_at) values (repeat('d', 201), 'special', now() + interval '601 days')$$),
  '23514', null, 'should reject a direct service insert with a name of 201 characters');
select throws_ok(
  pg_temp.attempt('super_admin', $$update public.services set name = repeat('u', 201) where name = repeat('d', 200)$$),
  '23514', null, 'should reject renaming a service to 201 characters');

-- The session time zone does not move the generated times: the church time zone decides
create temp table utc_run as select name, starts_at from public.services where name in ('Sunday First Service', 'Midweek Prayer');

create function pg_temp.regenerate_in_zone(p_zone text)
returns boolean
language plpgsql
as $$
declare
  v_same boolean;
begin
  set local session_replication_role = replica;
  delete from public.services where name in ('Sunday First Service', 'Midweek Prayer');
  set local session_replication_role = origin;
  perform set_config('timezone', p_zone, true);
  perform pg_temp.generated('secretary', $q$'[{"name":"Sunday First Service","type":"sunday","weekday":7,"time":"08:00"}]'::jsonb$q$, '10');
  perform pg_temp.generated('secretary', $q$'[{"name":"Midweek Prayer","type":"midweek","weekday":3,"time":"18:30"}]'::jsonb$q$, '4');
  select not exists (select name, starts_at from public.services where name in ('Sunday First Service', 'Midweek Prayer') except select name, starts_at from pg_temp.utc_run)
    and not exists (select name, starts_at from pg_temp.utc_run except select name, starts_at from public.services where name in ('Sunday First Service', 'Midweek Prayer'))
    into v_same;
  perform set_config('timezone', 'UTC', true);
  return v_same;
end;
$$;

select is((select count(*) from utc_run), 14::bigint, 'should have the UTC run of ten Sunday and four midweek services to compare with');
select is(pg_temp.regenerate_in_zone('Pacific/Kiritimati'), true, 'should generate identical times in a session set to UTC+14');
select is(pg_temp.regenerate_in_zone('America/Los_Angeles'), true, 'should generate identical times in a session set to Los Angeles time');
select is(pg_temp.regenerate_in_zone('Pacific/Pago_Pago'), true, 'should generate identical times in a session set to UTC-11');

select * from finish();

rollback;
