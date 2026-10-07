-- LBC-31 (AC 1, 5): the services and attendance schema, constraints, grants, audit triggers and comments, the rule
-- value helpers, and the small demo seed fixture. Runs as the database owner for catalog and constraint checks with the
-- demo seed still in place.

begin;

select plan(107);

-- Seed fixture (supabase/seed.sql): a handful of fake events, no real data

select is((select count(*) from public.services), 5::bigint, 'should seed five services');
select is((select count(*) from public.services where type = 'sunday' and starts_at < '2026-10-05'), 2::bigint, 'should seed two past Sunday services');
select is((select count(*) from public.services where type = 'sunday' and starts_at > '2026-10-05'), 1::bigint, 'should seed one upcoming Sunday service');
select is((select count(*) from public.services where type = 'special'), 1::bigint, 'should seed one special service');
select is((select count(*) from public.services where type = 'program' and program_id is not null), 1::bigint, 'should seed one program event linked to its program');
select is((select count(*) from public.attendance_counts), 1::bigint, 'should seed one headcount');
select is((select count(*) from public.attendance_counts where service_id = 'b1000000-0000-4000-8000-000000000001'), 1::bigint, 'should seed the headcount for the past first service');
select is((select count(*) from public.programs), 2::bigint, 'should seed two programs');
select is((select count(*) from public.program_participants where program_id = 'b2000000-0000-4000-8000-000000000001'), 2::bigint, 'should seed two participants in the children''s program');
select is(
  (select count(*) from public.program_participants as participant
   join public.members on members.id = participant.member_id
   join public.member_departments as link on link.member_id = members.id
   join public.departments on departments.id = link.department_id
   where private.is_minor(members.date_of_birth) and departments.is_childrens_ministry),
  1::bigint, 'should seed one minor in the children''s ministry as a participant');
select is((select count(*) from public.attendance_checkins), 1::bigint, 'should seed one check-in');

-- Objects

select has_type('public', 'service_type', 'should have the service_type enum');
select enum_has_labels('public', 'service_type', array['sunday', 'midweek', 'special', 'program'], 'should list the service types of the design');
select has_table('public', 'programs', 'should have programs');
select has_table('public', 'services', 'should have services');
select has_table('public', 'attendance_counts', 'should have attendance_counts');
select has_table('public', 'attendance_checkins', 'should have attendance_checkins');
select has_table('public', 'program_participants', 'should have program_participants');
select has_function('public', 'record_attendance_counts', array['uuid', 'integer', 'integer', 'integer', 'integer'], 'should have record_attendance_counts');
select has_function('public', 'generate_recurring_services', array['jsonb', 'integer'], 'should have generate_recurring_services');

select col_is_pk('public', 'programs', 'id', 'should key programs by id');
select col_is_pk('public', 'services', 'id', 'should key services by id');
select col_is_pk('public', 'attendance_counts', 'id', 'should key attendance_counts by a surrogate id, so the audit trigger can record it');
select col_is_pk('public', 'attendance_checkins', 'id', 'should key attendance_checkins by a surrogate id, so the audit trigger can record it');
select col_is_pk('public', 'program_participants', 'id', 'should key program_participants by a surrogate id, so the audit trigger can record it');
select col_type_is('public', 'attendance_counts', 'id', 'uuid', 'should make the surrogate id a uuid');

select is(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'attendance_counts_service_id_key'),
  'UNIQUE (service_id)', 'should allow one count per service');
select is(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'attendance_checkins_service_member_key'),
  'UNIQUE (service_id, member_id)', 'should allow one check-in per person per service');
select is(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'program_participants_program_member_key'),
  'UNIQUE (program_id, member_id)', 'should allow one registration per person per program');
select is(
  (select pg_get_constraintdef(oid) from pg_constraint where conname = 'services_name_starts_at_key'),
  'UNIQUE (name, starts_at)', 'should list a service once per name and start time');

select col_not_null('public', 'services', 'name', 'should require a service name');
select col_not_null('public', 'services', 'type', 'should require a service type');
select col_not_null('public', 'services', 'starts_at', 'should require a start time');
select col_is_null('public', 'services', 'program_id', 'should let a service have no program');
select col_is_null('public', 'services', 'archived_at', 'should let a service be active');
select col_type_is('public', 'services', 'starts_at', 'timestamp with time zone', 'should store the start time with its time zone');
select col_not_null('public', 'attendance_counts', 'recorded_by', 'should require a recorder');
select col_default_is('public', 'attendance_counts', 'men', '0', 'should default men to zero');
select col_not_null('public', 'attendance_counts', 'visitors', 'should require visitors');
select col_not_null('public', 'attendance_checkins', 'checked_in_by', 'should require the staff member who checked in');
select col_not_null('public', 'program_participants', 'member_id', 'should require a member');
select col_is_null('public', 'programs', 'department_id', 'should let a program have no department');

-- Constraints reject bad data even for the owner

select throws_ok($$insert into public.services (name, type, starts_at) values ('', 'sunday', now())$$, '23514', null, 'should reject an empty service name');
select throws_ok($$insert into public.services (name, type, starts_at) values ('   ', 'sunday', now())$$, '23514', null, 'should reject a blank service name');
select throws_ok($$insert into public.services (name, type, starts_at) values ('A', 'party', now())$$, '22P02', null, 'should reject an unknown service type');
select throws_ok($$insert into public.services (name, type, starts_at) values ('A', null, now())$$, '23502', null, 'should reject a service with no type');
select throws_ok($$insert into public.services (name, type, starts_at, program_id) values ('A', 'program', now(), gen_random_uuid())$$, '23503', null, 'should reject a service for an unknown program');
select throws_ok($$insert into public.services (name, type, starts_at) values ('Sunday First Service', 'sunday', '2026-10-04 08:00:00+00')$$, '23505', null, 'should reject the same service name and start time twice');
select throws_ok($$insert into public.programs (name, starts_on, ends_on) values ('A', '2026-02-02', '2026-02-01')$$, '23514', null, 'should reject a program that ends before it starts');
select throws_ok($$insert into public.programs (name, department_id) values ('A', gen_random_uuid())$$, '23503', null, 'should reject a program for an unknown department');
select lives_ok($$insert into public.programs (name, starts_on, ends_on) values ('SameDay', '2026-02-01', '2026-02-01')$$, 'should accept a program that starts and ends on the same day');
select lives_ok($$insert into public.programs (name) values ('Open ended')$$, 'should accept a program with no dates');
select throws_ok(
  $$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('b1000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000005')$$,
  '23505', null, 'should reject a second check-in of the same person at the same service');
select throws_ok(
  $$insert into public.program_participants (program_id, member_id) values ('b2000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000003')$$,
  '23505', null, 'should reject a second registration of the same person for the same program');
select throws_ok(
  $$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('b1000000-0000-4000-8000-000000000002', gen_random_uuid(), '10000000-0000-4000-8000-000000000005')$$,
  '23503', null, 'should reject a check-in of an unknown member');
select throws_ok(
  $$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('b1000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000001', gen_random_uuid())$$,
  '23503', null, 'should reject a check-in by an unknown staff member');

-- updated_at is maintained by the trigger
update public.programs set updated_at = '2000-01-01T00:00:00Z' where name = 'SameDay';
select is((select updated_at from public.programs where name = 'SameDay'), now(), 'should stamp updated_at on a program update');
update public.services set updated_at = '2000-01-01T00:00:00Z' where id = 'b1000000-0000-4000-8000-000000000003';
select is((select updated_at from public.services where id = 'b1000000-0000-4000-8000-000000000003'), now(), 'should stamp updated_at on a service update');

-- Security: RLS, policies, audit triggers

select is(
  (select count(*) from pg_class where oid in ('public.programs'::regclass, 'public.services'::regclass, 'public.attendance_counts'::regclass, 'public.attendance_checkins'::regclass, 'public.program_participants'::regclass) and relrowsecurity),
  5::bigint, 'should have row level security on all five tables');
select is(
  (select count(distinct polrelid) from pg_policy where polrelid in ('public.programs'::regclass, 'public.services'::regclass, 'public.attendance_counts'::regclass, 'public.attendance_checkins'::regclass, 'public.program_participants'::regclass)),
  5::bigint, 'should have at least one policy on each table');
select is(
  (select count(*) from pg_policy where polrelid in ('public.programs'::regclass, 'public.services'::regclass, 'public.attendance_counts'::regclass, 'public.attendance_checkins'::regclass, 'public.program_participants'::regclass) and polroles <> array['authenticated'::regrole::oid]),
  0::bigint, 'should scope every policy to authenticated, so none can apply to anon');
select is(
  (select count(*) from pg_policy where polrelid = 'public.attendance_counts'::regclass and polcmd <> 'r'),
  0::bigint, 'should have only select policies on attendance_counts, the function is the only writer');

select is(
  (select string_agg(tables.relname, ',' order by tables.relname)
   from pg_trigger
   join pg_class as tables on tables.oid = pg_trigger.tgrelid
   where pg_trigger.tgname = 'audit_' || tables.relname
     and tables.relname in ('programs', 'services', 'attendance_counts', 'attendance_checkins', 'program_participants')
     and pg_trigger.tgfoid = 'audit.record_change()'::regprocedure
     and pg_trigger.tgenabled = 'A'
     and pg_trigger.tgtype & 1 = 1 and pg_trigger.tgtype & 2 = 0 and pg_trigger.tgtype & 28 = 28),
  'attendance_checkins,attendance_counts,program_participants,programs,services',
  'should have the audit trigger, enabled always, AFTER INSERT OR UPDATE OR DELETE for each row, on every table');

-- Grants: anon has nothing, authenticated the minimum

select is(
  (select count(*) from information_schema.role_table_grants
   where table_schema = 'public' and grantee in ('anon', 'PUBLIC')
     and table_name in ('programs', 'services', 'attendance_counts', 'attendance_checkins', 'program_participants')),
  0::bigint, 'should grant anon nothing on any of the tables');
select is(
  (select count(*) from information_schema.column_privileges
   where table_schema = 'public' and grantee in ('anon', 'PUBLIC')
     and table_name in ('programs', 'services', 'attendance_counts', 'attendance_checkins', 'program_participants')),
  0::bigint, 'should grant anon no column on any of the tables');
select table_privs_are('public', 'attendance_counts', 'authenticated', array['SELECT'], 'should let authenticated only read attendance_counts');
select table_privs_are('public', 'services', 'authenticated', array['SELECT'], 'should give authenticated only a table level read on services, with column level writes and never a delete');
select table_privs_are('public', 'programs', 'authenticated', array['SELECT'], 'should give authenticated only a table level read on programs, with column level writes and never a delete');
select table_privs_are('public', 'attendance_checkins', 'authenticated', array['SELECT', 'DELETE'], 'should let authenticated read and delete check-ins, insert only by column, and never update');
select table_privs_are('public', 'program_participants', 'authenticated', array['SELECT', 'DELETE'], 'should let authenticated read and delete registrations, insert only by column, and never update');
select is(has_column_privilege('authenticated', 'public.services', 'id', 'update'), false, 'should not let authenticated change a service id');
select is(has_column_privilege('authenticated', 'public.services', 'created_at', 'update'), false, 'should not let authenticated change created_at');
select is(has_column_privilege('authenticated', 'public.services', 'updated_at', 'update'), false, 'should not let authenticated set updated_at');
select is(has_column_privilege('authenticated', 'public.programs', 'created_at', 'insert'), false, 'should not let authenticated set created_at on a program');
select is(has_column_privilege('authenticated', 'public.attendance_checkins', 'checked_in_at', 'insert'), false, 'should not let authenticated backdate a check-in');
select is(has_column_privilege('authenticated', 'public.attendance_checkins', 'checked_in_by', 'insert'), true, 'should let the check-in policy compare checked_in_by with the caller');
select is(has_column_privilege('authenticated', 'public.services', 'archived_at', 'insert'), false, 'should not let a service be created already archived');
select is(has_column_privilege('authenticated', 'public.services', 'name', 'insert'), true, 'should let authenticated insert a service name');
select is(has_column_privilege('authenticated', 'public.attendance_counts', 'men', 'insert') or has_column_privilege('authenticated', 'public.attendance_counts', 'men', 'update'), false, 'should not let authenticated write a count column');
select is(has_column_privilege('authenticated', 'public.services', 'archived_at', 'update'), true, 'should let a service be archived');

select is(has_function_privilege('anon', 'public.record_attendance_counts(uuid, integer, integer, integer, integer)', 'execute'), false, 'should not let anon execute record_attendance_counts');
select is(has_function_privilege('anon', 'public.generate_recurring_services(jsonb, integer)', 'execute'), false, 'should not let anon execute generate_recurring_services');
select is(has_function_privilege('authenticated', 'public.record_attendance_counts(uuid, integer, integer, integer, integer)', 'execute'), true, 'should let authenticated execute record_attendance_counts');
select is(has_function_privilege('authenticated', 'public.generate_recurring_services(jsonb, integer)', 'execute'), true, 'should let authenticated execute generate_recurring_services');
select is(
  (select count(*) from pg_proc where oid in ('public.record_attendance_counts(uuid, integer, integer, integer, integer)'::regprocedure, 'public.generate_recurring_services(jsonb, integer)'::regprocedure)
     and prosecdef and proconfig = array['search_path=""'] and provolatile = 'v'),
  2::bigint, 'should make both public functions security definer, volatile, with an empty search_path');
select is(
  (select count(*) from pg_proc join pg_namespace on pg_namespace.oid = pronamespace
   where nspname = 'private' and prosecdef and (proconfig is null or proconfig <> array['search_path=""'])),
  0::bigint, 'should give every security definer helper in private an empty search_path');
select is(
  (select count(*) from pg_proc join pg_namespace on pg_namespace.oid = pronamespace
   where nspname = 'private' and proname in ('church_time_zone', 'days_per_week', 'sunday_iso_weekday', 'default_generation_weeks', 'max_generation_weeks', 'max_service_templates', 'recurring_service_types', 'service_template_keys', 'is_valid_service_template', 'parse_service_templates')
     and (has_function_privilege('authenticated', pg_proc.oid, 'execute') or has_function_privilege('anon', pg_proc.oid, 'execute'))),
  0::bigint, 'should keep the rule values and input parsers closed to app roles');
select is(
  (select string_agg(proname, ',' order by proname) from pg_proc join pg_namespace on pg_namespace.oid = pronamespace
   where nspname = 'private' and proname in ('is_office_staff', 'can_record_attendance', 'heads_program', 'heads_service_program')
     and has_function_privilege('authenticated', pg_proc.oid, 'execute') and not has_function_privilege('anon', pg_proc.oid, 'execute')),
  'can_record_attendance,heads_program,heads_service_program,is_office_staff', 'should open only the policy helpers to authenticated and none to anon');

-- Rule values

select is(private.church_time_zone(), 'Africa/Accra', 'should write service times in the Accra time zone');
select is(private.days_per_week(), 7, 'should count seven days in a week');
select is(private.sunday_iso_weekday(), 7, 'should number Sunday 7');
select is(private.default_generation_weeks(), 8, 'should generate eight weeks by default');
select is(private.max_generation_weeks(), 26, 'should generate at most 26 weeks');
select is(private.max_service_templates(), 20, 'should accept at most twenty templates');
select is(private.max_headcount(), 100000, 'should cap a count at 100000');
select is(private.max_name_length(), 200, 'should cap a service name at 200 characters');
select is(has_function_privilege('service_role', 'private.max_headcount()', 'execute') and has_function_privilege('authenticated', 'private.max_headcount()', 'execute') and has_function_privilege('service_role', 'private.max_name_length()', 'execute') and has_function_privilege('authenticated', 'private.max_name_length()', 'execute'), true, 'should let the roles that write the checked tables run the two limits their CHECK constraints use');
select is(has_function_privilege('anon', 'private.max_headcount()', 'execute') or has_function_privilege('anon', 'private.max_name_length()', 'execute'), false, 'should keep the two limits closed to anon');
select is(private.recurring_service_types(), array['sunday', 'midweek'], 'should generate sunday and midweek services');
select isnt((select count(*) from pg_timezone_names where name = private.church_time_zone()), 0::bigint, 'should name a time zone Postgres knows');

-- Relationship names and comments

select is(
  (select count(*) from pg_constraint
   where contype = 'f' and conrelid in ('public.programs'::regclass, 'public.services'::regclass, 'public.attendance_counts'::regclass, 'public.attendance_checkins'::regclass, 'public.program_participants'::regclass)
     and obj_description(oid, 'pg_constraint') !~ '^@graphql[(][{]"foreign_name": ".+", "local_name": ".+"[}][)]$'),
  0::bigint, 'should name both ends of every foreign key for GraphQL');
select is(
  (select count(*) from pg_constraint
   where contype = 'f' and conrelid in ('public.programs'::regclass, 'public.services'::regclass, 'public.attendance_counts'::regclass, 'public.attendance_checkins'::regclass, 'public.program_participants'::regclass)),
  10::bigint, 'should have ten foreign keys on the five tables');

select is(
  (select count(*) from pg_class where oid in ('public.programs'::regclass, 'public.services'::regclass, 'public.attendance_counts'::regclass, 'public.attendance_checkins'::regclass, 'public.program_participants'::regclass) and obj_description(oid, 'pg_class') is null),
  0::bigint, 'should comment every table');
select is(
  (select count(*) from pg_attribute
   where attrelid in ('public.programs'::regclass, 'public.services'::regclass, 'public.attendance_counts'::regclass, 'public.attendance_checkins'::regclass, 'public.program_participants'::regclass)
     and attnum > 0 and not attisdropped and col_description(attrelid, attnum) is null),
  0::bigint, 'should comment every column');
select is(
  (select count(*) from pg_proc join pg_namespace on pg_namespace.oid = pronamespace
   where nspname in ('public', 'private') and obj_description(pg_proc.oid, 'pg_proc') is null),
  0::bigint, 'should comment every function in public and private');
select isnt(obj_description('public.service_type'::regtype, 'pg_type'), null, 'should comment the service_type enum');
select is(
  (select count(*) from pg_proc join pg_namespace on pg_namespace.oid = pronamespace
   where nspname in ('public', 'private') and obj_description(pg_proc.oid, 'pg_proc') ~ (chr(8212) || '|' || chr(8211))),
  0::bigint, 'should have no long dashes in function comments');

select * from finish();

rollback;
