-- LBC-26 (AC 1, 2, 5, 6): the members schema, constraints, grants, audit triggers and comments, the demo seed
-- fixture, and private.is_minor at its boundaries (turns 18 today, tomorrow, yesterday, leap day, unknown).
-- Runs as the database owner for catalog and constraint checks; the demo seed is still in place for the first block.

begin;

select plan(118);

-- Seed fixture (supabase/seed.sql): a small fake congregation, no real data

select is((select count(*) from public.households), 3::bigint, 'should seed three households');
select is((select count(*) from public.members), 8::bigint, 'should seed eight members');
select is((select count(*) from public.members where private.is_minor(date_of_birth, adult_confirmed)), 2::bigint, 'should seed two minors');
select is((select count(*) from public.members where archived_at is not null), 1::bigint, 'should seed one archived member');
select is((select count(*) from public.members where status = 'visitor'), 1::bigint, 'should seed one visitor');
select is((select count(distinct status) from public.members), 4::bigint, 'should seed members in four different statuses');
select is(
  (select count(*) from public.members as member
   join public.member_departments as link on link.member_id = member.id
   join public.departments on departments.id = link.department_id
   where private.is_minor(member.date_of_birth, member.adult_confirmed) and departments.is_childrens_ministry),
  1::bigint,
  'should seed one minor in the children''s ministry'
);
select is((select count(*) from (select member_id from public.member_departments group by member_id having count(*) = 2) as pairs), 1::bigint, 'should seed one member in two departments');
select is((select count(*) from public.visitor_followups), 1::bigint, 'should seed one follow-up');
select is((select count(*) from public.members where email is not null and email !~ '@example[.]org$'), 0::bigint, 'should use only example.org addresses');
select is((select count(*) from public.staff where member_id is not null), 0::bigint, 'should leave the seeded staff unlinked to members');

-- Objects

select has_type('public', 'member_status', 'should have the member_status enum');
select enum_has_labels('public', 'member_status', array['visitor', 'active', 'inactive', 'transferred', 'deceased'], 'should list the member statuses of the design');
select has_table('public', 'households', 'should have households');
select has_table('public', 'members', 'should have members');
select has_table('public', 'member_departments', 'should have member_departments');
select has_table('public', 'visitor_followups', 'should have visitor_followups');
select has_view('public', 'member_names', 'should have the member_names view');
select col_is_pk('public', 'members', 'id', 'should key members by id');
select col_is_pk('public', 'households', 'id', 'should key households by id');
select col_is_pk('public', 'member_departments', 'id', 'should key member_departments by a surrogate id so the audit trigger can record it');
select col_is_pk('public', 'visitor_followups', 'id', 'should key visitor_followups by id');
select has_unique('public', 'member_departments', 'should keep a member in a department only once');
select fk_ok('public', 'members', 'household_id', 'public', 'households', 'id', 'should link members to households');
select fk_ok('public', 'member_departments', 'member_id', 'public', 'members', 'id', 'should link department rows to members');
select fk_ok('public', 'member_departments', 'department_id', 'public', 'departments', 'id', 'should link department rows to departments');
select fk_ok('public', 'visitor_followups', 'member_id', 'public', 'members', 'id', 'should link follow-ups to the visitor');
select fk_ok('public', 'visitor_followups', 'assigned_to', 'public', 'staff', 'id', 'should link follow-ups to the staff member who does them');
select fk_ok('public', 'staff', 'member_id', 'public', 'members', 'id', 'should link staff to their member record (the key LBC-17 left for this migration)');
select is((select conname::text from pg_constraint where conrelid = 'public.staff'::regclass and contype = 'f' and confrelid = 'public.members'::regclass), 'staff_member_id_fkey', 'should name the staff foreign key staff_member_id_fkey');

-- Constraints and defaults (as the owner, so RLS is not in the way)

select throws_ok($$insert into public.members (first_name, last_name) values ('', 'Test')$$, '23514', null, 'should reject an empty first name');
select throws_ok($$insert into public.members (first_name, last_name) values ('Test', '   ')$$, '23514', null, 'should reject a blank last name');
select throws_ok($$insert into public.households (name) values ('')$$, '23514', null, 'should reject an empty household name');
select throws_ok($$insert into public.members (first_name, last_name, status) values ('Test', 'Test', 'wizard')$$, '22P02', null, 'should reject a status that is not in member_status');
select throws_ok($$insert into public.members (first_name, last_name, household_id) values ('Test', 'Test', gen_random_uuid())$$, '23503', null, 'should reject a member in a household that does not exist');
select throws_ok($$insert into public.member_departments (member_id, department_id) values (gen_random_uuid(), '20000000-0000-4000-8000-000000000001')$$, '23503', null, 'should reject a department link for an unknown member');
select throws_ok($$insert into public.member_departments (member_id, department_id) values ('40000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000003')$$, '23505', null, 'should reject the same department link twice');
select throws_ok($$insert into public.visitor_followups (member_id, status) values ('40000000-0000-4000-8000-000000000006', 'wizard')$$, '23514', null, 'should reject a follow-up status other than pending, contacted or done');
select throws_ok($$insert into public.visitor_followups (member_id) values (gen_random_uuid())$$, '23503', null, 'should reject a follow-up for an unknown member');
select throws_ok($$insert into public.visitor_followups (member_id, assigned_to) values ('40000000-0000-4000-8000-000000000006', gen_random_uuid())$$, '23503', null, 'should reject a follow-up assigned to unknown staff');
select throws_ok($$update public.staff set member_id = gen_random_uuid() where id = '10000000-0000-4000-8000-000000000001'$$, '23503', null, 'should reject linking staff to an unknown member');
select lives_ok($$update public.staff set member_id = '40000000-0000-4000-8000-000000000001' where id = '10000000-0000-4000-8000-000000000001'$$, 'should let staff be linked to a member');

insert into public.members (id, first_name, last_name) values ('61000000-0000-4000-8000-000000000001', 'Default', 'Check');
select is((select status from public.members where id = '61000000-0000-4000-8000-000000000001'), 'visitor'::public.member_status, 'should default a new member to visitor');
select is((select sms_opt_out from public.members where id = '61000000-0000-4000-8000-000000000001'), false, 'should default sms_opt_out to false');
select is((select consent_recorded_at from public.members where id = '61000000-0000-4000-8000-000000000001'), null, 'should leave consent unrecorded by default');
select is((select archived_at from public.members where id = '61000000-0000-4000-8000-000000000001'), null, 'should create members active');

insert into public.visitor_followups (id, member_id) values ('71000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000001');
select is((select status from public.visitor_followups where id = '71000000-0000-4000-8000-000000000001'), 'pending', 'should default a new follow-up to pending');

-- updated_at: start in the past so the trigger visibly changes it inside this transaction
insert into public.households (id, name, created_at, updated_at) values ('31000000-0000-4000-8000-000000000001', 'Stamp', '2020-01-01', '2020-01-01');
insert into public.members (id, first_name, last_name, created_at, updated_at) values ('61000000-0000-4000-8000-000000000002', 'Stamp', 'Check', '2020-01-01', '2020-01-01');
insert into public.visitor_followups (id, member_id, created_at, updated_at) values ('71000000-0000-4000-8000-000000000002', '61000000-0000-4000-8000-000000000002', '2020-01-01', '2020-01-01');
update public.households set name = 'Stamped' where id = '31000000-0000-4000-8000-000000000001';
update public.members set last_name = 'Stamped' where id = '61000000-0000-4000-8000-000000000002';
update public.visitor_followups set status = 'done' where id = '71000000-0000-4000-8000-000000000002';
select is((select updated_at from public.households where id = '31000000-0000-4000-8000-000000000001'), now(), 'should stamp updated_at on households');
select is((select updated_at from public.members where id = '61000000-0000-4000-8000-000000000002'), now(), 'should stamp updated_at on members');
select is((select updated_at from public.visitor_followups where id = '71000000-0000-4000-8000-000000000002'), now(), 'should stamp updated_at on visitor_followups');
select is((select created_at from public.members where id = '61000000-0000-4000-8000-000000000002'), '2020-01-01'::timestamptz, 'should leave created_at alone on update');

-- Row level security, audit trigger and grants (AC 5, 6)

select is(
  (select count(*) from pg_class where oid in ('public.households'::regclass, 'public.members'::regclass, 'public.member_departments'::regclass, 'public.visitor_followups'::regclass) and relrowsecurity),
  4::bigint,
  'should enable row level security on all four tables'
);

select is(
  (select tgenabled::text from pg_trigger where tgrelid = ('public.' || relation)::regclass and tgname = 'audit_' || relation),
  'A',
  format('should run audit_%s always, even in replica mode', relation)
) from unnest(array['households', 'members', 'member_departments', 'visitor_followups']) as relations (relation);

select is(
  (select tgfoid::regproc::text from pg_trigger where tgrelid = ('public.' || relation)::regclass and tgname = 'audit_' || relation),
  'audit.record_change',
  format('should have audit_%s call audit.record_change()', relation)
) from unnest(array['households', 'members', 'member_departments', 'visitor_followups']) as relations (relation);

select is(
  has_table_privilege(role_name, 'public.' || relation, privilege),
  false,
  format('should not grant %s %s on %s', role_name, privilege, relation)
) from unnest(array['anon', 'authenticated']) as roles (role_name)
cross join unnest(array['members', 'households', 'visitor_followups']) as relations (relation)
cross join unnest(array['DELETE', 'TRUNCATE']) as privileges (privilege)
order by role_name, relation, privilege;

select is(has_table_privilege('authenticated', 'public.member_departments', 'DELETE'), true, 'should let signed-in users reach the delete policy of member_departments');
select is(has_table_privilege('authenticated', 'public.member_departments', 'UPDATE'), false, 'should not let anyone update a department link');

select is(
  has_table_privilege('anon', 'public.' || relation, 'SELECT'),
  false,
  format('should not let anon select from %s', relation)
) from unnest(array['households', 'members', 'member_departments', 'visitor_followups', 'member_names']) as relations (relation);

select is(has_column_privilege('authenticated', 'public.members', 'id', 'UPDATE'), false, 'should not let anyone update members.id');
select is(has_column_privilege('authenticated', 'public.members', 'phone', 'UPDATE'), true, 'should let signed-in users update members.phone (policies decide who)');

-- Helper functions: callable by authenticated only where a policy needs it, never by anon

select is(
  has_function_privilege(role_name, signature, 'EXECUTE'),
  expected,
  format('should %s %s executing %s', case when expected then 'let' else 'not let' end, role_name, signature)
) from (values
  ('authenticated', 'private.is_minor(date, boolean)', true),
  ('authenticated', 'private.can_view_minors()', true),
  ('authenticated', 'private.can_manage_members()', true),
  ('authenticated', 'private.heads_department_of_member(uuid, boolean)', true),
  ('authenticated', 'private.is_minor_on(date, date)', false),
  ('authenticated', 'private.age_of_majority()', false),
  ('anon', 'private.is_minor(date, boolean)', false),
  ('anon', 'private.can_view_minors()', false),
  ('anon', 'private.can_manage_members()', false),
  ('anon', 'private.heads_department_of_member(uuid, boolean)', false)
) as checks (role_name, signature, expected);

-- private.is_minor_on: fixed dates, so the boundary is pinned whatever day the test runs

select is(private.age_of_majority(), 18, 'should set the age of majority to 18');

select is(private.is_minor_on(dob::date, on_day::date), expected, description)
from (values
  ('2008-10-05', '2026-10-05', false, 'should treat a person as an adult on their 18th birthday'),
  ('2008-10-06', '2026-10-05', true, 'should treat a person as a minor the day before their 18th birthday'),
  ('2008-10-04', '2026-10-05', false, 'should treat a person as an adult the day after their 18th birthday'),
  ('2026-10-05', '2026-10-05', true, 'should treat a newborn as a minor'),
  ('2030-01-01', '2026-10-05', true, 'should treat a date of birth in the future as a minor'),
  ('1900-01-01', '2026-10-05', false, 'should treat a very old date of birth as an adult'),
  ('2008-02-29', '2026-02-28', true, 'should keep a leap day birth a minor on 28 February of the 18th year'),
  ('2008-02-29', '2026-03-01', false, 'should make a leap day birth an adult on 1 March of the 18th year'),
  ('2004-02-29', '2022-02-28', true, 'should keep another leap day birth a minor on 28 February'),
  ('2004-02-29', '2022-03-01', false, 'should make another leap day birth an adult on 1 March'),
  ('2010-02-28', '2028-02-28', false, 'should make a 28 February birth an adult on 28 February of a leap year'),
  ('2010-03-01', '2028-02-29', true, 'should keep a 1 March birth a minor on 29 February of a leap year'),
  ('2008-12-31', '2026-12-31', false, 'should handle the end of the year'),
  ('2009-01-01', '2026-12-31', true, 'should handle the turn of the year')
) as cases (dob, on_day, expected, description);

select is(private.is_minor_on(null, '2026-10-05'), true, 'should treat an unknown date of birth as a minor');
select is(private.is_minor(null, false), true, 'should treat an unknown date of birth as a minor today');
select is(private.is_minor((current_date - interval '18 years')::date, false), false, 'should treat a person who turns 18 today as an adult');
select is(private.is_minor((current_date - interval '18 years' + interval '1 day')::date, false), true, 'should treat a person who turns 18 tomorrow as a minor');
select is(private.is_minor((current_date - interval '18 years' - interval '1 day')::date, false), false, 'should treat a person who turned 18 yesterday as an adult');
select is(private.is_minor(current_date, false), true, 'should treat a person born today as a minor');

-- Comments: pg_graphql publishes them as API documentation

select is_empty(
  $$ select attrelid::regclass::text || '.' || attname
     from pg_attribute
     where attrelid in ('public.households'::regclass, 'public.members'::regclass, 'public.member_departments'::regclass, 'public.visitor_followups'::regclass, 'public.member_names'::regclass)
       and attnum > 0 and not attisdropped
       and col_description(attrelid, attnum) is null $$,
  'should describe every column of the new tables and the view'
);

select is_empty(
  $$ select relname from pg_class
     where oid in ('public.households'::regclass, 'public.members'::regclass, 'public.member_departments'::regclass, 'public.visitor_followups'::regclass, 'public.member_names'::regclass)
       and obj_description(oid, 'pg_class') is null $$,
  'should describe every new table and the view'
);

select is_empty(
  $$ select proname from pg_proc
     where pronamespace = 'private'::regnamespace
       and proname in ('age_of_majority', 'is_minor_on', 'is_minor', 'can_view_minors', 'can_manage_members', 'heads_department_of_member')
       and obj_description(oid, 'pg_proc') is null $$,
  'should describe every new helper function'
);

select is(
  (select count(*) from pg_constraint
   where conname in ('members_household_id_fkey', 'member_departments_member_id_fkey', 'member_departments_department_id_fkey',
                     'visitor_followups_member_id_fkey', 'visitor_followups_assigned_to_fkey', 'staff_member_id_fkey')
     and obj_description(oid, 'pg_constraint') like '@graphql(%'),
  6::bigint,
  'should name every new GraphQL relationship in a constraint comment'
);

select is(
  (select count(*) from pg_policy where polrelid in ('public.households'::regclass, 'public.members'::regclass, 'public.member_departments'::regclass, 'public.visitor_followups'::regclass) and polcmd = 'd'),
  1::bigint,
  'should have exactly one delete policy, on member_departments'
);

select is(
  (select count(*) from pg_policy where polrelid in ('public.households'::regclass, 'public.members'::regclass, 'public.member_departments'::regclass, 'public.visitor_followups'::regclass) and 'anon'::regrole = any (polroles)),
  0::bigint,
  'should have no policy that applies to anon'
);

select * from finish();

rollback;
