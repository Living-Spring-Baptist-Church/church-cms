-- LBC-26 (AC 3, 7): row level security on member_departments and visitor_followups for every role. Both follow
-- the visibility of their member, so a secretary never sees a minor's department or follow-up, and a department
-- head sees only the links of the departments they head. Fixture and actors: see the preamble.

begin;

select plan(149);

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

-- member_departments: a row is visible only together with its member, and a department head sees only the
-- rows of the departments they head. Fixture: 9 rows, see the preamble.

create temp table expected_links (label text primary key, row_count bigint not null);
insert into expected_links
values
  ('super_admin', 9), ('pastor', 7), ('usher_and_pastor', 7), ('secretary', 5),
  ('head_choir', 2), ('head_youth', 2), ('head_children', 1), ('usher_and_head_children', 1),
  ('head_choir_and_children', 3);

select is(
  pg_temp.run_as(actors.label, 'select * from public.member_departments'),
  coalesce((select row_count from expected_links where expected_links.label = actors.label), 0),
  format('should show %s only the department links they may see', actors.label)
) from actors where label <> 'anon' order by label;

select throws_ok(pg_temp.attempt('anon', 'select * from public.member_departments'), '42501', null, 'should deny anon reading member_departments');

select is(
  pg_temp.run_as('head_choir', $$select * from public.member_departments where department_id = '40000000-0000-4000-8000-000000000002'$$),
  0::bigint,
  'should not show a department head the other departments of a member they can see'
);

select is(
  pg_temp.run_as('secretary', $$select * from public.member_departments where member_id = '60000000-0000-4000-8000-000000000005'$$),
  0::bigint,
  'should not show the secretary the department of a minor'
);

-- inserts

select is(
  pg_temp.run_as(label, $$insert into public.member_departments (member_id, department_id) values ('60000000-0000-4000-8000-000000000003', '40000000-0000-4000-8000-000000000001')$$),
  1::bigint,
  format('should let %s add a member to a department', label)
) from actors where label = 'super_admin'
union all
select is(
  pg_temp.run_as(label, $$insert into public.member_departments (member_id, department_id) values ('60000000-0000-4000-8000-000000000003', '40000000-0000-4000-8000-000000000002')$$),
  1::bigint,
  format('should let %s add a member to a department', label)
) from actors where label = 'secretary';

select throws_ok(
  pg_temp.attempt(label, $$insert into public.member_departments (member_id, department_id) values ('60000000-0000-4000-8000-000000000002', '40000000-0000-4000-8000-000000000001')$$),
  '42501', null,
  format('should reject %s adding a member to a department', label)
) from actors where label not in ('super_admin', 'secretary') order by label;

select throws_ok(
  pg_temp.attempt('secretary', $$insert into public.member_departments (member_id, department_id) values ('60000000-0000-4000-8000-000000000006', '40000000-0000-4000-8000-000000000002')$$),
  '42501', null,
  'should reject the secretary adding a minor to a department'
);

select throws_ok(
  pg_temp.attempt('secretary', $$insert into public.member_departments (member_id, department_id) values (gen_random_uuid(), '40000000-0000-4000-8000-000000000002')$$),
  '42501', null,
  'should answer the same for an unknown member as for a minor, so ids cannot be probed'
);

select is(
  pg_temp.run_as('super_admin', $$insert into public.member_departments (member_id, department_id) values ('60000000-0000-4000-8000-000000000006', '40000000-0000-4000-8000-000000000002')$$),
  1::bigint,
  'should let the super admin add a minor to a department'
);

select throws_ok(
  pg_temp.attempt('super_admin', $$insert into public.member_departments (member_id, department_id) values ('60000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001')$$),
  '23505', null,
  'should reject adding the same member to the same department twice'
);

select throws_ok(
  pg_temp.attempt('super_admin', $$update public.member_departments set department_id = '40000000-0000-4000-8000-000000000002'$$),
  '42501', null,
  'should not let anyone update a department link'
);

-- deletes: the link can be removed by super admin and secretary, for members they can see

select is(pg_temp.run_as('super_admin', $$delete from public.member_departments where member_id = '60000000-0000-4000-8000-000000000002'$$), 1::bigint, 'should let the super admin remove a department link');
select is(pg_temp.run_as('secretary', $$delete from public.member_departments where member_id = '60000000-0000-4000-8000-000000000009' and department_id = '40000000-0000-4000-8000-000000000002'$$), 1::bigint, 'should let the secretary remove a department link of an adult');
select is(pg_temp.run_as('secretary', $$delete from public.member_departments where member_id = '60000000-0000-4000-8000-000000000005'$$), 0::bigint, 'should not let the secretary remove the department link of a minor');

select is(
  pg_temp.run_as(label, $$delete from public.member_departments where member_id = '60000000-0000-4000-8000-000000000001'$$),
  0::bigint,
  format('should not let %s remove a department link', label)
) from actors where label not in ('super_admin', 'secretary', 'anon') order by label;

select throws_ok(pg_temp.attempt('anon', 'delete from public.member_departments'), '42501', null, 'should deny anon deleting department links');

-- visitor_followups: follow the visibility of the member

select is(
  pg_temp.seen_as(label, 'public.visitor_followups', 'notes'),
  case when label = 'super_admin' then 'FollowAdult,FollowArchived,FollowMinor'
       when label in ('pastor', 'usher_and_pastor') then 'FollowAdult,FollowMinor'
       when label = 'secretary' then 'FollowAdult,FollowArchived'
       else '' end,
  format('should show %s only the follow-ups they may see', label)
) from actors where label <> 'anon' order by label;

select throws_ok(pg_temp.attempt('anon', 'select * from public.visitor_followups'), '42501', null, 'should deny anon reading visitor_followups');

select is(
  pg_temp.run_as(label, $$insert into public.visitor_followups (member_id, assigned_to, notes, due_on) values ('60000000-0000-4000-8000-000000000003', null, 'NewFollow', current_date)$$),
  1::bigint,
  format('should let %s create a follow-up for an adult', label)
) from actors where label in ('super_admin', 'secretary') order by label;

select throws_ok(
  pg_temp.attempt(label, $$insert into public.visitor_followups (member_id, notes) values ('60000000-0000-4000-8000-000000000003', 'NewFollow')$$),
  '42501', null,
  format('should reject %s creating a follow-up', label)
) from actors where label not in ('super_admin', 'secretary') order by label;

select throws_ok(
  pg_temp.attempt('secretary', $$insert into public.visitor_followups (member_id, notes) values ('60000000-0000-4000-8000-000000000005', 'MinorFollow')$$),
  '42501', null,
  'should reject the secretary creating a follow-up for a minor'
);

select is(
  pg_temp.run_as('super_admin', $$insert into public.visitor_followups (member_id, notes) values ('60000000-0000-4000-8000-000000000005', 'MinorFollow')$$),
  1::bigint,
  'should let the super admin create a follow-up for a minor'
);

select throws_ok(
  pg_temp.attempt('super_admin', $$insert into public.visitor_followups (member_id, status) values ('60000000-0000-4000-8000-000000000003', 'wizard')$$),
  '23514', null,
  'should reject a follow-up status other than pending, contacted or done'
);

select is(
  (select status from public.visitor_followups where notes = 'NewFollow' limit 1),
  'pending',
  'should default a new follow-up to pending'
);

select is(
  pg_temp.run_as(label, $$update public.visitor_followups set status = 'contacted' where notes = 'FollowAdult'$$),
  case when label in ('super_admin', 'secretary') then 1 else 0 end::bigint,
  format('should let %s move a follow-up on only if super admin or secretary', label)
) from actors where label <> 'anon' order by label;

select throws_ok(pg_temp.attempt('anon', $$update public.visitor_followups set status = 'done'$$), '42501', null, 'should deny anon updating follow-ups');

select is(pg_temp.run_as('secretary', $$update public.visitor_followups set status = 'done' where notes = 'FollowMinor'$$), 0::bigint, 'should not let the secretary update the follow-up of a minor');
select is(pg_temp.run_as('super_admin', $$update public.visitor_followups set status = 'done' where notes = 'FollowMinor'$$), 1::bigint, 'should let the super admin update the follow-up of a minor');
select is(pg_temp.run_as('secretary', $$update public.visitor_followups set status = 'done' where notes = 'FollowArchived'$$), 1::bigint, 'should let the secretary update the follow-up of an archived adult');
select throws_ok(pg_temp.attempt('super_admin', $$update public.visitor_followups set status = 'wizard' where notes = 'FollowAdult'$$), '23514', null, 'should reject moving a follow-up to an unknown status');
select throws_ok(pg_temp.attempt('super_admin', $$update public.visitor_followups set member_id = '60000000-0000-4000-8000-000000000001' where notes = 'FollowAdult'$$), '42501', null, 'should not let anyone move a follow-up to another visitor');

select * from finish();

rollback;
