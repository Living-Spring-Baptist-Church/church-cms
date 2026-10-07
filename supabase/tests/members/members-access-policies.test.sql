-- LBC-26 (AC 2, 3, 5, 7): row level security on members and households, exercised as every role, as staff
-- holding two roles, as active staff with no role, as inactive staff and as anon. Minors, unknown birth dates and
-- archived rows are tested against each reader, and nobody can DELETE (archiving is an UPDATE).
-- Every actor runs through pg_temp.run_as(), which switches to the real database role with the JWT claims set,
-- so RLS and grants are exercised (never the table owner). The demo seed is cleared first.

begin;

select plan(303);

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

-- members: reads. Expected names come from expected_members; everyone not listed sees none.

select is(
  pg_temp.seen_as(actors.label, 'public.members', 'first_name'),
  coalesce((select seen from expected_members where expected_members.label = actors.label), ''),
  format('should show %s only the members they may see', actors.label)
) from actors where label <> 'anon' order by label;

select is(
  pg_temp.seen_as(label, 'public.members', 'phone'),
  case when label in ('super_admin', 'pastor', 'usher_and_pastor') then '+233200000201,+233200000202,+233200000203,+233200000208,+233200000209'
       when label = 'secretary' then '+233200000201,+233200000202,+233200000203,+233200000204,+233200000209'
       when label in ('head_choir', 'head_choir_and_children') then '+233200000201,+233200000209'
       when label = 'head_youth' then '+233200000202,+233200000209'
       else '' end,
  format('should show %s only the phone numbers of the members they may see', label)
) from actors where label in ('usher', 'treasurer', 'content_editor', 'no_role', 'inactive_usher', 'secretary', 'head_choir', 'head_youth')
order by label;

select is(
  pg_temp.seen_as('super_admin', 'public.members', 'phone') is not null and pg_temp.seen_as('super_admin', 'public.members', 'phone') <> '',
  true,
  'should let the super admin read phone numbers'
);

select throws_ok(pg_temp.attempt('anon', 'select * from public.members'), '42501', null, 'should deny anon reading members');
select throws_ok(pg_temp.attempt('anon', 'select * from public.households'), '42501', null, 'should deny anon reading households');
select throws_ok(pg_temp.attempt('anon', $$select phone from public.members where id = '60000000-0000-4000-8000-000000000001'$$), '42501', null, 'should deny anon reading one member by id');

-- IDOR: reading a member by id gives the same answer as listing, never more

select is(pg_temp.run_as(caller, format('select * from public.members where id = %L', member_id)), expected::bigint, format('should show %s %s: %s', caller, member_id, expected))
from (values
  ('head_choir', '60000000-0000-4000-8000-000000000002', 0),
  ('head_choir', '60000000-0000-4000-8000-000000000006', 0),
  ('head_choir', '60000000-0000-4000-8000-000000000004', 0),
  ('head_choir', '60000000-0000-4000-8000-000000000008', 0),
  ('head_choir', '60000000-0000-4000-8000-000000000009', 1),
  ('head_youth', '60000000-0000-4000-8000-000000000006', 0),
  ('head_children', '60000000-0000-4000-8000-000000000006', 0),
  ('head_children', '60000000-0000-4000-8000-000000000001', 0),
  ('head_children', '60000000-0000-4000-8000-000000000005', 1),
  ('head_children', '60000000-0000-4000-8000-000000000007', 0),
  ('head_choir_and_children', '60000000-0000-4000-8000-000000000006', 0),
  ('head_choir_and_children', '60000000-0000-4000-8000-000000000005', 1),
  ('usher', '60000000-0000-4000-8000-000000000001', 0),
  ('secretary', '60000000-0000-4000-8000-000000000005', 0),
  ('secretary', '60000000-0000-4000-8000-000000000008', 0),
  ('pastor', '60000000-0000-4000-8000-000000000004', 0),
  ('pastor', '60000000-0000-4000-8000-000000000005', 1)
) as probes (caller, member_id, expected);

-- members: inserts. Only super admin and secretary write, and the secretary only adults with a known birth date.

select is(
  pg_temp.run_as(label, $$insert into public.members (first_name, last_name, date_of_birth, status) values ('NewAdult', 'Test', '1990-01-01', 'active')$$),
  1::bigint,
  format('should let %s create an adult member', label)
) from actors where label in ('super_admin', 'secretary') order by label;

select throws_ok(
  pg_temp.attempt(label, $$insert into public.members (first_name, last_name, date_of_birth, status) values ('NewAdult', 'Test', '1990-01-01', 'active')$$),
  '42501', null,
  format('should reject %s creating a member', label)
) from actors where label not in ('super_admin', 'secretary') order by label;

select is(
  pg_temp.run_as('super_admin', format($$insert into public.members (first_name, last_name, date_of_birth) values ('NewMinor', 'Test', %L)$$, current_date - interval '9 years')),
  1::bigint,
  'should let the super admin create a minor'
);

select is(
  pg_temp.run_as('super_admin', $$insert into public.members (first_name, last_name) values ('NewUnknown', 'Test')$$),
  1::bigint,
  'should let the super admin create a member with no date of birth'
);

select throws_ok(
  pg_temp.attempt(label, format($$insert into public.members (first_name, last_name, date_of_birth) values ('NewMinor', 'Test', %L)$$, current_date - interval '9 years')),
  '42501', null,
  format('should reject %s creating a minor', label)
) from actors where label <> 'super_admin' order by label;

select throws_ok(
  pg_temp.attempt('secretary', $$insert into public.members (first_name, last_name) values ('NewUnknown', 'Test')$$),
  '42501', null,
  'should reject the secretary creating a member with no date of birth'
);

select throws_ok(
  pg_temp.attempt('secretary', format($$insert into public.members (first_name, last_name, date_of_birth) values ('TurnsEighteenTomorrow', 'Test', %L)$$, current_date - interval '18 years' + interval '1 day')),
  '42501', null,
  'should reject the secretary creating a person who turns 18 tomorrow'
);

select is(
  pg_temp.run_as('secretary', format($$insert into public.members (first_name, last_name, date_of_birth) values ('TurnedEighteenToday', 'Test', %L)$$, current_date - interval '18 years')),
  1::bigint,
  'should let the secretary create a person who turns 18 today'
);

select throws_ok(
  pg_temp.attempt('super_admin', $$insert into public.members (first_name, last_name, archived_at) values ('Arch', 'Test', now())$$),
  '42501', null,
  'should not let anyone set archived_at on insert'
);

select throws_ok(
  pg_temp.attempt('super_admin', $$insert into public.members (id, first_name, last_name, date_of_birth) values (gen_random_uuid(), 'Own', 'Id', '1990-01-01')$$),
  '42501', null,
  'should not let anyone choose the id of a new member'
);

-- members: updates

select is(
  pg_temp.run_as(label, $$update public.members set phone = '+233200000999' where first_name = 'AdultChoir'$$),
  case when label in ('super_admin', 'secretary') then 1 else 0 end::bigint,
  format('should let %s update an adult only if they are super admin or secretary', label)
) from actors where label <> 'anon' order by label;

select throws_ok(pg_temp.attempt('anon', $$update public.members set phone = '+233200000999'$$), '42501', null, 'should deny anon updating members');

select is(
  pg_temp.run_as(label, $$update public.members set phone = '+233200000998' where first_name = 'MinorChildren'$$),
  case when label = 'super_admin' then 1 else 0 end::bigint,
  format('should let %s update a minor only if super admin', label)
) from actors where label <> 'anon' order by label;

select throws_ok(
  pg_temp.attempt('secretary', $$update public.members set date_of_birth = current_date where first_name = 'AdultNone'$$),
  '42501', null,
  'should reject the secretary turning an adult into a minor'
);

select throws_ok(
  pg_temp.attempt('secretary', $$update public.members set date_of_birth = null where first_name = 'AdultNone'$$),
  '42501', null,
  'should reject the secretary clearing a date of birth, which would hide the record from her'
);

select is(
  (select date_of_birth from public.members where first_name = 'AdultNone'),
  '1980-01-01'::date,
  'should leave the date of birth unchanged after the rejected updates'
);

select is(
  pg_temp.run_as('super_admin', $$update public.members set date_of_birth = current_date where first_name = 'UnknownDob'$$),
  1::bigint,
  'should let the super admin set a date of birth'
);

select is(
  pg_temp.run_as('secretary', $$update public.members set phone = '+233200000997' where first_name = 'UnknownDob'$$),
  0::bigint,
  'should keep the secretary away from a record whose date of birth makes it a minor'
);

select is(
  pg_temp.run_as('secretary', $$update public.members set status = 'active' where first_name = 'AdultNone'$$),
  1::bigint,
  'should let the secretary change a visitor to an active member'
);

select is(
  pg_temp.run_as('head_youth', $$update public.members set status = 'inactive' where first_name = 'AdultYouth'$$),
  0::bigint,
  'should not let a department head change a member of their own department'
);

select throws_ok(pg_temp.attempt('super_admin', $$update public.members set id = gen_random_uuid() where first_name = 'AdultNone'$$), '42501', null, 'should not let anyone change a member id');
select throws_ok(pg_temp.attempt('super_admin', $$update public.members set created_at = now() where first_name = 'AdultNone'$$), '42501', null, 'should not let anyone change created_at');
select throws_ok(pg_temp.attempt('super_admin', $$update public.members set updated_at = now() where first_name = 'AdultNone'$$), '42501', null, 'should not let anyone set updated_at directly');
select throws_ok(pg_temp.attempt('super_admin', $$update public.members set status = 'wizard' where first_name = 'AdultNone'$$), '22P02', null, 'should reject a status that is not in member_status');

-- Archive: an UPDATE of archived_at that hides the member from the people who read non-archived rows only

select is(
  pg_temp.run_as('secretary', $$update public.members set archived_at = now() where first_name = 'AdultChoir'$$),
  1::bigint,
  'should let the secretary archive an adult'
);

select is(pg_temp.seen_as('head_choir', 'public.members', 'first_name'), 'AdultBoth', 'should hide an archived member from the department head');
select is(pg_temp.seen_as('pastor', 'public.members', 'first_name') like '%AdultChoir%', false, 'should hide an archived member from the pastor');
select is(pg_temp.seen_as('secretary', 'public.members', 'first_name') like '%AdultChoir%', true, 'should keep an archived adult visible to the secretary');
select is(pg_temp.seen_as('super_admin', 'public.members', 'first_name') like '%AdultChoir%', true, 'should keep an archived member visible to the super admin');

select is(
  pg_temp.run_as('secretary', $$update public.members set archived_at = null where first_name = 'AdultChoir'$$),
  1::bigint,
  'should let the secretary restore an archived adult'
);

select is(pg_temp.seen_as('head_choir', 'public.members', 'first_name'), 'AdultBoth,AdultChoir', 'should show a restored member to the department head again');

select is(
  pg_temp.run_as('secretary', $$update public.members set archived_at = now() where first_name = 'MinorChildren'$$),
  0::bigint,
  'should not let the secretary archive a minor'
);

select is(
  pg_temp.run_as('super_admin', $$update public.members set archived_at = now() where first_name = 'MinorChildren'$$),
  1::bigint,
  'should let the super admin archive a minor'
);

select is(pg_temp.seen_as('head_children', 'public.members', 'first_name'), '', 'should hide an archived minor from the head of children''s ministry');
select is(pg_temp.seen_as('pastor', 'public.members', 'first_name') like '%MinorChildren%', false, 'should hide an archived minor from the pastor');

-- No DELETE or TRUNCATE for anyone, the super admin included

select throws_ok(
  pg_temp.attempt(actors.label, format('delete from %s', relations.relation)),
  '42501', null,
  format('should refuse %s deleting from %s', actors.label, relations.relation)
) from actors
cross join (values ('public.members'), ('public.households'), ('public.visitor_followups')) as relations (relation)
order by actors.label, relations.relation;

select throws_ok(
  pg_temp.attempt(label, 'truncate public.members'),
  '42501', null,
  format('should refuse %s truncating members', label)
) from actors where label in ('super_admin', 'secretary', 'anon') order by label;

-- households: addresses. Pastor sees active households, super admin and secretary all, nobody else any.

select is(
  pg_temp.seen_as(label, 'public.households', 'name'),
  case when label in ('super_admin', 'secretary') then 'Alpha Household,Beta Household,Gamma Household'
       when label in ('pastor', 'usher_and_pastor') then 'Alpha Household,Beta Household'
       else '' end,
  format('should show %s only the households they may see', label)
) from actors where label <> 'anon' order by label;

select is(
  pg_temp.run_as(label, $$insert into public.households (name, address) values ('New Household', '9 Test Lane')$$),
  1::bigint,
  format('should let %s create a household', label)
) from actors where label in ('super_admin', 'secretary') order by label;

select throws_ok(
  pg_temp.attempt(label, $$insert into public.households (name, address) values ('New Household', '9 Test Lane')$$),
  '42501', null,
  format('should reject %s creating a household', label)
) from actors where label not in ('super_admin', 'secretary') order by label;

select is(
  pg_temp.run_as(label, $$update public.households set address = '10 Test Lane' where name = 'Alpha Household'$$),
  case when label in ('super_admin', 'secretary') then 1 else 0 end::bigint,
  format('should let %s update a household only if super admin or secretary', label)
) from actors where label <> 'anon' order by label;

select is(
  pg_temp.run_as('secretary', $$update public.households set archived_at = now() where name = 'Beta Household'$$),
  1::bigint,
  'should let the secretary archive a household'
);

select is(pg_temp.seen_as('pastor', 'public.households', 'name') like '%Beta Household%', false, 'should hide an archived household from the pastor');
select is(pg_temp.seen_as('secretary', 'public.households', 'name') like '%Beta Household%', true, 'should keep an archived household visible to the secretary');
select throws_ok(pg_temp.attempt('super_admin', $$insert into public.households (name) values ('   ')$$), '23514', null, 'should reject a blank household name');
select throws_ok(pg_temp.attempt('anon', $$insert into public.households (name) values ('Anon')$$), '42501', null, 'should deny anon creating a household');

select * from finish();

rollback;
