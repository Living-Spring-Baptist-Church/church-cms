-- LBC-42 hardening QA: try to break the minor conversion guard, the household guard and the session helper.
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

create temp table actors (label text primary key, staff_id uuid);
create temp table actor_roles (label text not null, role public.app_role not null, department_id uuid);

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

create function pg_temp.graphql_as(p_label text, p_query text)
returns jsonb
language plpgsql
as $$
declare
  v_original name := current_user;
  v_result jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', 'authenticated', 'sub', (select staff_id from actors where label = p_label))::text, true);
  perform set_config('role', 'authenticated', true);
  v_result := graphql.resolve(p_query);
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_result;
end;
$$;

create function pg_temp.session_probe()
returns boolean
language sql
security definer
as $$ select private.in_app_session(); $$;

create function pg_temp.role_setting_probe(p_role text)
returns boolean
language plpgsql
as $$
declare
  v_original name := current_user;
  v_result boolean;
begin
  perform set_config('role', p_role, true);
  v_result := pg_temp.session_probe();
  perform set_config('role', v_original::text, true);
  return v_result;
end;
$$;

insert into public.departments (id, name, is_childrens_ministry)
values ('d1000000-0000-4000-8000-000000000003', 'Children''s Ministry', true);

insert into actors (label) values ('super_admin'), ('secretary'), ('head_children'), ('usher'), ('pastor');
insert into actor_roles (label, role, department_id)
values
  ('super_admin', 'super_admin', null),
  ('secretary', 'secretary', null),
  ('usher', 'usher', null),
  ('pastor', 'pastor', null),
  ('head_children', 'department_head', 'd1000000-0000-4000-8000-000000000003');
update actors
set staff_id = ('d2000000-0000-4000-8000-' || lpad(numbered.position::text, 12, '0'))::uuid
from (select label, row_number() over (order by label) as position from actors) as numbered
where actors.label = numbered.label;
insert into auth.users (id, aud, role, email) select staff_id, 'authenticated', 'authenticated', label || '@test.invalid' from actors;
insert into public.staff (id, full_name, is_active) select staff_id, label, true from actors;
insert into public.staff_roles (staff_id, role, department_id)
select actors.staff_id, actor_roles.role, actor_roles.department_id from actor_roles join actors using (label);

-- Households: Hidden holds only a youth minor outside the ministry, Open holds an adult, Empty has nobody.
insert into public.households (id, name, address)
values
  ('d4000000-0000-4000-8000-000000000001', 'Hidden', '1 Test Lane'),
  ('d4000000-0000-4000-8000-000000000002', 'Open', '2 Test Lane'),
  ('d4000000-0000-4000-8000-000000000003', 'Empty', '3 Test Lane');

insert into public.members (id, household_id, first_name, last_name, date_of_birth, adult_confirmed, status)
values
  ('d3000000-0000-4000-8000-000000000001', 'd4000000-0000-4000-8000-000000000001', 'YouthHidden', 'Test', current_date - interval '15 years', false, 'active'),
  ('d3000000-0000-4000-8000-000000000002', 'd4000000-0000-4000-8000-000000000002', 'AdultOpen', 'Test', '1980-01-01', false, 'active'),
  ('d3000000-0000-4000-8000-000000000003', null, 'KidOne', 'Test', current_date - interval '8 years', false, 'active'),
  ('d3000000-0000-4000-8000-000000000004', null, 'KidTwo', 'Test', current_date - interval '9 years', false, 'active'),
  ('d3000000-0000-4000-8000-000000000005', null, 'KidThree', 'Test', null, false, 'active'),
  ('d3000000-0000-4000-8000-000000000006', null, 'KidFour', 'Test', current_date - interval '17 years' - interval '364 days', false, 'active'),
  ('d3000000-0000-4000-8000-000000000007', null, 'KidFive', 'Test', current_date - interval '6 years', false, 'active');
insert into public.member_departments (member_id, department_id)
select id, 'd1000000-0000-4000-8000-000000000003' from public.members where first_name like 'Kid%';

create function pg_temp.audit_updates(p_first_name text)
returns bigint
language sql
stable
as $$
  select count(*) from audit.log where action = 'UPDATE' and record_id = (select id from public.members where first_name = p_first_name);
$$;

create function pg_temp.minor_count()
returns bigint
language sql
stable
as $$
  select count(*) from public.members where first_name like 'Kid%' and private.is_minor(date_of_birth, adult_confirmed);
$$;

-- in_app_session: the helper behind every guard, per session role.
select is(private.in_app_session(), false, 'should be false for the postgres session used by migrations and seed');
select is(pg_temp.role_setting_probe('service_role'), false, 'should be false for the service role');
select is(pg_temp.role_setting_probe('authenticated'), true, 'should be true for an authenticated session');
select is(pg_temp.role_setting_probe('anon'), true, 'should be true for an anonymous session');
select is(has_function_privilege('authenticated', 'private.in_app_session()', 'execute'), false, 'should not let authenticated call in_app_session directly');

-- Bulk and mixed updates by the secretary: one converting row poisons the whole statement.
select is(pg_temp.try_as('secretary', $$update public.members set date_of_birth = '1990-01-01' where first_name like 'Kid%'$$), 'AUTH_FORBIDDEN', 'should refuse a bulk update when any row would turn from minor to adult');
select is(pg_temp.try_as('secretary', $$update public.members set phone = '0200000001', date_of_birth = '1990-01-01' where first_name = 'KidOne'$$), 'AUTH_FORBIDDEN', 'should refuse a conversion hidden among other column changes');
select is(pg_temp.try_as('secretary', $$update public.members set date_of_birth = null where first_name = 'KidOne'$$), 'ok:1', 'should allow clearing the date of birth of a minor, who stays a minor');
select is(pg_temp.try_as('secretary', $$update public.members set date_of_birth = null, adult_confirmed = true where first_name = 'KidTwo'$$), 'AUTH_FORBIDDEN', 'should refuse clearing the date of birth together with the adult tick');
select is(pg_temp.try_as('secretary', $$update public.members set adult_confirmed = false where first_name = 'KidTwo'$$), 'ok:1', 'should allow an unchanged adult_confirmed on a minor');
select is(pg_temp.try_as('secretary', $$update public.members set first_name = 'KidTwo', date_of_birth = current_date - interval '9 years' where first_name = 'KidTwo'$$), 'ok:1', 'should allow a no-op style update on a minor');
select is(pg_temp.try_as('secretary', $$update public.members set date_of_birth = current_date - interval '18 years' + interval '1 day' where first_name = 'KidFour'$$), 'ok:1', 'should allow a date of birth that leaves a person one day short of 18');
select is(pg_temp.try_as('secretary', $$update public.members set date_of_birth = current_date - interval '18 years' where first_name = 'KidFour'$$), 'AUTH_FORBIDDEN', 'should refuse a date of birth that makes a person exactly 18 today');
select is(pg_temp.try_as('secretary', $$update public.members set date_of_birth = current_date - interval '18 years' - interval '1 day' where first_name = 'KidFour'$$), 'AUTH_FORBIDDEN', 'should refuse a date of birth that makes a person 18 and one day');
select is(pg_temp.try_as('secretary', $$update public.members set date_of_birth = '1990-01-01', household_id = 'd4000000-0000-4000-8000-000000000002' where first_name = 'KidFive'$$), 'AUTH_FORBIDDEN', 'should refuse a conversion combined with a legitimate household move');
select is(pg_temp.minor_count(), 5::bigint, 'should leave every ministry child a minor after the refusals');
select is(pg_temp.audit_updates('KidFive'), 0::bigint, 'should leave no audit row for the refused combined update');

-- Insert then convert, and the upsert path, as the secretary.
select is(pg_temp.try_as('secretary', $$insert into public.members (first_name, last_name, date_of_birth, status) values ('FreshKid', 'Test', current_date - interval '7 years', 'visitor')$$), '42501', 'should refuse the secretary inserting a minor directly, so insert-then-convert has no start');
select is(pg_temp.try_as('secretary', $$insert into public.members (id, first_name, last_name, adult_confirmed, status) values ('d3000000-0000-4000-8000-000000000003', 'KidOne', 'Test', true, 'visitor') on conflict (id) do update set date_of_birth = '1990-01-01'$$), '42501', 'should close the upsert path for the secretary');
select is(pg_temp.try_as('super_admin', $$insert into public.members (id, first_name, last_name, adult_confirmed, status) values ('d3000000-0000-4000-8000-000000000003', 'KidOne', 'Test', true, 'visitor') on conflict (id) do update set date_of_birth = '1990-01-01'$$), '42501', 'should close the upsert path for the super admin too');
select is(pg_temp.try_as('head_children', $$insert into public.members (first_name, last_name, date_of_birth, status) values ('HeadMade', 'Test', current_date - interval '5 years', 'visitor')$$), '42501', 'should keep the ministry head from inserting a member directly');
select is((select date_of_birth from public.members where first_name = 'KidOne') is null, true, 'should leave the minor untouched after every upsert attempt');
select is(pg_temp.graphql_as('secretary', $$mutation { updateMembersCollection(set: {adultConfirmed: true}, atMost: 50) { affectedCount } }$$) #>> '{errors,0,message}', 'AUTH_FORBIDDEN', 'should refuse a GraphQL bulk tick for the secretary');
select is(pg_temp.graphql_as('usher', $$mutation { updateMembersCollection(set: {adultConfirmed: true}, atMost: 50) { affectedCount } }$$) #>> '{data,updateMembersCollection,affectedCount}', '0', 'should change nothing for an usher through GraphQL');
select is(pg_temp.try_as('pastor', $$update public.members set adult_confirmed = true where first_name = 'KidTwo'$$), 'ok:0', 'should change nothing for the pastor');

-- Household guard: same error for hidden and nonexistent households (no existence oracle).
select is(pg_temp.try_as('secretary', $$update public.members set household_id = 'd4000000-0000-4000-8000-000000000001' where first_name = 'KidTwo'$$), 'AUTH_FORBIDDEN', 'should refuse the secretary moving a child into a hidden household');
select is(pg_temp.try_as('secretary', $$update public.members set household_id = 'd4000000-0000-4000-8000-0000000000ff' where first_name = 'KidTwo'$$), 'AUTH_FORBIDDEN', 'should give the secretary the same error for a nonexistent household as for a hidden one');
select is(pg_temp.try_as('head_children', $$update public.members set household_id = 'd4000000-0000-4000-8000-0000000000ff' where first_name = 'KidTwo'$$), 'AUTH_FORBIDDEN', 'should give the ministry head the same error for a nonexistent household');
select is(pg_temp.try_as('head_children', $$update public.members set household_id = 'd4000000-0000-4000-8000-000000000002' where first_name = 'KidTwo'$$), 'AUTH_FORBIDDEN', 'should refuse the ministry head setting even a visible household');
select is(pg_temp.try_as('secretary', $$update public.members set household_id = 'd4000000-0000-4000-8000-000000000002', phone = '0244000000' where first_name = 'KidTwo'$$), 'ok:1', 'should allow a single-statement household move plus other changes to a visible household');
select is(pg_temp.try_as('head_children', $$update public.members set household_id = null, phone = '0244000001' where first_name = 'KidTwo'$$), 'ok:1', 'should let the ministry head clear a household together with other changes');
select is(pg_temp.try_as('head_children', $$update public.members set phone = '0244000002' where first_name = 'KidOne'$$), 'ok:1', 'should let the ministry head edit other fields without touching the household');
select is(pg_temp.try_as('secretary', $$insert into public.members (first_name, last_name, adult_confirmed, household_id) values ('Probe', 'Test', true, 'd4000000-0000-4000-8000-000000000001')$$), 'AUTH_FORBIDDEN', 'should refuse a new adult placed in a hidden household');
select is(pg_temp.try_as('secretary', $$insert into public.members (first_name, last_name, adult_confirmed, household_id) values ('Probe', 'Test', true, 'd4000000-0000-4000-8000-000000000003')$$), 'ok:1', 'should allow a new adult in an empty household');
select is(pg_temp.graphql_as('secretary', $$mutation { updateMembersCollection(set: {householdId: "d4000000-0000-4000-8000-000000000001"}, filter: {firstName: {eq: "KidTwo"}}) { affectedCount } }$$) #>> '{errors,0,message}', 'AUTH_FORBIDDEN', 'should refuse the household move through GraphQL for the secretary');
select is(pg_temp.graphql_as('secretary', $$mutation { updateMembersCollection(set: {householdId: "d4000000-0000-4000-8000-0000000000ff"}, filter: {firstName: {eq: "KidTwo"}}) { affectedCount } }$$) #>> '{errors,0,message}', 'AUTH_FORBIDDEN', 'should give the same GraphQL error for a nonexistent household');
select is(pg_temp.try_as('super_admin', $$update public.members set household_id = 'd4000000-0000-4000-8000-000000000001' where first_name = 'KidOne'$$), 'ok:1', 'should let the super admin use a hidden household');
select is(pg_temp.try_as('super_admin', $$update public.members set household_id = 'd4000000-0000-4000-8000-0000000000ff' where first_name = 'KidOne'$$), '23503', 'should let the super admin hit the foreign key for a nonexistent household');

-- Seed, migration and service role writes are unaffected.
update public.members set date_of_birth = '1990-01-01', household_id = 'd4000000-0000-4000-8000-000000000001' where first_name = 'KidThree';
select is((select household_id from public.members where first_name = 'KidThree'), 'd4000000-0000-4000-8000-000000000001'::uuid, 'should let the postgres session convert and move without a guard');

select * from finish();

rollback;
