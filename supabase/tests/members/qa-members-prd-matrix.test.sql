-- LBC-26 QA: the PRD permission matrix (members and visitors row, plus children's records) walked cell by cell
-- for every role, then the side channels, time zone and boundary dates, dual-role actors and the GraphQL flows a
-- secretary and a children's ministry head really perform. Own fixture: the demo seed cannot influence it.

begin;

select plan(157);

set local session_replication_role = replica;
delete from public.visitor_followups;
delete from public.member_departments;
delete from public.members;
delete from public.households;
delete from public.staff_roles;
delete from public.staff;
delete from public.departments;
set local session_replication_role = origin;

create temp table actors (label text primary key, staff_id uuid);
create temp table actor_roles (label text not null, role public.app_role not null, department_id uuid);

-- Runs a statement as a real database role with JWT claims. Returns the affected rows, or 'denied' for SQLSTATE 42501.
create function pg_temp.outcome(p_label text, p_statement text)
returns text
language plpgsql
as $$
declare
  v_original name := current_user;
  v_db_role name := case p_label when 'anon' then 'anon' else 'authenticated' end;
  v_rows bigint;
begin
  perform set_config('request.jwt.claims', json_build_object('role', v_db_role, 'sub', (select staff_id from actors where label = p_label))::text, true);
  perform set_config('role', v_db_role::text, true);
  begin
    execute p_statement;
    get diagnostics v_rows = row_count;
  exception when insufficient_privilege then
    perform set_config('role', v_original::text, true);
    perform set_config('request.jwt.claims', '', true);
    return 'denied';
  when others then
    perform set_config('role', v_original::text, true);
    perform set_config('request.jwt.claims', '', true);
    return 'error ' || sqlstate;
  end;
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_rows::text;
end;
$$;

-- Same, but the statement runs in a sub-transaction that is always undone, so the next check sees the fixture.
create function pg_temp.trial(p_label text, p_statement text)
returns text
language plpgsql
as $$
declare
  v_outcome text;
begin
  begin
    v_outcome := pg_temp.outcome(p_label, p_statement);
    raise exception 'UNDO';
  exception when raise_exception then
    if sqlerrm <> 'UNDO' then raise; end if;
  end;
  return v_outcome;
end;
$$;

-- Sorted, comma separated values of one column the actor can read ('denied' when the grant is missing).
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
  begin
    execute format('select coalesce(string_agg(%1$I::text, %2$L order by %1$I::text), %3$L) from %4$s', p_column, ',', '', p_relation) into v_seen;
  exception when insufficient_privilege then
    v_seen := 'denied';
  end;
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

create function pg_temp.count_as(p_label text, p_relation text)
returns int
language sql
as $$
  select coalesce(cardinality(string_to_array(nullif(pg_temp.seen_as(p_label, p_relation, 'id'), ''), ',')), 0);
$$;

create function pg_temp.scalar_as(p_label text, p_query text)
returns text
language plpgsql
as $$
declare
  v_original name := current_user;
  v_result text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', (select staff_id from actors where label = p_label))::text, true);
  perform set_config('role', 'authenticated', true);
  execute p_query into v_result;
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_result;
end;
$$;

-- Whether the actor sees a person whose 18th birthday is today (or tomorrow) in the given session time zone.
create function pg_temp.seen_as_in_zone(p_label text, p_zone text, p_tag text)
returns text
language plpgsql
as $$
declare
  v_seen text;
begin
  begin
    perform set_config('TimeZone', p_zone, true);
    insert into public.members (first_name, last_name, date_of_birth)
    values ('Probe', 'ZoneProbe', case p_tag when 'turns18today' then (current_date - interval '18 years')::date else (current_date + 1 - interval '18 years')::date end);
    v_seen := pg_temp.seen_as(p_label, $r$public.members where last_name = 'ZoneProbe'$r$, 'first_name');
    raise exception 'UNDO';
  exception when raise_exception then
    if sqlerrm <> 'UNDO' then raise; end if;
  end;
  return case when v_seen = '' then '0' else '1' end;
end;
$$;

create function pg_temp.sorted_values(p_edges jsonb, p_path text[])
returns jsonb
language sql
as $$
  select coalesce(jsonb_agg(edge #>> p_path order by edge #>> p_path), '[]'::jsonb) from jsonb_array_elements(p_edges) as edge;
$$;

insert into public.departments (id, name, is_childrens_ministry)
values
  ('c0000000-0000-4000-8000-000000000001', 'Choir', false),
  ('c0000000-0000-4000-8000-000000000002', 'Youth', false),
  ('c0000000-0000-4000-8000-000000000003', 'Children''s Ministry', true);

insert into actors (label)
values
  ('super_admin'), ('pastor'), ('treasurer'), ('secretary'), ('usher'), ('content_editor'), ('anon'),
  ('head_choir'), ('head_children'), ('secretary_and_head_children'), ('treasurer_and_pastor');

insert into actor_roles (label, role, department_id)
values
  ('super_admin', 'super_admin', null),
  ('pastor', 'pastor', null),
  ('treasurer', 'treasurer', null),
  ('secretary', 'secretary', null),
  ('usher', 'usher', null),
  ('content_editor', 'content_editor', null),
  ('head_choir', 'department_head', 'c0000000-0000-4000-8000-000000000001'),
  ('head_children', 'department_head', 'c0000000-0000-4000-8000-000000000003'),
  ('secretary_and_head_children', 'secretary', null),
  ('secretary_and_head_children', 'department_head', 'c0000000-0000-4000-8000-000000000003'),
  ('treasurer_and_pastor', 'treasurer', null),
  ('treasurer_and_pastor', 'pastor', null);

update actors
set staff_id = ('d0000000-0000-4000-8000-' || lpad(numbered.position::text, 12, '0'))::uuid
from (select label, row_number() over (order by label) as position from actors where label <> 'anon') as numbered
where actors.label = numbered.label;

insert into auth.users (id, aud, role, email)
select staff_id, 'authenticated', 'authenticated', label || '@test.invalid' from actors where label <> 'anon';
insert into public.staff (id, full_name) select staff_id, label from actors where label <> 'anon';
insert into public.staff_roles (staff_id, role, department_id)
select actors.staff_id, actor_roles.role, actor_roles.department_id from actor_roles join actors using (label);

insert into public.households (id, name, address, archived_at)
values
  ('e0000000-0000-4000-8000-000000000001', 'Alpha Household', '1 Test Lane', null),
  ('e0000000-0000-4000-8000-000000000002', 'Archived Household', '2 Test Lane', now());

-- Names say what the row is. Dates are relative to today so the fixture never ages.
insert into public.members (id, household_id, first_name, last_name, phone, email, date_of_birth, status, archived_at)
values
  ('f0000000-0000-4000-8000-000000000001', 'e0000000-0000-4000-8000-000000000001', 'AdultChoir', 'Matrix', '+233200000301', 'm1@example.org', '1980-01-01', 'active', null),
  ('f0000000-0000-4000-8000-000000000002', null, 'AdultNoDept', 'Matrix', '+233200000302', 'm2@example.org', '1980-01-01', 'visitor', null),
  ('f0000000-0000-4000-8000-000000000003', null, 'AdultArchived', 'Matrix', '+233200000303', null, '1980-01-01', 'transferred', now()),
  ('f0000000-0000-4000-8000-000000000004', 'e0000000-0000-4000-8000-000000000001', 'ChildKids', 'Matrix', null, null, current_date - interval '9 years', 'active', null),
  ('f0000000-0000-4000-8000-000000000005', null, 'TeenChoir', 'Matrix', null, null, current_date - interval '16 years', 'active', null),
  ('f0000000-0000-4000-8000-000000000006', null, 'NoDob', 'Matrix', '+233200000306', null, null, 'visitor', null);

insert into public.member_departments (member_id, department_id)
values
  ('f0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000001'),
  ('f0000000-0000-4000-8000-000000000004', 'c0000000-0000-4000-8000-000000000003'),
  ('f0000000-0000-4000-8000-000000000005', 'c0000000-0000-4000-8000-000000000001');

insert into public.visitor_followups (id, member_id, status, notes)
values
  ('a0000000-0000-4000-8000-000000000001', 'f0000000-0000-4000-8000-000000000002', 'pending', 'FollowAdult'),
  ('a0000000-0000-4000-8000-000000000002', 'f0000000-0000-4000-8000-000000000004', 'pending', 'FollowChild');

-- PRD row "Members & visitors": who reads which members, cell by cell.
create temp table expected_reads (label text primary key, members text not null, households int, member_departments int, followups int, member_names text not null);
insert into expected_reads
values
  ('super_admin', 'AdultArchived,AdultChoir,AdultNoDept,ChildKids,NoDob,TeenChoir', 2, 3, 2, ''),
  ('pastor', 'AdultChoir,AdultNoDept,ChildKids,NoDob,TeenChoir', 1, 3, 2, ''),
  ('treasurer', '', 0, 0, 0, 'AdultChoir,AdultNoDept'),
  ('secretary', 'AdultArchived,AdultChoir,AdultNoDept', 2, 1, 1, ''),
  ('usher', '', 0, 0, 0, 'AdultChoir,AdultNoDept'),
  ('content_editor', '', 0, 0, 0, ''),
  ('head_choir', 'AdultChoir', 0, 1, 0, ''),
  ('head_children', 'ChildKids', 0, 1, 0, ''),
  ('secretary_and_head_children', 'AdultArchived,AdultChoir,AdultNoDept,ChildKids', 2, 2, 2, ''),
  ('treasurer_and_pastor', 'AdultChoir,AdultNoDept,ChildKids,NoDob,TeenChoir', 1, 3, 2, 'AdultChoir,AdultNoDept,ChildKids,NoDob,TeenChoir');

select is(pg_temp.seen_as(label, 'public.members', 'first_name'), members, 'should show ' || label || ' exactly the members the PRD allows')
from expected_reads order by label;

select is(pg_temp.seen_as(label, 'public.member_names', 'first_name'), member_names, 'should list ' || label || ' the right names in member_names')
from expected_reads order by label;

select is(pg_temp.count_as(label, 'public.households'), households, 'should show ' || label || ' the right number of households')
from expected_reads order by label;

select is(pg_temp.count_as(label, 'public.member_departments'), member_departments, 'should show ' || label || ' the right number of department links')
from expected_reads order by label;

select is(pg_temp.count_as(label, 'public.visitor_followups'), followups, 'should show ' || label || ' the right number of follow-ups')
from expected_reads order by label;

select is(
  pg_temp.seen_as('super_admin', 'public.households', 'name') || '|' ||
  pg_temp.seen_as('pastor', 'public.households', 'name') || '|' ||
  pg_temp.seen_as('secretary', 'public.households', 'name') || '|' ||
  pg_temp.seen_as('usher', 'public.households', 'name') || '|' ||
  pg_temp.seen_as('head_choir', 'public.households', 'name'),
  'Alpha Household,Archived Household|Alpha Household|Alpha Household,Archived Household||',
  'should show households (addresses) to super admin, pastor (active) and secretary only');

select is(
  pg_temp.seen_as('super_admin', 'public.visitor_followups', 'notes') || '|' ||
  pg_temp.seen_as('secretary', 'public.visitor_followups', 'notes') || '|' ||
  pg_temp.seen_as('head_children', 'public.visitor_followups', 'notes') || '|' ||
  pg_temp.seen_as('usher', 'public.visitor_followups', 'notes'),
  'FollowAdult,FollowChild|FollowAdult||',
  'should hide the follow-up of a minor from the secretary and every follow-up from heads and ushers');

select is(
  pg_temp.seen_as('secretary', 'public.member_departments', 'department_id') || '|' || pg_temp.seen_as('head_choir', 'public.member_departments', 'department_id'),
  'c0000000-0000-4000-8000-000000000001|c0000000-0000-4000-8000-000000000001',
  'should show a choir head and the secretary only the choir link of the adult, never the minors links');

select is(pg_temp.seen_as('anon', 'public.members', 'first_name'), 'denied', 'should deny anon on members');
select is(pg_temp.seen_as('anon', 'public.member_names', 'first_name'), 'denied', 'should deny anon on member_names');
select is(pg_temp.seen_as('anon', 'public.households', 'name'), 'denied', 'should deny anon on households');
select is(pg_temp.trial('usher', 'select phone from public.member_names'), 'error 42703', 'should not expose phone numbers in member_names');

-- Write cells: E for super admin and secretary, nothing for everyone else.
create temp table write_expectations (label text, action text, statement text, expected text);
insert into write_expectations (label, action, statement, expected)
select roles.label, actions.action, actions.statement,
  case when roles.label = 'anon' then 'denied' else coalesce(actions.allowed ->> roles.label, actions.otherwise) end
from unnest(array['super_admin', 'pastor', 'treasurer', 'secretary', 'usher', 'content_editor', 'head_choir', 'head_children', 'anon']) as roles (label)
cross join (values
  ('insert adult', $$insert into public.members (first_name, last_name, date_of_birth) values ('N', 'A', '1990-01-01')$$,
    '{"super_admin": "1", "secretary": "1"}'::jsonb, 'denied'),
  ('insert child', $$insert into public.members (first_name, last_name, date_of_birth) values ('N', 'C', current_date - interval '5 years')$$,
    '{"super_admin": "1"}'::jsonb, 'denied'),
  ('edit adult', $$update public.members set last_name = 'Edited' where first_name = 'AdultChoir'$$,
    '{"super_admin": "1", "secretary": "1"}'::jsonb, '0'),
  ('edit child', $$update public.members set last_name = 'Edited' where first_name = 'ChildKids'$$,
    '{"super_admin": "1"}'::jsonb, '0'),
  ('archive adult', $$update public.members set archived_at = now() where first_name = 'AdultNoDept'$$,
    '{"super_admin": "1", "secretary": "1"}'::jsonb, '0')
) as actions (action, statement, allowed, otherwise);

select is(pg_temp.trial(label, statement), expected, format('should give %s the PRD result when trying to %s', label, action))
from write_expectations
where label <> 'anon'
order by label, action;

select is(pg_temp.trial('anon', 'update public.members set last_name = $$x$$'), 'denied', 'should deny anon an update on members');
select is(pg_temp.trial('anon', 'insert into public.households (name) values ($$x$$)'), 'denied', 'should deny anon an insert on households');

select is(pg_temp.trial(label, 'delete from public.members'), 'denied', 'should refuse every role a DELETE on members, including ' || label)
from expected_reads where label in ('super_admin', 'secretary', 'pastor');
select is(pg_temp.trial('super_admin', 'delete from public.households'), 'denied', 'should refuse a DELETE on households even for super admin');
select is(pg_temp.trial('super_admin', 'delete from public.visitor_followups'), 'denied', 'should refuse a DELETE on follow-ups even for super admin');

-- Abuse: the secretary tries to turn an adult into a hidden record, supply an id, or probe for hidden rows.
select is(pg_temp.trial('secretary', $$update public.members set date_of_birth = current_date where first_name = 'AdultChoir'$$), 'denied', 'should stop the secretary making an adult a minor');
select is(pg_temp.trial('secretary', $$update public.members set date_of_birth = null where first_name = 'AdultChoir'$$), 'denied', 'should stop the secretary clearing a date of birth');
select is(pg_temp.trial('secretary', $$insert into public.members (id, first_name, last_name, date_of_birth) values ('f0000000-0000-4000-8000-000000000004', 'a', 'b', '1990-01-01')$$), 'denied', 'should refuse a caller supplied member id');
select is(pg_temp.trial('secretary', $$update public.members set id = gen_random_uuid()$$), 'denied', 'should refuse changing a member id');
select is(pg_temp.trial('secretary', $$update public.members set created_at = now()$$), 'denied', 'should refuse changing created_at');
select is(pg_temp.trial('secretary', $$update public.members set household_id = 'e0000000-0000-4000-8000-000000000001' where first_name = 'AdultNoDept'$$), '1', 'should let the secretary move an adult into a household');

select is(
  pg_temp.trial('secretary', $$insert into public.member_departments (member_id, department_id) values ('f0000000-0000-4000-8000-000000000004', 'c0000000-0000-4000-8000-000000000001')$$),
  pg_temp.trial('secretary', $$insert into public.member_departments (member_id, department_id) values ('99999999-0000-4000-8000-000000000004', 'c0000000-0000-4000-8000-000000000001')$$),
  'should answer a link to a hidden minor exactly like a link to a missing member');
select is(
  pg_temp.trial('secretary', $$insert into public.visitor_followups (member_id) values ('f0000000-0000-4000-8000-000000000004')$$),
  pg_temp.trial('secretary', $$insert into public.visitor_followups (member_id) values ('99999999-0000-4000-8000-000000000004')$$),
  'should answer a follow-up for a hidden minor exactly like one for a missing member');

-- Error and filter side channels: policy conditions run before the caller's own conditions.
select is(pg_temp.trial('secretary', $$select 1 / (case when first_name = 'ChildKids' then 0 else 1 end) from public.members$$), '3', 'should not let the secretary trigger an error on a hidden minor row');
select is(pg_temp.trial('head_choir', $$select 1 / (case when first_name in ('ChildKids', 'TeenChoir', 'AdultNoDept') then 0 else 1 end) from public.members$$), '1', 'should not let a head trigger an error on rows outside their department');
select is(pg_temp.trial('usher', $$select 1 / (case when first_name in ('ChildKids', 'TeenChoir', 'NoDob', 'AdultArchived') then 0 else 1 end) from public.member_names$$), '2', 'should not let an usher trigger an error on rows the view filters out');
select is(pg_temp.trial('secretary', $$select first_name::int from public.members where first_name = 'TeenChoir'$$), '0', 'should not let a cast error reveal a hidden minor to the secretary');
select is(pg_temp.scalar_as('secretary', $$select count(*) from public.members where phone like '+233%'$$), '3', 'should count only visible rows when the secretary filters by phone');
select is(pg_temp.trial('secretary', $$select * from public.members where first_name = 'ChildKids' or true$$), '3', 'should keep hidden rows out when the filter has an or true');
select is(pg_temp.trial('secretary', $$select m.* from public.households h join public.members m on m.household_id = h.id$$), '1', 'should keep the minor out of a household join for the secretary');

-- member_names: shape, filter, order, limit.
select is((select count(*)::int from information_schema.columns where table_schema = 'public' and table_name = 'member_names'), 4, 'should expose exactly four columns in member_names');
select is(pg_temp.trial('usher', $$select * from public.member_names where last_name = 'Matrix' order by first_name desc limit 1 offset 1$$), '1', 'should let an usher filter, order and page member_names');
select is(pg_temp.trial('usher', $$select * from public.member_names where status = 'visitor'$$), '1', 'should let an usher filter member_names by status');
select is(pg_temp.trial('usher', $$select * from public.member_names where first_name = 'ChildKids'$$), '0', 'should not let an usher find a minor by name');
select is(pg_temp.trial('usher', $$select phone from public.member_names$$), 'error 42703', 'should reject a phone column on member_names');

-- Boundary dates, with the rule evaluated for a fixed day.
select is(private.is_minor_on('2008-10-07', '2026-10-07'), false, 'should treat a person as an adult on their 18th birthday');
select is(private.is_minor_on('2008-10-08', '2026-10-07'), true, 'should treat a person as a minor the day before their 18th birthday');
select is(private.is_minor_on('2008-10-06', '2026-10-07'), false, 'should treat a person as an adult the day after their 18th birthday');
select is(private.is_minor_on('2008-02-29', '2026-02-28'), true, 'should treat a leap day birth as a minor on 28 February');
select is(private.is_minor_on('2008-02-29', '2026-03-01'), false, 'should treat a leap day birth as an adult on 1 March');
select is(private.is_minor_on('2010-03-01', '2028-02-29'), true, 'should treat a person born 1 March as a minor on a leap day 18 years later');
select is(private.is_minor_on(null, '2026-10-07'), true, 'should treat a null date of birth as a minor');
select is(private.is_minor_on('2099-01-01', '2026-10-07'), true, 'should treat a future date of birth as a minor');
select is(private.is_minor_on('infinity', '2026-10-07'), true, 'should treat an infinite date of birth as a minor');
select is(private.is_minor_on('0001-01-01', '2026-10-07'), false, 'should treat the year 1 as an adult');

-- Time zone: the rule follows the session date, so visibility flips on that date and never earlier in the same zone.
select is(
  (select string_agg(zone || ':' || visible_today || ':' || visible_tomorrow, ',' order by zone) from (
    select zone,
      pg_temp.seen_as_in_zone('secretary', zone, 'turns18today') as visible_today,
      pg_temp.seen_as_in_zone('secretary', zone, 'turns18tomorrow') as visible_tomorrow
    from (values ('UTC'), ('Africa/Accra'), ('Pacific/Kiritimati'), ('Etc/GMT+12')) as zones (zone)
  ) as per_zone),
  'Africa/Accra:1:0,Etc/GMT+12:1:0,Pacific/Kiritimati:1:0,UTC:1:0',
  'should treat the 18th birthday as the day an adult record appears for the secretary in any session time zone');

-- GraphQL: the secretary registers, edits, archives and restores; super admin registers a child for the children's head.
select is(
  (select pg_temp.graphql_as('secretary', $$mutation { insertIntoHouseholdsCollection(objects: [{ name: "Quansah-O'Neil Household", address: "1 Fake Lane" }]) { affectedCount } }$$) #>> '{data,insertIntoHouseholdsCollection,affectedCount}'),
  '1', 'should let the secretary register a household through GraphQL');

select is(
  pg_temp.graphql_as('secretary', $$mutation { insertIntoMembersCollection(objects: [{ firstName: "Nana Adwoa", lastName: "Quansah-O'Neil", phone: "+233200000901", dateOfBirth: "1992-05-05", status: visitor }]) { affectedCount records { status } } }$$) #>> '{data,insertIntoMembersCollection,records,0,status}',
  'visitor', 'should let the secretary register an adult visitor with an apostrophe and a +233 number');

select is(
  pg_temp.graphql_as('secretary', $$mutation { insertIntoMemberDepartmentsCollection(objects: [{ memberId: "f0000000-0000-4000-8000-000000000002", departmentId: "c0000000-0000-4000-8000-000000000001" }]) { affectedCount } }$$) #>> '{data,insertIntoMemberDepartmentsCollection,affectedCount}',
  '1', 'should let the secretary link an adult to the choir through GraphQL');

select is(
  pg_temp.graphql_as('secretary', $$mutation { insertIntoVisitorFollowupsCollection(objects: [{ memberId: "f0000000-0000-4000-8000-000000000002", notes: "Call back", dueOn: "2026-10-11" }]) { records { status } } }$$) #>> '{data,insertIntoVisitorFollowupsCollection,records,0,status}',
  'pending', 'should default a new follow-up to pending');

select is(
  pg_temp.graphql_as('secretary', $$mutation { updateMembersCollection(set: { status: active, phone: "+233200000902" }, filter: { firstName: { eq: "Nana Adwoa" } }) { records { status phone } } }$$) #>> '{data,updateMembersCollection,records,0}',
  '{"phone": "+233200000902", "status": "active"}', 'should let the secretary edit the member through GraphQL');

select is(
  (select jsonb_agg(jsonb_build_array(table_name, action, changed_fields) order by id)
   from audit.log
   where table_name = 'members' and action = 'UPDATE' and new_data ->> 'first_name' = 'Nana Adwoa'
     and actor_id = (select staff_id from actors where label = 'secretary')),
  '[["members", "UPDATE", ["phone", "status"]]]'::jsonb,
  'should audit the GraphQL edit with the secretary as actor and the exact changed fields');

select is(
  pg_temp.graphql_as('secretary', $$mutation { updateMembersCollection(set: { archivedAt: "2026-10-07T10:00:00Z" }, filter: { firstName: { eq: "Nana Adwoa" } }) { affectedCount } }$$) #>> '{data,updateMembersCollection,affectedCount}',
  '1', 'should let the secretary archive a member through GraphQL');
select is(
  jsonb_array_length(pg_temp.graphql_as('usher', $$query { memberNamesCollection(filter: { firstName: { eq: "Nana Adwoa" } }) { edges { node { id } } } }$$) #> '{data,memberNamesCollection,edges}'),
  0, 'should hide an archived member from the usher view');
select is(
  jsonb_array_length(pg_temp.graphql_as('pastor', $$query { membersCollection(filter: { firstName: { eq: "Nana Adwoa" } }) { edges { node { id } } } }$$) #> '{data,membersCollection,edges}'),
  0, 'should hide an archived member from the pastor');
select is(
  pg_temp.graphql_as('secretary', $$mutation { updateMembersCollection(set: { archivedAt: null }, filter: { firstName: { eq: "Nana Adwoa" } }) { affectedCount } }$$) #>> '{data,updateMembersCollection,affectedCount}',
  '1', 'should let the secretary restore an archived member');
select is(
  jsonb_array_length(pg_temp.graphql_as('usher', $$query { memberNamesCollection(filter: { firstName: { eq: "Nana Adwoa" } }) { edges { node { id } } } }$$) #> '{data,memberNamesCollection,edges}'),
  1, 'should show a restored member to the usher again');

select isnt(
  pg_temp.graphql_as('secretary', $$mutation { insertIntoMembersCollection(objects: [{ firstName: "Kwabena", lastName: "Quansah-O'Neil", dateOfBirth: "2019-01-02" }]) { affectedCount } }$$) -> 'errors',
  null, 'should refuse the secretary a child record through GraphQL');
select is(
  pg_temp.graphql_as('super_admin', $$mutation { insertIntoMembersCollection(objects: [{ firstName: "Kwabena", lastName: "Quansah-O'Neil", dateOfBirth: "2019-01-02", status: active }]) { affectedCount } }$$) #>> '{data,insertIntoMembersCollection,affectedCount}',
  '1', 'should let super admin register a child through GraphQL');

select pg_temp.graphql_as('super_admin', $$mutation { insertIntoMemberDepartmentsCollection(objects: [{ memberId: "f0000000-0000-4000-8000-000000000004", departmentId: "c0000000-0000-4000-8000-000000000003" }]) { affectedCount } }$$);

select is(
  pg_temp.graphql_as('head_children', $$query { membersCollection(filter: { lastName: { eq: "Quansah-O'Neil" } }) { edges { node { firstName } } } }$$) #>> '{data,membersCollection,edges}',
  '[]', 'should not show the children ministry head a child who is not linked to the children ministry');

select is(
  (select jsonb_agg(edge #>> '{node,firstName}' order by edge #>> '{node,firstName}')
   from jsonb_array_elements(pg_temp.graphql_as('head_children', $$query { membersCollection { edges { node { firstName } } } }$$) #> '{data,membersCollection,edges}') as edge),
  '["ChildKids"]'::jsonb, 'should show the children ministry head only the children of that ministry through GraphQL');
select is(
  (select jsonb_agg(edge #>> '{node,firstName}' order by edge #>> '{node,firstName}')
   from jsonb_array_elements(pg_temp.graphql_as('head_choir', $$query { membersCollection { edges { node { firstName } } } }$$) #> '{data,membersCollection,edges}') as edge),
  '["AdultChoir", "AdultNoDept"]'::jsonb, 'should show the choir head only the adults linked to the choir through GraphQL');

select is(
  pg_temp.graphql_as('secretary', $$query { householdsCollection(filter: { name: { eq: "Alpha Household" } }) { edges { node { membersCollection { edges { node { firstName } } } } } } }$$) #>> '{data,householdsCollection,edges,0,node,membersCollection,edges}',
  '[{"node": {"firstName": "AdultChoir"}}]', 'should leave the minor out of a nested household to members query for the secretary');
select is(
  pg_temp.sorted_values(pg_temp.graphql_as('secretary', $$query { memberDepartmentsCollection { edges { node { member { firstName } } } } }$$) #> '{data,memberDepartmentsCollection,edges}', '{node,member,firstName}'),
  '["AdultChoir", "AdultNoDept"]'::jsonb,
  'should leave minors out of memberDepartmentsCollection for the secretary');
select is(
  pg_temp.sorted_values(pg_temp.graphql_as('secretary', $$query { visitorFollowupsCollection { edges { node { notes member { firstName } } } } }$$) #> '{data,visitorFollowupsCollection,edges}', '{node,notes}'),
  '["Call back", "FollowAdult"]'::jsonb,
  'should leave the follow-up of a minor out of visitorFollowupsCollection for the secretary');

select is(
  pg_temp.graphql_as('secretary', format($$query { node(nodeId: "%s") { __typename } }$$, replace(encode(convert_to('["public","members","f0000000-0000-4000-8000-000000000004"]', 'utf8'), 'base64'), E'\n', ''))) #>> '{data,node}',
  null, 'should return nothing when the secretary asks for a minor by node id');
select is(
  pg_temp.graphql_as('pastor', format($$query { node(nodeId: "%s") { __typename } }$$, replace(encode(convert_to('["public","members","f0000000-0000-4000-8000-000000000004"]', 'utf8'), 'base64'), E'\n', ''))) #>> '{data,node,__typename}',
  'Members', 'should return the minor by node id to the pastor');

select is(
  pg_temp.graphql_as('anon', $$query { membersCollection { edges { node { id } } } }$$) -> 'errors' is not null,
  true, 'should return an error to anon on membersCollection');

select * from finish();

rollback;
