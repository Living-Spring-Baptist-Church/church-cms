-- LBC-20 (OVR-01): public.get_new_visitors_this_month, the overview count of new visitors this month. Counts members
-- whose first_visit_on falls in the current month in the church time zone, whatever their status, and only the rows
-- the caller can read. Super admin, pastor and secretary may see it; everyone else is refused with AUTH_FORBIDDEN, and
-- anon has no execute grant. Every actor runs through pg_temp.count_as(), which switches to the real database role
-- with the JWT claims set, so grants and the role gate are exercised. The month is read from the clock inside the
-- transaction, so the seed cannot move the fixture.

begin;

select plan(31);

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

-- The first day of this church month and the first day of the next one, read once so every case uses the same clock.
create temp table clock (month_start date not null, next_month_start date not null);
insert into clock (month_start, next_month_start)
select this_month.month_start, (this_month.month_start + interval '1 month')::date
from (
  select date_trunc('month', (now() at time zone private.church_time_zone())::timestamp)::date as month_start
) as this_month;

-- One actor per role, a department head, an active staff member with no role, an inactive super admin, and anon.
create temp table actors (label text primary key, staff_id uuid, is_active boolean not null default true);
create temp table actor_roles (label text not null, role public.app_role not null, department_id uuid);

insert into public.departments (id, name, is_childrens_ministry)
values
  ('40000000-0000-4000-8000-000000000001', 'Choir', false),
  ('40000000-0000-4000-8000-000000000002', 'Children''s Ministry', true);

insert into actors (label, staff_id, is_active)
values
  ('super_admin', '50000000-0000-4000-8000-000000000001', true),
  ('pastor', '50000000-0000-4000-8000-000000000002', true),
  ('secretary', '50000000-0000-4000-8000-000000000003', true),
  ('usher', '50000000-0000-4000-8000-000000000004', true),
  ('treasurer', '50000000-0000-4000-8000-000000000005', true),
  ('department_head', '50000000-0000-4000-8000-000000000006', true),
  ('content_editor', '50000000-0000-4000-8000-000000000007', true),
  ('no_role', '50000000-0000-4000-8000-000000000008', true),
  ('inactive_super_admin', '50000000-0000-4000-8000-000000000009', false),
  ('anon', null, true);

insert into actor_roles (label, role, department_id)
values
  ('super_admin', 'super_admin', null),
  ('pastor', 'pastor', null),
  ('secretary', 'secretary', null),
  ('usher', 'usher', null),
  ('treasurer', 'treasurer', null),
  ('department_head', 'department_head', '40000000-0000-4000-8000-000000000001'),
  ('content_editor', 'content_editor', null),
  ('inactive_super_admin', 'super_admin', null);

insert into auth.users (id, aud, role, email)
select staff_id, 'authenticated', 'authenticated', label || '@test.invalid' from actors where label <> 'anon';

insert into public.staff (id, full_name, is_active)
select staff_id, label, is_active from actors where label <> 'anon';

insert into public.staff_roles (staff_id, role, department_id)
select actors.staff_id, actor_roles.role, actor_roles.department_id
from actor_roles
join actors using (label);

-- Members (60...01 to 60...13). Adults are born in 1980, minors ten years ago. Unknown ages are minors unless
-- adult_confirmed. The names say what each row tests.
insert into public.members (id, first_name, last_name, date_of_birth, status, first_visit_on, adult_confirmed)
select v.id, v.first_name, 'Test', v.date_of_birth, v.status, v.first_visit_on, v.adult_confirmed
from clock
cross join lateral (
  values
    ('60000000-0000-4000-8000-000000000001'::uuid, 'AdultFirstDay', '1980-01-01'::date, 'visitor'::public.member_status, clock.month_start, false),
    ('60000000-0000-4000-8000-000000000002'::uuid, 'AdultMidMonth', '1980-01-01'::date, 'visitor'::public.member_status, clock.month_start + 14, false),
    ('60000000-0000-4000-8000-000000000003'::uuid, 'ConvertedThisMonth', '1980-01-01'::date, 'active'::public.member_status, clock.month_start + 2, false),
    ('60000000-0000-4000-8000-000000000004'::uuid, 'ArchivedAdult', '1980-01-01'::date, 'inactive'::public.member_status, clock.month_start + 3, false),
    ('60000000-0000-4000-8000-000000000005'::uuid, 'MinorThisMonth', (current_date - interval '10 years')::date, 'visitor'::public.member_status, clock.month_start + 4, false),
    ('60000000-0000-4000-8000-000000000006'::uuid, 'UnknownAgeThisMonth', null::date, 'visitor'::public.member_status, clock.month_start + 5, false),
    ('60000000-0000-4000-8000-000000000007'::uuid, 'AdultLastDay', '1980-01-01'::date, 'visitor'::public.member_status, clock.next_month_start - 1, false),
    ('60000000-0000-4000-8000-000000000008'::uuid, 'VisitedLastMonth', '1980-01-01'::date, 'visitor'::public.member_status, clock.month_start - 1, false),
    ('60000000-0000-4000-8000-000000000009'::uuid, 'VisitedNextMonth', '1980-01-01'::date, 'visitor'::public.member_status, clock.next_month_start, false),
    ('60000000-0000-4000-8000-000000000010'::uuid, 'NoVisitDate', '1980-01-01'::date, 'active'::public.member_status, null::date, false),
    ('60000000-0000-4000-8000-000000000011'::uuid, 'VisitedLastYear', '1980-01-01'::date, 'visitor'::public.member_status, (clock.month_start - interval '1 year')::date, false),
    ('60000000-0000-4000-8000-000000000012'::uuid, 'MinorInChildrensMinistry', (current_date - interval '10 years')::date, 'active'::public.member_status, clock.month_start + 6, false),
    ('60000000-0000-4000-8000-000000000013'::uuid, 'UnknownAgeConfirmed', null::date, 'visitor'::public.member_status, clock.month_start + 7, true)
) as v (id, first_name, date_of_birth, status, first_visit_on, adult_confirmed);

update public.members set archived_at = now() where id = '60000000-0000-4000-8000-000000000004';

insert into public.member_departments (member_id, department_id)
values ('60000000-0000-4000-8000-000000000012', '40000000-0000-4000-8000-000000000002');

-- Runs the count as a real database role with the JWT claims set. Errors are left to the caller (throws_ok).
create function pg_temp.count_as(p_label text, p_aal text)
returns integer
language plpgsql
as $$
declare
  v_original name := current_user;
  v_db_role name := case p_label when 'anon' then 'anon' else 'authenticated' end;
  v_count integer;
begin
  perform set_config('request.jwt.claims', json_build_object('aal', p_aal, 'role', v_db_role, 'sub', (select staff_id from actors where label = p_label))::text, true);
  perform set_config('role', v_db_role::text, true);
  v_count := public.get_new_visitors_this_month();
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_count;
end;
$$;

-- Counts the members the actor can read whose first visit is this month, straight from the table, under RLS.
create function pg_temp.visits_seen_as(p_label text)
returns integer
language plpgsql
as $$
declare
  v_original name := current_user;
  v_db_role name := case p_label when 'anon' then 'anon' else 'authenticated' end;
  v_month_start date := (select month_start from clock);
  v_next_month_start date := (select next_month_start from clock);
  v_count integer;
begin
  perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', v_db_role, 'sub', (select staff_id from actors where label = p_label))::text, true);
  perform set_config('role', v_db_role::text, true);
  select count(*)::integer into v_count
  from public.members
  where members.first_visit_on >= v_month_start and members.first_visit_on < v_next_month_start;
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_count;
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

-- The function itself: its shape, its volatility and the grants that decide who may call it.

select function_returns('public', 'get_new_visitors_this_month', 'integer', 'should return a whole number');
select is((select provolatile::text from pg_proc where oid = 'public.get_new_visitors_this_month()'::regprocedure), 's', 'should be stable, since it is a read exposed as a GraphQL query');
select is((select prosecdef from pg_proc where oid = 'public.get_new_visitors_this_month()'::regprocedure), true, 'should run as security definer, because app roles cannot reach the private schema at run time');
select ok((select exists (select 1 from unnest(proconfig) as setting where setting like 'search_path=%') from pg_proc where oid = 'public.get_new_visitors_this_month()'::regprocedure), 'should pin search_path');
select isnt(obj_description('public.get_new_visitors_this_month()'::regprocedure, 'pg_proc'), null, 'should document the function in a comment');
select ok(has_function_privilege('authenticated', 'public.get_new_visitors_this_month()', 'EXECUTE'), 'should let authenticated users call the count');
select ok(not has_function_privilege('anon', 'public.get_new_visitors_this_month()', 'EXECUTE'), 'should not let anon call the count');
select ok(not has_function_privilege('anon', 'private.can_see_visitor_counts()', 'EXECUTE'), 'should not let anon run the role gate');
select ok(not has_function_privilege('authenticated', 'private.can_see_visitor_counts()', 'EXECUTE'), 'should keep the role gate out of reach of app roles');

-- The fixture: nine first visits fall in this month, counted by the table itself (both edges, archived, minors, unknown ages).

select is((select count(*)::integer from public.members, clock where members.first_visit_on >= clock.month_start and members.first_visit_on < clock.next_month_start), 9, 'should hold nine first visits in this month before any role reads them');

-- Allowed roles: super admin and pastor see every record, the secretary sees adults and the children of a ministry.

select is(pg_temp.count_as('super_admin', 'aal2'), 9, 'should count all nine this month for the super admin, minors and archived included');
select is(pg_temp.count_as('pastor', 'aal2'), 9, 'should count all nine this month for the pastor, who also sees archived records');
select is(pg_temp.count_as('secretary', 'aal2'), 7, 'should count seven for the secretary: no minor outside the ministry, no unknown age, archived adults and ministry children included');
select is(pg_temp.count_as('secretary', 'aal1'), 7, 'should count for the secretary at aal1, because the secretary role is not two-factor required');

-- Two-factor: the roles that require it are refused at aal1 (has_any_role counts them only at aal2).

select throws_ok($$select pg_temp.count_as('super_admin', 'aal1')$$, 'P0001', 'AUTH_FORBIDDEN', 'should refuse the super admin at aal1, since the role needs two-factor');
select throws_ok($$select pg_temp.count_as('pastor', 'aal1')$$, 'P0001', 'AUTH_FORBIDDEN', 'should refuse the pastor at aal1, since the role needs two-factor');

-- Denied roles: every other staff role, staff with no role, an inactive super admin, and anon.

select throws_ok($$select pg_temp.count_as('usher', 'aal2')$$, 'P0001', 'AUTH_FORBIDDEN', 'should refuse the usher');
select throws_ok($$select pg_temp.count_as('treasurer', 'aal2')$$, 'P0001', 'AUTH_FORBIDDEN', 'should refuse the treasurer');
select throws_ok($$select pg_temp.count_as('department_head', 'aal2')$$, 'P0001', 'AUTH_FORBIDDEN', 'should refuse a department head, even though they can read their own department');
select throws_ok($$select pg_temp.count_as('content_editor', 'aal2')$$, 'P0001', 'AUTH_FORBIDDEN', 'should refuse the content editor');
select throws_ok($$select pg_temp.count_as('no_role', 'aal2')$$, 'P0001', 'AUTH_FORBIDDEN', 'should refuse active staff who hold no role');
select throws_ok($$select pg_temp.count_as('inactive_super_admin', 'aal2')$$, 'P0001', 'AUTH_FORBIDDEN', 'should refuse an inactive super admin');
select throws_ok($$select pg_temp.count_as('anon', 'aal2')$$, '42501', null, 'should deny anon at the grant, before the function runs');

-- Status does not matter: a visitor who becomes active keeps the first visit date and still counts.

select lives_ok($$update public.members set status = 'active' where id = '60000000-0000-4000-8000-000000000001'$$, 'should let a fixture visitor be converted to active');
select is(pg_temp.count_as('super_admin', 'aal2'), 9, 'should still count a converted visitor whose first visit was this month');

-- The count never widens access: each role's number equals the rows that role can read from the table under RLS.

select is(pg_temp.visits_seen_as('secretary'), 7, 'should match the secretary''s visible rows, so the count adds no access');
select is(pg_temp.visits_seen_as('pastor'), 9, 'should match the pastor''s visible rows');
select is(pg_temp.visits_seen_as('super_admin'), 9, 'should match the super admin''s visible rows');

-- GraphQL: the operation the dashboard calls. Denied callers get the catalogued error through the API.

select is(pg_temp.graphql_as('secretary', '{ getNewVisitorsThisMonth }') #>> '{data,getNewVisitorsThisMonth}', '7', 'should return the secretary''s count through GraphQL');
select is(pg_temp.graphql_as('usher', '{ getNewVisitorsThisMonth }') #>> '{errors,0,message}', 'AUTH_FORBIDDEN', 'should refuse the usher through GraphQL with AUTH_FORBIDDEN');
select isnt(pg_temp.graphql_as('anon', '{ getNewVisitorsThisMonth }') -> 'errors', null, 'should offer no new visitor count to anon through GraphQL');

select * from finish();

rollback;
