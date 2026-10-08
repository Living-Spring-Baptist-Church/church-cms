-- LBC-42 hardening: only a super admin may change an existing minor into an adult (date_of_birth or
-- adult_confirmed). The secretary and the ministry head are refused with AUTH_FORBIDDEN and leave no audit row;
-- corrections that keep the same minor or adult state, and registering new adults, still work.
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

insert into public.departments (id, name, is_childrens_ministry)
values
  ('d1000000-0000-4000-8000-000000000001', 'Choir', false),
  ('d1000000-0000-4000-8000-000000000002', 'Youth', false),
  ('d1000000-0000-4000-8000-000000000003', 'Children''s Ministry', true),
  ('d1000000-0000-4000-8000-000000000004', 'Nursery', true);

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

-- Fixture. MinorA has a date of birth, MinorB has none. Both belong to the children's ministry, so the
-- secretary and the ministry head can see and edit them. Dates are relative to today so the fixture never ages.
insert into public.members (id, first_name, last_name, date_of_birth, adult_confirmed, status)
values
  ('d3000000-0000-4000-8000-00000000000a', 'MinorA', 'Test', current_date - interval '10 years', false, 'active'),
  ('d3000000-0000-4000-8000-00000000000b', 'MinorB', 'Test', null, false, 'active'),
  ('d3000000-0000-4000-8000-00000000000c', 'MinorC', 'Test', current_date - interval '12 years', false, 'active'),
  ('d3000000-0000-4000-8000-00000000000d', 'AdultD', 'Test', '1980-01-01', false, 'active'),
  ('d3000000-0000-4000-8000-00000000000e', 'MinorE', 'Test', current_date - interval '9 years', false, 'active'),
  ('d3000000-0000-4000-8000-00000000000f', 'MinorF', 'Test', null, false, 'active');
insert into public.member_departments (member_id, department_id)
select id, 'd1000000-0000-4000-8000-000000000003' from public.members where first_name like 'Minor%';

create function pg_temp.update_entries(p_first_name text)
returns bigint
language sql
stable
as $$
  select count(*) from audit.log
  where action = 'UPDATE' and record_id = (select id from public.members where first_name = p_first_name);
$$;

-- Refused: the secretary cannot convert a minor, by date of birth or by the tick, alone or together.
select is(pg_temp.try_as('secretary', $$update public.members set date_of_birth = current_date - interval '30 years' where first_name = 'MinorA'$$), 'AUTH_FORBIDDEN', 'should refuse the secretary changing a minor date of birth to an adult one');
select is(pg_temp.try_as('secretary', $$update public.members set adult_confirmed = true where first_name = 'MinorB'$$), 'AUTH_FORBIDDEN', 'should refuse the secretary ticking adult confirmed on an existing minor');
select is(pg_temp.try_as('secretary', $$update public.members set date_of_birth = current_date - interval '30 years' where first_name = 'MinorB'$$), 'AUTH_FORBIDDEN', 'should refuse the secretary giving an unknown-age minor an adult date of birth');
select is(pg_temp.try_as('secretary', $$update public.members set date_of_birth = current_date - interval '30 years', adult_confirmed = true where first_name = 'MinorA'$$), 'AUTH_FORBIDDEN', 'should refuse the secretary combining both changes');
select is(pg_temp.try_as('secretary', format($$update public.members set date_of_birth = %L where first_name = 'MinorA'$$, (current_date - make_interval(years => private.age_of_majority()))::date)), 'AUTH_FORBIDDEN', 'should refuse a date of birth that turns exactly 18 today');
select is(pg_temp.try_as('head_children', $$update public.members set date_of_birth = current_date - interval '30 years' where first_name = 'MinorA'$$), 'AUTH_FORBIDDEN', 'should refuse the ministry head changing a minor into an adult by date of birth');
select is(pg_temp.try_as('head_children', $$update public.members set adult_confirmed = true where first_name = 'MinorB'$$), 'AUTH_FORBIDDEN', 'should refuse the ministry head ticking adult confirmed');
select is(pg_temp.try_as('head_nursery', $$update public.members set date_of_birth = current_date - interval '30 years' where first_name = 'MinorA'$$), 'ok:0', 'should leave a minor of another ministry untouched for a head who cannot see them');
select is(pg_temp.try_as('pastor', $$update public.members set date_of_birth = current_date - interval '30 years' where first_name = 'MinorA'$$), 'ok:0', 'should not let the pastor write');
select is(pg_temp.graphql_as('secretary', $$mutation { updateMembersCollection(set: {dateOfBirth: "1990-01-01"}, filter: {firstName: {eq: "MinorA"}}) { affectedCount } }$$) #>> '{errors,0,message}', 'AUTH_FORBIDDEN', 'should refuse the secretary converting a minor through GraphQL');
select is(pg_temp.graphql_as('head_children', $$mutation { updateMembersCollection(set: {dateOfBirth: "1990-01-01"}, filter: {firstName: {eq: "MinorA"}}) { affectedCount } }$$) #>> '{errors,0,message}', 'AUTH_FORBIDDEN', 'should refuse the ministry head converting a minor through GraphQL');
select is((select count(*) from public.members where first_name in ('MinorA', 'MinorB') and private.is_minor(date_of_birth, adult_confirmed)), 2::bigint, 'should leave both minors as minors after every refusal');
select is(pg_temp.update_entries('MinorA') + pg_temp.update_entries('MinorB'), 0::bigint, 'should leave no audit row for a refused conversion');

-- Allowed for the secretary: everything that keeps the same state, and registering new adults.
select is(pg_temp.try_as('secretary', $$update public.members set date_of_birth = current_date - interval '11 years' where first_name = 'MinorC'$$), 'ok:1', 'should let the secretary correct a minor date of birth to another minor one');
select is(pg_temp.try_as('secretary', $$update public.members set date_of_birth = current_date - interval '5 years' where first_name = 'MinorF'$$), 'ok:1', 'should let the secretary give an unknown-age minor a minor date of birth');
select is(pg_temp.try_as('secretary', $$update public.members set date_of_birth = '1981-02-02' where first_name = 'AdultD'$$), 'ok:1', 'should let the secretary correct an adult date of birth to another adult one');
select is(pg_temp.try_as('secretary', $$update public.members set adult_confirmed = true where first_name = 'AdultD'$$), 'ok:1', 'should let the secretary tick adult confirmed on someone already an adult');
select is(pg_temp.try_as('secretary', $$insert into public.members (first_name, last_name, adult_confirmed, status) values ('NewVisitor', 'Test', true, 'visitor')$$), 'ok:1', 'should let the secretary register a new adult visitor with the tick');
select is(pg_temp.try_as('secretary', $$insert into public.members (first_name, last_name, date_of_birth, status) values ('NewAdult', 'Test', '1990-05-05', 'visitor')$$), 'ok:1', 'should let the secretary register a new adult with a date of birth');
select is(pg_temp.try_as('secretary', $$update public.members set phone = '0200000009' where first_name = 'MinorC'$$), 'ok:1', 'should let the secretary edit other fields of a ministry child');
select is(pg_temp.try_as('head_children', $$update public.members set date_of_birth = current_date - interval '4 years' where first_name = 'MinorE'$$), 'ok:1', 'should let the ministry head correct a date of birth that keeps the child a minor');
select is(pg_temp.update_entries('MinorE'), 1::bigint, 'should audit an allowed correction');

-- Allowed for the super admin, with an audit row.
select is(pg_temp.try_as('super_admin', $$update public.members set date_of_birth = '1990-01-01' where first_name = 'MinorA'$$), 'ok:1', 'should let the super admin turn a minor into an adult by date of birth');
select is(pg_temp.try_as('super_admin', $$update public.members set adult_confirmed = true where first_name = 'MinorB'$$), 'ok:1', 'should let the super admin turn an unknown-age minor into an adult with the tick');
select is(pg_temp.update_entries('MinorA'), 1::bigint, 'should record one audit row for the conversion');
select is((select actor_id from audit.log where action = 'UPDATE' and record_id = 'd3000000-0000-4000-8000-00000000000a'), (select staff_id from actors where label = 'super_admin'), 'should record the super admin as the actor of the conversion');
select is((select new_data ->> 'date_of_birth' from audit.log where action = 'UPDATE' and record_id = 'd3000000-0000-4000-8000-00000000000a'), '1990-01-01', 'should keep the new date of birth in the audit row');
select is(pg_temp.graphql_as('super_admin', $$mutation { updateMembersCollection(set: {dateOfBirth: "1985-03-03"}, filter: {firstName: {eq: "MinorC"}}) { affectedCount } }$$) #>> '{data,updateMembersCollection,affectedCount}', '1', 'should let the super admin convert through GraphQL');
select is((select count(*) from public.members where first_name in ('MinorA', 'MinorB', 'MinorC') and not private.is_minor(date_of_birth, adult_confirmed)), 3::bigint, 'should leave the converted people as adults');

select * from finish();

rollback;
