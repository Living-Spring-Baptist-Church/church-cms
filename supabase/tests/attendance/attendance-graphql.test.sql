-- LBC-31 (AC 3, 4): the GraphQL surface of services, attendance and programs. Every field of each new type is listed
-- so a duplicated relationship name cannot slip in (the LBC-17 pitfall), each relationship is shown to resolve to the
-- right rows, recordAttendanceCounts works as an usher and fails as the treasurer and anon, generateRecurringServices
-- is limited to the office, no direct write mutation exists for attendance_counts, and children never appear in a
-- nested read. Fixture and actors: see the preamble.

begin;

select plan(60);

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

create function pg_temp.mutation_names(p_label text)
returns jsonb
language sql
as $$
  select jsonb_agg(field ->> 'name' order by field ->> 'name')
  from jsonb_array_elements(
    pg_temp.graphql_as(p_label, '{ __schema { mutationType { fields { name } } } }') #> '{data,__schema,mutationType,fields}'
  ) as field;
$$;

create function pg_temp.record_counts(p_label text, p_service text, p_counts text)
returns jsonb
language sql
as $$
  select pg_temp.graphql_as(p_label, format('mutation { recordAttendanceCounts(pServiceId: "%s", %s) { id men women children visitors recordedByStaff { fullName } service { name } } }', p_service, p_counts));
$$;

-- Every field on each type
select is(pg_temp.type_fields('Services'),
  '["archivedAt", "attendanceCheckinsCollection", "attendanceCount", "createdAt", "id", "name", "nodeId", "program", "programId", "startsAt", "type", "updatedAt"]'::jsonb,
  'should list exactly these fields on Services');
select is(pg_temp.type_fields('Programs'),
  '["archivedAt", "createdAt", "department", "departmentId", "description", "endsOn", "id", "leadStaff", "leadStaffId", "name", "nodeId", "programParticipantsCollection", "servicesCollection", "startsOn", "updatedAt"]'::jsonb,
  'should list exactly these fields on Programs, with the department and the lead apart from their id fields');
select is(pg_temp.type_fields('AttendanceCounts'),
  '["children", "createdAt", "id", "men", "nodeId", "recordedBy", "recordedByStaff", "service", "serviceId", "updatedAt", "visitors", "women"]'::jsonb,
  'should list exactly these fields on AttendanceCounts, with the recording staff member apart from the recordedBy id');
select is(pg_temp.type_fields('AttendanceCheckins'),
  '["checkedInAt", "checkedInBy", "checkedInByStaff", "id", "member", "memberId", "nodeId", "service", "serviceId"]'::jsonb,
  'should list exactly these fields on AttendanceCheckins, with the checking-in staff member apart from the checkedInBy id');
select is(pg_temp.type_fields('ProgramParticipants'),
  '["id", "member", "memberId", "nodeId", "program", "programId"]'::jsonb,
  'should list exactly these fields on ProgramParticipants');

-- The API offers the function and the allowed generated writes, and no more
select is(
  pg_temp.mutation_names('usher') @> '["recordAttendanceCounts", "generateRecurringServices", "insertIntoAttendanceCheckinsCollection", "deleteFromAttendanceCheckinsCollection", "insertIntoServicesCollection", "updateServicesCollection", "insertIntoProgramsCollection", "updateProgramsCollection", "insertIntoProgramParticipantsCollection", "deleteFromProgramParticipantsCollection"]'::jsonb,
  true, 'should offer the attendance function and the generated writes of the new tables');
select is(
  (select jsonb_agg(name order by name) from jsonb_array_elements_text(pg_temp.mutation_names('super_admin')) as names (name)
   where name ~ '^(insertInto|update|deleteFrom)AttendanceCounts|^deleteFrom(Services|Programs)Collection$|^updateAttendanceCheckins|^updateProgramParticipants'),
  null, 'should offer no direct write on counts and no update or delete where the design allows none');
select is(
  pg_temp.graphql_as('anon', '{ __schema { mutationType { fields { name } } } }') #>> '{data,__schema,mutationType,fields}',
  null, 'should offer anon no mutation at all');

-- Relationships resolve to the right rows
create temp table first_record as
select pg_temp.record_counts('usher', 'bb200000-0000-4000-8000-000000000002', 'pMen: 40, pWomen: 50, pChildren: 20, pVisitors: 3') #> '{data,recordAttendanceCounts}' as result;

select is(
  (select result from first_record),
  (select jsonb_build_object('id', id, 'men', 40, 'women', 50, 'children', 20, 'visitors', 3, 'recordedByStaff', jsonb_build_object('fullName', 'usher'), 'service', jsonb_build_object('name', 'SundayNext'))
   from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000002'),
  'should let an usher record a count through recordAttendanceCounts and return the row with its relationships');

select is(
  pg_temp.record_counts('secretary', 'bb200000-0000-4000-8000-000000000002', 'pMen: 41, pWomen: 50, pChildren: 20, pVisitors: 3') #>> '{data,recordAttendanceCounts,men}',
  '41', 'should overwrite the count when recorded again');
select is((select count(*) from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000002'), 1::bigint, 'should hold one count after two GraphQL calls');
select is(
  (select recorded_by from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000002'),
  (select staff_id from actors where label = 'secretary'), 'should record the caller of the latest GraphQL call');

select is(
  pg_temp.graphql_as('super_admin', $$query { servicesCollection(filter: { name: { eq: "SundayPast" } }) { edges { node { attendanceCount { men recordedByStaff { fullName } } program { name } } } } }$$) #>> '{data,servicesCollection,edges,0,node}',
  '{"program": null, "attendanceCount": {"men": 10, "recordedByStaff": {"fullName": "usher"}}}',
  'should resolve Services.attendanceCount to the one count of the service');
select is(
  pg_temp.graphql_as('super_admin', $$query { servicesCollection(filter: { name: { eq: "ChoirEvent" } }) { edges { node { program { name department { name } leadStaff { fullName } } } } } }$$) #>> '{data,servicesCollection,edges,0,node,program}',
  '{"name": "ChoirProgram", "leadStaff": null, "department": {"name": "Choir"}}',
  'should resolve Services.program and Programs.department');
select is(
  jsonb_array_length(pg_temp.graphql_as('super_admin', $$query { programsCollection(filter: { name: { eq: "ChoirProgram" } }) { edges { node { servicesCollection { edges { node { name } } } } } } }$$) #> '{data,programsCollection,edges,0,node,servicesCollection,edges}'),
  1, 'should list on Programs.servicesCollection the services of the program');
select is(
  jsonb_array_length(pg_temp.graphql_as('super_admin', $$query { servicesCollection(filter: { name: { eq: "SundayPast" } }) { edges { node { attendanceCheckinsCollection { edges { node { member { firstName } checkedInByStaff { fullName } } } } } } } }$$) #> '{data,servicesCollection,edges,0,node,attendanceCheckinsCollection,edges}'),
  3, 'should list on Services.attendanceCheckinsCollection the check-ins of the service');
select is(
  pg_temp.graphql_as('super_admin', $$query { attendanceCheckinsCollection(filter: { id: { eq: "bb400000-0000-4000-8000-000000000001" } }) { edges { node { member { firstName } checkedInByStaff { fullName } service { name } } } } }$$) #>> '{data,attendanceCheckinsCollection,edges,0,node}',
  '{"member": {"firstName": "AdultChoir"}, "service": {"name": "SundayPast"}, "checkedInByStaff": {"fullName": "usher"}}',
  'should resolve the member, the staff member and the service of a check-in');
select is(
  pg_temp.graphql_as('super_admin', $$query { membersCollection(filter: { firstName: { eq: "AdultChoir" } }) { edges { node { attendanceCheckinsCollection { edges { node { service { name } } } } programParticipantsCollection { edges { node { program { name } } } } } } } }$$) #>> '{data,membersCollection,edges,0,node,attendanceCheckinsCollection,edges,0,node,service,name}',
  'SundayPast', 'should list on Members.attendanceCheckinsCollection the services a member attended');
select is(
  jsonb_array_length(pg_temp.graphql_as('super_admin', $$query { membersCollection(filter: { firstName: { eq: "AdultChoir" } }) { edges { node { programParticipantsCollection { edges { node { program { name } } } } } } } }$$) #> '{data,membersCollection,edges,0,node,programParticipantsCollection,edges}'),
  2, 'should list on Members.programParticipantsCollection the two programs of a member');
select is(
  jsonb_array_length(pg_temp.graphql_as('super_admin', $$query { staffCollection(filter: { fullName: { eq: "usher" } }) { edges { node { recordedAttendanceCountsCollection { edges { node { men } } } recordedAttendanceCheckinsCollection { edges { node { id } } } } } } }$$) #> '{data,staffCollection,edges,0,node,recordedAttendanceCountsCollection,edges}'),
  3, 'should list on Staff.recordedAttendanceCountsCollection the counts that staff member recorded');
select is(
  jsonb_array_length(pg_temp.graphql_as('super_admin', $$query { departmentsCollection(filter: { name: { eq: "Choir" } }) { edges { node { programsCollection { edges { node { name } } } } } } }$$) #> '{data,departmentsCollection,edges,0,node,programsCollection,edges}'),
  1, 'should list on Departments.programsCollection the programs of the department');

-- recordAttendanceCounts failures
select is(pg_temp.record_counts('treasurer', 'bb200000-0000-4000-8000-000000000002', 'pMen: 1, pWomen: 1, pChildren: 1, pVisitors: 1') #>> '{errors,0,message}', 'AUTH_FORBIDDEN', 'should refuse the treasurer with AUTH_FORBIDDEN');
select is(pg_temp.record_counts('pastor', 'bb200000-0000-4000-8000-000000000002', 'pMen: 1, pWomen: 1, pChildren: 1, pVisitors: 1') #>> '{errors,0,message}', 'AUTH_FORBIDDEN', 'should refuse the pastor with AUTH_FORBIDDEN');
select is(pg_temp.record_counts('usher', 'bb200000-0000-4000-8000-000000000002', 'pMen: -1, pWomen: 1, pChildren: 1, pVisitors: 1') #>> '{errors,0,message}', 'VALIDATION_FAILED', 'should refuse a negative count with VALIDATION_FAILED');
select is(pg_temp.record_counts('usher', 'bb200000-0000-4000-8000-000000000002', 'pMen: 1, pWomen: 1, pChildren: 1, pVisitors: 100001') #>> '{errors,0,message}', 'VALIDATION_FAILED', 'should refuse a count above the limit with VALIDATION_FAILED');
select is(pg_temp.record_counts('usher', 'bb200000-0000-4000-8000-000000000003', 'pMen: 1, pWomen: 1, pChildren: 1, pVisitors: 1') #>> '{errors,0,message}', 'VALIDATION_FAILED', 'should refuse an archived service with VALIDATION_FAILED');
select is(pg_temp.record_counts('usher', '00000000-0000-4000-8000-0000000000ff', 'pMen: 1, pWomen: 1, pChildren: 1, pVisitors: 1') #>> '{errors,0,message}', 'NOT_FOUND', 'should refuse an unknown service with NOT_FOUND');
select isnt(pg_temp.record_counts('usher', 'bb200000-0000-4000-8000-000000000002', 'pMen: 1.5, pWomen: 1, pChildren: 1, pVisitors: 1') -> 'errors', null, 'should refuse a fractional count');
select isnt(pg_temp.record_counts('usher', 'bb200000-0000-4000-8000-000000000002', 'pMen: 1, pWomen: 1, pChildren: 1') -> 'errors', null, 'should refuse a call with a count missing');
select isnt(pg_temp.record_counts('anon', 'bb200000-0000-4000-8000-000000000002', 'pMen: 1, pWomen: 1, pChildren: 1, pVisitors: 1') -> 'errors', null, 'should offer no recordAttendanceCounts to anon');
select is(
  (select men from public.attendance_counts where service_id = 'bb200000-0000-4000-8000-000000000002'), 41,
  'should keep the last valid count after every refused call');

-- Direct writes
select isnt(pg_temp.graphql_as('usher', $$mutation { insertIntoAttendanceCountsCollection(objects: [{ serviceId: "bb200000-0000-4000-8000-000000000006", men: 1 }]) { affectedCount } }$$) -> 'errors', null, 'should offer no direct insert into counts');
select isnt(pg_temp.graphql_as('super_admin', $$mutation { updateAttendanceCountsCollection(set: { men: 1 }) { affectedCount } }$$) -> 'errors', null, 'should offer no direct update of counts, even to the super admin');
select is(
  pg_temp.graphql_as('secretary', $$mutation { insertIntoServicesCollection(objects: [{ name: "GqlService", type: special, startsAt: "2027-02-01T09:00:00Z" }]) { affectedCount } }$$) #>> '{data,insertIntoServicesCollection,affectedCount}',
  '1', 'should let the secretary create a service through GraphQL');
select isnt(pg_temp.graphql_as('usher', $$mutation { insertIntoServicesCollection(objects: [{ name: "UsherService", type: special, startsAt: "2027-02-02T09:00:00Z" }]) { affectedCount } }$$) -> 'errors', null, 'should refuse the usher creating a service through GraphQL');
select is((select count(*) from public.services where name = 'UsherService'), 0::bigint, 'should leave no service behind after the usher''s refused insert');
select is(
  pg_temp.graphql_as('head_choir', $$mutation { insertIntoProgramsCollection(objects: [{ name: "GqlProgram", departmentId: "40000000-0000-4000-8000-000000000001" }]) { affectedCount } }$$) #>> '{data,insertIntoProgramsCollection,affectedCount}',
  '1', 'should let a department head create a program for their department through GraphQL');
select isnt(pg_temp.graphql_as('head_choir', $$mutation { insertIntoProgramsCollection(objects: [{ name: "GqlProgram2", departmentId: "40000000-0000-4000-8000-000000000002" }]) { affectedCount } }$$) -> 'errors', null, 'should refuse a department head creating a program for another department through GraphQL');
select is(
  pg_temp.graphql_as('usher', format($$mutation { insertIntoAttendanceCheckinsCollection(objects: [{ serviceId: "bb200000-0000-4000-8000-000000000002", memberId: "60000000-0000-4000-8000-000000000003", checkedInBy: "%s" }]) { affectedCount } }$$, (select staff_id from actors where label = 'usher'))) #>> '{data,insertIntoAttendanceCheckinsCollection,affectedCount}',
  '1', 'should let an usher check in an adult through GraphQL');
select isnt(
  pg_temp.graphql_as('usher', format($$mutation { insertIntoAttendanceCheckinsCollection(objects: [{ serviceId: "bb200000-0000-4000-8000-000000000002", memberId: "60000000-0000-4000-8000-000000000005", checkedInBy: "%s" }]) { affectedCount } }$$, (select staff_id from actors where label = 'usher'))) -> 'errors',
  null, 'should refuse an usher checking in a child through GraphQL');

-- generateRecurringServices through GraphQL
select is(
  pg_temp.graphql_as('secretary', $$mutation { generateRecurringServices(pTemplates: "[{\"name\":\"Gql Prayer\",\"type\":\"midweek\",\"weekday\":3,\"time\":\"18:30\"}]", pWeeks: 3) }$$) #>> '{data,generateRecurringServices}',
  '3', 'should let the secretary generate services through GraphQL and return how many were created');
select is(
  pg_temp.graphql_as('secretary', $$mutation { generateRecurringServices(pTemplates: "[{\"name\":\"Gql Prayer\",\"type\":\"midweek\",\"weekday\":3,\"time\":\"18:30\"}]", pWeeks: 3) }$$) #>> '{data,generateRecurringServices}',
  '0', 'should create nothing when the same call is repeated');
select is(
  pg_temp.graphql_as('usher', $$mutation { generateRecurringServices(pTemplates: "[{\"name\":\"Usher Prayer\",\"type\":\"midweek\",\"weekday\":3,\"time\":\"18:30\"}]") }$$) #>> '{errors,0,message}',
  'AUTH_FORBIDDEN', 'should refuse the usher generating services through GraphQL');
select isnt(pg_temp.graphql_as('anon', $$mutation { generateRecurringServices(pTemplates: "[]") }$$) -> 'errors', null, 'should offer no generateRecurringServices to anon');
select is(
  pg_temp.graphql_as('secretary', $$mutation { generateRecurringServices(pTemplates: "not json") }$$) #>> '{errors,0,message}',
  'invalid input syntax for type json', 'should refuse text that is not JSON before it reaches the function');

-- Reads: anon sees nothing, children never appear in a nested read
select isnt(pg_temp.graphql_as('anon', $$query { servicesCollection { edges { node { id } } } }$$) -> 'errors', null, 'should offer no services query to anon');
select isnt(pg_temp.graphql_as('anon', $$query { programsCollection { edges { node { id } } } }$$) -> 'errors', null, 'should offer no programs query to anon');
select isnt(pg_temp.graphql_as('anon', $$query { attendanceCountsCollection { edges { node { id } } } }$$) -> 'errors', null, 'should offer no attendance counts query to anon');
select isnt(pg_temp.graphql_as('anon', $$query { attendanceCheckinsCollection { edges { node { id } } } }$$) -> 'errors', null, 'should offer no check-ins query to anon');
select isnt(pg_temp.graphql_as('anon', $$query { programParticipantsCollection { edges { node { id } } } }$$) -> 'errors', null, 'should offer no program participants query to anon');

select is(
  jsonb_array_length(pg_temp.graphql_as('secretary', $$query { attendanceCheckinsCollection { edges { node { member { firstName } } } } }$$) #> '{data,attendanceCheckinsCollection,edges}'),
  3, 'should show the secretary only the check-ins of adults');
select is(
  pg_temp.graphql_as('secretary', $$query { attendanceCheckinsCollection { edges { node { member { firstName } } } } }$$)::text ~ 'Minor',
  false, 'should never name a child in the secretary''s check-in list');
select is(
  pg_temp.graphql_as('secretary', $$query { programsCollection(filter: { name: { eq: "ChildrenProgram" } }) { edges { node { programParticipantsCollection { edges { node { member { firstName } } } } } } } }$$) #>> '{data,programsCollection,edges,0,node,programParticipantsCollection,edges}',
  '[{"node": {"member": {"firstName": "AdultChoir"}}}]',
  'should show the secretary only the adult participant of the children''s program');
select is(
  pg_temp.graphql_as('usher', $$query { servicesCollection(filter: { name: { eq: "SundayPast" } }) { edges { node { attendanceCheckinsCollection { edges { node { member { firstName } } } } } } } }$$) #>> '{data,servicesCollection,edges,0,node,attendanceCheckinsCollection,edges}',
  '[{"node": {"member": null}}]',
  'should show the usher their own check-in but not the member behind it, which an usher cannot read');
select is(
  pg_temp.graphql_as('head_choir', $$query { programsCollection(filter: { name: { eq: "ChoirProgram" } }) { edges { node { name programParticipantsCollection { edges { node { member { firstName } } } } } } } }$$) #>> '{data,programsCollection,edges}',
  '[{"node": {"name": "ChoirProgram", "programParticipantsCollection": {"edges": [{"node": {"member": {"firstName": "AdultChoir"}}}]}}}]',
  'should show a department head their own program with only the participants they may see');
select is(
  pg_temp.graphql_as('head_choir', $$query { servicesCollection { edges { node { name attendanceCount { men } } } } }$$) #>> '{data,servicesCollection,edges}',
  '[{"node": {"name": "ChoirEvent", "attendanceCount": {"men": 10}}}]',
  'should show a department head only the services of their own programs');

create function pg_temp.node_id_of(p_collection text, p_id text)
returns text
language sql
as $$
  select pg_temp.graphql_as('super_admin', format('{ %s(filter: { id: { eq: "%s" } }) { edges { node { nodeId } } } }', p_collection, p_id)) #>> array['data', p_collection, 'edges', '0', 'node', 'nodeId'];
$$;

select is(
  pg_temp.graphql_as('secretary', format('{ node(nodeId: "%s") { __typename } }', pg_temp.node_id_of('programParticipantsCollection', 'bb500000-0000-4000-8000-000000000003'))) #>> '{data,node}',
  null, 'should not resolve the node id of a child''s registration for the secretary');
select is(
  pg_temp.graphql_as('super_admin', format('{ node(nodeId: "%s") { __typename } }', pg_temp.node_id_of('programParticipantsCollection', 'bb500000-0000-4000-8000-000000000003'))) #>> '{data,node,__typename}',
  'ProgramParticipants', 'should resolve the same node id for the super admin');
select is(
  pg_temp.graphql_as('head_choir', format('{ node(nodeId: "%s") { __typename } }', pg_temp.node_id_of('attendanceCountsCollection', 'bb300000-0000-4000-8000-000000000001'))) #>> '{data,node}',
  null, 'should not resolve the node id of a count outside the department head''s programs');
select is(
  pg_temp.graphql_as('usher', format('{ node(nodeId: "%s") { __typename } }', pg_temp.node_id_of('attendanceCheckinsCollection', 'bb400000-0000-4000-8000-000000000003'))) #>> '{data,node}',
  null, 'should not resolve the node id of a child''s check-in for the usher');

select * from finish();

rollback;
