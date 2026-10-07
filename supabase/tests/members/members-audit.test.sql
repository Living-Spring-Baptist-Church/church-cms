-- LBC-26 (AC 6): the audit trigger records inserts, updates, archives and department link removals on members,
-- households, member_departments and visitor_followups with the right actor, old and new data and
-- changed_fields, and refused statements leave no row. The rows that must show updated_at changing are created
-- with updated_at in the past, because now() is constant inside one transaction.

begin;

select plan(41);

-- Fixture: start from an empty congregation and identity model so the demo seed cannot influence the results.
set local session_replication_role = replica;
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

-- One active actor per role, department heads of each department, two staff holding two roles, staff with no
-- role, an inactive staff member for most roles, and anon.
insert into actors (label)
values
  ('super_admin'), ('pastor'), ('treasurer'), ('secretary'), ('usher'), ('content_editor'),
  ('head_choir'), ('head_youth'), ('head_children'),
  ('head_choir_and_children'), ('usher_and_pastor'), ('usher_and_head_children'), ('no_role');

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
where label in ('super_admin', 'pastor', 'treasurer', 'secretary', 'usher', 'content_editor', 'head_choir', 'head_children');

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
select staff_id, label, is_active from actors where label <> 'anon';

insert into public.staff_roles (staff_id, role, department_id)
select actors.staff_id, actor_roles.role, actor_roles.department_id
from actor_roles
join actors using (label);

-- Households: 30...01 and 30...02 active, 30...03 archived.
insert into public.households (id, name, address, archived_at)
values
  ('30000000-0000-4000-8000-000000000001', 'Alpha Household', '1 Test Lane', null),
  ('30000000-0000-4000-8000-000000000002', 'Beta Household', '2 Test Lane', null),
  ('30000000-0000-4000-8000-000000000003', 'Gamma Household', '3 Test Lane', now());

-- Members, keyed by first name (60...01 to 60...09). Ten years old is a minor, 1980 an adult.
insert into public.members (id, household_id, first_name, last_name, phone, email, date_of_birth, status, archived_at)
values
  ('60000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 'AdultChoir', 'Test', '+233200000201', 'a1@example.org', '1980-01-01', 'active', null),
  ('60000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', 'AdultYouth', 'Test', '+233200000202', 'a2@example.org', '1980-01-01', 'active', null),
  ('60000000-0000-4000-8000-000000000003', null, 'AdultNone', 'Test', '+233200000203', 'a3@example.org', '1980-01-01', 'visitor', null),
  ('60000000-0000-4000-8000-000000000004', null, 'AdultArchived', 'Test', '+233200000204', 'a4@example.org', '1980-01-01', 'transferred', now()),
  ('60000000-0000-4000-8000-000000000005', '30000000-0000-4000-8000-000000000002', 'MinorChildren', 'Test', null, null, current_date - interval '10 years', 'active', null),
  ('60000000-0000-4000-8000-000000000006', '30000000-0000-4000-8000-000000000002', 'MinorChoir', 'Test', null, null, current_date - interval '10 years', 'active', null),
  ('60000000-0000-4000-8000-000000000007', null, 'MinorArchived', 'Test', null, null, current_date - interval '10 years', 'inactive', now()),
  ('60000000-0000-4000-8000-000000000008', null, 'UnknownDob', 'Test', '+233200000208', null, null, 'visitor', null),
  ('60000000-0000-4000-8000-000000000009', null, 'AdultBoth', 'Test', '+233200000209', 'a9@example.org', '1980-01-01', 'active', null);

insert into public.member_departments (member_id, department_id)
values
  ('60000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000002'),
  ('60000000-0000-4000-8000-000000000004', '40000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000005', '40000000-0000-4000-8000-000000000003'),
  ('60000000-0000-4000-8000-000000000006', '40000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000007', '40000000-0000-4000-8000-000000000003'),
  ('60000000-0000-4000-8000-000000000008', '40000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000009', '40000000-0000-4000-8000-000000000001'),
  ('60000000-0000-4000-8000-000000000009', '40000000-0000-4000-8000-000000000002');

-- Follow-ups, keyed by notes: on an adult visitor, on a minor, on an archived adult.
insert into public.visitor_followups (id, member_id, assigned_to, status, notes)
select ids.id, ids.member_id, (select staff_id from actors where label = 'secretary'), 'pending', ids.notes
from (values
  ('70000000-0000-4000-8000-000000000001'::uuid, '60000000-0000-4000-8000-000000000003'::uuid, 'FollowAdult'),
  ('70000000-0000-4000-8000-000000000002'::uuid, '60000000-0000-4000-8000-000000000005'::uuid, 'FollowMinor'),
  ('70000000-0000-4000-8000-000000000003'::uuid, '60000000-0000-4000-8000-000000000004'::uuid, 'FollowArchived')
) as ids (id, member_id, notes);

-- Who may see which members: first names, sorted. Everyone not listed sees none.
create temp table expected_members (label text primary key, seen text not null);
insert into expected_members
values
  ('super_admin', 'AdultArchived,AdultBoth,AdultChoir,AdultNone,AdultYouth,MinorArchived,MinorChildren,MinorChoir,UnknownDob'),
  ('pastor', 'AdultBoth,AdultChoir,AdultNone,AdultYouth,MinorChildren,MinorChoir,UnknownDob'),
  ('usher_and_pastor', 'AdultBoth,AdultChoir,AdultNone,AdultYouth,MinorChildren,MinorChoir,UnknownDob'),
  ('secretary', 'AdultArchived,AdultBoth,AdultChoir,AdultNone,AdultYouth'),
  ('head_choir', 'AdultBoth,AdultChoir'),
  ('head_youth', 'AdultBoth,AdultYouth'),
  ('head_children', 'MinorChildren'),
  ('usher_and_head_children', 'MinorChildren'),
  ('head_choir_and_children', 'AdultBoth,AdultChoir,MinorChildren');

create function pg_temp.entries_for(p_record_id uuid, p_action text)
returns bigint
language sql
stable
as $$
  select count(*) from audit.log where record_id = p_record_id and action = p_action;
$$;

create function pg_temp.entry_field(p_record_id uuid, p_action text, p_column text)
returns text
language sql
stable
as $$
  select to_jsonb(entry) ->> p_column
  from audit.log as entry
  where entry.record_id = p_record_id and entry.action = p_action
  order by entry.id desc
  limit 1;
$$;

-- Rows with updated_at in the past, so the updated_at trigger shows up in changed_fields inside this transaction.
insert into public.members (id, first_name, last_name, date_of_birth, status, created_at, updated_at)
values
  ('61000000-0000-4000-8000-000000000002', 'AuditPhone', 'Test', '1980-01-01', 'active', '2020-01-01', '2020-01-01'),
  ('61000000-0000-4000-8000-000000000003', 'AuditArchive', 'Test', '1980-01-01', 'active', '2020-01-01', '2020-01-01'),
  ('61000000-0000-4000-8000-000000000004', 'AuditStatus', 'Test', '1980-01-01', 'visitor', '2020-01-01', '2020-01-01');
insert into public.households (id, name, created_at, updated_at)
values ('31000000-0000-4000-8000-000000000009', 'AuditHouse', '2020-01-01', '2020-01-01');
insert into public.visitor_followups (id, member_id, created_at, updated_at)
values ('71000000-0000-4000-8000-000000000009', '61000000-0000-4000-8000-000000000004', '2020-01-01', '2020-01-01');
insert into public.member_departments (id, member_id, department_id)
values ('80000000-0000-4000-8000-000000000001', '61000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000001');

-- Direct database access (the seed, jobs) is recorded with no actor

select is(pg_temp.entries_for('61000000-0000-4000-8000-000000000002', 'INSERT'), 1::bigint, 'should record an insert made by the database owner');
select is(pg_temp.entry_field('61000000-0000-4000-8000-000000000002', 'INSERT', 'actor_id'), null, 'should record no actor for direct database access');
select is(pg_temp.entry_field('61000000-0000-4000-8000-000000000002', 'INSERT', 'table_name'), 'members', 'should record the table name');
select is(pg_temp.entries_for('80000000-0000-4000-8000-000000000001', 'INSERT'), 1::bigint, 'should record a department link under its surrogate id');
select is(pg_temp.entry_field('80000000-0000-4000-8000-000000000001', 'INSERT', 'table_name'), 'member_departments', 'should record the department link under its own table name');

-- members, as the secretary and the super admin

select is(pg_temp.run_as('secretary', $$insert into public.members (first_name, last_name, date_of_birth, status) values ('AuditNew', 'Test', '1990-01-01', 'active')$$), 1::bigint, 'should let the secretary create a member');
select is(pg_temp.entries_for((select id from public.members where first_name = 'AuditNew'), 'INSERT'), 1::bigint, 'should record a member insert made through the API');
select is(pg_temp.entry_field((select id from public.members where first_name = 'AuditNew'), 'INSERT', 'actor_id'), (select staff_id::text from actors where label = 'secretary'), 'should record the secretary as the actor of a member insert');
select is(pg_temp.entry_field((select id from public.members where first_name = 'AuditNew'), 'INSERT', 'changed_fields'), null, 'should record no changed_fields for an insert');
select is((select new_data ->> 'first_name' from audit.log where record_id = (select id from public.members where first_name = 'AuditNew') and action = 'INSERT'), 'AuditNew', 'should keep the new row in new_data');

select is(pg_temp.run_as('secretary', $$update public.members set phone = '+233200000301' where first_name = 'AuditPhone'$$), 1::bigint, 'should let the secretary update a phone number');
select is(pg_temp.entry_field('61000000-0000-4000-8000-000000000002', 'UPDATE', 'changed_fields'), '["phone", "updated_at"]', 'should list phone and updated_at as the changed fields');
select is(pg_temp.entry_field('61000000-0000-4000-8000-000000000002', 'UPDATE', 'actor_id'), (select staff_id::text from actors where label = 'secretary'), 'should record the secretary as the actor of an update');
select is((select old_data ->> 'phone' from audit.log where record_id = '61000000-0000-4000-8000-000000000002' and action = 'UPDATE'), null, 'should keep the old phone in old_data');
select is((select new_data ->> 'phone' from audit.log where record_id = '61000000-0000-4000-8000-000000000002' and action = 'UPDATE'), '+233200000301', 'should keep the new phone in new_data');

select is(pg_temp.run_as('secretary', $$update public.members set archived_at = now() where first_name = 'AuditArchive'$$), 1::bigint, 'should let the secretary archive a member');
select is(pg_temp.entry_field('61000000-0000-4000-8000-000000000003', 'UPDATE', 'changed_fields'), '["archived_at", "updated_at"]', 'should record archiving as an UPDATE of archived_at');
select is(pg_temp.entries_for('61000000-0000-4000-8000-000000000003', 'DELETE'), 0::bigint, 'should record no DELETE when a member is archived');

select is(pg_temp.run_as('super_admin', $$update public.members set status = 'active' where first_name = 'AuditStatus'$$), 1::bigint, 'should let the super admin change a visitor to a member');
select is(pg_temp.entry_field('61000000-0000-4000-8000-000000000004', 'UPDATE', 'changed_fields'), '["status", "updated_at"]', 'should record a status change');
select is(pg_temp.entry_field('61000000-0000-4000-8000-000000000004', 'UPDATE', 'actor_id'), (select staff_id::text from actors where label = 'super_admin'), 'should record the super admin as the actor of a status change');

-- households

select is(pg_temp.run_as('secretary', $$insert into public.households (name) values ('AuditNewHouse')$$), 1::bigint, 'should let the secretary create a household');
select is(pg_temp.entries_for((select id from public.households where name = 'AuditNewHouse'), 'INSERT'), 1::bigint, 'should record a household insert');
select is(pg_temp.run_as('secretary', $$update public.households set archived_at = now() where name = 'AuditHouse'$$), 1::bigint, 'should let the secretary archive a household');
select is(pg_temp.entry_field('31000000-0000-4000-8000-000000000009', 'UPDATE', 'changed_fields'), '["archived_at", "updated_at"]', 'should record archiving a household as an UPDATE');
select is(pg_temp.entry_field('31000000-0000-4000-8000-000000000009', 'UPDATE', 'actor_id'), (select staff_id::text from actors where label = 'secretary'), 'should record the secretary as the actor for a household');

-- member_departments

select is(pg_temp.run_as('secretary', $$insert into public.member_departments (member_id, department_id) values ('61000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000002')$$), 1::bigint, 'should let the secretary add a department link');
select is(
  pg_temp.entries_for((select id from public.member_departments where member_id = '61000000-0000-4000-8000-000000000002' and department_id = '40000000-0000-4000-8000-000000000002'), 'INSERT'),
  1::bigint,
  'should record a department link insert'
);
select is(pg_temp.run_as('secretary', $$delete from public.member_departments where id = '80000000-0000-4000-8000-000000000001'$$), 1::bigint, 'should let the secretary remove a department link');
select is(pg_temp.entries_for('80000000-0000-4000-8000-000000000001', 'DELETE'), 1::bigint, 'should record a department link removal as a DELETE');
select is((select old_data ->> 'member_id' from audit.log where record_id = '80000000-0000-4000-8000-000000000001' and action = 'DELETE'), '61000000-0000-4000-8000-000000000002', 'should keep the removed link in old_data');
select is(pg_temp.entry_field('80000000-0000-4000-8000-000000000001', 'DELETE', 'actor_id'), (select staff_id::text from actors where label = 'secretary'), 'should record the secretary as the actor of a link removal');

-- visitor_followups

select is(pg_temp.run_as('secretary', $$insert into public.visitor_followups (member_id, notes) values ('61000000-0000-4000-8000-000000000004', 'AuditNewFollow')$$), 1::bigint, 'should let the secretary create a follow-up');
select is(pg_temp.entries_for((select id from public.visitor_followups where notes = 'AuditNewFollow'), 'INSERT'), 1::bigint, 'should record a follow-up insert');
select is(pg_temp.run_as('secretary', $$update public.visitor_followups set status = 'contacted' where id = '71000000-0000-4000-8000-000000000009'$$), 1::bigint, 'should let the secretary move a follow-up on');
select is(pg_temp.entry_field('71000000-0000-4000-8000-000000000009', 'UPDATE', 'changed_fields'), '["status", "updated_at"]', 'should record a follow-up status change');

-- Nothing is logged when nothing changes or the statement is refused

create temp table audit_before as select count(*) as entries from audit.log;

select throws_ok(pg_temp.attempt('usher', $$insert into public.members (first_name, last_name, date_of_birth) values ('Refused', 'Test', '1990-01-01')$$), '42501', null, 'should refuse a member insert by the usher');
select is(pg_temp.run_as('usher', $$update public.members set phone = 'x'$$), 0::bigint, 'should update no member rows for the usher');
select is(pg_temp.run_as('head_choir', $$update public.members set phone = 'x'$$), 0::bigint, 'should update no member rows for a department head');
select throws_ok(pg_temp.attempt('super_admin', 'delete from public.members'), '42501', null, 'should refuse deleting members even for the super admin');

select is((select count(*) from audit.log), (select entries from audit_before), 'should add no audit rows for refused or empty statements');

select * from finish();

rollback;
