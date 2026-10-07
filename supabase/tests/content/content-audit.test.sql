-- LBC-33 (CLAUDE.md rule 4): every change to content_items and sermons leaves an audit.log row with the right actor,
-- table, action and exact changed fields, including status changes made by the workflow functions; refused
-- statements leave nothing; the trigger still fires when session_replication_role is replica. Within this test every
-- statement runs at one transaction time, so updated_at is listed as changed only by the first update of a row whose
-- stored updated_at lies in the past. Fixture and actors: see the preamble.

begin;

select plan(13);

-- Fixture: start from an empty identity and content model so the demo seed cannot influence the results.
set local session_replication_role = replica;
delete from public.content_items;
delete from public.sermons;
delete from public.staff_roles;
delete from public.staff;
set local session_replication_role = origin;

-- Runs statements as a real database role with the JWT claims set, so RLS and grants are exercised.
-- The label picks the staff member; 'anon' is the signed-out role.
create temp table actors (label text primary key, staff_id uuid, is_active boolean not null default true);
create temp table actor_roles (label text not null, role public.app_role not null, department_id uuid);

-- Executes one statement as the actor and returns the row count.
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

-- Executes one statement as the actor and returns 'ok <rows>' or '<sqlstate> <message>' when it fails. The failed
-- statement is rolled back with its own role and claims settings, so the caller is never left as another role.
create function pg_temp.error_as(p_label text, p_statement text)
returns text
language plpgsql
as $$
begin
  return 'ok ' || pg_temp.run_as(p_label, p_statement);
exception when others then
  return sqlstate || ' ' || sqlerrm;
end;
$$;

-- The titles of one table the actor can read, sorted and comma separated.
create function pg_temp.titles_as(p_label text, p_relation text)
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
  execute format('select coalesce(string_agg(title, %L order by title), %L) from public.%I', ',', '', p_relation) into v_seen;
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

-- One actor per role, a second pastor and content editor, a secretary, staff with no role, a user with no staff
-- profile, deactivated staff, and anon.
insert into public.departments (id, name, is_childrens_ministry)
values ('d1000000-0000-4000-8000-000000000001', 'ContentTestDepartment', false);

insert into actors (label)
values
  ('super_admin'), ('pastor'), ('pastor_two'), ('treasurer'), ('secretary'), ('usher'), ('department_head'),
  ('content_editor'), ('content_editor_two'), ('no_role'), ('no_staff');

insert into actor_roles (label, role, department_id)
values
  ('super_admin', 'super_admin', null),
  ('pastor', 'pastor', null),
  ('pastor_two', 'pastor', null),
  ('treasurer', 'treasurer', null),
  ('secretary', 'secretary', null),
  ('usher', 'usher', null),
  ('department_head', 'department_head', 'd1000000-0000-4000-8000-000000000001'),
  ('content_editor', 'content_editor', null),
  ('content_editor_two', 'content_editor', null);

insert into actors (label, is_active)
select 'inactive_' || label, false
from actors
where label in ('super_admin', 'pastor', 'secretary', 'content_editor');

insert into actor_roles (label, role, department_id)
select 'inactive_' || label, role, department_id
from actor_roles
where 'inactive_' || label in (select label from actors);

insert into actors (label, is_active) values ('anon', true);

update actors
set staff_id = ('d2000000-0000-4000-8000-' || lpad(numbered.position::text, 12, '0'))::uuid
from (select label, row_number() over (order by label) as position from actors where label <> 'anon') as numbered
where actors.label = numbered.label;

insert into auth.users (id, aud, role, email)
select staff_id, 'authenticated', 'authenticated', label || '@test.invalid' from actors where label <> 'anon';

insert into public.staff (id, full_name, is_active)
select staff_id, label, is_active from actors where label not in ('anon', 'no_staff');

insert into public.staff_roles (staff_id, role, department_id)
select actors.staff_id, actor_roles.role, actor_roles.department_id
from actor_roles
join actors using (label);

create function pg_temp.staff_id_of(p_label text)
returns uuid
language sql
as $$
  select staff_id from actors where label = p_label;
$$;

-- Content items (c1...01 to 13), keyed by title. The test starts at transaction time, so now() is fixed for the file.
-- Public to anon: live_announcement, publish_at_now, no_expiry, history_page. Hidden: everything else.
insert into public.content_items (id, kind, slug, title, body, status, publish_at, expires_at, author_id, approved_by)
select ids.id, ids.kind::public.content_kind, ids.slug, ids.title, 'Body of ' || ids.title, ids.status::public.content_status,
  ids.publish_at, ids.expires_at, pg_temp.staff_id_of(ids.author),
  case when ids.is_approved then pg_temp.staff_id_of('pastor') end
from (values
  ('c1100000-0000-4000-8000-000000000001'::uuid, 'announcement', null, 'live_announcement', 'published', now() - interval '1 day', now() + interval '1 day', 'content_editor', true),
  ('c1100000-0000-4000-8000-000000000002', 'announcement', null, 'draft_item', 'draft', null, null, 'content_editor', false),
  ('c1100000-0000-4000-8000-000000000003', 'announcement', null, 'in_review_item', 'in_review', null, null, 'content_editor', false),
  ('c1100000-0000-4000-8000-000000000004', 'announcement', null, 'scheduled_future', 'published', now() + interval '1 day', null, 'content_editor', true),
  ('c1100000-0000-4000-8000-000000000005', 'announcement', null, 'expired_item', 'published', now() - interval '2 days', now() - interval '1 day', 'content_editor', true),
  ('c1100000-0000-4000-8000-000000000006', 'announcement', null, 'archived_item', 'archived', now() - interval '3 days', null, 'content_editor', true),
  ('c1100000-0000-4000-8000-000000000007', 'quote', null, 'publish_at_now', 'published', now(), null, 'content_editor', true),
  ('c1100000-0000-4000-8000-000000000008', 'announcement', null, 'expires_at_now', 'published', now() - interval '1 day', now(), 'content_editor', true),
  ('c1100000-0000-4000-8000-000000000009', 'announcement', null, 'no_expiry', 'published', now() - interval '1 day', null, 'content_editor', true),
  ('c1100000-0000-4000-8000-000000000010', 'page', 'history', 'history_page', 'published', now() - interval '1 day', null, 'content_editor', true),
  ('c1100000-0000-4000-8000-000000000011', 'announcement', null, 'draft_of_editor_two', 'draft', null, null, 'content_editor_two', false),
  ('c1100000-0000-4000-8000-000000000012', 'announcement', null, 'approved_in_review', 'in_review', null, null, 'content_editor', true),
  ('c1100000-0000-4000-8000-000000000013', 'announcement', null, 'draft_of_secretary', 'draft', null, null, 'secretary', false)
) as ids (id, kind, slug, title, status, publish_at, expires_at, author, is_approved);

-- Sermons (c2...01 to 06), keyed by title. Public to anon: live_sermon, sermon_publish_at_now.
insert into public.sermons (id, title, preacher, preached_on, status, publish_at, author_id, approved_by)
select ids.id, ids.title, 'Test Preacher', '2026-09-27', ids.status::public.content_status, ids.publish_at,
  pg_temp.staff_id_of('content_editor'), case when ids.is_approved then pg_temp.staff_id_of('pastor') end
from (values
  ('c2100000-0000-4000-8000-000000000001'::uuid, 'live_sermon', 'published', now() - interval '1 day', true),
  ('c2100000-0000-4000-8000-000000000002', 'draft_sermon', 'draft', null, false),
  ('c2100000-0000-4000-8000-000000000003', 'in_review_sermon', 'in_review', null, false),
  ('c2100000-0000-4000-8000-000000000004', 'scheduled_sermon', 'published', now() + interval '1 day', true),
  ('c2100000-0000-4000-8000-000000000005', 'archived_sermon', 'archived', now() - interval '3 days', true),
  ('c2100000-0000-4000-8000-000000000006', 'sermon_publish_at_now', 'published', now(), true)
) as ids (id, title, status, publish_at, is_approved);

-- One line per audit row of a record: action, who (system when there is no signed-in user) and the changed fields.
create function pg_temp.audit_trail(p_table text, p_id uuid)
returns text
language sql
as $$
  select string_agg(
    audit_log.action || ' ' || coalesce((select label from actors where staff_id = audit_log.actor_id), 'system') || ' ' || coalesce(array_to_string(audit_log.changed_fields, '+'), '-'),
    ' | ' order by audit_log.id)
  from audit.log as audit_log
  where audit_log.table_name = p_table and audit_log.record_id = p_id;
$$;

create function pg_temp.call_as(p_label text, p_function text, p_id uuid)
returns text
language sql
as $$
  select pg_temp.error_as(p_label, format('select * from public.%I(%L)', p_function, p_id));
$$;

create function pg_temp.step_as(p_label text, p_function text, p_id uuid)
returns void
language plpgsql
as $$
begin
  perform pg_temp.call_as(p_label, p_function, p_id);
end;
$$;


create function pg_temp.step_error_as(p_label text, p_statement text)
returns void
language plpgsql
as $$
begin
  perform pg_temp.error_as(p_label, p_statement);
end;
$$;

create function pg_temp.step_run_as(p_label text, p_statement text)
returns void
language plpgsql
as $$
begin
  perform pg_temp.run_as(p_label, p_statement);
end;
$$;

-- Item A is created by the editor through the table, item B by the owner with timestamps in the past
create function pg_temp.insert_as_editor()
returns void
language plpgsql
as $$
begin
  perform pg_temp.run_as('content_editor', format($sql$insert into public.content_items (kind, title, author_id) values ('announcement', 'audited_by_editor', %L)$sql$, pg_temp.staff_id_of('content_editor')));
end;
$$;
select pg_temp.insert_as_editor();

insert into public.content_items (id, kind, title, author_id, created_at, updated_at)
values ('c1900000-0000-4000-8000-000000000001', 'announcement', 'audited_flow', pg_temp.staff_id_of('content_editor'), now() - interval '1 day', now() - interval '1 day');
insert into public.sermons (id, title, preacher, preached_on, author_id, created_at, updated_at)
values ('c2900000-0000-4000-8000-000000000001', 'audited_sermon', 'Preacher', '2026-10-04', pg_temp.staff_id_of('content_editor'), now() - interval '1 day', now() - interval '1 day');

select is(
  pg_temp.audit_trail('content_items', (select id from public.content_items where title = 'audited_by_editor')),
  'INSERT content_editor -', 'should audit an insert through the table with the editor as actor');
select is(
  (select new_data ->> 'title' || ' ' || (new_data ->> 'status') from audit.log where table_name = 'content_items' and record_id = (select id from public.content_items where title = 'audited_by_editor')),
  'audited_by_editor draft', 'should record the new row, a draft, in new_data');
select is(pg_temp.audit_trail('content_items', 'c1900000-0000-4000-8000-000000000001'), 'INSERT system -', 'should audit an insert by the owner with no actor');

-- The flow of item B, step by step
select pg_temp.step_run_as('content_editor', $sql$update public.content_items set title = 'audited_flow_edited' where id = 'c1900000-0000-4000-8000-000000000001'$sql$);
select is(pg_temp.audit_trail('content_items', 'c1900000-0000-4000-8000-000000000001'), 'INSERT system - | UPDATE content_editor title+updated_at', 'should audit an edit with the editor as actor and the exact changed fields');
select is(
  (select old_data ->> 'title' || ' > ' || (new_data ->> 'title') from audit.log where table_name = 'content_items' and record_id = 'c1900000-0000-4000-8000-000000000001' and action = 'UPDATE'),
  'audited_flow > audited_flow_edited', 'should keep the old and new title');

select pg_temp.step_as('content_editor', 'submit_content_for_review', 'c1900000-0000-4000-8000-000000000001');
select pg_temp.step_as('pastor', 'approve_content', 'c1900000-0000-4000-8000-000000000001');
select pg_temp.step_as('content_editor', 'publish_content', 'c1900000-0000-4000-8000-000000000001');
select pg_temp.step_as('pastor', 'return_content_to_draft', 'c1900000-0000-4000-8000-000000000001');
select pg_temp.step_as('content_editor', 'archive_content', 'c1900000-0000-4000-8000-000000000001');
select is(
  pg_temp.audit_trail('content_items', 'c1900000-0000-4000-8000-000000000001'),
  'INSERT system - | UPDATE content_editor title+updated_at | UPDATE content_editor status | UPDATE pastor approved_by | UPDATE content_editor publish_at+status | UPDATE pastor approved_by+status | UPDATE content_editor status',
  'should audit submit, approve, publish, return to draft and archive with the signed-in user as actor and the exact fields');
select is(
  (select new_data ->> 'approved_by' from audit.log where table_name = 'content_items' and record_id = 'c1900000-0000-4000-8000-000000000001' and changed_fields = array['approved_by']),
  pg_temp.staff_id_of('pastor')::text, 'should record the approver in the audit row of the approval');

-- Sermons
select pg_temp.step_run_as('content_editor', $sql$update public.sermons set notes = 'edited notes' where id = 'c2900000-0000-4000-8000-000000000001'$sql$);
select pg_temp.step_as('content_editor', 'submit_sermon_for_review', 'c2900000-0000-4000-8000-000000000001');
select pg_temp.step_as('super_admin', 'approve_sermon', 'c2900000-0000-4000-8000-000000000001');
select pg_temp.step_as('content_editor', 'publish_sermon', 'c2900000-0000-4000-8000-000000000001');
select is(
  pg_temp.audit_trail('sermons', 'c2900000-0000-4000-8000-000000000001'),
  'INSERT system - | UPDATE content_editor notes+updated_at | UPDATE content_editor status | UPDATE super_admin approved_by | UPDATE content_editor publish_at+status',
  'should audit the sermon edit and each workflow step with the exact fields');

-- Refused statements leave nothing behind
create temp table audit_before as select count(*) as total from audit.log where table_name in ('content_items', 'sermons');
select pg_temp.step_error_as('content_editor_two', $sql$update public.content_items set title = 'hijack' where id = 'c1100000-0000-4000-8000-000000000002'$sql$);
select pg_temp.step_error_as('treasurer', $sql$insert into public.content_items (kind, title, author_id) values ('announcement', 'x', gen_random_uuid())$sql$);
select pg_temp.step_error_as('content_editor', $sql$update public.content_items set status = 'published' where id = 'c1100000-0000-4000-8000-000000000002'$sql$);
select pg_temp.step_error_as('pastor', $sql$delete from public.content_items$sql$);
select pg_temp.step_error_as('anon', $sql$update public.sermons set title = 'x'$sql$);
select pg_temp.step_as('content_editor', 'approve_content', 'c1100000-0000-4000-8000-000000000003');
select pg_temp.step_as('treasurer', 'publish_sermon', 'c2100000-0000-4000-8000-000000000003');
select pg_temp.step_as('pastor', 'approve_content', 'c1100000-0000-4000-8000-000000000006');
select is((select count(*) from audit.log where table_name in ('content_items', 'sermons')), (select total from audit_before), 'should leave no audit row after refused edits, inserts, deletes and workflow calls');

-- Replica mode cannot skip the trigger
set local session_replication_role = replica;
update public.content_items set title = 'replica_edit' where id = 'c1100000-0000-4000-8000-000000000002';
update public.sermons set title = 'replica_sermon_edit' where id = 'c2100000-0000-4000-8000-000000000002';
set local session_replication_role = origin;
select is(pg_temp.audit_trail('content_items', 'c1100000-0000-4000-8000-000000000002'), 'INSERT system - | UPDATE system title', 'should still audit a content item change made in replica mode');
select is(pg_temp.audit_trail('sermons', 'c2100000-0000-4000-8000-000000000002'), 'INSERT system - | UPDATE system title', 'should still audit a sermon change made in replica mode');

-- Delete by the owner is recorded too
delete from public.sermons where id = 'c2100000-0000-4000-8000-000000000002';
select is(pg_temp.audit_trail('sermons', 'c2100000-0000-4000-8000-000000000002'), 'INSERT system - | UPDATE system title | DELETE system -', 'should audit a delete made by the owner');

-- The audit trigger is the complete recipe on both tables
select is(
  (select count(*) from pg_trigger where tgrelid in ('public.content_items'::regclass, 'public.sermons'::regclass) and tgname in ('audit_content_items', 'audit_sermons')
    and tgenabled = 'A' and tgtype & 1 = 1 and tgtype & 2 = 0 and tgtype & 28 = 28 and tgfoid = 'audit.record_change()'::regprocedure),
  2::bigint, 'should have audit_content_items and audit_sermons as AFTER INSERT OR UPDATE OR DELETE row triggers, enabled always');

select * from finish();

rollback;
