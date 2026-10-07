-- LBC-33 (AC 2, 7): the approval flow of content_items and sermons. Draft to in review to published to archived,
-- each step by the right role: submit by the author or an approver, approve by a pastor or super admin only (a content
-- editor cannot), publish by any content role once approved (CONTENT_NOT_APPROVED otherwise), return to draft and
-- archive with the published-needs-an-approver rule, scheduled publishing, illegal and repeated transitions,
-- resurrecting an archived item, and the table guard that holds on every path. Fixture and actors: see the preamble.

begin;

select plan(132);

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

create function pg_temp.call_as(p_label text, p_function text, p_id uuid)
returns text
language sql
as $$
  select pg_temp.error_as(p_label, format('select * from public.%I(%L)', p_function, p_id));
$$;

create function pg_temp.state_of(p_id uuid)
returns text
language sql
as $$
  select status || ' / ' || coalesce((select full_name from public.staff where id = approved_by), 'no approver')
  from public.content_items where id = p_id;
$$;

create function pg_temp.sermon_state_of(p_id uuid)
returns text
language sql
as $$
  select status || ' / ' || coalesce((select full_name from public.staff where id = approved_by), 'no approver')
  from public.sermons where id = p_id;
$$;

-- Creates a draft as the actor through the table, the way the dashboard does, and returns its id.
create function pg_temp.new_draft_as(p_label text, p_title text, p_extra_columns text default '', p_extra_values text default '')
returns uuid
language plpgsql
as $$
begin
  perform pg_temp.run_as(p_label, format(
    'insert into public.content_items (kind, title, author_id%s) values (''announcement'', %L, %L%s)',
    p_extra_columns, p_title, (select staff_id from actors where label = p_label), p_extra_values));
  return (select id from public.content_items where title = p_title);
end;
$$;


-- Setup steps that must not print a result row, which TAP would read as a test line.
create function pg_temp.step_as(p_label text, p_function text, p_id uuid)
returns void
language plpgsql
as $$
begin
  perform pg_temp.call_as(p_label, p_function, p_id);
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

create temp table ids (name text primary key, id uuid);

-- Submit: draft to in_review, by the author or an approver
select is(pg_temp.call_as('content_editor', 'submit_content_for_review', 'c1100000-0000-4000-8000-000000000002'), 'ok 1', 'should let an author submit their draft');
select is(pg_temp.state_of('c1100000-0000-4000-8000-000000000002'), 'in_review / no approver', 'should leave the submitted item in_review with no approver');
select is(pg_temp.call_as('content_editor', 'submit_content_for_review', 'c1100000-0000-4000-8000-000000000013'), 'P0001 AUTH_FORBIDDEN', 'should refuse a content editor submitting the secretary''s draft');
select is(pg_temp.call_as('pastor', 'submit_content_for_review', 'c1100000-0000-4000-8000-000000000013'), 'ok 1', 'should let a pastor submit another author''s draft');
select is(pg_temp.state_of('c1100000-0000-4000-8000-000000000013'), 'in_review / no approver', 'should leave the item the pastor submitted in_review with no approver');
select is(pg_temp.call_as(actors.label, 'submit_content_for_review', 'c1100000-0000-4000-8000-000000000011'), 'P0001 AUTH_FORBIDDEN', format('should refuse %s submitting a draft', actors.label))
from actors
where label in ('treasurer', 'usher', 'department_head', 'no_role', 'no_staff', 'inactive_content_editor', 'inactive_pastor', 'inactive_super_admin', 'inactive_secretary')
order by label;
select is(pg_temp.call_as('content_editor', 'submit_content_for_review', 'c1100000-0000-4000-8000-000000000011'), 'P0001 AUTH_FORBIDDEN', 'should refuse a content editor submitting another editor''s draft');
select is(pg_temp.call_as('anon', 'submit_content_for_review', 'c1100000-0000-4000-8000-000000000011'), '42501 permission denied for function submit_content_for_review', 'should refuse anon calling submit_content_for_review');
select is(pg_temp.state_of('c1100000-0000-4000-8000-000000000011'), 'draft / no approver', 'should leave the draft unchanged after every refused submission');
select is(pg_temp.call_as('content_editor', 'submit_content_for_review', 'c1100000-0000-4000-8000-000000000002'), 'P0001 VALIDATION_FAILED', 'should refuse submitting an item that is already in review');
select is(pg_temp.call_as('pastor', 'submit_content_for_review', 'c1100000-0000-4000-8000-000000000001'), 'P0001 VALIDATION_FAILED', 'should refuse submitting a published item');
select is(pg_temp.call_as('pastor', 'submit_content_for_review', 'c1100000-0000-4000-8000-000000000006'), 'P0001 VALIDATION_FAILED', 'should refuse submitting an archived item');
select is(pg_temp.call_as('pastor', 'submit_content_for_review', '00000000-0000-4000-8000-0000000000ff'), 'P0001 NOT_FOUND', 'should refuse submitting an unknown item with NOT_FOUND');
select is(pg_temp.call_as('pastor', 'submit_content_for_review', null), 'P0001 NOT_FOUND', 'should refuse submitting a null id with NOT_FOUND');

-- Approve: pastor or super admin only
select is(pg_temp.call_as(actors.label, 'approve_content', 'c1100000-0000-4000-8000-000000000003'), 'P0001 AUTH_FORBIDDEN', format('should refuse %s approving content', actors.label))
from actors
where label in ('content_editor', 'content_editor_two', 'secretary', 'treasurer', 'usher', 'department_head', 'no_role', 'no_staff', 'inactive_pastor', 'inactive_super_admin', 'inactive_content_editor')
order by label;
select is(pg_temp.call_as('anon', 'approve_content', 'c1100000-0000-4000-8000-000000000003'), '42501 permission denied for function approve_content', 'should refuse anon calling approve_content');
select is(pg_temp.call_as('content_editor', 'approve_content', 'c1100000-0000-4000-8000-000000000002'), 'P0001 AUTH_FORBIDDEN', 'should refuse the author approving their own item in review');
select is(pg_temp.state_of('c1100000-0000-4000-8000-000000000003'), 'in_review / no approver', 'should leave the item without an approver after every refused approval');
select is(pg_temp.call_as('pastor', 'approve_content', 'c1100000-0000-4000-8000-000000000003'), 'ok 1', 'should let a pastor approve an item in review');
select is(pg_temp.state_of('c1100000-0000-4000-8000-000000000003'), 'in_review / pastor', 'should record the pastor as approver and keep the item in review');
select is(pg_temp.call_as('super_admin', 'approve_content', 'c1100000-0000-4000-8000-000000000003'), 'P0001 VALIDATION_FAILED', 'should refuse approving an item that is already approved');
select is(pg_temp.call_as('super_admin', 'approve_content', 'c1100000-0000-4000-8000-000000000013'), 'ok 1', 'should let a super admin approve an item in review');
select is(pg_temp.state_of('c1100000-0000-4000-8000-000000000013'), 'in_review / super_admin', 'should record the super admin as approver');
select is(pg_temp.call_as('pastor', 'approve_content', 'c1100000-0000-4000-8000-000000000011'), 'P0001 VALIDATION_FAILED', 'should refuse approving a draft');
select is(pg_temp.call_as('pastor', 'approve_content', 'c1100000-0000-4000-8000-000000000001'), 'P0001 VALIDATION_FAILED', 'should refuse approving a published item');
select is(pg_temp.call_as('pastor', 'approve_content', 'c1100000-0000-4000-8000-000000000006'), 'P0001 VALIDATION_FAILED', 'should refuse approving an archived item');
select is(pg_temp.call_as('pastor', 'approve_content', '00000000-0000-4000-8000-0000000000ff'), 'P0001 NOT_FOUND', 'should refuse approving an unknown item with NOT_FOUND');

-- A pastor may approve their own item (decision: PRD four-eyes is stated for expenses only)
insert into ids values ('pastor_own', pg_temp.new_draft_as('pastor', 'pastor_own_item'));
select is(pg_temp.call_as('pastor', 'submit_content_for_review', (select id from ids where name = 'pastor_own')), 'ok 1', 'should let a pastor submit their own item');
select is(pg_temp.call_as('pastor', 'approve_content', (select id from ids where name = 'pastor_own')), 'ok 1', 'should let a pastor approve their own item');
select is(pg_temp.state_of((select id from ids where name = 'pastor_own')), 'in_review / pastor', 'should record the pastor as approver of their own item');

-- Publish
insert into ids values ('unapproved', pg_temp.new_draft_as('content_editor', 'unapproved_item'));
select pg_temp.step_as('content_editor', 'submit_content_for_review', (select id from ids where name = 'unapproved'));
select is(pg_temp.call_as('content_editor', 'publish_content', (select id from ids where name = 'unapproved')), 'P0001 CONTENT_NOT_APPROVED', 'should refuse a content editor publishing an item nobody approved');
select is(pg_temp.call_as('secretary', 'publish_content', (select id from ids where name = 'unapproved')), 'P0001 CONTENT_NOT_APPROVED', 'should refuse the secretary publishing an item nobody approved');
select is(pg_temp.state_of((select id from ids where name = 'unapproved')), 'in_review / no approver', 'should leave an unapproved item in review after refused publishing');
select is(pg_temp.call_as(actors.label, 'publish_content', 'c1100000-0000-4000-8000-000000000012'), 'P0001 AUTH_FORBIDDEN', format('should refuse %s publishing content', actors.label))
from actors
where label in ('treasurer', 'usher', 'department_head', 'no_role', 'no_staff', 'inactive_pastor', 'inactive_content_editor')
order by label;
select is(pg_temp.call_as('anon', 'publish_content', 'c1100000-0000-4000-8000-000000000012'), '42501 permission denied for function publish_content', 'should refuse anon calling publish_content');
select is(pg_temp.titles_as('anon', 'content_items') like '%approved_in_review%', false, 'should keep an approved item in review invisible to anon');
select is(pg_temp.call_as('content_editor', 'publish_content', 'c1100000-0000-4000-8000-000000000012'), 'ok 1', 'should let a content editor publish an item a pastor approved');
select is(pg_temp.state_of('c1100000-0000-4000-8000-000000000012'), 'published / pastor', 'should keep the original approver on a published item');
select is((select publish_at = now() from public.content_items where id = 'c1100000-0000-4000-8000-000000000012'), true, 'should set publish_at to now when publishing an item with none');
select is(pg_temp.titles_as('anon', 'content_items') like '%approved_in_review%', true, 'should show anon an item as soon as it is published');
select is(pg_temp.call_as('pastor', 'publish_content', (select id from ids where name = 'unapproved')), 'ok 1', 'should let a pastor publish an unapproved item');
select is(pg_temp.state_of((select id from ids where name = 'unapproved')), 'published / pastor', 'should record the pastor as approver when publishing approves the item');
select is(pg_temp.call_as('pastor', 'publish_content', (select id from ids where name = 'unapproved')), 'P0001 VALIDATION_FAILED', 'should refuse publishing an item that is already published');
select is(pg_temp.call_as('pastor', 'publish_content', 'c1100000-0000-4000-8000-000000000011'), 'P0001 VALIDATION_FAILED', 'should refuse publishing a draft, which skips review');
select is(pg_temp.call_as('super_admin', 'publish_content', 'c1100000-0000-4000-8000-000000000006'), 'P0001 VALIDATION_FAILED', 'should refuse publishing an archived item');
select is(pg_temp.call_as('pastor', 'publish_content', '00000000-0000-4000-8000-0000000000ff'), 'P0001 NOT_FOUND', 'should refuse publishing an unknown item with NOT_FOUND');

-- Scheduled publishing: a future publish_at is kept and the item stays hidden until then
insert into ids values ('scheduled', pg_temp.new_draft_as('content_editor', 'scheduled_by_flow', ', publish_at', ', now() + interval ''2 days'''));
select pg_temp.step_as('content_editor', 'submit_content_for_review', (select id from ids where name = 'scheduled'));
select is(pg_temp.call_as('pastor', 'publish_content', (select id from ids where name = 'scheduled')), 'ok 1', 'should let a pastor publish an item scheduled for later');
select is((select status::text || ' ' || (publish_at = now() + interval '2 days')::text from public.content_items where id = (select id from ids where name = 'scheduled')), 'published true', 'should keep the future publish_at when publishing');
select is(pg_temp.titles_as('anon', 'content_items') like '%scheduled_by_flow%', false, 'should keep a scheduled item hidden from anon until its time');

-- An item whose expiry is not after its go-live time cannot be published
insert into ids values ('past_expiry', pg_temp.new_draft_as('content_editor', 'already_expired', ', expires_at', ', now() - interval ''1 hour'''));
select pg_temp.step_as('content_editor', 'submit_content_for_review', (select id from ids where name = 'past_expiry'));
select is(pg_temp.call_as('pastor', 'publish_content', (select id from ids where name = 'past_expiry')), 'P0001 VALIDATION_FAILED', 'should refuse publishing an item that has already expired');
select is(pg_temp.state_of((select id from ids where name = 'past_expiry')), 'in_review / no approver', 'should leave an item that cannot be published in review');

-- Return to draft
insert into ids values ('to_return', pg_temp.new_draft_as('content_editor', 'item_to_return'));
select pg_temp.step_as('content_editor', 'submit_content_for_review', (select id from ids where name = 'to_return'));
select pg_temp.step_as('pastor', 'approve_content', (select id from ids where name = 'to_return'));
select is(pg_temp.call_as('content_editor_two', 'return_content_to_draft', (select id from ids where name = 'to_return')), 'P0001 AUTH_FORBIDDEN', 'should refuse another editor returning an item to draft');
select is(pg_temp.call_as('treasurer', 'return_content_to_draft', (select id from ids where name = 'to_return')), 'P0001 AUTH_FORBIDDEN', 'should refuse the treasurer returning an item to draft');
select is(pg_temp.call_as('content_editor', 'return_content_to_draft', (select id from ids where name = 'to_return')), 'ok 1', 'should let the author take their approved item back to draft');
select is(pg_temp.state_of((select id from ids where name = 'to_return')), 'draft / no approver', 'should clear the approver when an item returns to draft');
select is(pg_temp.error_as('content_editor', format($sql$update public.content_items set title = 'edited after return' where id = %L$sql$, (select id from ids where name = 'to_return'))), 'ok 1', 'should let the author edit the item once it is a draft again');
select pg_temp.step_as('content_editor', 'submit_content_for_review', (select id from ids where name = 'to_return'));
select is(pg_temp.call_as('content_editor', 'publish_content', (select id from ids where name = 'to_return')), 'P0001 CONTENT_NOT_APPROVED', 'should need a fresh approval for an item that was edited after approval');
select is(pg_temp.call_as('content_editor', 'return_content_to_draft', 'c1100000-0000-4000-8000-000000000012'), 'P0001 AUTH_FORBIDDEN', 'should refuse an editor taking a published item back to draft');
select is(pg_temp.call_as('pastor', 'return_content_to_draft', 'c1100000-0000-4000-8000-000000000012'), 'ok 1', 'should let a pastor take a published item back to draft');
select is(pg_temp.state_of('c1100000-0000-4000-8000-000000000012'), 'draft / no approver', 'should clear the approver of an item taken back from published');
select is(pg_temp.titles_as('anon', 'content_items') like '%approved_in_review%', false, 'should hide an item from anon once it is back in draft');
select is(pg_temp.call_as('pastor', 'return_content_to_draft', 'c1100000-0000-4000-8000-000000000012'), 'P0001 VALIDATION_FAILED', 'should refuse returning a draft to draft');
select is(pg_temp.call_as('pastor', 'return_content_to_draft', 'c1100000-0000-4000-8000-000000000006'), 'P0001 VALIDATION_FAILED', 'should refuse returning an archived item to draft');
select is(pg_temp.call_as('anon', 'return_content_to_draft', 'c1100000-0000-4000-8000-000000000001'), '42501 permission denied for function return_content_to_draft', 'should refuse anon calling return_content_to_draft');

-- Archive: the author or an approver, and only an approver once it is published
select is(pg_temp.call_as('content_editor_two', 'archive_content', 'c1100000-0000-4000-8000-000000000011'), 'ok 1', 'should let the author archive their own draft');
select is(pg_temp.call_as('content_editor', 'archive_content', 'c1100000-0000-4000-8000-000000000002'), 'ok 1', 'should let the author archive their own item in review');
select is(pg_temp.call_as('content_editor', 'archive_content', 'c1100000-0000-4000-8000-000000000001'), 'P0001 AUTH_FORBIDDEN', 'should refuse an editor archiving a published item');
select is(pg_temp.call_as('secretary', 'archive_content', 'c1100000-0000-4000-8000-000000000001'), 'P0001 AUTH_FORBIDDEN', 'should refuse the secretary archiving a published item');
select is(pg_temp.call_as('pastor', 'archive_content', 'c1100000-0000-4000-8000-000000000001'), 'ok 1', 'should let a pastor archive a published item');
select is(pg_temp.state_of('c1100000-0000-4000-8000-000000000001'), 'archived / pastor', 'should keep the approver on an archived item');
select is(pg_temp.titles_as('anon', 'content_items') like '%live_announcement%', false, 'should hide an archived item from anon');
select is(pg_temp.call_as('pastor', 'archive_content', 'c1100000-0000-4000-8000-000000000001'), 'P0001 VALIDATION_FAILED', 'should refuse archiving an item twice');
select is(pg_temp.call_as('treasurer', 'archive_content', 'c1100000-0000-4000-8000-000000000004'), 'P0001 AUTH_FORBIDDEN', 'should refuse the treasurer archiving content');
select is(pg_temp.call_as('content_editor_two', 'archive_content', 'c1100000-0000-4000-8000-000000000003'), 'P0001 AUTH_FORBIDDEN', 'should refuse another editor archiving an item in review');
select is(pg_temp.call_as('anon', 'archive_content', 'c1100000-0000-4000-8000-000000000004'), '42501 permission denied for function archive_content', 'should refuse anon calling archive_content');

-- An archived item cannot come back by any step
select is(pg_temp.call_as('super_admin', fn.name, 'c1100000-0000-4000-8000-000000000001'), 'P0001 VALIDATION_FAILED', format('should refuse %s on an archived item', fn.name))
from (values ('submit_content_for_review'), ('approve_content'), ('publish_content'), ('return_content_to_draft'), ('archive_content')) as fn (name);

-- The table guards the flow on every path, including the owner and service role
select throws_ok($sql$update public.content_items set status = 'draft' where id = 'c1100000-0000-4000-8000-000000000001'$sql$, 'P0001', 'VALIDATION_FAILED', 'should refuse the owner bringing an archived item back');
select throws_ok($sql$update public.content_items set status = 'in_review' where id = 'c1100000-0000-4000-8000-000000000001'$sql$, 'P0001', 'VALIDATION_FAILED', 'should refuse the owner moving an archived item to review');
select throws_ok($sql$update public.content_items set status = 'published' where id = 'c1100000-0000-4000-8000-000000000011'$sql$, 'P0001', 'VALIDATION_FAILED', 'should refuse the owner skipping review from draft to published');
select throws_ok($sql$update public.content_items set status = 'published', approved_by = null, publish_at = now() where id = (select id from ids where name = 'past_expiry')$sql$, '23514', null, 'should refuse a published item with no approver');
select throws_ok($sql$update public.content_items set approved_by = (select id from public.staff limit 1) where status = 'draft'$sql$, '23514', null, 'should refuse a draft that has an approver');
select throws_ok($sql$update public.content_items set status = 'published', approved_by = (select id from public.staff limit 1) where id = 'c1100000-0000-4000-8000-000000000003'$sql$, '23514', null, 'should refuse a published item with no publish_at');

-- Sermons follow the same flow
select pg_temp.step_run_as('content_editor', format($sql$insert into public.sermons (title, preacher, preached_on, author_id) values ('flow_sermon', 'Preacher', '2026-10-04', %L)$sql$, pg_temp.staff_id_of('content_editor')));
insert into ids select 'sermon_draft', id from public.sermons where title = 'flow_sermon';
select is(pg_temp.call_as('content_editor', 'submit_sermon_for_review', (select id from ids where name = 'sermon_draft')), 'ok 1', 'should let an author submit their sermon');
select is(pg_temp.call_as('content_editor', 'approve_sermon', (select id from ids where name = 'sermon_draft')), 'P0001 AUTH_FORBIDDEN', 'should refuse a content editor approving a sermon');
select is(pg_temp.call_as('secretary', 'approve_sermon', (select id from ids where name = 'sermon_draft')), 'P0001 AUTH_FORBIDDEN', 'should refuse the secretary approving a sermon');
select is(pg_temp.call_as('content_editor', 'publish_sermon', (select id from ids where name = 'sermon_draft')), 'P0001 CONTENT_NOT_APPROVED', 'should refuse publishing a sermon nobody approved');
select is(pg_temp.call_as('pastor', 'approve_sermon', (select id from ids where name = 'sermon_draft')), 'ok 1', 'should let a pastor approve a sermon');
select is(pg_temp.sermon_state_of((select id from ids where name = 'sermon_draft')), 'in_review / pastor', 'should record the pastor as approver of the sermon');
select is(pg_temp.call_as('pastor', 'approve_sermon', (select id from ids where name = 'sermon_draft')), 'P0001 VALIDATION_FAILED', 'should refuse approving a sermon twice');
select is(pg_temp.call_as('content_editor', 'publish_sermon', (select id from ids where name = 'sermon_draft')), 'ok 1', 'should let a content editor publish an approved sermon');
select is(pg_temp.sermon_state_of((select id from ids where name = 'sermon_draft')), 'published / pastor', 'should leave the sermon published with its approver');
select is(pg_temp.titles_as('anon', 'sermons') like '%flow_sermon%', true, 'should show anon a sermon once it is published');
select is(pg_temp.call_as('content_editor', 'return_sermon_to_draft', (select id from ids where name = 'sermon_draft')), 'P0001 AUTH_FORBIDDEN', 'should refuse an editor taking a published sermon back to draft');
select is(pg_temp.call_as('content_editor', 'archive_sermon', (select id from ids where name = 'sermon_draft')), 'P0001 AUTH_FORBIDDEN', 'should refuse an editor archiving a published sermon');
select is(pg_temp.call_as('pastor', 'return_sermon_to_draft', (select id from ids where name = 'sermon_draft')), 'ok 1', 'should let a pastor take a sermon back to draft');
select is(pg_temp.sermon_state_of((select id from ids where name = 'sermon_draft')), 'draft / no approver', 'should clear the sermon approver on return to draft');
select is(pg_temp.call_as('content_editor', 'archive_sermon', (select id from ids where name = 'sermon_draft')), 'ok 1', 'should let an author archive their own draft sermon');
select is(pg_temp.call_as('super_admin', 'submit_sermon_for_review', (select id from ids where name = 'sermon_draft')), 'P0001 VALIDATION_FAILED', 'should refuse bringing an archived sermon back');
select is(pg_temp.call_as('super_admin', 'publish_sermon', 'c2100000-0000-4000-8000-000000000002'), 'P0001 VALIDATION_FAILED', 'should refuse publishing a draft sermon');
select is(pg_temp.call_as('super_admin', 'publish_sermon', 'c2100000-0000-4000-8000-000000000003'), 'ok 1', 'should let a super admin publish a sermon in review, approving it');
select is(pg_temp.sermon_state_of('c2100000-0000-4000-8000-000000000003'), 'published / super_admin', 'should record the super admin as approver of that sermon');
select is(pg_temp.call_as('treasurer', 'publish_sermon', 'c2100000-0000-4000-8000-000000000003'), 'P0001 AUTH_FORBIDDEN', 'should refuse the treasurer publishing a sermon');
select is(pg_temp.call_as('pastor', 'publish_sermon', '00000000-0000-4000-8000-0000000000ff'), 'P0001 NOT_FOUND', 'should refuse publishing an unknown sermon with NOT_FOUND');
select is(pg_temp.call_as('anon', 'approve_sermon', 'c2100000-0000-4000-8000-000000000003'), '42501 permission denied for function approve_sermon', 'should refuse anon calling approve_sermon');

select * from finish();

rollback;
