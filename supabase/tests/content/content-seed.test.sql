-- LBC-33: the demo seed fixture for content. It must load, stay deterministic and show anon exactly what the public
-- site would show: the live announcement, the quote, the history page and the published sermon, and none of the
-- draft, in-review, scheduled or expired items.

begin;

select plan(9);

-- The expiry job may or may not have run since the last reset, so run it now: the expired seed item is archived either way.
select set_config('request.jwt.claims', '', true);
select private.archive_expired_content();

select is((select count(*) from public.content_items), 7::bigint, 'should seed seven content items');
select is((select count(*) from public.sermons), 2::bigint, 'should seed two sermons');
select is(
  (select string_agg(status::text, ',' order by status) from public.content_items where kind = 'announcement'),
  'draft,in_review,published,published,archived', 'should seed announcements in every state of the flow, a scheduled one and an expired one (archived by the expiry job)');
select is((select slug from public.content_items where kind = 'page'), 'history', 'should seed a history page with its slug');

create function pg_temp.anon_titles(p_relation text)
returns text
language plpgsql
as $$
declare
  v_original name := current_user;
  v_titles text;
begin
  perform set_config('role', 'anon', true);
  execute format('select coalesce(string_agg(title, %L order by title), %L) from public.%I', ',', '', p_relation) into v_titles;
  perform set_config('role', v_original::text, true);
  return v_titles;
end;
$$;

select is(pg_temp.anon_titles('content_items'), 'Harvest Thanksgiving Service,Our History,Psalm 23:1', 'should show anon only the live announcement, the quote and the history page');
select is(pg_temp.anon_titles('sermons'), 'Walking in Faith', 'should show anon only the published sermon');
select is((select count(*) from public.content_items where author_id = '10000000-0000-4000-8000-000000000007'), 7::bigint, 'should have the demo content editor as author of every seeded item');
select is((select count(*) from public.content_items where status = 'published' and approved_by <> '10000000-0000-4000-8000-000000000002'), 0::bigint, 'should have the demo pastor as approver of every published item');
select is((select count(*) from public.content_items where body ~* '<script|javascript:'), 0::bigint, 'should seed no markup in a body');

select * from finish();

rollback;
