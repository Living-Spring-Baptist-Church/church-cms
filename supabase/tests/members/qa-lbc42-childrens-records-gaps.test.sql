-- LBC-42 QA gaps: attendance and links of children's ministry records, household moves, aal1 sessions, age
-- boundary, double registration, department flag toggling and GraphQL reads, as every role.
begin;

select * from no_plan();

set local session_replication_role = replica;
delete from public.visitor_followups;
delete from public.member_departments;
delete from public.members;
delete from public.households;
delete from public.staff_roles;
delete from public.staff;
delete from public.departments;
set local session_replication_role = origin;

create temp table actors (label text primary key, staff_id uuid, is_active boolean not null default true);
create temp table actor_roles (label text not null, role public.app_role not null, department_id uuid);

-- Returns the rows affected as 'ok:<n>', the coded message of a catalogued error (P0001), or the SQLSTATE.
create function pg_temp.try_as(p_label text, p_statement text, p_aal text default 'aal2')
returns text
language plpgsql
as $$
declare
  v_original name := current_user;
  v_db_role name := case p_label when 'anon' then 'anon' else 'authenticated' end;
  v_rows bigint;
  v_result text;
begin
  perform set_config('request.jwt.claims', json_build_object('aal', p_aal, 'role', v_db_role, 'sub', (select staff_id from actors where label = p_label))::text, true);
  perform set_config('role', v_db_role::text, true);
  begin
    execute p_statement;
    get diagnostics v_rows = row_count;
    v_result := 'ok:' || v_rows;
  exception when others then
    v_result := case when sqlstate = 'P0001' then sqlerrm else sqlstate end;
  end;
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_result;
end;
$$;

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

-- Departments: Choir, Youth, Children's Ministry and Nursery (both children's ministries) and a retired ministry.
insert into public.departments (id, name, is_childrens_ministry, archived_at)
values
  ('d1000000-0000-4000-8000-000000000001', 'Choir', false, null),
  ('d1000000-0000-4000-8000-000000000002', 'Youth', false, null),
  ('d1000000-0000-4000-8000-000000000003', 'Children''s Ministry', true, null),
  ('d1000000-0000-4000-8000-000000000004', 'Nursery', true, null),
  ('d1000000-0000-4000-8000-000000000005', 'Retired Ministry', true, now());

insert into actors (label)
values
  ('super_admin'), ('pastor'), ('treasurer'), ('secretary'), ('usher'), ('content_editor'),
  ('head_children'), ('head_nursery'), ('head_choir'), ('head_youth'), ('no_role');

insert into actor_roles (label, role, department_id)
values
  ('super_admin', 'super_admin', null),
  ('pastor', 'pastor', null),
  ('treasurer', 'treasurer', null),
  ('secretary', 'secretary', null),
  ('usher', 'usher', null),
  ('content_editor', 'content_editor', null),
  ('head_children', 'department_head', 'd1000000-0000-4000-8000-000000000003'),
  ('head_nursery', 'department_head', 'd1000000-0000-4000-8000-000000000004'),
  ('head_choir', 'department_head', 'd1000000-0000-4000-8000-000000000001'),
  ('head_youth', 'department_head', 'd1000000-0000-4000-8000-000000000002');

insert into actors (label, is_active) values ('inactive_secretary', false), ('inactive_head_children', false);
insert into actor_roles (label, role, department_id)
values
  ('inactive_secretary', 'secretary', null),
  ('inactive_head_children', 'department_head', 'd1000000-0000-4000-8000-000000000003');

insert into actors (label, is_active) values ('anon', true);

update actors
set staff_id = ('d2000000-0000-4000-8000-' || lpad(numbered.position::text, 12, '0'))::uuid
from (select label, row_number() over (order by label) as position from actors where label <> 'anon') as numbered
where actors.label = numbered.label;

insert into auth.users (id, aud, role, email)
select staff_id, 'authenticated', 'authenticated', label || '@test.invalid' from actors where label <> 'anon';
insert into public.staff (id, full_name, is_active)
select staff_id, label, is_active from actors where label <> 'anon';
insert into public.staff_roles (staff_id, role, department_id)
select actors.staff_id, actor_roles.role, actor_roles.department_id from actor_roles join actors using (label);

-- Households: Alpha (adult and child of the ministry), YouthOnly (one youth minor), Empty, Mixed (a ministry child
-- and a youth minor) and ArchivedEmpty.
insert into public.households (id, name, address, archived_at)
values
  ('d4000000-0000-4000-8000-000000000001', 'Alpha', '1 Test Lane', null),
  ('d4000000-0000-4000-8000-000000000002', 'YouthOnly', '2 Test Lane', null),
  ('d4000000-0000-4000-8000-000000000003', 'Empty', '3 Test Lane', null),
  ('d4000000-0000-4000-8000-000000000004', 'Mixed', '4 Test Lane', null),
  ('d4000000-0000-4000-8000-000000000005', 'ArchivedEmpty', '5 Test Lane', now());

-- Members, keyed by first name. Dates are relative to today so the fixture never ages.
insert into public.members (id, household_id, first_name, last_name, date_of_birth, adult_confirmed, status, archived_at)
values
  ('d3000000-0000-4000-8000-000000000001', 'd4000000-0000-4000-8000-000000000001', 'AdultA', 'Test', '1980-01-01', false, 'active', null),
  ('d3000000-0000-4000-8000-000000000002', 'd4000000-0000-4000-8000-000000000001', 'ChildKids', 'Test', current_date - interval '8 years', false, 'active', null),
  ('d3000000-0000-4000-8000-000000000003', null, 'ChildNursery', 'Test', current_date - interval '3 years', false, 'active', null),
  ('d3000000-0000-4000-8000-000000000004', 'd4000000-0000-4000-8000-000000000002', 'YouthMinor', 'Test', current_date - interval '15 years', false, 'active', null),
  ('d3000000-0000-4000-8000-000000000005', null, 'UnknownMinor', 'Test', null, false, 'visitor', null),
  ('d3000000-0000-4000-8000-000000000006', null, 'UnknownAdult', 'Test', null, true, 'visitor', null),
  ('d3000000-0000-4000-8000-000000000007', null, 'ChildNoDob', 'Test', null, false, 'active', null),
  ('d3000000-0000-4000-8000-000000000008', null, 'ChildArchived', 'Test', current_date - interval '7 years', false, 'inactive', now()),
  ('d3000000-0000-4000-8000-000000000009', 'd4000000-0000-4000-8000-000000000004', 'MixedChild', 'Test', current_date - interval '6 years', false, 'active', null),
  ('d3000000-0000-4000-8000-00000000000a', 'd4000000-0000-4000-8000-000000000004', 'MixedYouth', 'Test', current_date - interval '14 years', false, 'active', null),
  ('d3000000-0000-4000-8000-00000000000b', null, 'AdultArchived', 'Test', '1975-01-01', false, 'transferred', now());

insert into public.member_departments (member_id, department_id)
values
  ('d3000000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000003'),
  ('d3000000-0000-4000-8000-000000000003', 'd1000000-0000-4000-8000-000000000004'),
  ('d3000000-0000-4000-8000-000000000004', 'd1000000-0000-4000-8000-000000000002'),
  ('d3000000-0000-4000-8000-000000000007', 'd1000000-0000-4000-8000-000000000003'),
  ('d3000000-0000-4000-8000-000000000008', 'd1000000-0000-4000-8000-000000000003'),
  ('d3000000-0000-4000-8000-000000000009', 'd1000000-0000-4000-8000-000000000003'),
  ('d3000000-0000-4000-8000-00000000000a', 'd1000000-0000-4000-8000-000000000002');

insert into public.households (id, name, address) values ('d4000000-0000-4000-8000-000000000006', 'YouthOnlyTwo', '6 Test Lane');
update public.members set household_id = 'd4000000-0000-4000-8000-000000000006' where first_name = 'MixedYouth';
update public.members set household_id = 'd4000000-0000-4000-8000-000000000004' where first_name = 'MixedChild';
insert into public.services (id, name, type, starts_at)
values ('d5000000-0000-4000-8000-000000000001', 'QA Service', 'sunday', now());

-- Households a secretary cannot see must not become visible by moving someone into them
select is(pg_temp.try_as('secretary', $$update public.members set household_id = 'd4000000-0000-4000-8000-000000000002' where first_name = 'ChildKids'$$), 'AUTH_FORBIDDEN', 'should not let the secretary move a child into a household she cannot see');
select is(pg_temp.try_as('secretary', $$insert into public.members (first_name, last_name, adult_confirmed, household_id) values ('HouseProbe', 'Test', true, 'd4000000-0000-4000-8000-000000000002')$$), 'AUTH_FORBIDDEN', 'should not let the secretary register an adult into a household she cannot see');
select is(pg_temp.seen_as('secretary', 'public.households', 'name') like '%YouthOnly%', false, 'should keep the youth-only household hidden from the secretary');
select is(pg_temp.try_as('head_children', $$update public.members set household_id = 'd4000000-0000-4000-8000-000000000002' where first_name = 'ChildKids'$$), 'AUTH_FORBIDDEN', 'should not let the ministry head move a child into a household that is not theirs to see');
select is(pg_temp.seen_as('secretary', 'public.households', 'name') like '%YouthOnly%', false, 'should still hide the youth-only household after the head tried to move a child in');
select is(pg_temp.try_as('secretary', $$update public.members set household_id = 'd4000000-0000-4000-8000-000000000003' where first_name = 'ChildKids'$$), 'ok:1', 'should let the secretary move a child into an empty household');
select is(pg_temp.try_as('secretary', $$update public.members set household_id = 'd4000000-0000-4000-8000-000000000001' where first_name = 'ChildKids'$$), 'ok:1', 'should let the secretary move a child into a household that holds an adult');
select is(pg_temp.try_as('secretary', $$insert into public.members (first_name, last_name, adult_confirmed, household_id) values ('HouseOk', 'Test', true, 'd4000000-0000-4000-8000-000000000001')$$), 'ok:1', 'should let the secretary register an adult into a visible household');
select is(pg_temp.try_as('super_admin', $$update public.members set household_id = 'd4000000-0000-4000-8000-000000000002' where first_name = 'ChildNursery'$$), 'ok:1', 'should let the super admin place a person in any household');
update public.members set household_id = null where first_name = 'ChildNursery';
select is(pg_temp.try_as('head_children', $$update public.members set household_id = null where first_name = 'ChildKids'$$), 'ok:1', 'should let the ministry head clear a household');
select is(pg_temp.try_as('head_children', $$update public.members set household_id = 'd4000000-0000-4000-8000-000000000001' where first_name = 'ChildNursery'$$), 'ok:0', 'should not let the ministry head touch a child of another ministry');
update public.members set household_id = 'd4000000-0000-4000-8000-000000000001' where first_name = 'ChildKids';


-- Attendance
select is(pg_temp.try_as('secretary', $$insert into public.attendance_checkins (service_id, member_id, checked_in_by) select 'd5000000-0000-4000-8000-000000000001', 'd3000000-0000-4000-8000-000000000002', id from public.staff where full_name = 'secretary'$$), 'ok:1', 'should let the secretary check in a ministry child');
select is(pg_temp.try_as('secretary', $$insert into public.attendance_checkins (service_id, member_id, checked_in_by) select 'd5000000-0000-4000-8000-000000000001', 'd3000000-0000-4000-8000-000000000004', id from public.staff where full_name = 'secretary'$$), '42501', 'should not let the secretary check in a youth minor');
select is(pg_temp.try_as('usher', $$insert into public.attendance_checkins (service_id, member_id, checked_in_by) select 'd5000000-0000-4000-8000-000000000001', 'd3000000-0000-4000-8000-000000000002', id from public.staff where full_name = 'usher'$$), '42501', 'should not let an usher check in a child');
select is(pg_temp.try_as('head_children', $$insert into public.attendance_checkins (service_id, member_id, checked_in_by) select 'd5000000-0000-4000-8000-000000000001', 'd3000000-0000-4000-8000-000000000002', id from public.staff where full_name = 'head_children'$$), '42501', 'should not let a head write attendance');
insert into public.attendance_checkins (service_id, member_id, checked_in_by)
select 'd5000000-0000-4000-8000-000000000001', 'd3000000-0000-4000-8000-000000000004', (select id from public.staff where full_name = 'super_admin');
select is(pg_temp.seen_as('secretary', 'public.attendance_checkins', 'member_id'), 'd3000000-0000-4000-8000-000000000002', 'should show the secretary only the ministry child check-in');
select is(pg_temp.seen_as('usher', 'public.attendance_checkins', 'member_id'), '', 'should show an usher no check-in of a minor');
select is(pg_temp.seen_as('treasurer', 'public.attendance_checkins', 'member_id'), '', 'should show the treasurer no check-in');
select is(pg_temp.seen_as('head_choir', 'public.attendance_checkins', 'member_id'), '', 'should show the choir head no check-in of a minor');

-- member_departments visibility
select is(pg_temp.seen_as('secretary', 'public.member_departments', 'member_id') like '%000000000004%', false, 'should hide the youth minor link from the secretary');
select is(pg_temp.seen_as('head_choir', 'public.member_departments', 'member_id'), '', 'should show the choir head no link of a minor');
select is(pg_temp.seen_as('usher', 'public.member_departments', 'member_id'), '', 'should show an usher no link');
select is(pg_temp.try_as('anon', 'select * from public.member_departments'), '42501', 'should deny anon the links');

-- A child in the ministry and also in the choir is not the choir head's to read or edit
insert into public.member_departments (member_id, department_id) values ('d3000000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000001');
select is(pg_temp.seen_as('head_choir', 'public.members', 'first_name'), '', 'should keep a ministry child hidden from the choir head though the child sings in the choir');
select is(pg_temp.try_as('head_choir', $$update public.members set phone = '1' where first_name = 'ChildKids'$$), 'ok:0', 'should not let the choir head edit that child');
select is(pg_temp.seen_as('head_choir', 'public.member_departments', 'member_id'), '', 'should hide that child link from the choir head');

-- Flagging a department changes who sees its minors, and unflagging reverts it
select is(pg_temp.try_as('head_youth', $$update public.departments set is_childrens_ministry = true where name = 'Youth'$$), 'ok:0', 'should not let a head flag their own department as a children''s ministry');
select is(pg_temp.try_as('secretary', $$update public.departments set is_childrens_ministry = true where name = 'Youth'$$), 'ok:0', 'should not let the secretary flag a department');
update public.departments set is_childrens_ministry = true where name = 'Youth';
select is(pg_temp.seen_as('secretary', 'public.members', 'first_name') like '%YouthMinor%', true, 'should show youth minors to the secretary once an admin flags Youth');
update public.departments set is_childrens_ministry = false where name = 'Youth';
select is(pg_temp.seen_as('secretary', 'public.members', 'first_name') like '%YouthMinor%', false, 'should hide youth minors from the secretary again once unflagged');

-- aal1 sessions
select is(pg_temp.try_as('super_admin', $$select public.register_child('Aal1Super', 'Test', 'd1000000-0000-4000-8000-000000000003')$$, 'aal1'), 'AUTH_FORBIDDEN', 'should refuse register_child to a super admin without two-factor');
select is(pg_temp.try_as('secretary', $$select public.register_child('Aal1Sec', 'Test', 'd1000000-0000-4000-8000-000000000003')$$, 'aal1'), 'ok:1', 'should let the secretary register a child at aal1 since she needs no two-factor');

-- Names and dates
select is(pg_temp.try_as('secretary', $$select public.register_child('Zoë', 'O''Brien-Mensah', 'd1000000-0000-4000-8000-000000000003')$$), 'ok:1', 'should accept diacritics and apostrophes in a child name');
select is((select first_name || '|' || last_name from public.members where first_name like 'Zo%'), 'Zoë|O''Brien-Mensah', 'should store the name exactly');
select is(pg_temp.try_as('secretary', format($$select public.register_child('EdgeLong', %L, 'd1000000-0000-4000-8000-000000000003')$$, repeat('x', 5000))) in ('VALIDATION_FAILED', 'ok:1'), true, 'should answer a very long name with a catalogued result and not a raw database error');
select is(pg_temp.try_as('secretary', format($$select public.register_child('EdgeOld', 'Test', 'd1000000-0000-4000-8000-000000000003', %L)$$, current_date - make_interval(years => private.age_of_majority()))), 'VALIDATION_FAILED', 'should reject a person who turned 18 today');
select is(pg_temp.try_as('secretary', format($$select public.register_child('EdgeYoung', 'Test', 'd1000000-0000-4000-8000-000000000003', %L)$$, (current_date - make_interval(years => private.age_of_majority()))::date + 1)), 'ok:1', 'should accept a child who turns 18 tomorrow');
select is(pg_temp.try_as('secretary', $$select public.register_child('EdgeToday', 'Test', 'd1000000-0000-4000-8000-000000000003', current_date)$$), 'ok:1', 'should accept a baby born today');
select is(pg_temp.try_as('secretary', $$select public.register_child('Twin', 'Test', 'd1000000-0000-4000-8000-000000000003')$$), 'ok:1', 'should register a child once');
select is(pg_temp.try_as('secretary', $$select public.register_child('Twin', 'Test', 'd1000000-0000-4000-8000-000000000003')$$), 'ok:1', 'should accept a second identical registration, as the database holds no unique name');
select is((select count(*) from public.member_departments as link join public.members on members.id = link.member_id where members.first_name = 'Twin'), 2::bigint, 'should link each twin to exactly one department row');

-- GraphQL reads
select is(
  (pg_temp.graphql_as('secretary', $$query { membersCollection(filter: {firstName: {in: ["YouthMinor", "MixedYouth", "UnknownMinor"]}}) { edges { node { firstName } } } }$$) #> '{data,membersCollection,edges}'),
  '[]'::jsonb,
  'should return no youth minor to the secretary through GraphQL'
);
select is(
  jsonb_array_length(pg_temp.graphql_as('secretary', $$query { membersCollection(filter: {firstName: {eq: "ChildKids"}}) { edges { node { firstName } } } }$$) #> '{data,membersCollection,edges}'),
  1,
  'should return the ministry child to the secretary through GraphQL'
);
select is(
  (pg_temp.graphql_as('usher', $$query { memberNamesCollection(filter: {firstName: {in: ["ChildKids", "YouthMinor", "UnknownMinor"]}}) { edges { node { firstName } } } }$$) #> '{data,memberNamesCollection,edges}'),
  '[]'::jsonb,
  'should return no minor in memberNames to an usher through GraphQL'
);
select is(
  (pg_temp.graphql_as('head_children', $$mutation { updateMembersCollection(set: {phone: "0200000001"}, filter: {firstName: {eq: "YouthMinor"}}) { affectedCount } }$$) #>> '{data,updateMembersCollection,affectedCount}')::int,
  0,
  'should change nothing when the ministry head updates a youth minor through GraphQL'
);
select is(
  (pg_temp.graphql_as('head_children', $$mutation { updateMembersCollection(set: {phone: "0200000002"}, filter: {firstName: {eq: "ChildKids"}}) { affectedCount } }$$) #>> '{data,updateMembersCollection,affectedCount}')::int,
  1,
  'should let the ministry head update their child through GraphQL'
);
select is(
  pg_temp.graphql_as('head_children', $$mutation { updateMembersCollection(set: {adultConfirmed: true}, filter: {firstName: {eq: "ChildNoDob"}}) { affectedCount } }$$) #>> '{errors,0,message}',
  'AUTH_FORBIDDEN',
  'should refuse the ministry head setting adultConfirmed through GraphQL'
);
select is(
  (pg_temp.graphql_as('secretary', $$query { householdsCollection(filter: {name: {eq: "YouthOnlyTwo"}}) { edges { node { name address } } } }$$) #> '{data,householdsCollection,edges}'),
  '[]'::jsonb,
  'should hide the youth-only household from the secretary through GraphQL'
);

-- Archive and restore of an adult by the secretary
select is(pg_temp.try_as('secretary', $$update public.members set archived_at = now() where first_name = 'AdultA'$$), 'ok:1', 'should let the secretary archive an adult');
select is(pg_temp.try_as('secretary', $$update public.members set archived_at = null where first_name = 'AdultA'$$), 'ok:1', 'should let the secretary restore an adult');

select * from finish();

rollback;
