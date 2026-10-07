-- LBC-33 (AC 1, 7): the shape of content_items and sermons: enums, columns, constraints, indexes, comments, triggers,
-- privileges (including the column level SELECT grant for anon), function attributes and the format checks for slugs,
-- storage paths and YouTube links. Fixture and actors: see the preamble.

begin;

select plan(159);

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

-- Enums
select is((select array_agg(enumlabel::text order by enumsortorder) from pg_enum where enumtypid = 'public.content_kind'::regtype), array['announcement', 'quote', 'page', 'activity'], 'should have content_kind with the four kinds of the design');
select is((select array_agg(enumlabel::text order by enumsortorder) from pg_enum where enumtypid = 'public.content_status'::regtype), array['draft', 'in_review', 'published', 'archived'], 'should have content_status with the four statuses of the design, no scheduled status');

-- Columns and keys
select columns_are('public', 'content_items', array['id', 'kind', 'slug', 'title', 'body', 'image_path', 'status', 'publish_at', 'expires_at', 'author_id', 'approved_by', 'created_at', 'updated_at'], 'should have exactly the design columns on content_items');
select columns_are('public', 'sermons', array['id', 'title', 'preacher', 'preached_on', 'series', 'scripture', 'notes', 'video_url', 'audio_path', 'status', 'publish_at', 'author_id', 'approved_by', 'created_at', 'updated_at'], 'should have the design columns on sermons plus publish_at, created_at and updated_at');
select col_is_pk('public', 'content_items', 'id', 'should have id as the primary key of content_items');
select col_is_pk('public', 'sermons', 'id', 'should have id as the primary key of sermons');
select col_is_unique('public', 'content_items', 'slug', 'should keep page slugs unique');
select col_not_null('public', 'content_items', 'kind', 'should require a kind');
select col_not_null('public', 'content_items', 'title', 'should require a title');
select col_not_null('public', 'content_items', 'status', 'should require a status');
select col_not_null('public', 'content_items', 'author_id', 'should require an author');
select col_not_null('public', 'sermons', 'preacher', 'should require a preacher');
select col_not_null('public', 'sermons', 'preached_on', 'should require the date preached');
select col_default_is('public', 'content_items', 'status', 'draft'::text, 'should start every content item as a draft');
select col_default_is('public', 'sermons', 'status', 'draft'::text, 'should start every sermon as a draft');
select col_type_is('public', 'content_items', 'publish_at', 'timestamp with time zone', 'should store publish_at as timestamptz');
select col_type_is('public', 'content_items', 'expires_at', 'timestamp with time zone', 'should store expires_at as timestamptz');
select col_type_is('public', 'sermons', 'preached_on', 'date', 'should store the day preached as a date');
select fk_ok('public', 'content_items', 'author_id', 'public', 'staff', 'id', 'should link content_items.author_id to staff');
select fk_ok('public', 'content_items', 'approved_by', 'public', 'staff', 'id', 'should link content_items.approved_by to staff');
select fk_ok('public', 'sermons', 'author_id', 'public', 'staff', 'id', 'should link sermons.author_id to staff');
select fk_ok('public', 'sermons', 'approved_by', 'public', 'staff', 'id', 'should link sermons.approved_by to staff');
select has_index('public', 'content_items', 'content_items_author_id_idx', 'author_id', 'should index content_items.author_id');
select has_index('public', 'content_items', 'content_items_approved_by_idx', 'approved_by', 'should index content_items.approved_by');
select has_index('public', 'sermons', 'sermons_author_id_idx', 'author_id', 'should index sermons.author_id');
select has_index('public', 'sermons', 'sermons_approved_by_idx', 'approved_by', 'should index sermons.approved_by');

-- RLS, policies, triggers
select is((select relrowsecurity from pg_class where oid = 'public.content_items'::regclass), true, 'should enable row level security on content_items');
select is((select relrowsecurity from pg_class where oid = 'public.sermons'::regclass), true, 'should enable row level security on sermons');
select policies_are('public', 'content_items', array['content_items_select_public', 'content_items_select_editors', 'content_items_insert_editors', 'content_items_update_editors'], 'should have exactly these policies on content_items, and none for delete');
select policies_are('public', 'sermons', array['sermons_select_public', 'sermons_select_editors', 'sermons_insert_editors', 'sermons_update_editors'], 'should have exactly these policies on sermons, and none for delete');
select policy_roles_are('public', 'content_items', 'content_items_select_public', array['anon'], 'should apply the public policy to anon only');
select policy_cmd_is('public', 'content_items', 'content_items_select_public', 'SELECT', 'should make the public policy a select policy');
select is(
  (select count(*) from pg_trigger where tgrelid in ('public.content_items'::regclass, 'public.sermons'::regclass) and tgname in ('audit_content_items', 'audit_sermons') and tgenabled = 'A'),
  2::bigint, 'should have the audit triggers enabled always');
select is(
  (select count(*) from pg_trigger where tgrelid in ('public.content_items'::regclass, 'public.sermons'::regclass) and tgname in ('content_items_updated_at', 'sermons_updated_at', 'content_items_status_flow', 'sermons_status_flow')),
  4::bigint, 'should have the updated_at and status flow triggers on both tables');

-- Every table, column and function has a comment (they become the API documentation)
select is((select count(*) from pg_description where objoid = 'public.content_items'::regclass and objsubid = 0), 1::bigint, 'should comment content_items');
select is((select count(*) from pg_description where objoid = 'public.sermons'::regclass and objsubid = 0), 1::bigint, 'should comment sermons');
select is(
  (select count(*) from pg_attribute where attrelid = 'public.content_items'::regclass and attnum > 0 and not attisdropped and col_description(attrelid, attnum) is null),
  0::bigint, 'should comment every column of content_items');
select is(
  (select count(*) from pg_attribute where attrelid = 'public.sermons'::regclass and attnum > 0 and not attisdropped and col_description(attrelid, attnum) is null),
  0::bigint, 'should comment every column of sermons');
select is(
  (select count(*) from pg_proc where pronamespace in ('public'::regnamespace, 'private'::regnamespace) and proname ~ '(content|sermon|slug|youtube|storage_path|expiry|expired|link_length|title_length|body_length|reserved_slugs)' and obj_description(oid, 'pg_proc') is null),
  0::bigint, 'should comment every content function');
select is(
  (select count(*) from pg_constraint where conrelid in ('public.content_items'::regclass, 'public.sermons'::regclass) and contype = 'f' and obj_description(oid, 'pg_constraint') !~ 'foreign_name'),
  0::bigint, 'should name the GraphQL relationship of every foreign key');

-- Privileges
select is(has_table_privilege('anon', 'public.content_items', 'select'), false, 'should give anon no table level select on content_items');
select is(has_table_privilege('anon', 'public.sermons', 'select'), false, 'should give anon no table level select on sermons');
select is(
  (select array_agg(attname::text order by attnum) from pg_attribute where attrelid = 'public.content_items'::regclass and attnum > 0 and has_column_privilege('anon', attrelid, attnum, 'select')),
  array['id', 'kind', 'slug', 'title', 'body', 'image_path', 'publish_at', 'expires_at'], 'should give anon select on exactly the public columns of content_items');
select is(
  (select array_agg(attname::text order by attnum) from pg_attribute where attrelid = 'public.sermons'::regclass and attnum > 0 and has_column_privilege('anon', attrelid, attnum, 'select')),
  array['id', 'title', 'preacher', 'preached_on', 'series', 'scripture', 'notes', 'video_url', 'audio_path', 'publish_at'], 'should give anon select on exactly the public columns of sermons');
select is(
  (select count(*) from pg_attribute where attrelid in ('public.content_items'::regclass, 'public.sermons'::regclass) and attnum > 0 and (has_column_privilege('anon', attrelid, attnum, 'insert') or has_column_privilege('anon', attrelid, attnum, 'update') or has_column_privilege('anon', attrelid, attnum, 'references'))),
  0::bigint, 'should give anon no write or reference privilege on any column');
select is(
  (select count(*) from (values ('delete'), ('truncate'), ('references'), ('trigger')) as privileges (name), (values ('public.content_items'), ('public.sermons')) as tables (name), (values ('anon'), ('authenticated')) as roles (name)
    where has_table_privilege(roles.name, tables.name, privileges.name)),
  0::bigint, 'should give neither anon nor authenticated delete, truncate, references or trigger on the content tables');
select is(
  (select array_agg(attname::text order by attnum) from pg_attribute where attrelid = 'public.content_items'::regclass and attnum > 0 and has_column_privilege('authenticated', attrelid, attnum, 'update')),
  array['kind', 'slug', 'title', 'body', 'image_path', 'publish_at', 'expires_at'], 'should let authenticated update only the content columns of content_items');
select is(
  (select array_agg(attname::text order by attnum) from pg_attribute where attrelid = 'public.sermons'::regclass and attnum > 0 and has_column_privilege('authenticated', attrelid, attnum, 'update')),
  array['title', 'preacher', 'preached_on', 'series', 'scripture', 'notes', 'video_url', 'audio_path', 'publish_at'], 'should let authenticated update only the content columns of sermons');
select is(
  (select array_agg(attname::text order by attnum) from pg_attribute where attrelid = 'public.content_items'::regclass and attnum > 0 and has_column_privilege('authenticated', attrelid, attnum, 'insert')),
  array['kind', 'slug', 'title', 'body', 'image_path', 'publish_at', 'expires_at', 'author_id'], 'should let authenticated insert only the content columns and the author');
select is(
  (select array_agg(attname::text order by attnum) from pg_attribute where attrelid = 'public.sermons'::regclass and attnum > 0 and has_column_privilege('authenticated', attrelid, attnum, 'insert')),
  array['title', 'preacher', 'preached_on', 'series', 'scripture', 'notes', 'video_url', 'audio_path', 'publish_at', 'author_id'], 'should let authenticated insert only the sermon columns and the author');

-- Functions: the workflow is public and volatile (a GraphQL mutation), definer with an empty search path, for signed-in users only
create temp table workflow_functions (name text, args text, returns_type text);
insert into workflow_functions
values
  ('submit_content_for_review', 'uuid', 'content_items'), ('approve_content', 'uuid', 'content_items'), ('publish_content', 'uuid', 'content_items'),
  ('return_content_to_draft', 'uuid', 'content_items'), ('archive_content', 'uuid', 'content_items'),
  ('submit_sermon_for_review', 'uuid', 'sermons'), ('approve_sermon', 'uuid', 'sermons'), ('publish_sermon', 'uuid', 'sermons'),
  ('return_sermon_to_draft', 'uuid', 'sermons'), ('archive_sermon', 'uuid', 'sermons');

select is((select count(*) from workflow_functions where to_regprocedure(format('public.%s(%s)', name, args)) is not null), 10::bigint, 'should have all ten workflow functions in public');
select is((select count(*) from workflow_functions where (select provolatile from pg_proc where oid = to_regprocedure(format('public.%s(%s)', name, args))) = 'v'), 10::bigint, 'should make every workflow function volatile, so it is a mutation');
select is((select count(*) from workflow_functions where (select prosecdef from pg_proc where oid = to_regprocedure(format('public.%s(%s)', name, args)))), 10::bigint, 'should make every workflow function security definer');
select is((select count(*) from workflow_functions where (select proconfig from pg_proc where oid = to_regprocedure(format('public.%s(%s)', name, args))) = array['search_path=""']), 10::bigint, 'should give every workflow function an empty search path');
select is((select count(*) from workflow_functions where (select prorettype::regtype::text from pg_proc where oid = to_regprocedure(format('public.%s(%s)', name, args))) = returns_type), 10::bigint, 'should return one row of the right table from every workflow function');
select is((select count(*) from pg_proc where oid in (select to_regprocedure(format('public.%s(%s)', name, args)) from workflow_functions) and proretset), 0::bigint, 'should return no set from a mutation');
select is((select count(*) from workflow_functions where has_function_privilege('anon', to_regprocedure(format('public.%s(%s)', name, args)), 'execute')), 0::bigint, 'should let anon execute no workflow function');
select is((select count(*) from workflow_functions where has_function_privilege('authenticated', to_regprocedure(format('public.%s(%s)', name, args)), 'execute')), 10::bigint, 'should let authenticated execute every workflow function');
select is((select count(*) from workflow_functions, pg_proc where pg_proc.oid = to_regprocedure(format('public.%s(%s)', name, args)) and not exists (select 1 from aclexplode(coalesce(proacl, acldefault('f', proowner))) as acl where acl.grantee = 0 and acl.privilege_type = 'EXECUTE')), 10::bigint, 'should not leave execute with PUBLIC on any workflow function');
select is((select count(*) from workflow_functions where length(name) > 0 and (select pronargs from pg_proc where oid = to_regprocedure(format('public.%s(%s)', name, args))) = 1 and (select proargnames[1] from pg_proc where oid = to_regprocedure(format('public.%s(%s)', name, args))) = 'p_id'), 10::bigint, 'should give every workflow function a single p_id argument');

select is(
  (select count(*) from pg_proc where pronamespace = 'private'::regnamespace
    and proname in ('max_title_length', 'max_slug_length', 'max_body_length', 'max_link_length', 'reserved_slugs', 'youtube_hosts', 'is_valid_slug', 'is_safe_storage_path', 'is_youtube_url', 'can_edit_content', 'can_approve_content', 'guard_content_status_flow', 'next_content_status', 'next_content_approver', 'expiry_job_name', 'expiry_job_schedule', 'archive_expired_content')
    and has_function_privilege('anon', oid, 'execute')),
  0::bigint, 'should let anon execute no private content helper');
select is(
  (select count(*) from pg_proc where pronamespace = 'private'::regnamespace
    and proname in ('guard_content_status_flow', 'next_content_status', 'next_content_approver', 'expiry_job_name', 'expiry_job_schedule', 'archive_expired_content')
    and has_function_privilege('authenticated', oid, 'execute')),
  0::bigint, 'should let authenticated execute none of the flow, guard and job functions directly');
select is(
  (select count(*) from pg_proc where pronamespace = 'private'::regnamespace
    and proname in ('is_valid_slug', 'is_safe_storage_path', 'is_youtube_url', 'can_edit_content', 'can_approve_content', 'next_content_status', 'next_content_approver', 'guard_content_status_flow', 'archive_expired_content')
    and (proconfig is null or proconfig <> array['search_path=""'])),
  0::bigint, 'should give every private content function an empty search path');

-- Constants
select is(private.max_title_length(), 200, 'should cap titles at 200 characters');
select is(private.max_slug_length(), 100, 'should cap slugs at 100 characters');
select is(private.max_body_length(), 50000, 'should cap bodies at 50000 characters');
select is(private.max_link_length(), 500, 'should cap paths and links at 500 characters');

-- Slugs
select is(private.is_valid_slug('history'), true, 'should accept a simple slug');
select is(private.is_valid_slug('our-story-2'), true, 'should accept hyphens and digits');
select is(private.is_valid_slug(slug), false, format('should reject the slug %L', replace(slug, chr(10), ' ')))
from unnest(array['History', 'has space', 'a--b', '-lead', 'trail-', 'a/b', '../etc', 'caf' || chr(233), 'under_score', 'dot.dot', E'history\n', '', 'admin', 'api', 'login', 'sermons', repeat('a', 101)]) as slug;
select is(private.is_valid_slug(repeat('a', 100)), true, 'should accept a slug of exactly 100 characters');
select is(private.is_valid_slug(null), null, 'should pass a null slug on to the CHECK, which accepts it');

-- Storage paths
select is(private.is_safe_storage_path(path), true, format('should accept the storage path %L', path))
from unnest(array['images/church.png', 'sermons/walking-in-faith.mp3', 'a.b-c_d/e']) as path;
select is(private.is_safe_storage_path(path), false, format('should reject the storage path %L', replace(path, chr(10), ' ')))
from unnest(array['https://evil.example/x.png', '//evil.example/x', '/abs/path', '../x', 'a/../b', 'a//b', 'a b', 'a?b', 'a#b', 'a<b', E'a\nb', 'javascript:alert(1)', 'data:text/html,x', '', repeat('a', 501)]) as path;

-- YouTube links
select is(private.is_youtube_url(url), true, format('should accept the video link %L', url))
from unnest(array['https://www.youtube.com/watch?v=abc123', 'https://youtu.be/abc123', 'https://youtube.com/watch?v=abc&t=10', 'https://m.youtube.com/watch?v=abc', 'https://www.youtube-nocookie.com/embed/abc123']) as url;
select is(private.is_youtube_url(url), false, format('should reject the video link %L', replace(url, chr(10), ' ')))
from unnest(array['http://www.youtube.com/watch?v=abc', 'https://evil.com/watch?v=abc', 'https://youtube.com.evil.com/x', 'https://evil.com/youtube.com/x', 'https://user@www.youtube.com/x', 'https://www.youtube.com:8080/x', 'https://www.youtube.com/', 'https://www.youtube.com', 'javascript:alert(1)', 'https://www.youtube.com/a b', 'https://www.youtube.com/"onload=x', 'https://www.youtube.com/<script>', E'https://www.youtube.com/x\ny', '//www.youtube.com/x', 'ftp://www.youtube.com/x', 'https://WWW.YOUTUBE.COM.evil.com/x', repeat('a', 501)]) as url;

-- The table refuses what the helpers refuse, and the other content rules
create function pg_temp.insert_item(p_columns text, p_values text)
returns text
language plpgsql
as $$
begin
  execute format('insert into public.content_items (kind, title, author_id%s) values (''announcement'', ''t'', %L%s)', p_columns, (select staff_id from actors where label = 'content_editor'), p_values);
  return 'ok';
exception when others then
  return sqlstate || ' ' || substring(sqlerrm from 'constraint "([a-z_]+)"');
end;
$$;

select is(pg_temp.insert_item('', ''), 'ok', 'should accept a plain announcement');
select throws_ok($sql$insert into public.content_items (kind, slug, title, author_id) values ('page', 'Bad Slug', 't', (select id from public.staff limit 1))$sql$, '23514', null, 'should reject a badly formed page slug');
select throws_ok($sql$insert into public.content_items (kind, slug, title, author_id) values ('page', 'admin', 't', (select id from public.staff limit 1))$sql$, '23514', null, 'should reject a reserved page slug');
select is(pg_temp.insert_item(', slug', ', ''history'''), '23514 content_items_page_slug_check', 'should reject a slug on an announcement');
select is(pg_temp.insert_item(', image_path', ', ''https://evil.example/x.png'''), '23514 content_items_image_path_check', 'should reject an image link to another site');
select is(pg_temp.insert_item(', image_path', ', ''images/a.png'''), 'ok', 'should accept an image path in the bucket');
select is(pg_temp.insert_item(', publish_at, expires_at', ', now(), now()'), '23514 content_items_window_check', 'should reject an expiry that is not after publish_at');
select is(pg_temp.insert_item(', publish_at, expires_at', ', now(), now() + interval ''1 second'''), 'ok', 'should accept an expiry one second after publish_at');
select is(pg_temp.insert_item(', body', ', repeat(''a'', 50001)'), '23514 content_items_body_check', 'should reject a body over the limit');
select is(pg_temp.insert_item(', body', ', repeat(''a'', 50000)'), 'ok', 'should accept a body of exactly the limit');
select is(pg_temp.insert_item(', body', ', ''<script>alert(1)</script> **bold**'''), 'ok', 'should store Markdown and markup as plain text, to be rendered safely by the reader');
select is((select body from public.content_items where body like '<script>%'), '<script>alert(1)</script> **bold**', 'should keep the body exactly as written');
select throws_ok($sql$insert into public.content_items (kind, title, author_id) values ('page', 't', (select id from public.staff limit 1))$sql$, '23514', null, 'should reject a page with no slug');
select throws_ok($sql$insert into public.content_items (kind, title, author_id) values ('announcement', '   ', (select id from public.staff limit 1))$sql$, '23514', null, 'should reject a blank title');
select throws_ok($sql$insert into public.content_items (kind, title, author_id) values ('announcement', repeat('a', 201), (select id from public.staff limit 1))$sql$, '23514', null, 'should reject a title over 200 characters');
select throws_ok($sql$insert into public.content_items (kind, slug, title, author_id) values ('page', 'history', 'second history', (select id from public.staff limit 1))$sql$, '23505', null, 'should reject a second page with the same slug');
select throws_ok($sql$insert into public.content_items (kind, title, author_id) values ('banner', 'x', (select id from public.staff limit 1))$sql$, '22P02', null, 'should reject a kind that is not in the enum');
select throws_ok($sql$insert into public.content_items (kind, title, author_id) values ('announcement', 'x', gen_random_uuid())$sql$, '23503', null, 'should reject an author who is not staff');
select throws_ok($sql$insert into public.content_items (kind, title, author_id, status) values ('announcement', 'x', (select id from public.staff limit 1), 'scheduled')$sql$, '22P02', null, 'should reject a scheduled status, which is not part of the design');

create function pg_temp.insert_sermon(p_columns text, p_values text)
returns text
language plpgsql
as $$
begin
  execute format('insert into public.sermons (title, preacher, preached_on, author_id%s) values (''t'', ''p'', ''2026-10-04'', %L%s)', p_columns, (select staff_id from actors where label = 'content_editor'), p_values);
  return 'ok';
exception when others then
  return sqlstate || ' ' || substring(sqlerrm from 'constraint "([a-z_]+)"');
end;
$$;

select is(pg_temp.insert_sermon('', ''), 'ok', 'should accept a plain sermon');
select is(pg_temp.insert_sermon(', video_url', ', ''https://www.youtube.com/watch?v=abc123'''), 'ok', 'should accept a YouTube link');
select is(pg_temp.insert_sermon(', video_url', ', ''https://evil.example/watch?v=abc'''), '23514 sermons_video_url_check', 'should reject a video link that is not YouTube');
select is(pg_temp.insert_sermon(', video_url', ', ''http://www.youtube.com/watch?v=abc'''), '23514 sermons_video_url_check', 'should reject a video link that is not https');
select is(pg_temp.insert_sermon(', audio_path', ', ''https://evil.example/a.mp3'''), '23514 sermons_audio_path_check', 'should reject an audio link to another site');
select is(pg_temp.insert_sermon(', audio_path', ', ''sermons/a.mp3'''), 'ok', 'should accept an audio path in the bucket');
select is(pg_temp.insert_sermon(', notes', ', repeat(''a'', 50001)'), '23514 sermons_notes_check', 'should reject notes over the limit');
select is(pg_temp.insert_sermon(', series', ', repeat(''a'', 201)'), '23514 sermons_series_check', 'should reject a series name over the limit');
select is(pg_temp.insert_sermon(', scripture', ', repeat(''a'', 201)'), '23514 sermons_scripture_check', 'should reject a scripture reference over the limit');
select throws_ok($sql$insert into public.sermons (title, preacher, preached_on, author_id) values ('', 'p', '2026-10-04', (select id from public.staff limit 1))$sql$, '23514', null, 'should reject a sermon with an empty title');
select throws_ok($sql$insert into public.sermons (title, preacher, preached_on, author_id) values ('t', '  ', '2026-10-04', (select id from public.staff limit 1))$sql$, '23514', null, 'should reject a sermon with a blank preacher');
select throws_ok($sql$insert into public.sermons (title, preacher, author_id) values ('t', 'p', (select id from public.staff limit 1))$sql$, '23502', null, 'should reject a sermon with no date');

select * from finish();

rollback;
