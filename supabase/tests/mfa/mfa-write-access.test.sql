-- LBC-41 (AC 2, 3, 4): writes and business functions at aal1 and aal2. grant_role and revoke_role, direct writes
-- to staff, staff_roles, departments and members, the attendance functions, the content and sermon workflow and
-- log_audit_event all behave the same way: a super admin, pastor or treasurer is refused at aal1 and allowed at
-- aal2, every other role is unaffected, and a mixed user keeps only the role that needs no second factor.
-- Every actor runs through pg_temp.error_as(), which switches to the real database role with the JWT claims set
-- and returns 'ok <rows>' or '<sqlstate> <message>', so the exact failure is checked.

begin;

select plan(74);

-- Fixture: start from an empty model so the demo seed cannot influence the results.
set local session_replication_role = replica;
delete from public.content_items;
delete from public.sermons;
delete from public.attendance_checkins;
delete from public.attendance_counts;
delete from public.program_participants;
delete from public.services;
delete from public.programs;
delete from public.visitor_followups;
delete from public.member_departments;
delete from public.members;
delete from public.households;
delete from public.staff_roles;
delete from public.staff;
delete from public.departments;
set local session_replication_role = origin;

create temp table actors (label text primary key, staff_id uuid, is_active boolean not null default true);
create temp table actor_roles (label text not null, role public.app_role not null);

create function pg_temp.claims_for(p_label text, p_aal text)
returns text
language sql
as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'role', 'authenticated',
    'sub', (select staff_id from actors where label = p_label),
    'aal', p_aal
  ))::text;
$$;

create function pg_temp.run_as(p_label text, p_aal text, p_statement text)
returns bigint
language plpgsql
as $$
declare
  v_original name := current_user;
  v_rows bigint;
begin
  perform set_config('request.jwt.claims', pg_temp.claims_for(p_label, p_aal), true);
  perform set_config('role', 'authenticated', true);
  execute p_statement;
  get diagnostics v_rows = row_count;
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_rows;
end;
$$;

-- The failed statement is rolled back with its own role and claims settings, so the caller is never left as another role.
create function pg_temp.error_as(p_label text, p_aal text, p_statement text)
returns text
language plpgsql
as $$
begin
  return 'ok ' || pg_temp.run_as(p_label, p_aal, p_statement);
exception when others then
  return sqlstate || ' ' || sqlerrm;
end;
$$;

insert into actors (label)
values
  ('super_admin'), ('pastor'), ('treasurer'), ('secretary'), ('usher'), ('content_editor'),
  ('pastor_usher'), ('super_admin_secretary'), ('treasurer_content_editor'), ('no_role'), ('target');
insert into actors (label, is_active) values ('inactive_pastor', false);

insert into actor_roles (label, role)
values
  ('super_admin', 'super_admin'), ('pastor', 'pastor'), ('treasurer', 'treasurer'), ('secretary', 'secretary'),
  ('usher', 'usher'), ('content_editor', 'content_editor'),
  ('pastor_usher', 'pastor'), ('pastor_usher', 'usher'),
  ('super_admin_secretary', 'super_admin'), ('super_admin_secretary', 'secretary'),
  ('treasurer_content_editor', 'treasurer'), ('treasurer_content_editor', 'content_editor'),
  ('inactive_pastor', 'pastor');

update actors
set staff_id = ('e6000000-0000-4000-8000-' || lpad(numbered.position::text, 12, '0'))::uuid
from (select label, row_number() over (order by label) as position from actors) as numbered
where actors.label = numbered.label;

insert into auth.users (id, aud, role, email)
select staff_id, 'authenticated', 'authenticated', label || '@test.invalid' from actors;
insert into public.staff (id, full_name, is_active) select staff_id, label, is_active from actors;
insert into public.staff_roles (staff_id, role)
select actors.staff_id, actor_roles.role from actor_roles join actors using (label);

create function pg_temp.staff_id_of(p_label text)
returns uuid
language sql
as $$
  select staff_id from actors where label = p_label;
$$;

insert into public.members (id, first_name, last_name, date_of_birth, status)
values ('e7000000-0000-4000-8000-000000000001', 'MfaAdult', 'Test', '1980-01-01', 'active');

insert into public.services (id, name, type, starts_at)
values ('e8000000-0000-4000-8000-000000000001', 'MfaTestService', 'sunday', now() + interval '1 day');

-- Content in review, one item per approval attempt, because an approval changes the item.
insert into public.content_items (id, kind, title, status, author_id)
select ('e9000000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'announcement',
  'MfaItem' || n, case when n <= 4 then 'in_review' else 'draft' end::public.content_status, pg_temp.staff_id_of('content_editor')
from generate_series(1, 8) as n;

insert into public.content_items (id, kind, title, status, author_id)
values
  ('e9000000-0000-4000-8000-000000000020', 'announcement', 'MfaPastorDraft', 'draft', pg_temp.staff_id_of('pastor')),
  ('e9000000-0000-4000-8000-000000000021', 'announcement', 'MfaMixedDraft', 'draft', pg_temp.staff_id_of('treasurer_content_editor'));

insert into public.sermons (id, title, preacher, preached_on, status, author_id)
values
  ('ea000000-0000-4000-8000-000000000001', 'MfaSermonOne', 'Test Preacher', '2026-09-27', 'in_review', pg_temp.staff_id_of('content_editor')),
  ('ea000000-0000-4000-8000-000000000002', 'MfaSermonTwo', 'Test Preacher', '2026-09-27', 'in_review', pg_temp.staff_id_of('content_editor'));

create function pg_temp.call_as(p_label text, p_aal text, p_call text)
returns text
language sql
as $$
  select pg_temp.error_as(p_label, p_aal, 'select * from ' || p_call);
$$;

-- grant_role and revoke_role (super admin only).
select is(pg_temp.call_as('super_admin', 'aal1', format('public.grant_role(%L, ''usher'')', pg_temp.staff_id_of('no_role'))), 'P0001 AUTH_FORBIDDEN', 'should refuse grant_role to a super admin at aal1');
select is(pg_temp.call_as('super_admin_secretary', 'aal1', format('public.grant_role(%L, ''usher'')', pg_temp.staff_id_of('no_role'))), 'P0001 AUTH_FORBIDDEN', 'should refuse grant_role to a super admin who is also secretary at aal1');
select is((select count(*) from public.staff_roles where staff_id = pg_temp.staff_id_of('no_role')), 0::bigint, 'should have granted nothing at aal1');
select is(pg_temp.call_as('super_admin', 'aal2', format('public.grant_role(%L, ''usher'')', pg_temp.staff_id_of('no_role'))), 'ok 1', 'should allow grant_role to a super admin at aal2');
select is(pg_temp.call_as('super_admin', 'aal1', format('public.revoke_role(%L, ''usher'')', pg_temp.staff_id_of('no_role'))), 'P0001 AUTH_FORBIDDEN', 'should refuse revoke_role to a super admin at aal1');
select is((select count(*) from public.staff_roles where staff_id = pg_temp.staff_id_of('no_role')), 1::bigint, 'should have kept the role after the refused revoke at aal1');
select is(pg_temp.call_as('super_admin', 'aal2', format('public.revoke_role(%L, ''usher'')', pg_temp.staff_id_of('no_role'))), 'ok 1', 'should allow revoke_role to a super admin at aal2');
select is(pg_temp.call_as('secretary', 'aal2', format('public.grant_role(%L, ''usher'')', pg_temp.staff_id_of('no_role'))), 'P0001 AUTH_FORBIDDEN', 'should still refuse grant_role to a secretary');

-- Direct writes to the identity tables (super admin only).
select is(left(pg_temp.error_as('super_admin', 'aal1', format('insert into public.staff_roles (staff_id, role, granted_by) values (%L, ''usher'', %L)', pg_temp.staff_id_of('no_role'), pg_temp.staff_id_of('super_admin'))), 5), '42501', 'should refuse a direct staff_roles insert to a super admin at aal1');
select is(pg_temp.error_as('super_admin', 'aal2', format('insert into public.staff_roles (staff_id, role, granted_by) values (%L, ''usher'', %L)', pg_temp.staff_id_of('no_role'), pg_temp.staff_id_of('super_admin'))), 'ok 1', 'should allow a direct staff_roles insert to a super admin at aal2');
select is(pg_temp.error_as('super_admin', 'aal1', format('delete from public.staff_roles where staff_id = %L', pg_temp.staff_id_of('no_role'))), 'ok 0', 'should delete no staff_roles row for a super admin at aal1');
select is(pg_temp.error_as('super_admin', 'aal2', format('delete from public.staff_roles where staff_id = %L', pg_temp.staff_id_of('no_role'))), 'ok 1', 'should delete the staff_roles row for a super admin at aal2');
select is(pg_temp.error_as('super_admin', 'aal1', format('update public.staff set full_name = ''Changed'' where id = %L', pg_temp.staff_id_of('target'))), 'ok 0', 'should update no staff row for a super admin at aal1');
select is(pg_temp.error_as('super_admin', 'aal2', format('update public.staff set full_name = ''Changed'' where id = %L', pg_temp.staff_id_of('target'))), 'ok 1', 'should update the staff row for a super admin at aal2');
select is(left(pg_temp.error_as('super_admin', 'aal1', 'insert into public.departments (name) values (''MfaNewDepartment'')'), 5), '42501', 'should refuse a department insert to a super admin at aal1');
select is(pg_temp.error_as('super_admin', 'aal2', 'insert into public.departments (name) values (''MfaNewDepartment'')'), 'ok 1', 'should allow a department insert to a super admin at aal2');

-- Members (super admin, secretary).
select is(left(pg_temp.error_as('super_admin', 'aal1', 'insert into public.members (first_name, last_name, date_of_birth) values (''New'', ''Person'', ''1980-01-01'')'), 5), '42501', 'should refuse a member insert to a super admin at aal1');
select is(pg_temp.error_as('super_admin', 'aal2', 'insert into public.members (first_name, last_name, date_of_birth) values (''New'', ''Person'', ''1980-01-01'')'), 'ok 1', 'should allow a member insert to a super admin at aal2');
select is(pg_temp.error_as('secretary', 'aal1', 'insert into public.members (first_name, last_name, date_of_birth) values (''New'', ''Person'', ''1980-01-01'')'), 'ok 1', 'should allow a member insert to a secretary at aal1');
select is(pg_temp.error_as('super_admin_secretary', 'aal1', 'insert into public.members (first_name, last_name, date_of_birth) values (''New'', ''Person'', ''1980-01-01'')'), 'ok 1', 'should let a super admin who is also secretary insert an adult member at aal1 through the secretary role');
select is(left(pg_temp.error_as('super_admin_secretary', 'aal1', 'insert into public.members (first_name, last_name) values (''Unknown'', ''Age'')'), 5), '42501', 'should refuse that user a member with no birth date at aal1, which only super admin may write');
select is(pg_temp.error_as('super_admin_secretary', 'aal2', 'insert into public.members (first_name, last_name) values (''Unknown'', ''Age'')'), 'ok 1', 'should allow that user a member with no birth date at aal2');
select is(pg_temp.error_as('super_admin', 'aal1', 'update public.members set phone = ''+233200000001'' where first_name = ''MfaAdult'''), 'ok 0', 'should update no member for a super admin at aal1');
select is(pg_temp.error_as('super_admin', 'aal2', 'update public.members set phone = ''+233200000001'' where first_name = ''MfaAdult'''), 'ok 1', 'should update the member for a super admin at aal2');
select is(pg_temp.error_as('pastor', 'aal2', 'update public.members set phone = ''+233200000002'' where first_name = ''MfaAdult'''), 'ok 0', 'should still let a pastor write no member at aal2');

-- Attendance functions and check-ins (super admin, secretary, usher).
select is(pg_temp.call_as('super_admin', 'aal1', format('public.record_attendance_counts(%L, 1, 2, 3, 4)', 'e8000000-0000-4000-8000-000000000001')), 'P0001 AUTH_FORBIDDEN', 'should refuse record_attendance_counts to a super admin at aal1');
select is(pg_temp.call_as('super_admin', 'aal2', format('public.record_attendance_counts(%L, 1, 2, 3, 4)', 'e8000000-0000-4000-8000-000000000001')), 'ok 1', 'should allow record_attendance_counts to a super admin at aal2');
select is(pg_temp.call_as('usher', 'aal1', format('public.record_attendance_counts(%L, 5, 6, 7, 8)', 'e8000000-0000-4000-8000-000000000001')), 'ok 1', 'should allow record_attendance_counts to an usher at aal1');
select is(pg_temp.call_as('secretary', 'aal1', format('public.record_attendance_counts(%L, 5, 6, 7, 8)', 'e8000000-0000-4000-8000-000000000001')), 'ok 1', 'should allow record_attendance_counts to a secretary at aal1');
select is(pg_temp.call_as('super_admin_secretary', 'aal1', format('public.record_attendance_counts(%L, 9, 9, 9, 9)', 'e8000000-0000-4000-8000-000000000001')), 'ok 1', 'should let a super admin who is also secretary record attendance at aal1 through the secretary role');
select is(pg_temp.call_as('pastor_usher', 'aal1', format('public.record_attendance_counts(%L, 9, 9, 9, 9)', 'e8000000-0000-4000-8000-000000000001')), 'ok 1', 'should let a pastor who is also usher record attendance at aal1 through the usher role');
select is(pg_temp.call_as('treasurer', 'aal1', format('public.record_attendance_counts(%L, 9, 9, 9, 9)', 'e8000000-0000-4000-8000-000000000001')), 'P0001 AUTH_FORBIDDEN', 'should still refuse record_attendance_counts to a treasurer');
select is(
  pg_temp.call_as('super_admin', 'aal1', 'public.generate_recurring_services(''[{"name":"MfaMidweek","type":"midweek","weekday":3,"time":"08:00"}]''::jsonb, 1)'),
  'P0001 AUTH_FORBIDDEN', 'should refuse generate_recurring_services to a super admin at aal1');
select is(
  pg_temp.call_as('super_admin', 'aal2', 'public.generate_recurring_services(''[{"name":"MfaMidweek","type":"midweek","weekday":3,"time":"08:00"}]''::jsonb, 1)'),
  'ok 1', 'should allow generate_recurring_services to a super admin at aal2');
select is(
  pg_temp.error_as('usher', 'aal1', format('insert into public.attendance_checkins (service_id, member_id, checked_in_by) values (%L, %L, %L)', 'e8000000-0000-4000-8000-000000000001', 'e7000000-0000-4000-8000-000000000001', pg_temp.staff_id_of('usher'))),
  'ok 1', 'should allow a check-in to an usher at aal1');
select is(
  left(pg_temp.error_as('super_admin', 'aal1', format('insert into public.attendance_checkins (service_id, member_id, checked_in_by) values (%L, %L, %L)', 'e8000000-0000-4000-8000-000000000001', 'e7000000-0000-4000-8000-000000000001', pg_temp.staff_id_of('super_admin'))), 5),
  '42501', 'should refuse a check-in to a super admin at aal1');

-- Content workflow (approve: pastor and super admin; submit and publish: every content role).
select is(pg_temp.call_as('pastor', 'aal1', 'public.approve_content(''e9000000-0000-4000-8000-000000000001'')'), 'P0001 AUTH_FORBIDDEN', 'should refuse approve_content to a pastor at aal1');
select is((select status::text from public.content_items where id = 'e9000000-0000-4000-8000-000000000001'), 'in_review', 'should leave the item in review after the refused approval');
select is(pg_temp.call_as('pastor', 'aal2', 'public.approve_content(''e9000000-0000-4000-8000-000000000001'')'), 'ok 1', 'should allow approve_content to a pastor at aal2');
select is(pg_temp.call_as('super_admin', 'aal1', 'public.approve_content(''e9000000-0000-4000-8000-000000000002'')'), 'P0001 AUTH_FORBIDDEN', 'should refuse approve_content to a super admin at aal1');
select is(pg_temp.call_as('super_admin', 'aal2', 'public.approve_content(''e9000000-0000-4000-8000-000000000002'')'), 'ok 1', 'should allow approve_content to a super admin at aal2');
select is(pg_temp.call_as('treasurer_content_editor', 'aal1', 'public.approve_content(''e9000000-0000-4000-8000-000000000003'')'), 'P0001 AUTH_FORBIDDEN', 'should refuse approve_content to a treasurer who is also content editor');
select is(pg_temp.call_as('content_editor', 'aal2', 'public.approve_content(''e9000000-0000-4000-8000-000000000004'')'), 'P0001 AUTH_FORBIDDEN', 'should still refuse approve_content to a content editor');
select is(pg_temp.call_as('pastor', 'aal1', 'public.submit_content_for_review(''e9000000-0000-4000-8000-000000000020'')'), 'P0001 AUTH_FORBIDDEN', 'should refuse submit_content_for_review to a pastor at aal1');
select is(pg_temp.call_as('pastor', 'aal2', 'public.submit_content_for_review(''e9000000-0000-4000-8000-000000000020'')'), 'ok 1', 'should allow submit_content_for_review to a pastor at aal2');
select is(pg_temp.call_as('treasurer_content_editor', 'aal1', 'public.submit_content_for_review(''e9000000-0000-4000-8000-000000000021'')'), 'ok 1', 'should let a treasurer who is also content editor submit content at aal1 through the editor role');
select is(pg_temp.call_as('content_editor', 'aal1', 'public.submit_content_for_review(''e9000000-0000-4000-8000-000000000005'')'), 'ok 1', 'should allow submit_content_for_review to a content editor at aal1');
select is(pg_temp.call_as('super_admin', 'aal1', 'public.archive_content(''e9000000-0000-4000-8000-000000000006'')'), 'P0001 AUTH_FORBIDDEN', 'should refuse archive_content to a super admin at aal1');
select is(pg_temp.call_as('super_admin', 'aal2', 'public.archive_content(''e9000000-0000-4000-8000-000000000006'')'), 'ok 1', 'should allow archive_content to a super admin at aal2');
select is(left(pg_temp.error_as('pastor', 'aal1', format('insert into public.content_items (kind, title, author_id) values (''announcement'', ''MfaNew'', %L)', pg_temp.staff_id_of('pastor'))), 5), '42501', 'should refuse a content insert to a pastor at aal1');
select is(pg_temp.error_as('pastor', 'aal2', format('insert into public.content_items (kind, title, author_id) values (''announcement'', ''MfaNew'', %L)', pg_temp.staff_id_of('pastor'))), 'ok 1', 'should allow a content insert to a pastor at aal2');
select is(pg_temp.call_as('pastor', 'aal1', 'public.approve_sermon(''ea000000-0000-4000-8000-000000000001'')'), 'P0001 AUTH_FORBIDDEN', 'should refuse approve_sermon to a pastor at aal1');
select is(pg_temp.call_as('pastor', 'aal2', 'public.approve_sermon(''ea000000-0000-4000-8000-000000000001'')'), 'ok 1', 'should allow approve_sermon to a pastor at aal2');
select is(pg_temp.call_as('super_admin', 'aal1', 'public.approve_sermon(''ea000000-0000-4000-8000-000000000002'')'), 'P0001 AUTH_FORBIDDEN', 'should refuse approve_sermon to a super admin at aal1');

-- log_audit_event: staff who hold a two-factor role need aal2, other active staff do not.
create temp table expected_audit_events (label text not null, aal text not null, expected text not null, primary key (label, aal));
insert into expected_audit_events
values
  ('super_admin', 'aal1', 'P0001 AUTH_FORBIDDEN'), ('super_admin', 'aal2', 'ok 1'),
  ('pastor', 'aal1', 'P0001 AUTH_FORBIDDEN'), ('pastor', 'aal2', 'ok 1'),
  ('treasurer', 'aal1', 'P0001 AUTH_FORBIDDEN'), ('treasurer', 'aal2', 'ok 1'),
  ('secretary', 'aal1', 'ok 1'), ('secretary', 'aal2', 'ok 1'),
  ('usher', 'aal1', 'ok 1'), ('usher', 'aal2', 'ok 1'),
  ('no_role', 'aal1', 'ok 1'), ('no_role', 'aal2', 'ok 1'),
  ('pastor_usher', 'aal1', 'P0001 AUTH_FORBIDDEN'), ('pastor_usher', 'aal2', 'ok 1'),
  ('treasurer_content_editor', 'aal1', 'P0001 AUTH_FORBIDDEN'), ('treasurer_content_editor', 'aal2', 'ok 1'),
  ('inactive_pastor', 'aal1', 'P0001 AUTH_FORBIDDEN'), ('inactive_pastor', 'aal2', 'P0001 AUTH_FORBIDDEN');

select is(
  pg_temp.call_as(label, aal, 'public.log_audit_event(''LOGIN'', ''staff'')'),
  expected,
  format('should give %s at %s the result %s for a LOGIN event', label, aal, expected)
) from expected_audit_events order by label, aal;

select is(
  (select count(*) from audit.log where action = 'LOGIN' and actor_id in (select staff_id from actors)),
  (select count(*) from expected_audit_events where expected = 'ok 1'),
  'should have written exactly one LOGIN audit row for each allowed call and none for a refused one'
);

select is(pg_temp.call_as('pastor', 'aal1', 'public.log_audit_event(''EXPORT'', ''members'')'), 'P0001 AUTH_FORBIDDEN', 'should refuse an EXPORT event to a pastor at aal1');

select * from finish();

rollback;
