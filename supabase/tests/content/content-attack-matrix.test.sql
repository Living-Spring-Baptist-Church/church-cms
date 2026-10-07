-- LBC-33 (AC 7): an attack matrix written from the attacker's side, independent of the policy tests. Every attack runs
-- as a real role in this rolled-back transaction: anon reaching hidden rows by id, relationship, filter, ordering,
-- error messages and locking; injection through slug, title and body; a hijacked search path; privilege escalation by
-- writing status, approved_by or author_id (directly, by upsert, by role switching); an editor reaching another
-- editor's draft; bringing an archived item back; probing for the existence of records; and the job and cron tables.
-- Fixture and actors: see the preamble.

begin;

select plan(70);

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

create function pg_temp.call_as(p_label text, p_function text, p_id uuid)
returns text
language sql
as $$
  select pg_temp.error_as(p_label, format('select * from public.%I(%L)', p_function, p_id));
$$;

-- 1. anon against hidden rows
-- A leak through an error message: a hidden row whose title cannot be cast must never be evaluated before the policy
insert into public.content_items (kind, title, status, publish_at, author_id, approved_by)
values
  ('announcement', '1', 'published', now() - interval '1 day', pg_temp.staff_id_of('content_editor'), pg_temp.staff_id_of('pastor'));
insert into public.content_items (kind, title, author_id)
values ('announcement', 'not a number', pg_temp.staff_id_of('content_editor'));

select is(pg_temp.error_as('anon', $sql$select id from public.content_items where (case when title = 'not a number' then title::integer else 1 end) = 1$sql$), 'ok 5', 'should not let anon trigger a cast error on a hidden row, so no hidden row is probed');
select is(pg_temp.error_as('anon', $sql$select id from public.content_items where 1 / (case when title = 'draft_item' then 0 else 1 end) = 1$sql$), 'ok 5', 'should not let anon trigger a division error on a hidden row');
select is(pg_temp.error_as('anon', 'select id from public.content_items for update'), '42501 permission denied for table content_items', 'should not let anon lock rows');
select is(pg_temp.error_as('anon', 'select count(*) from public.content_items'), 'ok 1', 'should let anon count, which only sees live rows');
select is((select count(*) from public.content_items), 15::bigint, 'should have fifteen rows in total for the owner, of which anon sees five');
select is(pg_temp.run_as('anon', 'select id from public.content_items'), 5::bigint, 'should show anon the five live rows and nothing hidden');
select is(
  pg_temp.graphql_as('anon', '{ contentItemsCollection { totalCount edges { node { id } } } }') #>> '{data,contentItemsCollection,totalCount}' is distinct from '15', true,
  'should never give anon the real row count through GraphQL');
select is(pg_temp.error_as('anon', $sql$select id from public.content_items where id in (select id from public.content_items where title like 'draft%')$sql$), 'ok 0', 'should show anon no draft through a subquery on the same table');
select is(pg_temp.error_as('anon', 'select id from public.sermons where preacher = (select preacher from public.sermons where title = ''draft_sermon'')'), 'ok 0', 'should show anon no sermon through a subquery on a draft');
select is(pg_temp.error_as('anon', 'select author_id from public.content_items'), '42501 permission denied for table content_items', 'should hide the author from anon');
select is(pg_temp.error_as('anon', 'select (c.*)::text from public.content_items c'), '42501 permission denied for table content_items', 'should not let anon read a whole row as text, which would include hidden columns');
select is(pg_temp.error_as('anon', 'select to_jsonb(c) from public.content_items c'), '42501 permission denied for table content_items', 'should not let anon read a whole row as jsonb');
select is(pg_temp.error_as('anon', 'select * from public.staff'), '42501 permission denied for table staff', 'should keep staff closed to anon');
select is(pg_temp.error_as('anon', 'select * from cron.job'), '42501 permission denied for schema cron', 'should keep the cron table closed to anon');
select is(pg_temp.error_as('pastor', 'select * from cron.job'), '42501 permission denied for schema cron', 'should keep the cron table closed to a pastor');
select is(pg_temp.error_as('super_admin', 'select cron.schedule(''evil'', ''* * * * *'', ''select 1'')'), '42501 permission denied for schema cron', 'should not let a super admin schedule jobs through SQL');
select is(pg_temp.error_as('anon', 'select private.can_edit_content()'), '42501 permission denied for schema private', 'should keep the private helpers closed to anon');
select is(pg_temp.error_as('content_editor', 'select private.can_approve_content()'), '42501 permission denied for schema private', 'should keep the private helpers closed to a content editor');
select is(pg_temp.error_as('content_editor', 'select private.next_content_status(''approve'', ''in_review'', null, null)'), '42501 permission denied for schema private', 'should not let a content editor call the flow rules directly');
select is(pg_temp.error_as('anon', 'truncate public.content_items'), '42501 permission denied for table content_items', 'should not let anon truncate');
select is(pg_temp.error_as('pastor', 'truncate public.sermons'), '42501 permission denied for table sermons', 'should not let a pastor truncate');

-- 2. Probing for existence: a caller who may not use a function learns nothing about an id
select is(pg_temp.call_as('treasurer', 'approve_content', 'c1100000-0000-4000-8000-000000000003'), pg_temp.call_as('treasurer', 'approve_content', '00000000-0000-4000-8000-0000000000ff'), 'should answer the treasurer the same for a real and an unknown id');
select is(pg_temp.call_as('no_staff', 'publish_sermon', 'c2100000-0000-4000-8000-000000000003'), pg_temp.call_as('no_staff', 'publish_sermon', '00000000-0000-4000-8000-0000000000ff'), 'should answer a user with no staff profile the same for a real and an unknown sermon id');
select is(pg_temp.call_as('inactive_pastor', 'approve_content', 'c1100000-0000-4000-8000-000000000003'), 'P0001 AUTH_FORBIDDEN', 'should refuse a deactivated pastor');
select is(pg_temp.call_as('inactive_super_admin', 'approve_sermon', 'c2100000-0000-4000-8000-000000000003'), 'P0001 AUTH_FORBIDDEN', 'should refuse a deactivated super admin');

-- 3. Injection
create function pg_temp.insert_text_as_editor(p_title text, p_body text)
returns text
language plpgsql
as $$
begin
  perform pg_temp.run_as('content_editor', format('insert into public.content_items (kind, title, body, author_id) values (''announcement'', %L, %L, %L)', p_title, p_body, (select staff_id from actors where label = 'content_editor')));
  return 'ok';
exception when others then
  return sqlstate;
end;
$$;

select is(pg_temp.insert_text_as_editor($t$x'); drop table public.sermons; --$t$, $b$'); delete from public.staff; --$b$), 'ok', 'should store a title and body full of SQL as plain text');
select is((select count(*) from public.sermons), 6::bigint, 'should leave sermons intact after the injection attempt');
select is((select count(*) from public.staff where full_name = 'pastor'), 1::bigint, 'should leave staff intact after the injection attempt');
select is((select title from public.content_items where title like 'x%drop table%'), $t$x'); drop table public.sermons; --$t$, 'should keep the injected text exactly as written');
select is(pg_temp.insert_text_as_editor('<img src=x onerror=alert(1)>', '<script>alert(document.cookie)</script>'), 'ok', 'should store markup as plain text for the reader to render safely');
select throws_ok($sql$insert into public.content_items (kind, slug, title, author_id) values ('page', $s$x'; drop table public.sermons; --$s$, 't', (select id from public.staff limit 1))$sql$, '23514', null, 'should reject SQL in a slug');
select throws_ok($sql$insert into public.content_items (kind, slug, title, author_id) values ('page', E'history\n', 't', (select id from public.staff limit 1))$sql$, '23514', null, 'should reject a slug with a trailing newline');
select throws_ok($sql$insert into public.sermons (title, preacher, preached_on, video_url, author_id) values ('t', 'p', '2026-10-04', $v$https://www.youtube.com/x'; drop table public.sermons; --$v$, (select id from public.staff limit 1))$sql$, '23514', null, 'should reject SQL in a video link');
select is(
  pg_temp.graphql_as('content_editor', format($q$mutation { insertIntoContentItemsCollection(objects: [{ kind: announcement, title: "\"}) { affectedCount } } mutation { x", body: "\\ \"; --", authorId: "%s" }]) { records { title } } }$q$, pg_temp.staff_id_of('content_editor'))) #>> '{data,insertIntoContentItemsCollection,records,0,title}',
  '"}) { affectedCount } } mutation { x', 'should keep a GraphQL-shaped title as plain text');
select is(
  pg_temp.graphql_as('anon', '{ contentItemsCollection(filter: { title: { eq: "x'' or ''1''=''1" } }) { edges { node { id } } } }') #>> '{data,contentItemsCollection,edges}', '[]',
  'should not let a quote in a GraphQL filter widen what anon sees');

-- 4. Search path hijack: temp tables and a first schema named like the real ones
create function pg_temp.hijack_as(p_label text, p_function text, p_id uuid)
returns text
language plpgsql
as $$
declare
  v_original name := current_user;
  v_staff uuid := (select staff_id from actors where label = p_label);
  v_path text := current_setting('search_path');
  v_shadowed bigint;
  v_result text;
begin
  perform set_config('request.jwt.claims', json_build_object('role', 'authenticated', 'sub', v_staff)::text, true);
  perform set_config('role', 'authenticated', true);
  create temp table staff_roles (staff_id uuid, role public.app_role, department_id uuid);
  create temp table staff (id uuid, is_active boolean);
  insert into pg_temp.staff_roles values (v_staff, 'pastor', null), (v_staff, 'super_admin', null);
  insert into pg_temp.staff values (v_staff, true);
  perform set_config('search_path', 'pg_temp, public', true);
  -- Control: with this search path the unqualified name staff_roles really is the attacker's table
  execute 'select count(*) from staff_roles' into v_shadowed;
  begin
    execute format('select * from public.%I(%L)', p_function, p_id);
    v_result := 'ok';
  exception when others then
    v_result := sqlstate || ' ' || sqlerrm;
  end;
  perform set_config('search_path', v_path, true);
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_result || ' shadowed=' || v_shadowed;
end;
$$;

select is(pg_temp.hijack_as('content_editor', 'approve_content', 'c1100000-0000-4000-8000-000000000003'), 'P0001 AUTH_FORBIDDEN shadowed=2', 'should still refuse a content editor approving when temp tables claim they are a pastor and a super admin');
drop table if exists pg_temp.staff_roles, pg_temp.staff;
select is(pg_temp.hijack_as('content_editor', 'approve_sermon', 'c2100000-0000-4000-8000-000000000003'), 'P0001 AUTH_FORBIDDEN shadowed=2', 'should still refuse a content editor approving a sermon under the same hijack');
drop table if exists pg_temp.staff_roles, pg_temp.staff;
select is(pg_temp.hijack_as('treasurer', 'publish_content', 'c1100000-0000-4000-8000-000000000012'), 'P0001 AUTH_FORBIDDEN shadowed=2', 'should still refuse the treasurer publishing under the same hijack');
drop table if exists pg_temp.staff_roles, pg_temp.staff;
select is(pg_temp.titles_as('treasurer', 'content_items'), '', 'should still show the treasurer nothing');
select is((select count(*) from (values ('anon'), ('authenticated')) as roles (name), (values ('postgres'), ('service_role'), ('supabase_admin')) as powerful (name) where pg_has_role(roles.name, powerful.name, 'member')), 0::bigint, 'should make neither anon nor authenticated a member of a more powerful role, so SET ROLE cannot escalate');
select is(pg_temp.error_as('anon', 'set session_replication_role = replica'), '42501 permission denied to set parameter "session_replication_role"', 'should not let anon turn off triggers');
select is(pg_temp.error_as('super_admin', 'set session_replication_role = replica'), '42501 permission denied to set parameter "session_replication_role"', 'should not let even a super admin turn off triggers');

-- 5. Privilege escalation by writing status, approved_by and author_id
select is(pg_temp.error_as('content_editor', format($sql$insert into public.content_items (kind, title, author_id) values ('announcement', 'upsert', %L) on conflict (id) do update set status = 'published'$sql$, pg_temp.staff_id_of('content_editor'))), '42501 permission denied for table content_items', 'should refuse an upsert that sets the status');
select is(pg_temp.error_as('pastor', $sql$update public.content_items set status = 'published', approved_by = (select id from public.staff where full_name = 'pastor') where id = 'c1100000-0000-4000-8000-000000000003'$sql$), '42501 permission denied for table content_items', 'should refuse even a pastor approving by writing the columns');
select is(pg_temp.error_as('super_admin', $sql$update public.content_items set author_id = (select id from public.staff where full_name = 'super_admin')$sql$), '42501 permission denied for table content_items', 'should refuse a super admin taking over authorship');
select is(pg_temp.error_as('content_editor', format($sql$update public.content_items set author_id = %L where id = 'c1100000-0000-4000-8000-000000000002'$sql$, pg_temp.staff_id_of('content_editor_two'))), '42501 permission denied for table content_items', 'should refuse an editor handing a draft to another author');
select is(pg_temp.error_as('content_editor', format($sql$update public.content_items set author_id = %L where id = 'c1100000-0000-4000-8000-000000000011'$sql$, pg_temp.staff_id_of('content_editor'))), '42501 permission denied for table content_items', 'should refuse an editor taking over another editor''s draft');
select is(pg_temp.error_as('content_editor', $sql$update public.content_items set title = 'stolen' where id = 'c1100000-0000-4000-8000-000000000011'$sql$), 'ok 0', 'should change nothing when an editor edits another editor''s draft');
select is((select title from public.content_items where id = 'c1100000-0000-4000-8000-000000000011'), 'draft_of_editor_two', 'should leave the other editor''s draft as it was');
select is(pg_temp.error_as('content_editor', $sql$update public.content_items set publish_at = now() - interval '1 year', expires_at = now() + interval '10 years' where id = 'c1100000-0000-4000-8000-000000000005'$sql$), 'ok 0', 'should not let an editor stretch the window of a published item');
select is(pg_temp.error_as('content_editor', $sql$update public.content_items set body = 'defaced' where id = 'c1100000-0000-4000-8000-000000000010'$sql$), 'ok 0', 'should not let an editor deface a published page');
select is(pg_temp.error_as('pastor', $sql$update public.content_items set body = 'defaced' where id = 'c1100000-0000-4000-8000-000000000010'$sql$), 'ok 0', 'should not let even a pastor edit a published page in place');
select is((select body from public.content_items where id = 'c1100000-0000-4000-8000-000000000010'), 'Body of history_page', 'should leave the published page as it was');
select is(pg_temp.error_as('content_editor', $sql$update public.sermons set video_url = 'https://evil.example/x' where id = 'c2100000-0000-4000-8000-000000000001'$sql$), 'ok 0', 'should not let an editor repoint a published sermon');
select is(pg_temp.error_as('pastor', $sql$delete from public.content_items where id = 'c1100000-0000-4000-8000-000000000001'$sql$), '42501 permission denied for table content_items', 'should not let a pastor delete a published item');
select is(pg_temp.error_as('content_editor', $sql$update public.content_items set slug = 'history' where id = 'c1100000-0000-4000-8000-000000000002'$sql$), '23514 new row for relation "content_items" violates check constraint "content_items_page_slug_check"', 'should refuse an announcement taking a page slug');
select is(pg_temp.error_as('content_editor', $sql$update public.content_items set kind = 'page', slug = 'history' where id = 'c1100000-0000-4000-8000-000000000002'$sql$), '23505 duplicate key value violates unique constraint "content_items_slug_key"', 'should refuse a second page taking over the history slug');

-- 6. Bringing back what was archived
select is(pg_temp.call_as('pastor', 'return_content_to_draft', 'c1100000-0000-4000-8000-000000000006'), 'P0001 VALIDATION_FAILED', 'should refuse a pastor returning an archived item to draft');
select is(pg_temp.call_as('super_admin', 'publish_content', 'c1100000-0000-4000-8000-000000000006'), 'P0001 VALIDATION_FAILED', 'should refuse a super admin publishing an archived item');
select is(pg_temp.call_as('super_admin', 'approve_sermon', 'c2100000-0000-4000-8000-000000000005'), 'P0001 VALIDATION_FAILED', 'should refuse approving an archived sermon');
select is(pg_temp.call_as('super_admin', 'submit_sermon_for_review', 'c2100000-0000-4000-8000-000000000005'), 'P0001 VALIDATION_FAILED', 'should refuse submitting an archived sermon');
select is(pg_temp.error_as('pastor', $sql$update public.content_items set status = 'draft' where id = 'c1100000-0000-4000-8000-000000000006'$sql$), '42501 permission denied for table content_items', 'should refuse a pastor writing an archived item back to draft');
select throws_ok($sql$update public.sermons set status = 'published' where id = 'c2100000-0000-4000-8000-000000000005'$sql$, 'P0001', 'VALIDATION_FAILED', 'should refuse even the owner publishing an archived sermon');
select is(pg_temp.titles_as('anon', 'sermons') like '%archived_sermon%', false, 'should keep an archived sermon invisible to anon');
select is(pg_temp.call_as('content_editor', 'archive_content', 'c1100000-0000-4000-8000-000000000010'), 'P0001 AUTH_FORBIDDEN', 'should not let an editor take a published page down');

-- 7. Malformed arguments
select is(pg_temp.error_as('pastor', $sql$select * from public.approve_content('not-a-uuid')$sql$), '22P02 invalid input syntax for type uuid: "not-a-uuid"', 'should refuse a malformed id');
select is(pg_temp.error_as('pastor', $sql$select * from public.approve_content('c1100000-0000-4000-8000-000000000003''; drop table public.sermons; --')$sql$), '22P02 invalid input syntax for type uuid: "c1100000-0000-4000-8000-000000000003''; drop table public.sermons; --"', 'should refuse SQL in an id');
select is(pg_temp.error_as('pastor', $sql$select * from public.approve_content()$sql$), '42883 function public.approve_content() does not exist', 'should refuse a call with no id');
select is(pg_temp.error_as('pastor', $sql$select * from public.approve_content('c1100000-0000-4000-8000-000000000003', 'extra')$sql$), '42883 function public.approve_content(unknown, unknown) does not exist', 'should refuse a call with an extra argument');
select is((select count(*) from public.sermons), 6::bigint, 'should still have all the sermons after every malformed call');

select * from finish();

rollback;
