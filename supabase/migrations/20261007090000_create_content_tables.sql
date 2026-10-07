-- Content (LBC-33): content_items and sermons with the content_kind and content_status enums, their row level
-- security, the first anon-readable data in the project, and the status flow guard.
-- Source: docs/system-design.md, section "Content, messaging & system tables" and the policy example
-- content_public; PRD CNT-01 to CNT-09 and the permission matrix row "Public content".
-- The status transition functions and the expiry job are in the next migration.
--
-- Deviations from the design sketch, all needing a human decision (see the ticket hand-off):
--   * created_at and updated_at are added to sermons, and sermons gets publish_at (scheduled publishing, CNT-07).
--     The sketch gives sermons neither, yet the design says the public site reads sermons "where status = 'published'
--     and publish_at <= now()". Sermons get no expires_at: only announcements expire (CNT-06).
--   * A published row must carry publish_at and approved_by (CHECK), so the design rule publish_at <= now() is the
--     whole publication test and a null publish_at fails closed, never visible.
--   * Scheduling is not a status. The enum stays draft, in_review, published, archived. A scheduled item is
--     status = 'published' with publish_at in the future: invisible to anon until then, with no job needed.
--   * slug is required for kind page and forbidden for the others. slug, video_url, image_path and audio_path get
--     format checks so a path or link the public site renders cannot carry markup, a scheme or a path escape.
--   * The quote kind has no source column in the sketch: use title for the source (for example a scripture
--     reference) and body for the quote text.
--
-- Who sees and does what (PRD matrix row "Public content", CNT-07):
--   anon: reads published rows whose publish_at has passed and whose expires_at has not, and only the public
--     columns (no author, approver, status or timestamps).
--   super admin, pastor, secretary, content editor: read every row; create rows as themselves; edit the content
--     fields of a DRAFT. A secretary or content editor edits only their own drafts; a pastor or super admin edits any
--     draft. Nobody edits an item that is in review, published or archived: it goes back to draft first.
--   status, approved_by and author_id are never written directly. The workflow functions are the only path.
--   Nobody can DELETE: an item is archived.
--   The treasurer, ushers, department heads and signed-in users with no role see and change nothing.

create type public.content_kind as enum ('announcement', 'quote', 'page', 'activity');
create type public.content_status as enum ('draft', 'in_review', 'published', 'archived');

comment on type public.content_kind is 'What a content item is: announcement, quote (quote of the week), page (such as church history) or activity (weekly activity).';
comment on type public.content_status is 'Where an item is in the approval flow: draft, in_review, published or archived. A scheduled item is published with a future publish_at.';

-- Rule values. Same convention as LBC-26 and LBC-31: fixed values are immutable functions in private.

create function private.max_title_length()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 200;
$$;

create function private.max_slug_length()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 100;
$$;

create function private.max_body_length()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 50000;
$$;

create function private.max_link_length()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 500;
$$;

create function private.reserved_slugs()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['admin', 'announcements', 'api', 'auth', 'dashboard', 'login', 'logout', 'robots', 'sermons', 'sitemap'];
$$;

create function private.youtube_hosts()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['youtube.com', 'www.youtube.com', 'm.youtube.com', 'www.youtube-nocookie.com', 'youtu.be'];
$$;

comment on function private.max_title_length() is 'Longest title, preacher, series or scripture reference accepted, in characters.';
comment on function private.max_slug_length() is 'Longest page slug accepted, in characters.';
comment on function private.max_body_length() is 'Longest Markdown body or sermon note accepted, in characters.';
comment on function private.max_link_length() is 'Longest storage path or video link accepted, in characters.';
comment on function private.reserved_slugs() is 'Slugs a page may not take because the public site uses them for its own routes. Keep in step with the public site routes.';
comment on function private.youtube_hosts() is 'Hosts a sermon video link may point to (CNT-04: video is embedded from YouTube).';

-- Format checks. They return null for null input, so a CHECK passes on an empty optional column. They are SECURITY
-- DEFINER because a SQL function body is resolved when it runs, and the writing role has no USAGE on private.

create function private.is_valid_slug(p_slug text)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select p_slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    and char_length(p_slug) <= private.max_slug_length()
    and p_slug <> all (private.reserved_slugs());
$$;

create function private.is_safe_storage_path(p_path text)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  select p_path ~ '^[A-Za-z0-9][A-Za-z0-9_./-]*$'
    and p_path !~ '[.][.]'
    and p_path !~ '//'
    and char_length(p_path) <= private.max_link_length();
$$;

create function private.is_youtube_url(p_url text)
returns boolean
language sql
immutable
security definer
set search_path = ''
as $$
  -- https only, a plain host (no user info, port or spaces) from the allowed list, and a path
  select p_url ~ '^https://[A-Za-z0-9.-]+/[A-Za-z0-9_./?=&%#+~-]+$'
    and substring(p_url from '^https://([A-Za-z0-9.-]+)/') = any (private.youtube_hosts())
    and char_length(p_url) <= private.max_link_length();
$$;

comment on function private.is_valid_slug(text) is 'True for a lowercase slug of letters, digits and single hyphens that is not reserved and is at most max_slug_length long.';
comment on function private.is_safe_storage_path(text) is 'True for a relative storage path of letters, digits, dots, hyphens, underscores and slashes: no scheme, no leading slash, no double dot, no double slash.';
comment on function private.is_youtube_url(text) is 'True for an https link to one of the YouTube hosts, with a path and nothing that could change the host.';

-- Role helpers, SECURITY DEFINER like the other role helpers because the private schema is closed to app roles.

create function private.can_edit_content()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_any_role(array['super_admin', 'pastor', 'secretary', 'content_editor']::public.app_role[]);
$$;

create function private.can_approve_content()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_any_role(array['super_admin', 'pastor']::public.app_role[]);
$$;

comment on function private.can_edit_content() is 'True when the signed-in user is an active super admin, pastor, secretary or content editor, the roles of the PRD row "Public content".';
comment on function private.can_approve_content() is 'True when the signed-in user is an active super admin or pastor, the only roles that approve content (CNT-07).';

-- Status flow guard: one definition for both tables, so no path (the functions, a service role, a job or direct SQL)
-- can skip a step or bring an archived item back.
create function private.guard_content_status_flow()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not (
    (old.status = 'draft' and new.status in ('in_review', 'archived'))
    or (old.status = 'in_review' and new.status in ('draft', 'published', 'archived'))
    or (old.status = 'published' and new.status in ('draft', 'archived'))
  ) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = format('An item that is %s cannot become %s', old.status, new.status);
  end if;
  return new;
end;
$$;

comment on function private.guard_content_status_flow() is 'Before update trigger on content_items and sermons: allows draft to in_review, in_review to published or back to draft, published back to draft, and archiving from any status. Archived is final.';

-- Tables

create table public.content_items (
  id uuid primary key default gen_random_uuid(),
  kind public.content_kind not null,
  slug text,
  title text not null,
  body text,
  image_path text,
  status public.content_status not null default 'draft',
  publish_at timestamptz,
  expires_at timestamptz,
  author_id uuid not null references public.staff (id),
  approved_by uuid references public.staff (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint content_items_slug_key unique (slug),
  constraint content_items_title_check check (btrim(title) <> '' and char_length(title) <= private.max_title_length()),
  constraint content_items_body_check check (char_length(body) <= private.max_body_length()),
  constraint content_items_slug_check check (private.is_valid_slug(slug)),
  constraint content_items_page_slug_check check ((kind = 'page') = (slug is not null)),
  constraint content_items_image_path_check check (private.is_safe_storage_path(image_path)),
  constraint content_items_window_check check (publish_at is null or expires_at is null or expires_at > publish_at),
  constraint content_items_published_has_publish_at_check check (status <> 'published' or publish_at is not null),
  constraint content_items_published_has_approver_check check (status <> 'published' or approved_by is not null),
  constraint content_items_draft_has_no_approver_check check (status <> 'draft' or approved_by is null)
);

comment on table public.content_items is 'Announcements, quote of the week, pages and weekly activities (CNT-01, CNT-02, CNT-05, CNT-06) in one table, so the approval flow (CNT-07) is written once. Never deleted: archived. The public site, as anon, reads only published rows inside their publish window and only the public columns.';
comment on column public.content_items.id is 'Unique id of the item.';
comment on column public.content_items.kind is 'announcement, quote, page or activity.';
comment on column public.content_items.slug is 'Public path of a page, for example history. Required for pages and empty for every other kind. Lowercase letters, digits and single hyphens; unique; some words are reserved for the public site.';
comment on column public.content_items.title is 'Headline of the item. For a quote, the source (for example a scripture reference).';
comment on column public.content_items.body is 'Markdown text, stored as written. Never HTML: the reader must render Markdown safely.';
comment on column public.content_items.image_path is 'Relative path of an image in the public storage bucket. Never a link to another site.';
comment on column public.content_items.status is 'draft, in_review, published or archived. Changed only by the workflow functions, never by a direct write.';
comment on column public.content_items.publish_at is 'When the item goes live. Required once published. A future time schedules it: it stays hidden from the public until then.';
comment on column public.content_items.expires_at is 'When the item stops being public (CNT-06). Empty for items that do not expire. Later than publish_at.';
comment on column public.content_items.author_id is 'The staff member who created the item. Always the signed-in user at creation and never changed.';
comment on column public.content_items.approved_by is 'The pastor or super admin who approved the item. Set only by the workflow functions.';
comment on column public.content_items.created_at is 'When the item was created.';
comment on column public.content_items.updated_at is 'When the item was last changed. Maintained by a trigger.';

create index content_items_author_id_idx on public.content_items (author_id);
create index content_items_approved_by_idx on public.content_items (approved_by);
create index content_items_kind_status_idx on public.content_items (kind, status);
create index content_items_public_idx on public.content_items (kind, publish_at) where status = 'published';
create index content_items_expires_at_idx on public.content_items (expires_at) where status = 'published' and expires_at is not null;

create table public.sermons (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  preacher text not null,
  preached_on date not null,
  series text,
  scripture text,
  notes text,
  video_url text,
  audio_path text,
  status public.content_status not null default 'draft',
  publish_at timestamptz,
  author_id uuid not null references public.staff (id),
  approved_by uuid references public.staff (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint sermons_title_check check (btrim(title) <> '' and char_length(title) <= private.max_title_length()),
  constraint sermons_preacher_check check (btrim(preacher) <> '' and char_length(preacher) <= private.max_title_length()),
  constraint sermons_series_check check (char_length(series) <= private.max_title_length()),
  constraint sermons_scripture_check check (char_length(scripture) <= private.max_title_length()),
  constraint sermons_notes_check check (char_length(notes) <= private.max_body_length()),
  constraint sermons_video_url_check check (private.is_youtube_url(video_url)),
  constraint sermons_audio_path_check check (private.is_safe_storage_path(audio_path)),
  constraint sermons_published_has_publish_at_check check (status <> 'published' or publish_at is not null),
  constraint sermons_published_has_approver_check check (status <> 'published' or approved_by is not null),
  constraint sermons_draft_has_no_approver_check check (status <> 'draft' or approved_by is null)
);

comment on table public.sermons is 'The sermon library (CNT-03, CNT-04): title, preacher, date, series, scripture, notes, a YouTube link and an audio file. Never deleted: archived. Same approval flow as content_items. The public site, as anon, reads only published rows whose publish_at has passed and only the public columns.';
comment on column public.sermons.id is 'Unique id of the sermon.';
comment on column public.sermons.title is 'Title of the sermon.';
comment on column public.sermons.preacher is 'Who preached it.';
comment on column public.sermons.preached_on is 'The date it was preached.';
comment on column public.sermons.series is 'The series it belongs to, if any.';
comment on column public.sermons.scripture is 'The scripture reference, for example John 3:16.';
comment on column public.sermons.notes is 'Sermon notes in Markdown, shown on the public site once published. Never put internal remarks here. The reader must render Markdown safely.';
comment on column public.sermons.video_url is 'An https link to the video on YouTube (CNT-04). The app embeds it and never streams video itself.';
comment on column public.sermons.audio_path is 'Relative path of the audio file in the public storage bucket. Never a link to another site.';
comment on column public.sermons.status is 'draft, in_review, published or archived. Changed only by the workflow functions, never by a direct write.';
comment on column public.sermons.publish_at is 'When the sermon goes live. Required once published. A future time schedules it: it stays hidden from the public until then.';
comment on column public.sermons.author_id is 'The staff member who created the sermon. Always the signed-in user at creation and never changed.';
comment on column public.sermons.approved_by is 'The pastor or super admin who approved the sermon. Set only by the workflow functions.';
comment on column public.sermons.created_at is 'When the sermon was created.';
comment on column public.sermons.updated_at is 'When the sermon was last changed. Maintained by a trigger.';

create index sermons_author_id_idx on public.sermons (author_id);
create index sermons_approved_by_idx on public.sermons (approved_by);
create index sermons_preached_on_idx on public.sermons (preached_on);
create index sermons_series_idx on public.sermons (series) where series is not null;
create index sermons_public_idx on public.sermons (publish_at) where status = 'published';

create trigger content_items_updated_at
  before update on public.content_items
  for each row execute function private.set_updated_at();

create trigger sermons_updated_at
  before update on public.sermons
  for each row execute function private.set_updated_at();

create trigger content_items_status_flow
  before update of status on public.content_items
  for each row
  when (old.status is distinct from new.status)
  execute function private.guard_content_status_flow();

create trigger sermons_status_flow
  before update of status on public.sermons
  for each row
  when (old.status is distinct from new.status)
  execute function private.guard_content_status_flow();

-- Two foreign keys point at staff on each table, so name every relationship explicitly. Each foreign_name differs
-- from the inflected name of its column (authorId, approvedBy), otherwise both fields share a name.
comment on constraint content_items_author_id_fkey on public.content_items is
  e'@graphql({"foreign_name": "authorStaff", "local_name": "authoredContentItemsCollection"})';
comment on constraint content_items_approved_by_fkey on public.content_items is
  e'@graphql({"foreign_name": "approvedByStaff", "local_name": "approvedContentItemsCollection"})';
comment on constraint sermons_author_id_fkey on public.sermons is
  e'@graphql({"foreign_name": "authorStaff", "local_name": "authoredSermonsCollection"})';
comment on constraint sermons_approved_by_fkey on public.sermons is
  e'@graphql({"foreign_name": "approvedByStaff", "local_name": "approvedSermonsCollection"})';

-- Audit triggers (AFTER, and ENABLE ALWAYS so replica mode cannot skip them), as LBC-21 did.

create trigger audit_content_items
  after insert or update or delete on public.content_items
  for each row execute function audit.record_change();

create trigger audit_sermons
  after insert or update or delete on public.sermons
  for each row execute function audit.record_change();

alter table public.content_items enable always trigger audit_content_items;
alter table public.sermons enable always trigger audit_sermons;

-- Row level security and grants. Supabase grants new public tables to anon and authenticated by default: start
-- from nothing. anon gets column level SELECT on the public columns only, and the policy limits the rows.

alter table public.content_items enable row level security;
alter table public.sermons enable row level security;

revoke all on table public.content_items, public.sermons from public, anon, authenticated;

grant select (id, kind, slug, title, body, image_path, publish_at, expires_at) on public.content_items to anon;
grant select (id, title, preacher, preached_on, series, scripture, notes, video_url, audio_path, publish_at)
  on public.sermons to anon;

grant select on public.content_items, public.sermons to authenticated;

-- status, approved_by and the timestamps are written only by the workflow functions and triggers; author_id is
-- set at creation and never updated.
grant insert (kind, slug, title, body, image_path, publish_at, expires_at, author_id),
  update (kind, slug, title, body, image_path, publish_at, expires_at)
  on public.content_items to authenticated;
grant insert (title, preacher, preached_on, series, scripture, notes, video_url, audio_path, publish_at, author_id),
  update (title, preacher, preached_on, series, scripture, notes, video_url, audio_path, publish_at)
  on public.sermons to authenticated;

-- Policies are evaluated as the caller, so the helpers and rule values they and the CHECK constraints use are
-- executable by authenticated (and service_role, which an edge function uses).
revoke execute on function
  private.max_title_length(),
  private.max_slug_length(),
  private.max_body_length(),
  private.max_link_length(),
  private.reserved_slugs(),
  private.youtube_hosts(),
  private.is_valid_slug(text),
  private.is_safe_storage_path(text),
  private.is_youtube_url(text),
  private.can_edit_content(),
  private.can_approve_content(),
  private.guard_content_status_flow()
from public, anon, authenticated;

grant execute on function
  private.max_title_length(),
  private.max_slug_length(),
  private.max_body_length(),
  private.max_link_length(),
  private.reserved_slugs(),
  private.youtube_hosts(),
  private.is_valid_slug(text),
  private.is_safe_storage_path(text),
  private.is_youtube_url(text)
to authenticated, service_role;

grant execute on function private.can_edit_content(), private.can_approve_content() to authenticated;

-- content_items. The public rule is the design's: status = 'published' and publish_at <= now(), and not expired.
-- now() is the transaction time, so scheduled publishing and expiry take effect at once, with no job needed.
-- A null publish_at is never visible (the comparison is not true).

create policy content_items_select_public on public.content_items for select to anon
  using (status = 'published' and publish_at <= now() and (expires_at is null or expires_at > now()));

create policy content_items_select_editors on public.content_items for select to authenticated
  using ((select private.can_edit_content()));

create policy content_items_insert_editors on public.content_items for insert to authenticated
  with check ((select private.can_edit_content()) and author_id = (select auth.uid()) and status = 'draft');

-- Only drafts are edited, by their author or by an approver. Everything else goes back to draft first.
create policy content_items_update_editors on public.content_items for update to authenticated
  using (
    (select private.can_edit_content())
    and status = 'draft'
    and (author_id = (select auth.uid()) or (select private.can_approve_content()))
  )
  with check ((select private.can_edit_content()) and status = 'draft');

-- sermons: the same rules. A sermon never expires.

create policy sermons_select_public on public.sermons for select to anon
  using (status = 'published' and publish_at <= now());

create policy sermons_select_editors on public.sermons for select to authenticated
  using ((select private.can_edit_content()));

create policy sermons_insert_editors on public.sermons for insert to authenticated
  with check ((select private.can_edit_content()) and author_id = (select auth.uid()) and status = 'draft');

create policy sermons_update_editors on public.sermons for update to authenticated
  using (
    (select private.can_edit_content())
    and status = 'draft'
    and (author_id = (select auth.uid()) or (select private.can_approve_content()))
  )
  with check ((select private.can_edit_content()) and status = 'draft');
