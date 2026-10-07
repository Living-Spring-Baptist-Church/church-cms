-- LBC-33 QA: edge cases found by trying to break the content schema. Real transaction-time rows on both sides of the
-- publish and expiry boundaries in several session time zones, error-based probing of hidden rows by anon, the exact
-- columns anon can read, multi-byte length caps, link and path variants, the approval flow when an item is edited
-- after approval, and the expiry job. Everything runs as a real role and rolls back.

begin;

select plan(44);

-- Runs one statement as a role and returns 'ok <rows>' or '<sqlstate> <message>'. The role and claims are undone.
create function pg_temp.outcome_as(p_sub text, p_statement text)
returns text
language plpgsql
as $$
declare
  v_db_role text := case when p_sub = 'anon' then 'anon' else 'authenticated' end;
  v_rows bigint;
  v_result text;
begin
  begin
    perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', v_db_role, 'sub', nullif(p_sub, 'anon'))::text, true);
    perform set_config('role', v_db_role, true);
    execute p_statement;
    get diagnostics v_rows = row_count;
    v_result := 'ok ' || v_rows;
    raise exception using errcode = 'QAUND';
  exception
    when sqlstate 'QAUND' then null;
    when others then v_result := sqlstate || ' ' || sqlerrm;
  end;
  return v_result;
end;
$$;

-- The flow below keeps its changes between steps, so call_as does not undo a step that worked.

-- The titles anon sees, sorted, with the session time zone set first.
create function pg_temp.anon_titles(p_zone text)
returns text
language plpgsql
as $$
declare
  v_titles text;
begin
  perform set_config('timezone', p_zone, true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  perform set_config('role', 'anon', true);
  select coalesce(string_agg(title, ',' order by title), '') into v_titles
  from public.content_items where title like 'QA %';
  perform set_config('role', 'postgres', true);
  perform set_config('timezone', 'UTC', true);
  return v_titles;
end;
$$;

create function pg_temp.gql_as(p_sub text, p_query text)
returns jsonb
language plpgsql
as $$
declare
  v_db_role text := case when p_sub = 'anon' then 'anon' else 'authenticated' end;
  v_result jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', v_db_role, 'sub', nullif(p_sub, 'anon'))::text, true);
  perform set_config('role', v_db_role, true);
  v_result := graphql.resolve(p_query);
  perform set_config('role', 'postgres', true);
  return v_result;
end;
$$;

create function pg_temp.call_as(p_sub text, p_function text, p_id uuid)
returns text
language plpgsql
as $$
begin
  begin
    perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', 'authenticated', 'sub', p_sub)::text, true);
    perform set_config('role', 'authenticated', true);
    execute format('select public.%I(%L)', p_function, p_id);
    perform set_config('role', 'postgres', true);
    return 'ok 1';
  exception when others then
    return sqlstate || ' ' || sqlerrm;
  end;
end;
$$;

-- Fixture: six announcements around now(), all published and approved by the demo pastor.
insert into public.content_items (id, kind, title, status, publish_at, expires_at, author_id, approved_by) values
  ('c1100000-0000-4000-8000-000000000001', 'announcement', 'QA pub now', 'published', now(), null, '10000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000002'),
  ('c1100000-0000-4000-8000-000000000002', 'announcement', 'QA pub plus one second', 'published', now() + interval '1 second', null, '10000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000002'),
  ('c1100000-0000-4000-8000-000000000003', 'announcement', 'QA pub minus one second', 'published', now() - interval '1 second', null, '10000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000002'),
  ('c1100000-0000-4000-8000-000000000004', 'announcement', 'QA exp now', 'published', now() - interval '1 day', now(), '10000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000002'),
  ('c1100000-0000-4000-8000-000000000005', 'announcement', 'QA exp plus one second', 'published', now() - interval '1 day', now() + interval '1 second', '10000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000002'),
  ('c1100000-0000-4000-8000-000000000006', 'announcement', 'QA exp minus one second', 'published', now() - interval '1 day', now() - interval '1 second', '10000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000002'),
  ('c1100000-0000-4000-8000-000000000007', 'announcement', 'QA hidden draft', 'draft', null, null, '10000000-0000-4000-8000-000000000007', null),
  ('c1100000-0000-4000-8000-000000000008', 'announcement', 'QA hidden review', 'in_review', null, null, '10000000-0000-4000-8000-000000000007', null);

-- Boundaries and time zones: publish_at = now() is visible, expires_at = now() is hidden, whatever the zone.
select is(pg_temp.anon_titles('UTC'), 'QA exp plus one second,QA pub minus one second,QA pub now', 'should show the item that goes live now and hide the one that expires now when the zone is UTC');
select is(pg_temp.anon_titles('Pacific/Kiritimati'), 'QA exp plus one second,QA pub minus one second,QA pub now', 'should give the same rows when the zone is Pacific/Kiritimati (UTC+14)');
select is(pg_temp.anon_titles('Etc/GMT+12'), 'QA exp plus one second,QA pub minus one second,QA pub now', 'should give the same rows when the zone is Etc/GMT+12 (UTC-12)');
select is(pg_temp.anon_titles('Africa/Accra'), 'QA exp plus one second,QA pub minus one second,QA pub now', 'should give the same rows when the zone is Africa/Accra');

-- Error-based probing: a runtime error in a filter must never fire on a row the policy hides.
select is(
  pg_temp.outcome_as('anon', $q$select 1 from public.content_items where (case when title like 'QA hidden%' then 1 / (length(title) - length(title)) else 1 end) = 1$q$),
  'ok 6',
  'should not evaluate a failing expression on hidden drafts and in-review items when anon filters by title'
);
select is(
  pg_temp.outcome_as('anon', $q$select 1 from public.content_items where (case when title like 'QA hidden%' then title::int else 1 end) = 1$q$),
  'ok 6',
  'should not reveal a hidden title through a cast error when anon filters by it'
);
select is(
  pg_temp.outcome_as('anon', $q$select 1 from public.sermons where (case when title like 'Draft%' then 1 / (length(title) - length(title)) else 1 end) = 1$q$),
  'ok 1',
  'should not evaluate a failing expression on a hidden draft sermon'
);
select is(
  pg_temp.outcome_as('anon', 'select 1 from public.content_items tablesample bernoulli (100) where title like ''QA hidden%'''),
  'ok 0',
  'should not return hidden rows through TABLESAMPLE'
);
select is(
  pg_temp.outcome_as('anon', 'select id from public.content_items where id = ''c1100000-0000-4000-8000-000000000007'''),
  'ok 0',
  'should return no row for a hidden draft by id when anon asks for it'
);

-- Exactly the public columns, no more.
select is(
  (select string_agg(column_name, ',' order by column_name) from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'content_items' and grantee = 'anon' and privilege_type = 'SELECT'),
  'body,expires_at,id,image_path,kind,publish_at,slug,title',
  'should give anon only the public content columns'
);
select is(
  (select string_agg(column_name, ',' order by column_name) from information_schema.column_privileges
   where table_schema = 'public' and table_name = 'sermons' and grantee = 'anon' and privilege_type = 'SELECT'),
  'audio_path,id,notes,preached_on,preacher,publish_at,scripture,series,title,video_url',
  'should give anon only the public sermon columns'
);
select is(pg_temp.outcome_as('anon', 'select to_jsonb(t) from public.content_items t'), '42501 permission denied for table content_items', 'should refuse to_jsonb of a whole row to anon');
select is(pg_temp.outcome_as('anon', 'select ctid from public.content_items'), '42501 permission denied for table content_items', 'should refuse the ctid system column to anon');
select is(pg_temp.outcome_as('anon', 'select id from public.content_items for update'), '42501 permission denied for table content_items', 'should refuse row locks to anon');
select is(pg_temp.outcome_as('anon', 'select author_id from public.content_items'), '42501 permission denied for table content_items', 'should refuse author_id to anon');
select is(pg_temp.outcome_as('anon', 'select count(*) from public.content_items c join public.staff s on s.id = c.id'), '42501 permission denied for table staff', 'should refuse a join to staff for anon');

-- GraphQL: a hidden row is null by primary key and absent from a filtered collection.
select is(pg_temp.gql_as('anon', '{ contentItemsByPk(id: "c1100000-0000-4000-8000-000000000007") { id } }') #>> '{data,contentItemsByPk}', null, 'should return null for a hidden draft by primary key through GraphQL');
select is(pg_temp.gql_as('anon', '{ contentItemsCollection(filter: {title: {ilike: "QA hidden%"}}) { edges { node { id } } } }') #>> '{data,contentItemsCollection,edges}', '[]', 'should return no hidden rows when anon filters a collection by their title through GraphQL');

-- Length caps count characters, not bytes.
select is(pg_temp.outcome_as('10000000-0000-4000-8000-000000000007', format('insert into public.content_items(kind, title, author_id) values (''announcement'', %L, auth.uid())', repeat(chr(128512), 200))), 'ok 1', 'should accept a title of 200 four-byte characters');
select ok(pg_temp.outcome_as('10000000-0000-4000-8000-000000000007', format('insert into public.content_items(kind, title, author_id) values (''announcement'', %L, auth.uid())', repeat(chr(128512), 201))) like '23514%content_items_title_check%', 'should refuse a title of 201 four-byte characters');
select is(pg_temp.outcome_as('10000000-0000-4000-8000-000000000007', format('insert into public.content_items(kind, title, body, author_id) values (''announcement'', ''t'', %L, auth.uid())', repeat('é', 50000))), 'ok 1', 'should accept a body of 50000 two-byte characters');
select ok(pg_temp.outcome_as('10000000-0000-4000-8000-000000000007', format('insert into public.content_items(kind, title, body, author_id) values (''announcement'', ''t'', %L, auth.uid())', repeat('é', 50001))) like '23514%content_items_body_check%', 'should refuse a body of 50001 two-byte characters');
select is(pg_temp.outcome_as('10000000-0000-4000-8000-000000000007', 'insert into public.content_items(kind, title, author_id) values (''announcement'', ''O''''Brien Asamoah-Boateng, Ama Nkrumah'', auth.uid())'), 'ok 1', 'should accept apostrophes, hyphens and commas in a title');
select ok(pg_temp.outcome_as('10000000-0000-4000-8000-000000000007', 'insert into public.content_items(kind, title, author_id) values (''announcement'', ''   '', auth.uid())') like '23514%content_items_title_check%', 'should refuse a title of only spaces');

-- Links and paths: allowed hosts only, no way to change the host or climb out of the bucket.
select is(
  (select array_agg(url order by url) from unnest(array[
    'https://www.youtube.com/watch?v=abc', 'https://youtu.be/abc', 'https://m.youtube.com/watch?v=abc', 'https://www.youtube-nocookie.com/embed/abc'
  ]) as url where private.is_youtube_url(url)),
  array['https://m.youtube.com/watch?v=abc', 'https://www.youtube-nocookie.com/embed/abc', 'https://www.youtube.com/watch?v=abc', 'https://youtu.be/abc'],
  'should accept the four allowed YouTube hosts'
);
select is(
  (select count(*) from unnest(array[
    'http://www.youtube.com/watch?v=abc', 'https://www.youtube.com@evil.com/watch', 'https://evil.com@www.youtube.com/watch', 'https://www.youtube.com:443/watch',
    'https://www.youtube.com.evil.com/watch', 'https://evilyoutube.com/watch', 'https://WWW.YOUTUBE.COM/watch', 'https://www.youtube.com./watch',
    'javascript:alert(1)', 'data:text/html,x', 'https://www.youtube.com', 'https://www.youtube.com/', E'https://www.youtube.com/watch?v=abc\n',
    'https://www.youtube.com/watch?v="x', 'https://www.youtube.com/watch?v=<x>', 'https://www.youtube.com/a b', 'https://www.yоutube.com/watch'
  ]) as url where private.is_youtube_url(url)),
  0::bigint,
  'should refuse every lookalike, userinfo, port, scheme, case and whitespace variant of a YouTube link'
);
select is(
  (select count(*) from unnest(array[
    '../x.png', 'a/../b.png', '/etc/passwd', '//evil.com/x.png', 'a//b.png', 'http://evil.com/x.png', 'javascript:alert(1)', 'a b.png',
    E'a.png\n', 'a\b.png', '%2e%2e/x.png', '.env', '', 'a.png?x=1', 'é.png'
  ]) as path where private.is_safe_storage_path(path)),
  0::bigint,
  'should refuse traversal, scheme, absolute, double slash, whitespace and encoded storage paths'
);
select is(
  (select count(*) from unnest(array['abc', 'a-b', '2026', 'church-history']) as slug where private.is_valid_slug(slug)),
  4::bigint,
  'should accept lowercase slugs with digits and single hyphens'
);
select is(
  (select count(*) from unnest(array['Abc', 'a--b', '-a', 'a-', 'café', '', 'a/b', E'abc\n', 'admin', 'api', 'sermons', repeat('a', 101)]) as slug where private.is_valid_slug(slug)),
  0::bigint,
  'should refuse uppercase, repeated hyphens, accents, empty, slash, newline, reserved and over-long slugs'
);

-- Approval flow when an item changes after approval.
insert into public.content_items (id, kind, title, status, author_id) values
  ('c1100000-0000-4000-8000-000000000010', 'announcement', 'QA flow item', 'draft', '10000000-0000-4000-8000-000000000007');
select is(pg_temp.call_as('10000000-0000-4000-8000-000000000007', 'submit_content_for_review', 'c1100000-0000-4000-8000-000000000010'), 'ok 1', 'should let the editor submit their own draft');
select is(pg_temp.call_as('10000000-0000-4000-8000-000000000007', 'publish_content', 'c1100000-0000-4000-8000-000000000010'), 'P0001 CONTENT_NOT_APPROVED', 'should refuse the editor publishing before approval');
select is(pg_temp.call_as('10000000-0000-4000-8000-000000000002', 'approve_content', 'c1100000-0000-4000-8000-000000000010'), 'ok 1', 'should let the pastor approve');
select is(pg_temp.call_as('10000000-0000-4000-8000-000000000007', 'return_content_to_draft', 'c1100000-0000-4000-8000-000000000010'), 'ok 1', 'should let the author return an approved item to draft');
select is((select approved_by from public.content_items where id = 'c1100000-0000-4000-8000-000000000010'), null, 'should clear the approval when the item goes back to draft');
select is(pg_temp.call_as('10000000-0000-4000-8000-000000000007', 'submit_content_for_review', 'c1100000-0000-4000-8000-000000000010'), 'ok 1', 'should let the editor resubmit the edited draft');
select is(pg_temp.call_as('10000000-0000-4000-8000-000000000007', 'publish_content', 'c1100000-0000-4000-8000-000000000010'), 'P0001 CONTENT_NOT_APPROVED', 'should need approval again after the item was returned to draft');
select is(pg_temp.call_as('10000000-0000-4000-8000-000000000002', 'publish_content', 'c1100000-0000-4000-8000-000000000010'), 'ok 1', 'should let the pastor approve and publish in one step');
select is((select approved_by from public.content_items where id = 'c1100000-0000-4000-8000-000000000010'), '10000000-0000-4000-8000-000000000002'::uuid, 'should record the pastor as approver after a one-step publish');
select is(pg_temp.call_as('10000000-0000-4000-8000-000000000007', 'return_content_to_draft', 'c1100000-0000-4000-8000-000000000010'), 'P0001 AUTH_FORBIDDEN', 'should not let an editor pull a published item back to draft');
select is(pg_temp.call_as('10000000-0000-4000-8000-000000000001', 'archive_content', 'c1100000-0000-4000-8000-000000000010'), 'ok 1', 'should let the super admin archive a published item');
select is(pg_temp.call_as('10000000-0000-4000-8000-000000000001', 'return_content_to_draft', 'c1100000-0000-4000-8000-000000000010'), 'P0001 VALIDATION_FAILED', 'should not bring an archived item back');

-- Expiry job: archives only expired published rows, is idempotent and leaves a null actor in the audit trail.
select set_config('request.jwt.claims', '', true);
select is(private.archive_expired_content(), 3, 'should archive exactly the three published items that have expired (two fixture rows and the seed one)');
select is(private.archive_expired_content(), 0, 'should archive nothing on a second run');
select is(
  (select count(*) from audit.log where table_name = 'content_items' and action = 'UPDATE' and record_id = 'c1100000-0000-4000-8000-000000000006' and actor_id is null and changed_fields @> array['status']),
  1::bigint,
  'should record the expiry archive with no actor'
);

select * from finish();

rollback;
