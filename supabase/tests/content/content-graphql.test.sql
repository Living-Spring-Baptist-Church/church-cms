-- LBC-33 (AC 2, 4, 7): the GraphQL surface of content_items and sermons. Every field of each type is listed for anon
-- and for a signed-in user, so a duplicated relationship name or a leaked column cannot slip in. anon sees only the two
-- collections with the public columns and no relationship, no mutation and no staff type; the workflow mutations work
-- for a pastor and fail for a content editor; there is no delete mutation and no way to write status or approved_by;
-- a node id cannot be used to read a hidden row. Fixture and actors: see the preamble.

begin;

select plan(76);

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

-- pg_graphql answers introspection only when the schema comment turns it on (as scripts/export-graphql-schema.mjs
-- does). Switched on here for this rolled-back transaction only.
do $enable_introspection$
begin
  execute format(
    'comment on schema public is %L',
    regexp_replace(obj_description('public'::regnamespace, 'pg_namespace'), '^@graphql[(][{]', '@graphql({"introspection": true, ')
  );
end
$enable_introspection$;

create function pg_temp.type_fields(p_label text, p_type text)
returns jsonb
language sql
as $$
  select jsonb_agg(field ->> 'name' order by field ->> 'name')
  from jsonb_array_elements(
    pg_temp.graphql_as(p_label, format('{ __type(name: "%s") { fields { name } } }', p_type)) #> '{data,__type,fields}'
  ) as field;
$$;

create function pg_temp.input_fields(p_label text, p_type text)
returns jsonb
language sql
as $$
  select jsonb_agg(field ->> 'name' order by field ->> 'name')
  from jsonb_array_elements(
    pg_temp.graphql_as(p_label, format('{ __type(name: "%s") { inputFields { name } } }', p_type)) #> '{data,__type,inputFields}'
  ) as field;
$$;

create function pg_temp.mutation_names(p_label text)
returns jsonb
language sql
as $$
  select jsonb_agg(field ->> 'name' order by field ->> 'name')
  from jsonb_array_elements(
    pg_temp.graphql_as(p_label, '{ __schema { mutationType { fields { name } } } }') #> '{data,__schema,mutationType,fields}'
  ) as field;
$$;

create function pg_temp.query_names(p_label text)
returns jsonb
language sql
as $$
  select jsonb_agg(field ->> 'name' order by field ->> 'name')
  from jsonb_array_elements(
    pg_temp.graphql_as(p_label, '{ __schema { queryType { fields { name } } } }') #> '{data,__schema,queryType,fields}'
  ) as field;
$$;

create function pg_temp.node_id_of(p_collection text, p_id text)
returns text
language sql
as $$
  select pg_temp.graphql_as('super_admin', format('{ %s(filter: { id: { eq: "%s" } }) { edges { node { nodeId } } } }', p_collection, p_id)) #>> array['data', p_collection, 'edges', '0', 'node', 'nodeId'];
$$;

create function pg_temp.titles_of(p_result jsonb, p_collection text)
returns text
language sql
as $$
  select string_agg(edge #>> '{node,title}', ',' order by edge #>> '{node,title}')
  from jsonb_array_elements(p_result #> array['data', p_collection, 'edges']) as edge;
$$;

-- Every field on each type, for anon and for a signed-in user
select is(pg_temp.type_fields('anon', 'ContentItems'),
  '["body", "expiresAt", "id", "imagePath", "kind", "nodeId", "publishAt", "slug", "title"]'::jsonb,
  'should list for anon exactly the public fields of ContentItems, with no status, author or approver');
select is(pg_temp.type_fields('anon', 'Sermons'),
  '["audioPath", "id", "nodeId", "notes", "preachedOn", "preacher", "publishAt", "scripture", "series", "title", "videoUrl"]'::jsonb,
  'should list for anon exactly the public fields of Sermons');
select is(pg_temp.type_fields('pastor', 'ContentItems'),
  '["approvedBy", "approvedByStaff", "authorId", "authorStaff", "body", "createdAt", "expiresAt", "id", "imagePath", "kind", "nodeId", "publishAt", "slug", "status", "title", "updatedAt"]'::jsonb,
  'should list for a signed-in user exactly these fields of ContentItems, with each staff relationship apart from its id field');
select is(pg_temp.type_fields('pastor', 'Sermons'),
  '["approvedBy", "approvedByStaff", "audioPath", "authorId", "authorStaff", "createdAt", "id", "nodeId", "notes", "preachedOn", "preacher", "publishAt", "scripture", "series", "status", "title", "updatedAt", "videoUrl"]'::jsonb,
  'should list for a signed-in user exactly these fields of Sermons');
select is(pg_temp.type_fields('super_admin', 'Staff') @> '["approvedContentItemsCollection", "approvedSermonsCollection", "authoredContentItemsCollection", "authoredSermonsCollection"]'::jsonb, true,
  'should list the four content relationships on Staff');

-- What anon can reach at all
select is(pg_temp.query_names('anon'), '["contentItemsByPk", "contentItemsCollection", "node", "sermonsByPk", "sermonsCollection"]'::jsonb, 'should offer anon only the two content collections and node as queries');
select is(pg_temp.graphql_as('anon', '{ __schema { mutationType { fields { name } } } }') #>> '{data,__schema,mutationType}', null, 'should offer anon no mutation at all');
select is(pg_temp.graphql_as('anon', '{ __type(name: "Staff") { name } }') #>> '{data,__type}', null, 'should not show anon the Staff type');
select is(pg_temp.graphql_as('anon', '{ __type(name: "ContentItemsFilter") { name } }') #>> '{data,__type,name}', 'ContentItemsFilter', 'should show anon the filter of the public columns');
select is(pg_temp.input_fields('anon', 'ContentItemsFilter'), '["and", "body", "expiresAt", "id", "imagePath", "kind", "nodeId", "not", "or", "publishAt", "slug", "title"]'::jsonb, 'should let anon filter only on public columns');
select is(pg_temp.input_fields('anon', 'ContentItemsOrderBy'), '["body", "expiresAt", "id", "imagePath", "kind", "publishAt", "slug", "title"]'::jsonb, 'should let anon order only by public columns');
select is(pg_temp.input_fields('anon', 'SermonsFilter'), '["and", "audioPath", "id", "nodeId", "not", "notes", "or", "preachedOn", "preacher", "publishAt", "scripture", "series", "title", "videoUrl"]'::jsonb, 'should let anon filter sermons only on public columns');
select is(pg_temp.type_fields('anon', 'Query') @> '["servicesCollection"]'::jsonb, false, 'should not offer anon the services collection (weekly activities are a public-site decision)');

-- What a signed-in user can write
select is(pg_temp.input_fields('pastor', 'ContentItemsInsertInput'), '["authorId", "body", "expiresAt", "imagePath", "kind", "publishAt", "slug", "title"]'::jsonb, 'should accept only these fields when inserting a content item, never status or approvedBy');
select is(pg_temp.input_fields('pastor', 'ContentItemsUpdateInput'), '["body", "expiresAt", "imagePath", "kind", "publishAt", "slug", "title"]'::jsonb, 'should accept only these fields when updating a content item');
select is(pg_temp.input_fields('pastor', 'SermonsInsertInput'), '["audioPath", "authorId", "notes", "preachedOn", "preacher", "publishAt", "scripture", "series", "title", "videoUrl"]'::jsonb, 'should accept only these fields when inserting a sermon');
select is(pg_temp.input_fields('pastor', 'SermonsUpdateInput'), '["audioPath", "notes", "preachedOn", "preacher", "publishAt", "scripture", "series", "title", "videoUrl"]'::jsonb, 'should accept only these fields when updating a sermon');
select is(
  (select jsonb_agg(name order by name) from jsonb_array_elements_text(pg_temp.mutation_names('pastor')) as names (name) where name ~ '(?i)content|sermon'),
  '["approveContent", "approveSermon", "archiveContent", "archiveSermon", "insertIntoContentItemsCollection", "insertIntoSermonsCollection", "publishContent", "publishSermon", "returnContentToDraft", "returnSermonToDraft", "submitContentForReview", "submitSermonForReview", "updateContentItemsCollection", "updateSermonsCollection"]'::jsonb,
  'should offer the ten workflow mutations and the generated insert and update, and no delete');

-- anon reads the public site queries
select is(pg_temp.titles_of(pg_temp.graphql_as('anon', '{ contentItemsCollection { edges { node { title } } } }'), 'contentItemsCollection'),
  'history_page,live_announcement,no_expiry,publish_at_now', 'should let anon list exactly the live content items through GraphQL');
select is(pg_temp.titles_of(pg_temp.graphql_as('anon', '{ sermonsCollection { edges { node { title } } } }'), 'sermonsCollection'),
  'live_sermon,sermon_publish_at_now', 'should let anon list exactly the live sermons through GraphQL');
select is(pg_temp.titles_of(pg_temp.graphql_as('anon', '{ contentItemsCollection(filter: { kind: { eq: page } }) { edges { node { title slug } } } }'), 'contentItemsCollection'),
  'history_page', 'should let anon fetch a page by kind');
select is(pg_temp.graphql_as('anon', '{ contentItemsCollection(filter: { slug: { eq: "history" } }) { edges { node { title body } } } }') #>> '{data,contentItemsCollection,edges,0,node,body}',
  'Body of history_page', 'should let anon fetch a page by slug');
select is(pg_temp.graphql_as('anon', '{ contentItemsCollection(orderBy: [{ publishAt: DescNullsLast }], first: 1) { edges { node { title } } } }') #>> '{data,contentItemsCollection,edges,0,node,title}',
  'publish_at_now', 'should let anon order the live items newest first');
select is(pg_temp.graphql_as('anon', '{ contentItemsByPk(id: "c1100000-0000-4000-8000-000000000001") { title } }') #>> '{data,contentItemsByPk,title}',
  'live_announcement', 'should let anon fetch a live item by id');

-- anon cannot reach hidden rows or hidden fields
select is(pg_temp.graphql_as('anon', '{ contentItemsByPk(id: "c1100000-0000-4000-8000-000000000002") { title } }') #>> '{data,contentItemsByPk}', null, 'should give anon nothing for the id of a draft');
select is(pg_temp.graphql_as('anon', '{ contentItemsByPk(id: "c1100000-0000-4000-8000-000000000005") { title } }') #>> '{data,contentItemsByPk}', null, 'should give anon nothing for the id of an expired item');
select is(pg_temp.graphql_as('anon', '{ contentItemsByPk(id: "c1100000-0000-4000-8000-000000000004") { title } }') #>> '{data,contentItemsByPk}', null, 'should give anon nothing for the id of a scheduled item');
select is(pg_temp.graphql_as('anon', '{ sermonsByPk(id: "c2100000-0000-4000-8000-000000000002") { title } }') #>> '{data,sermonsByPk}', null, 'should give anon nothing for the id of a draft sermon');
select isnt(pg_temp.graphql_as('anon', '{ contentItemsCollection { edges { node { status } } } }') -> 'errors', null, 'should refuse anon asking for status');
select isnt(pg_temp.graphql_as('anon', '{ contentItemsCollection { edges { node { authorStaff { fullName } } } } }') -> 'errors', null, 'should refuse anon asking for the author');
select isnt(pg_temp.graphql_as('anon', '{ contentItemsCollection { edges { node { approvedByStaff { fullName } } } } }') -> 'errors', null, 'should refuse anon asking for the approver');
select isnt(pg_temp.graphql_as('anon', '{ contentItemsCollection { edges { node { createdAt } } } }') -> 'errors', null, 'should refuse anon asking for createdAt');
select isnt(pg_temp.graphql_as('anon', '{ contentItemsCollection(filter: { status: { eq: draft } }) { edges { node { title } } } }') -> 'errors', null, 'should refuse anon filtering by status');
select isnt(pg_temp.graphql_as('anon', '{ contentItemsCollection(orderBy: [{ authorId: AscNullsLast }]) { edges { node { title } } } }') -> 'errors', null, 'should refuse anon ordering by author');
select isnt(pg_temp.graphql_as('anon', '{ sermonsCollection { edges { node { approvedBy } } } }') -> 'errors', null, 'should refuse anon asking for the sermon approver');

-- anon and node ids (IDOR): a node id of a hidden row resolves to nothing, a live one resolves
select is(pg_temp.graphql_as('anon', format('{ node(nodeId: "%s") { __typename } }', pg_temp.node_id_of('contentItemsCollection', 'c1100000-0000-4000-8000-000000000002'))) #>> '{data,node}', null, 'should not resolve the node id of a draft for anon');
select is(pg_temp.graphql_as('anon', format('{ node(nodeId: "%s") { __typename } }', pg_temp.node_id_of('contentItemsCollection', 'c1100000-0000-4000-8000-000000000003'))) #>> '{data,node}', null, 'should not resolve the node id of an item in review for anon');
select is(pg_temp.graphql_as('anon', format('{ node(nodeId: "%s") { __typename } }', pg_temp.node_id_of('contentItemsCollection', 'c1100000-0000-4000-8000-000000000004'))) #>> '{data,node}', null, 'should not resolve the node id of a scheduled item for anon');
select is(pg_temp.graphql_as('anon', format('{ node(nodeId: "%s") { __typename } }', pg_temp.node_id_of('contentItemsCollection', 'c1100000-0000-4000-8000-000000000005'))) #>> '{data,node}', null, 'should not resolve the node id of an expired item for anon');
select is(pg_temp.graphql_as('anon', format('{ node(nodeId: "%s") { __typename } }', pg_temp.node_id_of('sermonsCollection', 'c2100000-0000-4000-8000-000000000003'))) #>> '{data,node}', null, 'should not resolve the node id of a sermon in review for anon');
select is(pg_temp.graphql_as('anon', format('{ node(nodeId: "%s") { __typename } }', pg_temp.node_id_of('contentItemsCollection', 'c1100000-0000-4000-8000-000000000001'))) #>> '{data,node,__typename}', 'ContentItems', 'should resolve the node id of a live item for anon');
select is(pg_temp.graphql_as('treasurer', format('{ node(nodeId: "%s") { __typename } }', pg_temp.node_id_of('contentItemsCollection', 'c1100000-0000-4000-8000-000000000002'))) #>> '{data,node}', null, 'should not resolve the node id of a draft for the treasurer');
select is(pg_temp.graphql_as('pastor', format('{ node(nodeId: "%s") { __typename } }', pg_temp.node_id_of('contentItemsCollection', 'c1100000-0000-4000-8000-000000000002'))) #>> '{data,node,__typename}', 'ContentItems', 'should resolve the node id of a draft for a pastor');

-- anon cannot call any mutation
select isnt(pg_temp.graphql_as('anon', 'mutation { approveContent(pId: "c1100000-0000-4000-8000-000000000003") { id } }') -> 'errors', null, 'should offer no approveContent to anon');
select isnt(pg_temp.graphql_as('anon', 'mutation { publishContent(pId: "c1100000-0000-4000-8000-000000000003") { id } }') -> 'errors', null, 'should offer no publishContent to anon');
select isnt(pg_temp.graphql_as('anon', 'mutation { updateContentItemsCollection(set: { title: "x" }) { affectedCount } }') -> 'errors', null, 'should offer no update to anon');
select isnt(pg_temp.graphql_as('anon', 'mutation { deleteFromContentItemsCollection { affectedCount } }') -> 'errors', null, 'should offer no delete to anon');

-- The workflow through GraphQL
select is(pg_temp.graphql_as('content_editor', 'mutation { approveContent(pId: "c1100000-0000-4000-8000-000000000003") { id status } }') #>> '{errors,0,message}', 'AUTH_FORBIDDEN', 'should refuse approveContent for a content editor with AUTH_FORBIDDEN');
select is(pg_temp.graphql_as('content_editor', 'mutation { publishContent(pId: "c1100000-0000-4000-8000-000000000003") { id status } }') #>> '{errors,0,message}', 'CONTENT_NOT_APPROVED', 'should refuse publishContent of an unapproved item with CONTENT_NOT_APPROVED');
select is(pg_temp.graphql_as('content_editor', 'mutation { submitContentForReview(pId: "c1100000-0000-4000-8000-000000000002") { id status approvedBy } }') #>> '{data,submitContentForReview}',
  '{"id": "c1100000-0000-4000-8000-000000000002", "status": "in_review", "approvedBy": null}', 'should let a content editor submit their draft and return the row');
select is(pg_temp.graphql_as('pastor', 'mutation { approveContent(pId: "c1100000-0000-4000-8000-000000000003") { id status approvedBy } }') #>> '{data,approveContent}',
  format('{"id": "c1100000-0000-4000-8000-000000000003", "status": "in_review", "approvedBy": "%s"}', pg_temp.staff_id_of('pastor'))::jsonb::text, 'should let a pastor approve and return the approver');
select is(pg_temp.graphql_as('super_admin', 'mutation { approveContent(pId: "c1100000-0000-4000-8000-000000000003") { id } }') #>> '{errors,0,message}', 'VALIDATION_FAILED', 'should refuse approving twice with VALIDATION_FAILED');
select is(pg_temp.graphql_as('content_editor', 'mutation { publishContent(pId: "c1100000-0000-4000-8000-000000000003") { id status } }') #>> '{data,publishContent,status}', 'published', 'should let a content editor publish the approved item');
select is(pg_temp.titles_of(pg_temp.graphql_as('anon', '{ contentItemsCollection { edges { node { title } } } }'), 'contentItemsCollection') like '%in_review_item%', true, 'should show anon the item as soon as it is published through GraphQL');
select is(pg_temp.graphql_as('super_admin', 'mutation { approveContent(pId: "c1100000-0000-4000-8000-0000000000ff") { id } }') #>> '{errors,0,message}', 'NOT_FOUND', 'should refuse an unknown id with NOT_FOUND');
select isnt(pg_temp.graphql_as('pastor', 'mutation { approveContent(pId: "not-a-uuid") { id } }') -> 'errors', null, 'should refuse a malformed id');
select isnt(pg_temp.graphql_as('pastor', 'mutation { approveContent { id } }') -> 'errors', null, 'should refuse a call with no id');
select is(pg_temp.graphql_as('pastor', 'mutation { approveSermon(pId: "c2100000-0000-4000-8000-000000000003") { id status approvedByStaff { fullName } } }') #>> '{data,approveSermon,status}', 'in_review', 'should let a pastor approve a sermon through GraphQL');
select is(pg_temp.graphql_as('super_admin', 'mutation { approveSermon(pId: "c2100000-0000-4000-8000-000000000003") { id } }') #>> '{errors,0,message}', 'VALIDATION_FAILED', 'should refuse a second approval of the sermon');
select is(pg_temp.graphql_as('treasurer', 'mutation { archiveContent(pId: "c1100000-0000-4000-8000-000000000004") { id } }') #>> '{errors,0,message}', 'AUTH_FORBIDDEN', 'should refuse the treasurer archiving through GraphQL');

-- Writing through the generated mutations
select isnt(pg_temp.graphql_as('pastor', format('mutation { insertIntoContentItemsCollection(objects: [{ kind: announcement, title: "gql", authorId: "%s", status: published }]) { affectedCount } }', pg_temp.staff_id_of('pastor'))) -> 'errors', null, 'should refuse inserting with a status through GraphQL');
select isnt(pg_temp.graphql_as('pastor', format('mutation { insertIntoContentItemsCollection(objects: [{ kind: announcement, title: "gql", authorId: "%s", approvedBy: "%s" }]) { affectedCount } }', pg_temp.staff_id_of('pastor'), pg_temp.staff_id_of('pastor'))) -> 'errors', null, 'should refuse inserting an approver through GraphQL');
select is(pg_temp.graphql_as('content_editor', format('mutation { insertIntoContentItemsCollection(objects: [{ kind: announcement, title: "gql_created", authorId: "%s" }]) { affectedCount records { title status approvedBy } } }', pg_temp.staff_id_of('content_editor'))) #>> '{data,insertIntoContentItemsCollection}',
  '{"records": [{"title": "gql_created", "status": "draft", "approvedBy": null}], "affectedCount": 1}', 'should let an editor create a draft through GraphQL');
select is(pg_temp.graphql_as('content_editor', format('mutation { insertIntoContentItemsCollection(objects: [{ kind: announcement, title: "gql_forged", authorId: "%s" }]) { affectedCount } }', pg_temp.staff_id_of('content_editor_two'))) #>> '{errors,0,message}', 'new row violates row-level security policy for table "content_items"', 'should refuse creating an item as another author through GraphQL');
select isnt(pg_temp.graphql_as('pastor', 'mutation { updateContentItemsCollection(set: { status: published }, filter: { title: { eq: "draft_item" } }) { affectedCount } }') -> 'errors', null, 'should refuse setting the status through the generated update');
select is(pg_temp.graphql_as('content_editor', 'mutation { updateContentItemsCollection(set: { title: "gql_edited" }, filter: { title: { eq: "gql_created" } }) { affectedCount } }') #>> '{data,updateContentItemsCollection,affectedCount}', '1', 'should let the author edit their draft through GraphQL');
select is(pg_temp.graphql_as('content_editor_two', 'mutation { updateContentItemsCollection(set: { title: "gql_hijacked" }, filter: { title: { eq: "gql_edited" } }) { affectedCount } }') #>> '{data,updateContentItemsCollection,affectedCount}', '0', 'should change nothing when another editor edits that draft through GraphQL');
select isnt(pg_temp.graphql_as('pastor', 'mutation { deleteFromContentItemsCollection { affectedCount } }') -> 'errors', null, 'should offer no delete mutation, even to a pastor');

-- Relationships resolve to the right rows
select is(pg_temp.graphql_as('super_admin', '{ contentItemsCollection(filter: { title: { eq: "live_announcement" } }) { edges { node { authorStaff { fullName } approvedByStaff { fullName } } } } }') #>> '{data,contentItemsCollection,edges,0,node}',
  '{"authorStaff": {"fullName": "content_editor"}, "approvedByStaff": {"fullName": "pastor"}}', 'should resolve the author and approver of an item for the super admin');
select is(pg_temp.graphql_as('super_admin', '{ sermonsCollection(filter: { title: { eq: "live_sermon" } }) { edges { node { authorStaff { fullName } approvedByStaff { fullName } } } } }') #>> '{data,sermonsCollection,edges,0,node}',
  '{"authorStaff": {"fullName": "content_editor"}, "approvedByStaff": {"fullName": "pastor"}}', 'should resolve the author and approver of a sermon for the super admin');
select is(jsonb_array_length(pg_temp.graphql_as('super_admin', '{ staffCollection(filter: { fullName: { eq: "content_editor" } }) { edges { node { authoredContentItemsCollection { edges { node { id } } } } } } }') #> '{data,staffCollection,edges,0,node,authoredContentItemsCollection,edges}') > 10, true, 'should list on Staff.authoredContentItemsCollection the items an editor wrote');
select is(jsonb_array_length(pg_temp.graphql_as('super_admin', '{ staffCollection(filter: { fullName: { eq: "pastor" } }) { edges { node { approvedSermonsCollection { edges { node { id } } } } } } }') #> '{data,staffCollection,edges,0,node,approvedSermonsCollection,edges}') >= 3, true, 'should list on Staff.approvedSermonsCollection the sermons a pastor approved');
select is(pg_temp.graphql_as('content_editor', '{ contentItemsCollection(filter: { title: { eq: "live_announcement" } }) { edges { node { authorStaff { fullName } approvedByStaff { fullName } } } } }') #>> '{data,contentItemsCollection,edges,0,node}',
  '{"authorStaff": {"fullName": "content_editor"}, "approvedByStaff": null}', 'should show an editor their own name as author but not the approver, whose staff row an editor cannot read');
select is(pg_temp.graphql_as('treasurer', '{ contentItemsCollection { edges { node { id } } } }') #>> '{data,contentItemsCollection,edges}', '[]', 'should show the treasurer no content items through GraphQL');
select is(pg_temp.graphql_as('usher', '{ sermonsCollection { edges { node { id } } } }') #>> '{data,sermonsCollection,edges}', '[]', 'should show an usher no sermons through GraphQL');
select is(pg_temp.graphql_as('no_staff', '{ contentItemsCollection { edges { node { id } } } }') #>> '{data,contentItemsCollection,edges}', '[]', 'should show a signed-in user with no staff profile no content items');

select * from finish();

rollback;
