-- LBC-33 (AC 3, 4, 7): time based visibility and the pg_cron expiry job. anon sees an item exactly while
-- publish_at <= now() < expires_at, to the transaction clock, whatever the session time zone, and with no job needed.
-- The job (private.archive_expired_content) only keeps the stored status truthful: it archives expired published
-- items, is idempotent, leaves everything else alone, runs with a null actor, and is scheduled once under its name.
-- Fixture and actors: see the preamble.

begin;

select plan(39);

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
  perform set_config('request.jwt.claims', json_build_object('role', v_db_role, 'sub', (select staff_id from actors where label = p_label))::text, true);
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
  perform set_config('request.jwt.claims', json_build_object('role', v_db_role, 'sub', (select staff_id from actors where label = p_label))::text, true);
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
  perform set_config('request.jwt.claims', json_build_object('role', v_db_role, 'sub', (select staff_id from actors where label = p_label))::text, true);
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

-- Extra rows around the edges: a minute either side of the boundaries, and a draft whose expiry has passed
insert into public.content_items (kind, title, status, publish_at, expires_at, author_id, approved_by)
select 'announcement', rows.title, rows.status::public.content_status, rows.publish_at, rows.expires_at,
  pg_temp.staff_id_of('content_editor'), case when rows.status = 'published' then pg_temp.staff_id_of('pastor') end
from (values
  ('in_one_minute', 'published', now() + interval '1 minute', null::timestamptz),
  ('one_second_ago', 'published', now() - interval '1 second', null),
  ('expires_in_one_minute', 'published', now() - interval '1 hour', now() + interval '1 minute'),
  ('draft_past_expiry', 'draft', null, now() - interval '1 day')
) as rows (title, status, publish_at, expires_at);


create function pg_temp.anon_sees(p_title text)
returns boolean
language sql
as $$
  select p_title = any (string_to_array(pg_temp.titles_as('anon', 'content_items'), ','));
$$;

create temp table visible_before as
select pg_temp.titles_as('anon', 'content_items') as titles;

-- Visibility without any job
select is((select titles from visible_before), 'expires_in_one_minute,history_page,live_announcement,no_expiry,one_second_ago,publish_at_now',
  'should show anon only what is inside its window, before the job has ever run');
select is(pg_temp.anon_sees('publish_at_now'), true, 'should show an item whose publish_at is exactly now');
select is(pg_temp.anon_sees('expires_at_now'), false, 'should hide an item whose expires_at is exactly now');
select is(pg_temp.anon_sees('in_one_minute'), false, 'should hide an item that goes live in a minute');
select is(pg_temp.anon_sees('expires_in_one_minute'), true, 'should show an item that expires in a minute');
select is(pg_temp.anon_sees('expired_item'), false, 'should hide an item that expired yesterday although its status is still published');
select is(pg_temp.anon_sees('no_expiry'), true, 'should show a published item with no expiry');
select is(pg_temp.titles_as('anon', 'sermons'), 'live_sermon,sermon_publish_at_now', 'should show anon only sermons whose publish_at has passed');

-- Time zone safety: timestamptz compares instants, so the session zone cannot move the window
set local timezone to 'Pacific/Kiritimati';
select is(pg_temp.titles_as('anon', 'content_items'), (select titles from visible_before), 'should show anon the same items in a session at UTC+14');
select is(pg_temp.titles_as('anon', 'sermons'), 'live_sermon,sermon_publish_at_now', 'should show anon the same sermons in a session at UTC+14');
set local timezone to 'Pacific/Pago_Pago';
select is(pg_temp.titles_as('anon', 'content_items'), (select titles from visible_before), 'should show anon the same items in a session at UTC-11');
set local timezone to 'Africa/Accra';
select is(pg_temp.titles_as('anon', 'content_items'), (select titles from visible_before), 'should show anon the same items in the church time zone');
set local timezone to 'America/Los_Angeles';
select is(pg_temp.titles_as('anon', 'content_items'), (select titles from visible_before), 'should show anon the same items in a zone with daylight saving');
set local timezone to default;

-- Published rows must carry a publish_at, so a null one can never be public
select throws_ok($sql$update public.content_items set publish_at = null where title = 'no_expiry'$sql$, '23514', null, 'should refuse a published item with no publish_at');
select throws_ok($sql$insert into public.content_items (kind, title, status, author_id, approved_by) values ('announcement', 'null_publish_at', 'published', (select id from public.staff limit 1), (select id from public.staff limit 1))$sql$, '23514', null, 'should refuse inserting a published item with no publish_at');

-- The job
select is(has_function_privilege('anon', 'private.archive_expired_content()', 'execute'), false, 'should not let anon run the expiry job');
select is(has_function_privilege('authenticated', 'private.archive_expired_content()', 'execute'), false, 'should not let authenticated run the expiry job');
select is(has_function_privilege('service_role', 'private.archive_expired_content()', 'execute'), false, 'should not let service_role run the expiry job');
select is(pg_temp.error_as('pastor', 'select private.archive_expired_content()'), '42501 permission denied for schema private', 'should not let a pastor run the expiry job through SQL');

select is((select count(*) from public.content_items where status = 'published' and expires_at <= now()), 2::bigint, 'should have two published items that are due to expire (expired_item and expires_at_now)');
select is(private.archive_expired_content(), 2, 'should archive exactly the two expired published items on the first run');
select is(
  (select string_agg(title, ',' order by title) from public.content_items where status = 'archived' and title in ('expired_item', 'expires_at_now')),
  'expired_item,expires_at_now', 'should have archived expired_item and expires_at_now');
select is(
  (select string_agg(title || '=' || status, ',' order by title) from public.content_items where title in ('live_announcement', 'scheduled_future', 'in_one_minute', 'expires_in_one_minute', 'draft_past_expiry', 'archived_item', 'no_expiry', 'draft_item')),
  'archived_item=archived,draft_item=draft,draft_past_expiry=draft,expires_in_one_minute=published,in_one_minute=published,live_announcement=published,no_expiry=published,scheduled_future=published',
  'should leave live, scheduled, unexpired, draft and already archived items alone');
select is(private.archive_expired_content(), 0, 'should archive nothing on a second run');
select is(pg_temp.titles_as('anon', 'content_items'), (select titles from visible_before), 'should show anon exactly the same items after the job as before it');
select is(
  (select count(*) from public.sermons where status = 'published'), 3::bigint, 'should not touch sermons, which do not expire');

select is(
  (select count(*) from audit.log where table_name = 'content_items' and action = 'UPDATE' and record_id in ('c1100000-0000-4000-8000-000000000005', 'c1100000-0000-4000-8000-000000000008')
    and actor_id is null and changed_fields @> array['status'] and old_data ->> 'status' = 'published' and new_data ->> 'status' = 'archived'),
  2::bigint, 'should audit each expiry as a status change from published to archived with a null actor');
select is(
  (select count(*) from audit.log where table_name = 'content_items' and action = 'UPDATE' and record_id = 'c1100000-0000-4000-8000-000000000005'),
  1::bigint, 'should write one audit row for the expiry, not one per run');

-- The schedule
select is((select count(*) from cron.job where jobname = 'archive-expired-content'), 1::bigint, 'should have exactly one cron job named archive-expired-content');
select is((select schedule from cron.job where jobname = 'archive-expired-content'), '*/15 * * * *', 'should run the expiry job every 15 minutes');
select is((select command from cron.job where jobname = 'archive-expired-content'), 'select private.archive_expired_content()', 'should run only the expiry function');
select is((select active from cron.job where jobname = 'archive-expired-content'), true, 'should have the expiry job active');
select is((select username from cron.job where jobname = 'archive-expired-content'), 'postgres', 'should run the expiry job as postgres, not as a user role');
select is((select database::text from cron.job where jobname = 'archive-expired-content'), current_database()::text, 'should run the expiry job in this database');
select is((select count(*) from cron.job), 1::bigint, 'should have no other cron job');

create temp table job_before as select jobid from cron.job where jobname = 'archive-expired-content';
do $schedule$ begin perform cron.schedule('archive-expired-content', '*/15 * * * *', 'select private.archive_expired_content()'); end $schedule$;
select is((select count(*) from cron.job where jobname = 'archive-expired-content'), 1::bigint, 'should still have one job after scheduling the same name again');
select is((select jobid from cron.job where jobname = 'archive-expired-content'), (select jobid from job_before), 'should update the existing job rather than create another');

-- The stored command is what runs: execute it as cron would, after making one more item expire
update public.content_items set expires_at = now() where title = 'expires_in_one_minute';
create function pg_temp.run_job_command()
returns bigint
language plpgsql
as $$
declare
  v_archived bigint;
begin
  execute (select command from cron.job where jobname = 'archive-expired-content') into v_archived;
  return v_archived;
end;
$$;
select is(pg_temp.run_job_command(), 1::bigint, 'should archive the newly expired item when the stored cron command is run');
select is((select status::text from public.content_items where title = 'expires_in_one_minute'), 'archived', 'should leave that item archived');

select * from finish();

rollback;
