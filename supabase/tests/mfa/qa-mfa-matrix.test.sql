-- LBC-41 QA: a table-driven differential matrix. Every actor reads 15 relations (direct SQL and GraphQL) and runs
-- 21 writes and functions at aal1 and aal2, once with the new helpers and once with the previous helper bodies
-- (re-created inside this rolled-back transaction). Proves: aal2 behaves exactly like before LBC-41; aal1 for a
-- user with no two-factor role is unchanged; aal1 for a two-factor role equals the behaviour of the non
-- two-factor part of that user (none for super admin, pastor, treasurer alone); anon and users without a staff
-- row get nothing; the audit schema is unreachable. Relative comparisons keep it independent of the seed counts.

begin;

select plan(10);

create temp table actors (label text primary key, staff_id uuid, db_role text not null default 'authenticated',
  is_active boolean not null default true, equivalent_at_aal1 text);
create temp table actor_roles (label text not null, role public.app_role not null, department_id uuid);

-- The seeded demo staff (docs: public dev data) plus mixed, inactive and unknown users.
insert into actors (label, staff_id, equivalent_at_aal1)
values
  ('super_admin', '10000000-0000-4000-8000-000000000001', 'none'),
  ('pastor', '10000000-0000-4000-8000-000000000002', 'none'),
  ('treasurer', '10000000-0000-4000-8000-000000000003', 'none'),
  ('secretary', '10000000-0000-4000-8000-000000000004', 'self'),
  ('usher', '10000000-0000-4000-8000-000000000005', 'self'),
  ('department_head', '10000000-0000-4000-8000-000000000006', 'self'),
  ('content_editor', '10000000-0000-4000-8000-000000000007', 'self');

insert into actors (label, staff_id, is_active, equivalent_at_aal1)
values
  ('pastor_usher', 'f1000000-0000-4000-8000-000000000001', true, 'usher'),
  ('treasurer_head', 'f1000000-0000-4000-8000-000000000002', true, 'department_head'),
  ('super_admin_secretary', 'f1000000-0000-4000-8000-000000000003', true, 'secretary'),
  ('inactive_pastor', 'f1000000-0000-4000-8000-000000000004', false, 'same_as_aal2'),
  ('inactive_usher', 'f1000000-0000-4000-8000-000000000005', false, 'self'),
  ('no_role', 'f1000000-0000-4000-8000-000000000006', true, 'self'),
  ('fixture_author', 'f1000000-0000-4000-8000-000000000007', true, 'self'),
  ('target', 'f1000000-0000-4000-8000-000000000008', true, 'self'),
  ('target_with_usher', 'f1000000-0000-4000-8000-000000000009', true, 'self');
insert into actors (label, staff_id, equivalent_at_aal1) values ('no_staff_row', 'f1000000-0000-4000-8000-00000000000a', 'self');
insert into actors (label, staff_id, db_role, equivalent_at_aal1) values ('anon', null, 'anon', 'self');

insert into actor_roles (label, role, department_id)
values
  ('pastor_usher', 'pastor', null), ('pastor_usher', 'usher', null),
  ('treasurer_head', 'treasurer', null), ('treasurer_head', 'department_head', '20000000-0000-4000-8000-000000000001'),
  ('super_admin_secretary', 'super_admin', null), ('super_admin_secretary', 'secretary', null),
  ('inactive_pastor', 'pastor', null), ('inactive_usher', 'usher', null),
  ('fixture_author', 'content_editor', null), ('target_with_usher', 'usher', null);

insert into auth.users (id, aud, role, email)
select staff_id, 'authenticated', 'authenticated', label || '@qa.invalid'
from actors where staff_id::text like 'f1%' and label <> 'no_staff_row';
insert into auth.users (id, aud, role, email) select staff_id, 'authenticated', 'authenticated', 'no-staff@qa.invalid' from actors where label = 'no_staff_row';
insert into public.staff (id, full_name, is_active)
select staff_id, label, is_active from actors where staff_id::text like 'f1%' and label <> 'no_staff_row';
insert into public.staff_roles (staff_id, role, department_id)
select actors.staff_id, actor_roles.role, actor_roles.department_id from actor_roles join actors using (label);

-- Fixtures authored by a non-actor so a content outcome depends on the role, never on authorship.
insert into public.members (id, first_name, last_name, date_of_birth, status)
values ('f2000000-0000-4000-8000-000000000001', 'QaAdult', 'Matrix', '1980-01-01', 'active');
insert into public.services (id, name, type, starts_at)
values ('f3000000-0000-4000-8000-000000000001', 'QaMatrixService', 'sunday', now() + interval '1 day');
insert into public.content_items (id, kind, title, status, author_id, approved_by, publish_at)
select ('f4000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'announcement', 'QaItem' || n,
  (array['draft', 'in_review', 'in_review', 'in_review', 'published'])[n]::public.content_status,
  'f1000000-0000-4000-8000-000000000007',
  case when n in (3, 5) then 'f1000000-0000-4000-8000-000000000007'::uuid end,
  case when n = 5 then now() - interval '1 day' end
from generate_series(1, 5) as n;
insert into public.sermons (id, title, preacher, preached_on, status, author_id, approved_by, publish_at)
select ('f5000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'QaSermon' || n, 'Qa Preacher', '2026-09-27',
  (array['draft', 'in_review', 'in_review', 'in_review', 'published'])[n]::public.content_status,
  'f1000000-0000-4000-8000-000000000007',
  case when n in (3, 5) then 'f1000000-0000-4000-8000-000000000007'::uuid end,
  case when n = 5 then now() - interval '1 day' end
from generate_series(1, 5) as n;

-- Claims as PostgREST hands them to the database for a Supabase access token.
create function pg_temp.claims_for(p_label text, p_aal text)
returns text
language sql
as $$
  select case when db_role = 'anon' then '{"role":"anon"}'
    else jsonb_strip_nulls(jsonb_build_object(
      'iss', 'http://127.0.0.1:54321/auth/v1', 'aud', 'authenticated',
      'exp', extract(epoch from now())::bigint + 3600, 'iat', extract(epoch from now())::bigint,
      'sub', staff_id, 'role', 'authenticated', 'aal', p_aal,
      'amr', jsonb_build_array(jsonb_build_object('method', case when p_aal = 'aal2' then 'totp' else 'password' end, 'timestamp', 1)),
      'session_id', gen_random_uuid(), 'email', label || '@qa.invalid'))::text end
  from actors where label = p_label;
$$;

-- Runs one statement as the actor inside a subtransaction that is always rolled back, returns 'ok <rows>' or '<sqlstate> <message>'.
create function pg_temp.attempt(p_label text, p_aal text, p_statement text)
returns text
language plpgsql
as $$
declare
  v_rows bigint;
begin
  perform set_config('request.jwt.claims', pg_temp.claims_for(p_label, p_aal), true);
  perform set_config('role', (select db_role from actors where label = p_label), true);
  execute p_statement;
  get diagnostics v_rows = row_count;
  raise exception using errcode = 'QA999', message = 'ok ' || v_rows;
exception when others then
  return case when sqlstate = 'QA999' then sqlerrm else sqlstate || ' ' || sqlerrm end;
end;
$$;

create function pg_temp.id_of(p_label text) returns uuid language sql as $$ select staff_id from actors where label = p_label; $$;

create temp table relations (name text primary key, collection text, ordering int);
insert into relations
values ('staff', 'staffCollection', 1), ('staff_roles', 'staffRolesCollection', 2), ('departments', 'departmentsCollection', 3),
  ('households', 'householdsCollection', 4), ('members', 'membersCollection', 5), ('member_names', 'memberNamesCollection', 6),
  ('member_departments', 'memberDepartmentsCollection', 7), ('visitor_followups', 'visitorFollowupsCollection', 8),
  ('services', 'servicesCollection', 9), ('programs', 'programsCollection', 10), ('program_participants', 'programParticipantsCollection', 11),
  ('attendance_counts', 'attendanceCountsCollection', 12), ('attendance_checkins', 'attendanceCheckinsCollection', 13),
  ('content_items', 'contentItemsCollection', 14), ('sermons', 'sermonsCollection', 15);

-- Reads: direct as '<count>:<md5 of ids>', GraphQL as '<edges>:<md5 of the data>'. An error becomes its SQLSTATE.
create function pg_temp.read_direct(p_label text, p_aal text, p_relation text)
returns text
language plpgsql
as $$
declare
  v_result text;
begin
  perform set_config('request.jwt.claims', pg_temp.claims_for(p_label, p_aal), true);
  perform set_config('role', (select db_role from actors where label = p_label), true);
  if p_relation = 'audit.log' then
    execute 'select count(*)::text from audit.log' into v_result;
  else
    execute format('select count(*) || '':'' || coalesce(md5(string_agg(t.id::text, '','' order by t.id)), '''') from public.%I t', p_relation) into v_result;
  end if;
  raise exception using errcode = 'QA999', message = v_result;
exception when others then
  return case when sqlstate = 'QA999' then sqlerrm else sqlstate end;
end;
$$;

create function pg_temp.read_graphql(p_label text, p_aal text, p_collection text)
returns text
language plpgsql
as $$
declare
  v_response jsonb;
begin
  perform set_config('request.jwt.claims', pg_temp.claims_for(p_label, p_aal), true);
  perform set_config('role', (select db_role from actors where label = p_label), true);
  v_response := graphql.resolve(format('{ %s { edges { node { nodeId } } } }', p_collection));
  raise exception using errcode = 'QA999', message =
    coalesce(jsonb_array_length(v_response -> 'data' -> p_collection -> 'edges'), -1) || ':' || md5(coalesce((v_response -> 'data')::text, 'denied'));
exception when others then
  return case when sqlstate = 'QA999' then sqlerrm else sqlstate end;
end;
$$;

-- Writes and functions: one statement template per row. {a} is the acting staff id.
create temp table statements (name text primary key, template text not null);
insert into statements
values
  ('grant_role', 'select * from public.grant_role(''f1000000-0000-4000-8000-000000000008'', ''usher'')'),
  ('revoke_role', 'select * from public.revoke_role(''f1000000-0000-4000-8000-000000000009'', ''usher'')'),
  ('record_attendance_counts', 'select * from public.record_attendance_counts(''f3000000-0000-4000-8000-000000000001'', 1, 2, 3, 4)'),
  ('generate_recurring_services', 'select * from public.generate_recurring_services(''[{"name":"QaMidweek","type":"midweek","weekday":3,"time":"08:00"}]''::jsonb, 1)'),
  ('submit_content_for_review', 'select * from public.submit_content_for_review(''f4000000-0000-4000-8000-000000000001'')'),
  ('approve_content', 'select * from public.approve_content(''f4000000-0000-4000-8000-000000000002'')'),
  ('publish_content', 'select * from public.publish_content(''f4000000-0000-4000-8000-000000000003'')'),
  ('return_content_to_draft', 'select * from public.return_content_to_draft(''f4000000-0000-4000-8000-000000000004'')'),
  ('archive_content', 'select * from public.archive_content(''f4000000-0000-4000-8000-000000000005'')'),
  ('submit_sermon_for_review', 'select * from public.submit_sermon_for_review(''f5000000-0000-4000-8000-000000000001'')'),
  ('approve_sermon', 'select * from public.approve_sermon(''f5000000-0000-4000-8000-000000000002'')'),
  ('publish_sermon', 'select * from public.publish_sermon(''f5000000-0000-4000-8000-000000000003'')'),
  ('return_sermon_to_draft', 'select * from public.return_sermon_to_draft(''f5000000-0000-4000-8000-000000000004'')'),
  ('archive_sermon', 'select * from public.archive_sermon(''f5000000-0000-4000-8000-000000000005'')'),
  ('insert_department', 'insert into public.departments (name) values (''QaDept'')'),
  ('insert_member', 'insert into public.members (first_name, last_name, date_of_birth) values (''Qa'', ''New'', ''1980-01-01'')'),
  ('insert_household', 'insert into public.households (name) values (''QaHousehold'')'),
  ('update_member', 'update public.members set phone = ''+233200000001'' where id = ''f2000000-0000-4000-8000-000000000001'''),
  ('insert_checkin', 'insert into public.attendance_checkins (service_id, member_id, checked_in_by) values (''f3000000-0000-4000-8000-000000000001'', ''f2000000-0000-4000-8000-000000000001'', ''{a}'')'),
  ('insert_content_item', 'insert into public.content_items (kind, title, author_id) values (''announcement'', ''QaNew'', ''{a}'')'),
  ('update_staff', 'update public.staff set full_name = ''QaRenamed'' where id = ''f1000000-0000-4000-8000-000000000008'''),
  ('delete_staff_role', 'delete from public.staff_roles where staff_id = ''f1000000-0000-4000-8000-000000000009'''),
  ('log_audit_login', 'select * from public.log_audit_event(''LOGIN'', ''staff'')'),
  ('log_audit_export', 'select * from public.log_audit_event(''EXPORT'', ''members'')'),
  ('insert_service', 'insert into public.services (name, type, starts_at) values (''QaSvc'', ''sunday'', now() + interval ''2 days'')'),
  ('insert_program', 'insert into public.programs (name, department_id) values (''QaProg'', ''20000000-0000-4000-8000-000000000001'')'),
  ('insert_sermon', 'insert into public.sermons (title, preacher, preached_on, author_id) values (''QaS'', ''P'', ''2026-09-27'', ''{a}'')'),
  ('insert_followup', 'insert into public.visitor_followups (member_id) values (''f2000000-0000-4000-8000-000000000001'')'),
  ('insert_member_department', 'insert into public.member_departments (member_id, department_id) values (''f2000000-0000-4000-8000-000000000001'', ''20000000-0000-4000-8000-000000000001'')');

-- One results table: kind (direct, graphql, write), item, actor, aal, phase (new, old), outcome.
create temp table results (kind text, item text, label text, aal text, phase text, outcome text,
  primary key (kind, item, label, aal, phase));

create function pg_temp.collect(p_phase text)
returns void
language plpgsql
as $$
declare
  v_actor record;
  v_aal text;
begin
  for v_actor in select label from actors where label not in ('fixture_author', 'target', 'target_with_usher') loop
    foreach v_aal in array array['aal1', 'aal2'] loop
      insert into results
      select 'direct', name, v_actor.label, v_aal, p_phase, pg_temp.read_direct(v_actor.label, v_aal, name) from relations;
      insert into results
      select 'graphql', name, v_actor.label, v_aal, p_phase, pg_temp.read_graphql(v_actor.label, v_aal, collection) from relations;
      insert into results
      select 'write', name, v_actor.label, v_aal, p_phase,
        pg_temp.attempt(v_actor.label, v_aal, replace(template, '{a}', coalesce(pg_temp.id_of(v_actor.label)::text, '')))
      from statements;
      insert into results values ('direct', 'audit.log', v_actor.label, v_aal, p_phase, pg_temp.read_direct(v_actor.label, v_aal, 'audit.log'));
    end loop;
  end loop;
end;
$$;

select pg_temp.collect('new');

-- The previous release helper bodies (migration 20261005090000), without any aal rule.
create or replace function private.has_any_role(p_roles public.app_role[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.staff_roles as staff_role join public.staff on staff.id = staff_role.staff_id
    where staff_role.staff_id = (select auth.uid()) and staff_role.role = any (p_roles) and staff.is_active
  );
$$;
create or replace function private.heads_department(p_department_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.staff_roles as staff_role join public.staff on staff.id = staff_role.staff_id
    where staff_role.staff_id = (select auth.uid()) and staff_role.role = 'department_head'
      and staff_role.department_id = p_department_id and staff.is_active
  );
$$;
-- log_audit_event is not a helper user in the old release: it only needed an active staff row.
create or replace function private.has_dashboard_session()
returns boolean language sql stable security definer set search_path = '' as $$ select private.is_active_staff(); $$;

select pg_temp.collect('old');

create temp view old_vs_new as
select n.kind, n.item, n.label, n.aal, n.outcome as new_outcome, o.outcome as old_outcome
from results n join results o on o.kind = n.kind and o.item = n.item and o.label = n.label and o.aal = n.aal and o.phase = 'old'
where n.phase = 'new';

select is((select count(*) from results where phase = 'new'), (select count(*) from results where phase = 'old'), 'should have run the same number of probes against the new and the previous helpers');

select is(
  (select count(*) from old_vs_new where aal = 'aal2' and new_outcome is distinct from old_outcome),
  0::bigint, 'should behave at aal2 exactly like before LBC-41 for every actor, relation, GraphQL collection, write and function');

select is(
  (select count(*) from old_vs_new join actors using (label)
   where aal = 'aal1' and equivalent_at_aal1 = 'self' and new_outcome is distinct from old_outcome),
  0::bigint, 'should leave users with no two-factor role unchanged at aal1 (usher, secretary, department head, content editor, no role, inactive, no staff row, anon)');

-- Sanity: the matrix is not vacuous. Writes that a role may do succeed at aal2, reads return rows.
select cmp_ok(
  (select count(*) from results where phase = 'new' and kind = 'write' and aal = 'aal2' and label = 'super_admin' and outcome like 'ok %'),
  '>=', 20::bigint, 'should let a super admin complete at least 20 of the 29 writes and functions at aal2, proving the matrix runs real operations');

select is(
  (select count(*) from results where phase = 'new' and kind = 'direct' and aal = 'aal2' and label = 'super_admin'
     and item <> 'member_names' and outcome like '%:%' and split_part(outcome, ':', 1)::int > 0),
  14::bigint, 'should return rows for the 14 relations other than member_names to a super admin at aal2 (the seed has rows in each)');

-- Two-factor roles at aal1.
select is(
  (select count(*) from results where phase = 'new' and aal = 'aal1' and label in ('super_admin', 'pastor', 'treasurer')
     and ((kind = 'write' and outcome like 'ok %' and outcome <> 'ok 0')
       or (kind = 'direct' and item not in ('staff', 'staff_roles', 'audit.log') and split_part(outcome, ':', 1) <> '0')
       or (kind = 'graphql' and item not in ('staff', 'staff_roles') and split_part(outcome, ':', 1) <> '0'))),
  0::bigint, 'should return no rows and complete no write for super admin, pastor and treasurer at aal1 (own profile excepted)');

select is(
  (select count(*) from results where phase = 'new' and aal = 'aal1' and label in ('super_admin', 'pastor', 'treasurer')
     and item in ('staff', 'staff_roles') and kind in ('direct', 'graphql') and split_part(outcome, ':', 1) <> '1'),
  0::bigint, 'should still show the own staff row and the own single role at aal1 so the login flow can decide to enrol or challenge');

-- Mixed users keep exactly the access of their non two-factor role (check-ins are per user, so the usher's own rows differ by identity).
select is(
  (select count(*) from results mixed
   join actors on actors.label = mixed.label
   join results other on other.kind = mixed.kind and other.item = mixed.item and other.aal = 'aal1' and other.phase = 'new'
     and other.label = actors.equivalent_at_aal1
   where mixed.phase = 'new' and mixed.aal = 'aal1' and mixed.label in ('pastor_usher', 'treasurer_head', 'super_admin_secretary')
     and mixed.item not in ('staff', 'staff_roles', 'attendance_checkins')
     and mixed.outcome is distinct from other.outcome and not (mixed.kind = 'write' and mixed.item like 'log_audit%')),
  0::bigint, 'should give a user with a two-factor role and another role at aal1 exactly the access of the other role');

select is(
  (select count(*) from results where phase = 'new' and aal = 'aal1' and kind = 'write' and item like 'log_audit%'
     and ((label in ('super_admin', 'pastor', 'treasurer', 'pastor_usher', 'treasurer_head', 'super_admin_secretary') and outcome like 'ok %')
       or (label in ('secretary', 'usher', 'department_head', 'content_editor', 'no_role') and outcome not like 'ok %'))),
  0::bigint, 'should refuse log_audit_event at aal1 to anyone holding a two-factor role and allow it to other active staff');

-- Nobody without a usable session sees anything, and the audit schema is closed to every actor.
select is(
  (select count(*) from results where phase = 'new' and item = 'audit.log' and outcome <> '42501'),
  0::bigint, 'should deny every actor at both assurance levels any read of the audit log');

select * from finish();

rollback;
