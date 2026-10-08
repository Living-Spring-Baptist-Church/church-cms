-- LBC-42: children's records (owner decision, option d) and the adult_confirmed rule, exercised as every role.
-- The secretary is treated like the head of a children's ministry: she reads, creates and edits only the minors who
-- belong to a department flagged is_childrens_ministry, never other minors. Heads of those departments edit the
-- minors of their own department. register_child is the one atomic way to create a child. Ushers never read minors.
-- Every actor runs through pg_temp.try_as(), which switches to the real database role with the JWT claims set, so
-- RLS and grants are exercised (never the table owner). The demo seed is cleared first.

begin;

select plan(271);

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
create function pg_temp.try_as(p_label text, p_statement text)
returns text
language plpgsql
as $$
declare
  v_original name := current_user;
  v_db_role name := case p_label when 'anon' then 'anon' else 'authenticated' end;
  v_rows bigint;
  v_result text;
begin
  perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', v_db_role, 'sub', (select staff_id from actors where label = p_label))::text, true);
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

-- Reads

create temp table expected_members (label text primary key, seen text not null);
insert into expected_members
values
  ('super_admin', 'AdultA,AdultArchived,ChildArchived,ChildKids,ChildNoDob,ChildNursery,MixedChild,MixedYouth,UnknownAdult,UnknownMinor,YouthMinor'),
  ('pastor', 'AdultA,AdultArchived,ChildArchived,ChildKids,ChildNoDob,ChildNursery,MixedChild,MixedYouth,UnknownAdult,UnknownMinor,YouthMinor'),
  ('secretary', 'AdultA,AdultArchived,ChildArchived,ChildKids,ChildNoDob,ChildNursery,MixedChild,UnknownAdult'),
  ('head_children', 'ChildKids,ChildNoDob,MixedChild'),
  ('head_nursery', 'ChildNursery');

select is(
  pg_temp.seen_as(label, 'public.members', 'first_name'),
  coalesce((select seen from expected_members where expected_members.label = actors.label), ''),
  format('should show %s only the members they may see', label)
) from actors where label <> 'anon' order by label;

select is(pg_temp.try_as('anon', 'select * from public.members'), '42501', 'should deny anon reading members');

select is(
  pg_temp.seen_as(label, 'public.member_names', 'first_name'),
  case when label in ('usher', 'treasurer') then 'AdultA,UnknownAdult' else '' end,
  format('should list %s only the adults a confirmed adult tick or a birth date allows in member_names', label)
) from actors where label <> 'anon' order by label;

select is(pg_temp.try_as('usher', $$select * from public.members where first_name = 'ChildKids'$$), 'ok:0', 'should not let an usher read a child of the ministry');
select is(pg_temp.try_as('usher', $$select * from public.member_names where first_name in ('ChildKids', 'UnknownMinor', 'YouthMinor')$$), 'ok:0', 'should not list any minor to an usher in member_names');

-- adult_confirmed: the rule itself

select is(private.is_minor(null, false), true, 'should treat no birth date and no tick as a minor');
select is(private.is_minor(null, null), true, 'should treat no birth date and an unknown tick as a minor');
select is(private.is_minor(null, true), false, 'should treat no birth date with the adult tick as an adult');
select is(private.is_minor('1990-01-01', false), false, 'should treat an adult birth date as an adult');
select is(private.is_minor((current_date - interval '5 years')::date, false), true, 'should treat a child birth date as a minor');
select is(private.is_minor((current_date - interval '5 years')::date, true), true, 'should let a known birth date override the adult tick');
select is((select adult_confirmed from public.members where first_name = 'AdultA'), false, 'should default adult_confirmed to false');

-- adult_confirmed: who may set it

select is(
  pg_temp.try_as(label, format($$insert into public.members (first_name, last_name, adult_confirmed) values (%L, 'Test', true)$$, 'Tick' || label)),
  case when label in ('super_admin', 'secretary') then 'ok:1' else 'AUTH_FORBIDDEN' end,
  format('should let only super admin and secretary register an adult visitor with the tick and refuse every other signed-in role, tested as %s', label)
) from actors where label <> 'anon' order by label;

select is(pg_temp.try_as('anon', $$insert into public.members (first_name, last_name, adult_confirmed) values ('TickAnon', 'Test', true)$$), '42501', 'should deny anon registering a visitor');

select is(pg_temp.try_as('secretary', $$insert into public.members (first_name, last_name) values ('NoTick', 'Test')$$), '42501', 'should treat a visitor with no birth date and no tick as a minor the secretary cannot create');
select is(pg_temp.try_as('secretary', format($$insert into public.members (first_name, last_name, date_of_birth, adult_confirmed) values ('TickedChild', 'Test', %L, true)$$, current_date - interval '9 years')), '42501', 'should not let the secretary use the tick to register a child with a known birth date');
select is(pg_temp.seen_as('secretary', 'public.members', 'first_name') like '%Ticksecretary%', true, 'should let the secretary read the adult visitor she registered with the tick');
select is(pg_temp.seen_as('usher', 'public.member_names', 'first_name') like '%Ticksecretary%', true, 'should list the ticked adult visitor to an usher');

select is(pg_temp.try_as('head_children', $$update public.members set adult_confirmed = true where first_name = 'ChildNoDob'$$), 'AUTH_FORBIDDEN', 'should refuse a children''s ministry head setting adult_confirmed');
select is((select adult_confirmed from public.members where first_name = 'ChildNoDob'), false, 'should leave the child a minor after the refused tick');
select is(pg_temp.try_as(label, $$update public.members set adult_confirmed = true where first_name = 'UnknownMinor'$$), 'ok:0', format('should let %s change nothing when ticking a hidden record', label))
from actors where label in ('pastor', 'treasurer', 'usher', 'content_editor', 'head_children', 'head_choir', 'no_role', 'inactive_secretary', 'secretary') order by label;
select is(pg_temp.try_as('anon', $$update public.members set adult_confirmed = true$$), '42501', 'should deny anon ticking a record');
select is(pg_temp.try_as('secretary', $$update public.members set adult_confirmed = false where first_name = 'UnknownAdult'$$), '42501', 'should stop the secretary taking the tick off an adult, which would hide the record from her');

select is(pg_temp.try_as('super_admin', $$update public.members set adult_confirmed = true where first_name = 'UnknownMinor'$$), 'ok:1', 'should let the super admin confirm an unknown-age visitor as an adult');
select is(pg_temp.seen_as('usher', 'public.member_names', 'first_name') like '%UnknownMinor%', true, 'should list the confirmed visitor to an usher');
select is(pg_temp.try_as('super_admin', $$update public.members set adult_confirmed = false where first_name = 'UnknownMinor'$$), 'ok:1', 'should let the super admin take the tick off again');
select is(pg_temp.seen_as('usher', 'public.member_names', 'first_name') like '%UnknownMinor%', false, 'should hide the visitor from the usher again');

-- register_child: who may call it

create temp table registered (label text primary key, department_id uuid);

select is(
  pg_temp.try_as(label, format($$select public.register_child('Reg' || %L, 'Test', 'd1000000-0000-4000-8000-000000000003', date '2020-01-01')$$, label)),
  case when label in ('super_admin', 'secretary', 'head_children') then 'ok:1' when label = 'anon' then '42501' else 'AUTH_FORBIDDEN' end,
  format('should let only super admin, secretary and the head of the ministry register a child, tested as %s', label)
) from actors order by label;

select is(pg_temp.try_as('head_nursery', $$select public.register_child('RegNursery', 'Test', 'd1000000-0000-4000-8000-000000000004')$$), 'ok:1', 'should let the head of the nursery register a child in the nursery');
select is(pg_temp.try_as('head_nursery', $$select public.register_child('RegWrong', 'Test', 'd1000000-0000-4000-8000-000000000003')$$), 'AUTH_FORBIDDEN', 'should refuse a head registering a child in a ministry they do not head');
select is(pg_temp.try_as('head_children', $$select public.register_child('RegHousehold', 'Test', 'd1000000-0000-4000-8000-000000000003', null, 'd4000000-0000-4000-8000-000000000001')$$), 'AUTH_FORBIDDEN', 'should refuse a head setting a household');
select is(pg_temp.try_as('head_choir', $$select public.register_child('RegChoir', 'Test', 'd1000000-0000-4000-8000-000000000001')$$), 'VALIDATION_FAILED', 'should reject the head of the choir registering a child, because the choir is not a children''s ministry');

-- register_child: validation, each failure leaves no row

select is(
  pg_temp.try_as('secretary', format($$select public.register_child(%s)$$, arguments)),
  expected,
  description
) from (values
  ('''Bad'', ''Test'', ''d1000000-0000-4000-8000-000000000001''', 'VALIDATION_FAILED', 'should reject a department that is not a children''s ministry'),
  ('''Bad'', ''Test'', ''d1000000-0000-4000-8000-000000000005''', 'VALIDATION_FAILED', 'should reject an archived children''s ministry'),
  ('''Bad'', ''Test'', gen_random_uuid()', 'VALIDATION_FAILED', 'should reject an unknown department'),
  ('''Bad'', ''Test'', null', 'VALIDATION_FAILED', 'should reject a missing department'),
  ('''   '', ''Test'', ''d1000000-0000-4000-8000-000000000003''', 'VALIDATION_FAILED', 'should reject a blank first name'),
  ('''Bad'', '''', ''d1000000-0000-4000-8000-000000000003''', 'VALIDATION_FAILED', 'should reject an empty last name'),
  ('null, ''Test'', ''d1000000-0000-4000-8000-000000000003''', 'VALIDATION_FAILED', 'should reject a missing first name'),
  ('''Bad'', ''Test'', ''d1000000-0000-4000-8000-000000000003'', date ''1990-01-01''', 'VALIDATION_FAILED', 'should reject a birth date that makes the person an adult'),
  ('''Bad'', ''Test'', ''d1000000-0000-4000-8000-000000000003'', current_date + 1', 'VALIDATION_FAILED', 'should reject a birth date in the future'),
  ('''Bad'', ''Test'', ''d1000000-0000-4000-8000-000000000003'', null, ''d4000000-0000-4000-8000-000000000002''', 'NOT_FOUND', 'should answer NOT_FOUND for a household that holds only youth minors'),
  ('''Bad'', ''Test'', ''d1000000-0000-4000-8000-000000000003'', null, ''d4000000-0000-4000-8000-000000000005''', 'NOT_FOUND', 'should answer NOT_FOUND for an archived household'),
  ('''Bad'', ''Test'', ''d1000000-0000-4000-8000-000000000003'', null, gen_random_uuid()', 'NOT_FOUND', 'should answer NOT_FOUND for an unknown household')
) as cases (arguments, expected, description);

select is((select count(*) from public.members where first_name = 'Bad'), 0::bigint, 'should leave no member behind when registration is rejected');

-- register_child: success paths and the atomic link

select is(
  (select count(*) from public.members where first_name in ('Regsuper_admin', 'Regsecretary', 'Reghead_children', 'RegNursery')),
  4::bigint,
  'should have created each registered child'
);

select is(
  (select count(*) from public.members as child
   where child.first_name in ('Regsuper_admin', 'Regsecretary', 'Reghead_children', 'RegNursery')
     and not exists (select 1 from public.member_departments as link where link.member_id = child.id)),
  0::bigint,
  'should link every registered child to a department in the same step, so none is an orphan'
);

select is(
  (select count(*) from public.members as child
   join public.member_departments as link on link.member_id = child.id
   where child.first_name in ('Regsuper_admin', 'Regsecretary', 'Reghead_children') and link.department_id = 'd1000000-0000-4000-8000-000000000003'),
  3::bigint,
  'should link the children registered for the Children''s Ministry to it'
);
select is(
  (select count(*) from public.members as child
   join public.member_departments as link on link.member_id = child.id
   where child.first_name = 'RegNursery' and link.department_id = 'd1000000-0000-4000-8000-000000000004'),
  1::bigint,
  'should link the child registered for the Nursery to it'
);

select is(pg_temp.seen_as('secretary', 'public.members', 'first_name') like '%Regsecretary%Regsuper_admin%' , true, 'should let the secretary read the children registered in the ministry');
select is(pg_temp.seen_as('head_children', 'public.members', 'first_name') like '%Reghead_children%', true, 'should let the head read the child they registered');
select is(pg_temp.seen_as('head_nursery', 'public.members', 'first_name'), 'ChildNursery,RegNursery', 'should show the nursery head only the nursery children');
select is(pg_temp.seen_as('usher', 'public.member_names', 'first_name') like '%Reg%', false, 'should keep every registered child out of member_names for the usher');
select is(pg_temp.seen_as('usher', 'public.members', 'first_name'), '', 'should keep every registered child out of members for the usher');

select is(
  (select row(first_name, status, date_of_birth, adult_confirmed, household_id)::text from public.members where first_name = 'Regsecretary'),
  row('Regsecretary', 'active', date '2020-01-01', false, null)::text,
  'should register an active child with the given birth date and no adult tick'
);

select is(pg_temp.try_as('secretary', $$select public.register_child('  Padded  ', 'Test', 'd1000000-0000-4000-8000-000000000003', null, 'd4000000-0000-4000-8000-000000000001', 'female')$$), 'ok:1', 'should let the secretary register a child with no birth date, in a household she can see');
select is((select first_name || '|' || coalesce(gender, '') from public.members where last_name = 'Test' and first_name = 'Padded'), 'Padded|female', 'should trim the name and keep the gender');
select is((select household_id from public.members where first_name = 'Padded'), 'd4000000-0000-4000-8000-000000000001'::uuid, 'should place the child in the household');
select is(pg_temp.try_as('secretary', $$select public.register_child('Padded2', 'Test', 'd1000000-0000-4000-8000-000000000003', null, 'd4000000-0000-4000-8000-000000000003')$$), 'ok:1', 'should let the secretary use an empty household');
select is(pg_temp.try_as('super_admin', $$select public.register_child('Padded3', 'Test', 'd1000000-0000-4000-8000-000000000003', null, 'd4000000-0000-4000-8000-000000000001')$$), 'ok:1', 'should let the super admin use any active household');

-- Direct inserts of minors stay with the super admin: no policy can know the department yet

select is(
  pg_temp.try_as(label, format($$insert into public.members (first_name, last_name, date_of_birth) values (%L, 'Test', current_date - interval '4 years')$$, 'Direct' || label)),
  case when label = 'super_admin' then 'ok:1' else '42501' end,
  format('should let only the super admin insert a minor directly, tested as %s', label)
) from actors where label <> 'anon' order by label;

select is(pg_temp.try_as('head_children', $$insert into public.member_departments (member_id, department_id) values ('d3000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000003')$$), '42501', 'should not let a head link anyone to their department directly');

-- Updates

select is(
  pg_temp.try_as(label, format($$update public.members set phone = %L where first_name = 'ChildKids'$$, 'phone-' || label)),
  case when label in ('super_admin', 'secretary', 'head_children') then 'ok:1' when label = 'anon' then '42501' else 'ok:0' end,
  format('should let only super admin, secretary and the ministry head edit a child of the ministry, tested as %s', label)
) from actors order by label;

select is(
  pg_temp.try_as(label, format($$update public.members set phone = %L where first_name = 'ChildNursery'$$, 'phone-' || label)),
  case when label in ('super_admin', 'secretary', 'head_nursery') then 'ok:1' when label = 'anon' then '42501' else 'ok:0' end,
  format('should let only super admin, secretary and the nursery head edit a nursery child, tested as %s', label)
) from actors order by label;

select is(
  pg_temp.try_as(label, format($$update public.members set phone = %L where first_name in ('YouthMinor', 'MixedYouth', 'UnknownMinor')$$, 'phone-' || label)),
  case when label = 'super_admin' then 'ok:3' when label = 'anon' then '42501' else 'ok:0' end,
  format('should let only the super admin edit a minor outside the children''s ministry, tested as %s', label)
) from actors order by label;

select is(pg_temp.try_as('head_children', $$update public.members set phone = '+233200000558' where first_name = 'AdultA'$$), 'ok:0', 'should keep the ministry head from editing an adult');
select is(pg_temp.try_as('secretary', $$update public.members set phone = '+233200000559' where first_name = 'AdultA'$$), 'ok:1', 'should still let the secretary edit an adult');
select is(pg_temp.try_as('head_children', format($$update public.members set date_of_birth = %L where first_name = 'ChildKids'$$, current_date - interval '30 years')), '42501', 'should refuse a ministry head turning a child into an adult');
select is(pg_temp.try_as('head_children', $$update public.members set archived_at = now() where first_name = 'ChildKids'$$), '42501', 'should refuse a ministry head archiving a child, who would then vanish from their view');
select is(pg_temp.try_as('head_children', $$update public.members set id = gen_random_uuid() where first_name = 'ChildKids'$$), '42501', 'should not let a head change a member id');
select is(pg_temp.try_as('head_children', $$delete from public.members where first_name = 'ChildKids'$$), '42501', 'should not let a head delete a child');
select is(pg_temp.try_as('secretary', $$delete from public.members where first_name = 'ChildKids'$$), '42501', 'should not let the secretary delete a child');

select is(
  pg_temp.try_as('secretary', format($$update public.members set date_of_birth = %L where first_name = 'AdultA'$$, current_date - interval '5 years')),
  '42501',
  'should stop the secretary turning an adult into a minor outside the ministry'
);
select is(pg_temp.try_as('secretary', $$update public.members set archived_at = now() where first_name = 'ChildKids'$$), 'ok:1', 'should let the secretary archive a child of the ministry');
select is(pg_temp.seen_as('head_children', 'public.members', 'first_name') like '%ChildKids%', false, 'should hide the archived child from the ministry head');
select is(pg_temp.seen_as('secretary', 'public.members', 'first_name') like '%ChildKids%', true, 'should keep the archived child visible to the secretary');
select is(pg_temp.try_as('secretary', $$update public.members set archived_at = null where first_name = 'ChildKids'$$), 'ok:1', 'should let the secretary restore the child');
select is(pg_temp.seen_as('head_children', 'public.members', 'first_name') like '%ChildKids%', true, 'should show the restored child to the ministry head again');
select is(pg_temp.try_as('secretary', $$update public.members set status = 'inactive' where first_name = 'ChildArchived'$$), 'ok:1', 'should let the secretary edit an archived child of the ministry');

-- Department links: removing the children's ministry link would orphan the child

select is(pg_temp.try_as('secretary', $$delete from public.member_departments where member_id = 'd3000000-0000-4000-8000-000000000002'$$), 'ok:0', 'should not let the secretary remove the ministry link of a child');
select is(pg_temp.try_as('head_children', $$delete from public.member_departments where member_id = 'd3000000-0000-4000-8000-000000000002'$$), 'ok:0', 'should not let the head remove the ministry link of a child');
select is(pg_temp.try_as('secretary', $$insert into public.member_departments (member_id, department_id) values ('d3000000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000001')$$), 'ok:1', 'should let the secretary add a visible child to another department');
select is(pg_temp.try_as('secretary', $$delete from public.member_departments where member_id = 'd3000000-0000-4000-8000-000000000002' and department_id = 'd1000000-0000-4000-8000-000000000001'$$), 'ok:1', 'should let the secretary remove a link that is not the ministry');
select is(pg_temp.try_as('secretary', $$insert into public.member_departments (member_id, department_id) values ('d3000000-0000-4000-8000-000000000004', 'd1000000-0000-4000-8000-000000000001')$$), '42501', 'should not let the secretary link a youth minor she cannot see');
select is(pg_temp.try_as('super_admin', $$delete from public.member_departments where member_id = 'd3000000-0000-4000-8000-000000000007'$$), 'ok:1', 'should let the super admin remove the ministry link of a child');
select is(pg_temp.seen_as('secretary', 'public.members', 'first_name') like '%ChildNoDob%', false, 'should hide a child with no ministry link from the secretary, which is why only the super admin may remove it');
select is(pg_temp.try_as('super_admin', $$insert into public.member_departments (member_id, department_id) values ('d3000000-0000-4000-8000-000000000007', 'd1000000-0000-4000-8000-000000000003')$$), 'ok:1', 'should let the super admin link the child again');
select is(pg_temp.seen_as('secretary', 'public.members', 'first_name') like '%ChildNoDob%', true, 'should show the relinked child to the secretary');

-- Follow-ups follow the visibility of the child

select is(pg_temp.try_as('secretary', $$insert into public.visitor_followups (member_id, notes) values ('d3000000-0000-4000-8000-000000000003', 'ChildFollow')$$), 'ok:1', 'should let the secretary add a follow-up for a child of the ministry');
select is(pg_temp.try_as('secretary', $$insert into public.visitor_followups (member_id, notes) values ('d3000000-0000-4000-8000-000000000004', 'YouthFollow')$$), '42501', 'should not let the secretary add a follow-up for a youth minor');
select is(pg_temp.try_as('head_children', $$insert into public.visitor_followups (member_id, notes) values ('d3000000-0000-4000-8000-000000000002', 'HeadFollow')$$), '42501', 'should not let the ministry head add a follow-up');

-- Households (decision for the human: visible when empty or when someone in them is visible)

select is(
  pg_temp.seen_as(label, 'public.households', 'name'),
  case when label in ('super_admin', 'pastor') then 'Alpha,ArchivedEmpty,Empty,Mixed,YouthOnly'
       when label = 'secretary' then 'Alpha,ArchivedEmpty,Empty,Mixed'
       else '' end,
  format('should show %s only the households they may see', label)
) from actors where label <> 'anon' order by label;

select is(
  pg_temp.try_as(label, $$update public.households set address = '10 Test Lane' where name = 'YouthOnly'$$),
  case when label in ('super_admin') then 'ok:1' when label = 'anon' then '42501' else 'ok:0' end,
  format('should let only the super admin edit a household that holds only youth minors, tested as %s', label)
) from actors order by label;

select is(pg_temp.try_as('secretary', $$update public.households set address = '11 Test Lane' where name = 'Mixed'$$), 'ok:1', 'should let the secretary edit a household with a child of the ministry');
select is(pg_temp.try_as('secretary', $$update public.households set address = '12 Test Lane' where name = 'Empty'$$), 'ok:1', 'should let the secretary edit an empty household');
select is(pg_temp.try_as('secretary', $$insert into public.households (name, address) values ('SecretaryHome', '13 Test Lane')$$), 'ok:1', 'should let the secretary create a household');
select is(pg_temp.seen_as('secretary', 'public.households', 'name') like '%SecretaryHome%', true, 'should let the secretary read the household she just created');
select is(
  pg_temp.graphql_as('secretary', $$mutation { insertIntoHouseholdsCollection(objects: [{ name: "GqlHome" }]) { records { name } } }$$) #>> '{data,insertIntoHouseholdsCollection,records,0,name}',
  'GqlHome',
  'should return the new household to the secretary through GraphQL'
);
select is(pg_temp.try_as('pastor', $$update public.households set address = 'x' where name = 'Alpha'$$), 'ok:0', 'should keep the pastor from editing a household');
select is(pg_temp.seen_as('pastor', 'public.households', 'name') like '%ArchivedEmpty%', true, 'should show an archived household to the pastor');

-- GraphQL: registerChild

select is(
  pg_temp.graphql_as('secretary', $$mutation { registerChild(pFirstName: "GqlChild", pLastName: "Test", pDepartmentId: "d1000000-0000-4000-8000-000000000003", pDateOfBirth: "2021-03-04") { firstName lastName dateOfBirth status adultConfirmed } }$$) #> '{data,registerChild}',
  '{"status": "active", "lastName": "Test", "firstName": "GqlChild", "dateOfBirth": "2021-03-04", "adultConfirmed": false}'::jsonb,
  'should register a child through the registerChild mutation and return the row'
);
select is(
  pg_temp.graphql_as('pastor', $$mutation { registerChild(pFirstName: "GqlPastor", pLastName: "Test", pDepartmentId: "d1000000-0000-4000-8000-000000000003") { id } }$$) #>> '{errors,0,message}',
  'AUTH_FORBIDDEN',
  'should return AUTH_FORBIDDEN to the pastor through GraphQL'
);
select is(
  pg_temp.graphql_as('head_children', $$mutation { registerChild(pFirstName: "GqlHead", pLastName: "Test", pDepartmentId: "d1000000-0000-4000-8000-000000000001") { id } }$$) #>> '{errors,0,message}',
  'AUTH_FORBIDDEN',
  'should return AUTH_FORBIDDEN to a head registering outside their ministry through GraphQL'
);
select is(
  pg_temp.graphql_as('secretary', $$mutation { registerChild(pFirstName: "GqlBad", pLastName: "Test", pDepartmentId: "d1000000-0000-4000-8000-000000000001") { id } }$$) #>> '{errors,0,message}',
  'VALIDATION_FAILED',
  'should return VALIDATION_FAILED for a department that is not a children''s ministry through GraphQL'
);
select is(pg_temp.graphql_as('anon', $$mutation { registerChild(pFirstName: "GqlAnon", pLastName: "Test", pDepartmentId: "d1000000-0000-4000-8000-000000000003") { id } }$$) -> 'errors' is not null, true, 'should refuse anon registerChild through GraphQL');

-- Audit: every children's write is recorded with the actor, the table and the changed fields

select is(
  (select count(*) from audit.log
   where table_name = 'members' and action = 'INSERT' and actor_id = (select staff_id from actors where label = 'secretary')
     and new_data ->> 'first_name' = 'Regsecretary'),
  1::bigint,
  'should audit the member row inserted by the secretary through register_child'
);
select is(
  (select count(*) from audit.log
   where table_name = 'member_departments' and action = 'INSERT' and actor_id = (select staff_id from actors where label = 'secretary')
     and new_data ->> 'member_id' = (select id::text from public.members where first_name = 'Regsecretary')),
  1::bigint,
  'should audit the department link inserted by the secretary through register_child'
);
select is(
  (select count(*) from audit.log
   where table_name = 'members' and action = 'INSERT' and actor_id = (select staff_id from actors where label = 'head_children')
     and new_data ->> 'first_name' = 'Reghead_children'),
  1::bigint,
  'should audit the member row inserted by the ministry head through register_child'
);
select is(
  (select count(*) from audit.log
   where table_name = 'member_departments' and action = 'INSERT' and actor_id = (select staff_id from actors where label = 'head_nursery')
     and new_data ->> 'member_id' = (select id::text from public.members where first_name = 'RegNursery')),
  1::bigint,
  'should audit the department link inserted by the nursery head through register_child'
);
select is(
  (select count(*) from audit.log where table_name = 'members' and action = 'INSERT' and actor_id is null and new_data ->> 'first_name' like 'Reg%'),
  0::bigint,
  'should never record a registered child without an actor'
);
select is(
  (select changed_fields from audit.log
   where table_name = 'members' and action = 'UPDATE' and record_id = 'd3000000-0000-4000-8000-000000000003'
     and actor_id = (select staff_id from actors where label = 'head_nursery')),
  array['phone'],
  'should audit the nursery head''s edit of a child with the exact changed field'
);
select is(
  (select count(*) from audit.log
   where table_name = 'members' and action = 'UPDATE' and record_id = 'd3000000-0000-4000-8000-000000000002'
     and actor_id = (select staff_id from actors where label = 'head_children') and changed_fields = array['phone']),
  1::bigint,
  'should audit the ministry head''s edit of a child'
);
select is(
  (select count(*) from audit.log
   where table_name = 'members' and action = 'UPDATE' and record_id = 'd3000000-0000-4000-8000-000000000002'
     and actor_id = (select staff_id from actors where label = 'secretary') and changed_fields = array['phone']),
  1::bigint,
  'should audit the secretary''s edit of a child'
);
select is(
  (select array_agg(changed_fields::text order by id) from audit.log
   where table_name = 'members' and action = 'UPDATE' and record_id = 'd3000000-0000-4000-8000-000000000002'
     and actor_id = (select staff_id from actors where label = 'secretary') and changed_fields <> array['phone']),
  array['{archived_at}', '{archived_at}'],
  'should audit the secretary archiving and restoring a child'
);
select is(
  (select count(*) from audit.log
   where table_name = 'members' and action = 'UPDATE' and actor_id = (select staff_id from actors where label = 'head_children')
     and record_id = 'd3000000-0000-4000-8000-000000000001'),
  0::bigint,
  'should leave no audit row for an edit the ministry head was refused'
);
select is(
  (select count(*) from audit.log
   where table_name = 'members' and action = 'UPDATE' and new_data ->> 'first_name' = 'ChildNoDob'
     and 'adult_confirmed' = any (changed_fields)),
  0::bigint,
  'should leave no audit row for the refused adult_confirmed change'
);
select is(
  (select changed_fields from audit.log
   where table_name = 'members' and action = 'UPDATE' and new_data ->> 'first_name' = 'UnknownMinor'
     and actor_id = (select staff_id from actors where label = 'super_admin') and 'adult_confirmed' = any (changed_fields)
   order by id limit 1),
  array['adult_confirmed'],
  'should audit the super admin setting adult_confirmed'
);
select is(
  (select count(*) from audit.log
   where table_name = 'member_departments' and action = 'DELETE' and old_data ->> 'member_id' = 'd3000000-0000-4000-8000-000000000007'
     and actor_id = (select staff_id from actors where label = 'super_admin')),
  1::bigint,
  'should audit the super admin removing a ministry link'
);
select is(
  (select count(*) from audit.log
   where table_name = 'members' and action = 'INSERT' and actor_id = (select staff_id from actors where label = 'secretary')
     and new_data ->> 'first_name' = 'Ticksecretary' and new_data ->> 'adult_confirmed' = 'true'),
  1::bigint,
  'should audit the secretary registering an adult visitor with the tick'
);

-- Structure: grants, definer settings and documentation of the new objects

select is(
  has_function_privilege(role_name, signature, 'EXECUTE'),
  expected,
  format('should %s %s executing %s', case when expected then 'let' else 'not let' end, role_name, signature)
) from (values
  ('authenticated', 'public.register_child(text, text, uuid, date, uuid, text)', true),
  ('anon', 'public.register_child(text, text, uuid, date, uuid, text)', false),
  ('authenticated', 'private.is_in_childrens_ministry(uuid)', true),
  ('authenticated', 'private.is_childrens_ministry_link(uuid, uuid)', true),
  ('authenticated', 'private.household_visible_to_secretary(uuid)', true),
  ('authenticated', 'private.is_minor(date, boolean)', true),
  ('authenticated', 'private.guard_adult_confirmed()', false),
  ('anon', 'private.is_in_childrens_ministry(uuid)', false),
  ('anon', 'private.household_visible_to_secretary(uuid)', false),
  ('anon', 'private.is_minor(date, boolean)', false)
) as checks (role_name, signature, expected);

select is(
  (select prosecdef and proconfig = array['search_path=""'] from pg_proc where oid = 'public.register_child(text, text, uuid, date, uuid, text)'::regprocedure),
  true,
  'should run register_child as definer with an empty search_path'
);
select is((select provolatile from pg_proc where oid = 'public.register_child(text, text, uuid, date, uuid, text)'::regprocedure), 'v', 'should mark register_child volatile so it is a mutation');
select is(to_regprocedure('private.is_minor(date)') is null, true, 'should have dropped the one-argument is_minor so no policy can use the unsafe form');
select is(
  (select count(*) from pg_proc
   where oid in ('public.register_child(text, text, uuid, date, uuid, text)'::regprocedure,
                 'private.is_in_childrens_ministry(uuid)'::regprocedure, 'private.is_childrens_ministry_link(uuid, uuid)'::regprocedure,
                 'private.household_visible_to_secretary(uuid)'::regprocedure, 'private.is_minor(date, boolean)'::regprocedure,
                 'private.guard_adult_confirmed()'::regprocedure)
     and obj_description(oid, 'pg_proc') is null),
  0::bigint,
  'should describe every new function'
);
select is(col_description('public.members'::regclass, (select attnum from pg_attribute where attrelid = 'public.members'::regclass and attname = 'adult_confirmed')) is not null, true, 'should describe the adult_confirmed column');
select is(
  (select tgenabled::text from pg_trigger where tgrelid = 'public.members'::regclass and tgname = 'members_guard_adult_confirmed'),
  'O',
  'should have the adult_confirmed guard trigger enabled'
);
select is(
  (select tgenabled::text from pg_trigger where tgrelid = 'public.members'::regclass and tgname = 'audit_members'),
  'A',
  'should still run the members audit trigger always'
);
select is(has_column_privilege('anon', 'public.members', 'adult_confirmed', 'UPDATE'), false, 'should not let anon update adult_confirmed');
select is(
  (select count(*) from pg_policy where polrelid = 'public.members'::regclass and polname = 'members_update_children_head'),
  1::bigint,
  'should have the update policy of the children''s ministry head'
);

select * from finish();

rollback;
