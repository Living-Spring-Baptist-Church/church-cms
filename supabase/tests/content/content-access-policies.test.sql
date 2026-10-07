-- LBC-33 (AC 4, 7): the row level security and grants of content_items and sermons for every role. The four content
-- roles (super admin, pastor, secretary, content editor) see every row and edit only drafts, a secretary or content
-- editor only their own; nobody else sees anything; anon sees only published rows inside their window and only the
-- public columns; status, approved_by and author_id are never written directly; nobody deletes. Fixture and actors:
-- see the preamble.

begin;

select plan(205);

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

-- Who sees which rows: the four content roles see every row, anon sees only the live ones, nobody else sees any.
create temp table content_viewers (label text primary key);
insert into content_viewers values ('super_admin'), ('pastor'), ('pastor_two'), ('secretary'), ('content_editor'), ('content_editor_two');

select is(
  pg_temp.run_as(actors.label, format('select id from public.%I', relations.relation)),
  case
    when actors.label in (select label from content_viewers) then relations.total_rows
    when actors.label = 'anon' then relations.public_rows
    else 0::bigint
  end,
  format('should show %s %s rows of %s', actors.label,
    case when actors.label in (select label from content_viewers) then relations.total_rows when actors.label = 'anon' then relations.public_rows else 0 end,
    relations.relation)
)
from actors
cross join (values ('content_items', 13::bigint, 4::bigint), ('sermons', 6::bigint, 2::bigint)) as relations (relation, total_rows, public_rows)
order by relations.relation, actors.label;

-- anon sees exactly the live rows, by title
select is(pg_temp.titles_as('anon', 'content_items'), 'history_page,live_announcement,no_expiry,publish_at_now',
  'should show anon exactly the published announcements, quote and page inside their window');
select is(pg_temp.titles_as('anon', 'sermons'), 'live_sermon,sermon_publish_at_now',
  'should show anon exactly the published sermons whose publish_at has passed');

-- Insert: the four content roles create drafts as themselves, everyone else is refused
select is(
  pg_temp.error_as(actors.label, format($sql$insert into public.content_items (kind, title, author_id) values ('announcement', %L, %L)$sql$, 'new_by_' || actors.label, actors.staff_id)),
  case
    when actors.label in ('super_admin', 'pastor', 'pastor_two', 'secretary', 'content_editor', 'content_editor_two') then 'ok 1'
    when actors.label = 'anon' then '42501 permission denied for table content_items'
    else '42501 new row violates row-level security policy for table "content_items"'
  end,
  format('should %s %s creating a content item', case when actors.label in ('super_admin', 'pastor', 'pastor_two', 'secretary', 'content_editor', 'content_editor_two') then 'let' else 'refuse' end, actors.label)
)
from actors
order by actors.label;

select is(
  pg_temp.error_as(actors.label, format($sql$insert into public.sermons (title, preacher, preached_on, author_id) values (%L, 'Preacher', '2026-10-04', %L)$sql$, 'new_by_' || actors.label, actors.staff_id)),
  case
    when actors.label in ('super_admin', 'pastor', 'pastor_two', 'secretary', 'content_editor', 'content_editor_two') then 'ok 1'
    when actors.label = 'anon' then '42501 permission denied for table sermons'
    else '42501 new row violates row-level security policy for table "sermons"'
  end,
  format('should %s %s creating a sermon', case when actors.label in ('super_admin', 'pastor', 'pastor_two', 'secretary', 'content_editor', 'content_editor_two') then 'let' else 'refuse' end, actors.label)
)
from actors
order by actors.label;

select is(
  (select count(*) from public.content_items where title like 'new_by_%' and status = 'draft' and approved_by is null and author_id = (select staff_id from actors where label = right(title, -7))),
  6::bigint, 'should record each created item as a draft by its own author with no approver');

select is(pg_temp.error_as('content_editor', format($sql$insert into public.content_items (kind, title, author_id) values ('announcement', 'impersonated', %L)$sql$, pg_temp.staff_id_of('content_editor_two'))),
  '42501 new row violates row-level security policy for table "content_items"', 'should refuse creating an item in another author''s name');
select is(pg_temp.error_as('pastor', format($sql$insert into public.content_items (kind, title, author_id) values ('announcement', 'impersonated', %L)$sql$, pg_temp.staff_id_of('content_editor'))),
  '42501 new row violates row-level security policy for table "content_items"', 'should refuse even a pastor creating an item in another author''s name');
select is(pg_temp.error_as('content_editor', format($sql$insert into public.content_items (kind, title, author_id, status, publish_at, approved_by) values ('announcement', 'self_published', %L, 'published', now(), %L)$sql$, pg_temp.staff_id_of('content_editor'), pg_temp.staff_id_of('pastor'))),
  '42501 permission denied for table content_items', 'should refuse creating an item that is already published and approved');
select is(pg_temp.error_as('content_editor', format($sql$insert into public.content_items (kind, title, author_id, approved_by) values ('announcement', 'self_approved', %L, %L)$sql$, pg_temp.staff_id_of('content_editor'), pg_temp.staff_id_of('content_editor'))),
  '42501 permission denied for table content_items', 'should refuse naming an approver at creation');
select is(pg_temp.error_as('super_admin', format($sql$insert into public.content_items (kind, title, author_id, status) values ('announcement', 'super_published', %L, 'published')$sql$, pg_temp.staff_id_of('super_admin'))),
  '42501 permission denied for table content_items', 'should refuse even a super admin setting the status directly at creation');
select is(pg_temp.error_as('content_editor', format($sql$insert into public.sermons (title, preacher, preached_on, author_id, status) values ('self_published', 'P', '2026-10-04', %L, 'published')$sql$, pg_temp.staff_id_of('content_editor'))),
  '42501 permission denied for table sermons', 'should refuse creating a sermon with a status');

-- Update: only drafts, only by their author or a pastor or super admin, and only the content columns
select is(
  pg_temp.error_as(actors.label, $sql$update public.content_items set title = 'edited' where id = 'c1100000-0000-4000-8000-000000000002'$sql$),
  case
    when actors.label in ('super_admin', 'pastor', 'pastor_two', 'content_editor') then 'ok 1'
    when actors.label = 'anon' then '42501 permission denied for table content_items'
    else 'ok 0'
  end,
  format('should %s %s editing the draft of content_editor', case when actors.label in ('super_admin', 'pastor', 'pastor_two', 'content_editor') then 'let' else 'not let' end, actors.label)
)
from actors
order by actors.label;

select is(pg_temp.error_as('secretary', $sql$update public.content_items set title = 'edited' where id = 'c1100000-0000-4000-8000-000000000013'$sql$), 'ok 1', 'should let the secretary edit their own draft');
select is(pg_temp.error_as('content_editor', $sql$update public.content_items set title = 'edited' where id = 'c1100000-0000-4000-8000-000000000013'$sql$), 'ok 0', 'should not let a content editor edit the secretary''s draft');
select is(pg_temp.error_as('pastor', $sql$update public.content_items set title = 'edited' where id = 'c1100000-0000-4000-8000-000000000013'$sql$), 'ok 1', 'should let a pastor edit the secretary''s draft');
select is(pg_temp.error_as('content_editor', $sql$update public.content_items set kind = 'quote', body = 'new text' where id = 'c1100000-0000-4000-8000-000000000002'$sql$), 'ok 1', 'should let an author change the kind and body of their draft');

select is(
  pg_temp.error_as(actors.label, format($sql$update public.content_items set title = 'edited' where id = %L$sql$, items.id)),
  'ok 0',
  format('should not let %s edit the %s item', actors.label, items.title)
)
from (select * from actors where label in ('super_admin', 'pastor', 'content_editor', 'secretary')) as actors
cross join (select id, title from public.content_items where title in ('in_review_item', 'live_announcement', 'archived_item', 'scheduled_future', 'approved_in_review')) as items
order by items.title, actors.label;

select is(pg_temp.error_as('pastor', $sql$update public.sermons set title = 'edited' where id = 'c2100000-0000-4000-8000-000000000002'$sql$), 'ok 1', 'should let a pastor edit a draft sermon');
select is(pg_temp.error_as('content_editor', $sql$update public.sermons set title = 'edited' where id = 'c2100000-0000-4000-8000-000000000002'$sql$), 'ok 1', 'should let the author edit their draft sermon');
select is(pg_temp.error_as('content_editor_two', $sql$update public.sermons set title = 'edited' where id = 'c2100000-0000-4000-8000-000000000002'$sql$), 'ok 0', 'should not let another editor edit the draft sermon');
select is(pg_temp.error_as('secretary', $sql$update public.sermons set title = 'edited' where id = 'c2100000-0000-4000-8000-000000000002'$sql$), 'ok 0', 'should not let the secretary edit another author''s draft sermon');
select is(pg_temp.error_as('treasurer', $sql$update public.sermons set title = 'edited' where id = 'c2100000-0000-4000-8000-000000000002'$sql$), 'ok 0', 'should not let the treasurer edit a sermon');
select is(pg_temp.error_as('pastor', $sql$update public.sermons set title = 'edited' where id = 'c2100000-0000-4000-8000-000000000003'$sql$), 'ok 0', 'should not let a pastor edit a sermon that is in review');
select is(pg_temp.error_as('pastor', $sql$update public.sermons set title = 'edited' where id = 'c2100000-0000-4000-8000-000000000001'$sql$), 'ok 0', 'should not let a pastor edit a published sermon');

-- Update of the columns only the workflow may write: refused for every role, even on an editable draft
select is(
  pg_temp.error_as(actors.label, format($sql$update public.content_items set %I = %s where id = 'c1100000-0000-4000-8000-000000000002'$sql$, changes.column_name, changes.new_value)),
  '42501 permission denied for table content_items',
  format('should refuse %s writing %s directly', actors.label, changes.column_name)
)
from (select * from actors where label in ('super_admin', 'pastor', 'secretary', 'content_editor')) as actors
cross join (values
  ('status', '''published'''),
  ('approved_by', '(select id from public.staff limit 1)'),
  ('author_id', '(select id from public.staff limit 1)'),
  ('created_at', 'now()'),
  ('updated_at', 'now()'),
  ('id', 'gen_random_uuid()')
) as changes (column_name, new_value)
order by changes.column_name, actors.label;

select is(
  pg_temp.error_as(actors.label, format($sql$update public.sermons set %I = %s where id = 'c2100000-0000-4000-8000-000000000002'$sql$, changes.column_name, changes.new_value)),
  '42501 permission denied for table sermons',
  format('should refuse %s writing sermons.%s directly', actors.label, changes.column_name)
)
from (select * from actors where label in ('super_admin', 'pastor', 'content_editor')) as actors
cross join (values ('status', '''published'''), ('approved_by', '(select id from public.staff limit 1)'), ('author_id', '(select id from public.staff limit 1)')) as changes (column_name, new_value)
order by changes.column_name, actors.label;

-- Delete: nobody, ever
select is(
  pg_temp.error_as(actors.label, format('delete from public.%I', relations.relation)),
  format('42501 permission denied for table %s', relations.relation),
  format('should refuse %s deleting from %s', actors.label, relations.relation)
)
from actors
cross join (values ('content_items'), ('sermons')) as relations (relation)
order by relations.relation, actors.label;

-- Edits that would break a content rule are rejected by the table itself
select is(pg_temp.error_as('content_editor', $sql$update public.content_items set slug = 'not-a-page-slug' where id = 'c1100000-0000-4000-8000-000000000002'$sql$), '23514 new row for relation "content_items" violates check constraint "content_items_page_slug_check"', 'should refuse a slug on an announcement');

-- Anon: public columns only, and nothing else
select is(pg_temp.error_as('anon', 'select id, kind, slug, title, body, image_path, publish_at, expires_at from public.content_items'), 'ok 4', 'should let anon read the public columns of content_items');
select is(pg_temp.error_as('anon', 'select id, title, preacher, preached_on, series, scripture, notes, video_url, audio_path, publish_at from public.sermons'), 'ok 2', 'should let anon read the public columns of sermons');
select is(pg_temp.error_as('anon', 'select * from public.content_items'), '42501 permission denied for table content_items', 'should refuse anon select * on content_items');
select is(pg_temp.error_as('anon', 'select * from public.sermons'), '42501 permission denied for table sermons', 'should refuse anon select * on sermons');
select is(
  pg_temp.error_as('anon', format('select %I from public.content_items', hidden.column_name)),
  '42501 permission denied for table content_items',
  format('should hide content_items.%s from anon', hidden.column_name)
)
from (values ('status'), ('author_id'), ('approved_by'), ('created_at'), ('updated_at')) as hidden (column_name);
select is(
  pg_temp.error_as('anon', format('select %I from public.sermons', hidden.column_name)),
  '42501 permission denied for table sermons',
  format('should hide sermons.%s from anon', hidden.column_name)
)
from (values ('status'), ('author_id'), ('approved_by'), ('created_at'), ('updated_at')) as hidden (column_name);
select is(pg_temp.error_as('anon', $sql$select id from public.content_items where status = 'draft'$sql$), '42501 permission denied for table content_items', 'should refuse anon filtering on the hidden status column');
select is(pg_temp.error_as('anon', $sql$select id from public.content_items order by author_id$sql$), '42501 permission denied for table content_items', 'should refuse anon ordering by a hidden column');
select is(pg_temp.error_as('anon', $sql$insert into public.content_items (kind, title, author_id) values ('announcement', 'x', gen_random_uuid())$sql$), '42501 permission denied for table content_items', 'should refuse anon inserting');
select is(pg_temp.error_as('anon', $sql$update public.content_items set title = 'x'$sql$), '42501 permission denied for table content_items', 'should refuse anon updating');
select is(pg_temp.error_as('anon', $sql$select * from audit.log$sql$), '42501 permission denied for schema audit', 'should keep the audit log closed to anon');

select * from finish();

rollback;
