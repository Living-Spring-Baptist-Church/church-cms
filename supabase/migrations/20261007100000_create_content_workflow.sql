-- Content workflow and expiry (LBC-33): the status transition rules, the ten functions that apply them to
-- content_items and sermons, and the pg_cron job that archives expired announcements.
-- Source: docs/system-design.md ("publishContent(id) / approveContent(id)", CONTENT_NOT_APPROVED in backend.md),
-- PRD CNT-06 and CNT-07.
--
-- The flow, one function per step, each on both tables (approve_content, approve_sermon and so on):
--   submit            draft -> in_review. The author, a pastor or a super admin.
--   approve           in_review stays in_review and approved_by is set to the caller. Pastor or super admin only.
--                     A pastor may approve their own item: PRD four-eyes is stated for expenses only (flagged).
--   publish           in_review -> published. publish_at becomes now() when empty; a future publish_at schedules it.
--                     Any editing role may publish an approved item. A pastor or super admin may publish an item that
--                     is not yet approved, which approves it in the same step. Anyone else gets CONTENT_NOT_APPROVED.
--   return_to_draft   in_review -> draft, or published -> draft (approvers only). Clears approved_by, so an edited
--                     item is approved again.
--   archive           draft, in_review or published -> archived. The author or an approver, and only an approver for
--                     a published item. Archived is final.
-- All functions are SECURITY DEFINER because status and approved_by have no column grant for app roles and the private
-- schema is closed to them. The role check is therefore the gate and runs first, then the row is locked and read.

create type private.content_action as enum ('submit', 'approve', 'publish', 'return_to_draft', 'archive');

comment on type private.content_action is 'A step of the content approval flow.';

create function private.next_content_status(
  p_action private.content_action,
  p_status public.content_status,
  p_author_id uuid,
  p_approved_by uuid
)
returns public.content_status
language plpgsql
stable
set search_path = ''
as $$
declare
  v_is_approver boolean := private.can_approve_content();
  v_is_allowed boolean;
  v_is_valid_source boolean;
begin
  v_is_allowed := case
    when p_action = 'approve' then v_is_approver
    when p_action = 'publish' then true
    when p_status = 'published' then v_is_approver
    else v_is_approver or p_author_id = (select auth.uid())
  end;
  if not v_is_allowed then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN',
      detail = format('This role cannot %s an item that is %s', replace(p_action::text, '_', ' '), p_status);
  end if;

  v_is_valid_source := case p_action
    when 'submit' then p_status = 'draft'
    when 'approve' then p_status = 'in_review'
    when 'publish' then p_status = 'in_review'
    when 'return_to_draft' then p_status in ('in_review', 'published')
    else p_status <> 'archived'
  end;
  if not v_is_valid_source then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = format('Cannot %s an item that is %s', replace(p_action::text, '_', ' '), p_status);
  end if;

  if p_action = 'approve' and p_approved_by is not null then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED', detail = 'The item is already approved';
  end if;
  if p_action = 'publish' and p_approved_by is null and not v_is_approver then
    raise exception using errcode = 'P0001', message = 'CONTENT_NOT_APPROVED',
      detail = 'A pastor or super admin must approve the item before it is published';
  end if;

  return case p_action
    when 'submit' then 'in_review'::public.content_status
    when 'approve' then 'in_review'::public.content_status
    when 'publish' then 'published'::public.content_status
    when 'return_to_draft' then 'draft'::public.content_status
    else 'archived'::public.content_status
  end;
end;
$$;

comment on function private.next_content_status(private.content_action, public.content_status, uuid, uuid) is 'The one place the approval flow is defined. Checks the caller may take the step, that the item is in a status that allows it and, for publish, that it is approved. Returns the new status or raises AUTH_FORBIDDEN, VALIDATION_FAILED or CONTENT_NOT_APPROVED.';

create function private.next_content_approver(p_action private.content_action, p_approved_by uuid)
returns uuid
language sql
stable
set search_path = ''
as $$
  select case p_action
    when 'approve' then (select auth.uid())
    when 'publish' then coalesce(p_approved_by, (select auth.uid()))
    when 'return_to_draft' then null
    else p_approved_by
  end;
$$;

comment on function private.next_content_approver(private.content_action, uuid) is 'Who the item is approved by after a step: the caller on approve, kept (or the caller who is an approver) on publish, nobody on return_to_draft, unchanged otherwise.';

-- The job runs every 15 minutes, which keeps dashboard statuses truthful; public visibility never waits for it.
create function private.expiry_job_name()
returns text
language sql
immutable
set search_path = ''
as $$
  select 'archive-expired-content';
$$;

create function private.expiry_job_schedule()
returns text
language sql
immutable
set search_path = ''
as $$
  select '*/15 * * * *';
$$;

comment on function private.expiry_job_name() is 'Name of the pg_cron job that archives expired content.';
comment on function private.expiry_job_schedule() is 'Cron schedule of the expiry job: every 15 minutes.';

-- The submit, approve, publish, return_to_draft and archive functions of content_items

create function public.submit_content_for_review(p_id uuid)
returns public.content_items
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_item public.content_items;
begin
  if not private.can_edit_content() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN', detail = 'Only content staff can submit content';
  end if;
  select * into v_item from public.content_items where id = p_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'No content item with that id';
  end if;

  update public.content_items
  set status = private.next_content_status('submit', v_item.status, v_item.author_id, v_item.approved_by)
  where id = p_id
  returning * into v_item;
  return v_item;
end;
$$;

create function public.approve_content(p_id uuid)
returns public.content_items
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_item public.content_items;
begin
  if not private.can_approve_content() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN', detail = 'Only a pastor or super admin can approve content';
  end if;
  select * into v_item from public.content_items where id = p_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'No content item with that id';
  end if;

  update public.content_items
  set status = private.next_content_status('approve', v_item.status, v_item.author_id, v_item.approved_by),
      approved_by = private.next_content_approver('approve', v_item.approved_by)
  where id = p_id
  returning * into v_item;
  return v_item;
end;
$$;

create function public.publish_content(p_id uuid)
returns public.content_items
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_item public.content_items;
begin
  if not private.can_edit_content() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN', detail = 'Only content staff can publish content';
  end if;
  select * into v_item from public.content_items where id = p_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'No content item with that id';
  end if;
  if v_item.expires_at is not null and v_item.expires_at <= coalesce(v_item.publish_at, now()) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = 'expires_at must be later than the time the item goes live';
  end if;

  update public.content_items
  set status = private.next_content_status('publish', v_item.status, v_item.author_id, v_item.approved_by),
      approved_by = private.next_content_approver('publish', v_item.approved_by),
      publish_at = coalesce(v_item.publish_at, now())
  where id = p_id
  returning * into v_item;
  return v_item;
end;
$$;

create function public.return_content_to_draft(p_id uuid)
returns public.content_items
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_item public.content_items;
begin
  if not private.can_edit_content() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN', detail = 'Only content staff can return content to draft';
  end if;
  select * into v_item from public.content_items where id = p_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'No content item with that id';
  end if;

  update public.content_items
  set status = private.next_content_status('return_to_draft', v_item.status, v_item.author_id, v_item.approved_by),
      approved_by = private.next_content_approver('return_to_draft', v_item.approved_by)
  where id = p_id
  returning * into v_item;
  return v_item;
end;
$$;

create function public.archive_content(p_id uuid)
returns public.content_items
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_item public.content_items;
begin
  if not private.can_edit_content() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN', detail = 'Only content staff can archive content';
  end if;
  select * into v_item from public.content_items where id = p_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'No content item with that id';
  end if;

  update public.content_items
  set status = private.next_content_status('archive', v_item.status, v_item.author_id, v_item.approved_by)
  where id = p_id
  returning * into v_item;
  return v_item;
end;
$$;

-- The same five functions for sermons

create function public.submit_sermon_for_review(p_id uuid)
returns public.sermons
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_sermon public.sermons;
begin
  if not private.can_edit_content() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN', detail = 'Only content staff can submit a sermon';
  end if;
  select * into v_sermon from public.sermons where id = p_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'No sermon with that id';
  end if;

  update public.sermons
  set status = private.next_content_status('submit', v_sermon.status, v_sermon.author_id, v_sermon.approved_by)
  where id = p_id
  returning * into v_sermon;
  return v_sermon;
end;
$$;

create function public.approve_sermon(p_id uuid)
returns public.sermons
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_sermon public.sermons;
begin
  if not private.can_approve_content() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN', detail = 'Only a pastor or super admin can approve a sermon';
  end if;
  select * into v_sermon from public.sermons where id = p_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'No sermon with that id';
  end if;

  update public.sermons
  set status = private.next_content_status('approve', v_sermon.status, v_sermon.author_id, v_sermon.approved_by),
      approved_by = private.next_content_approver('approve', v_sermon.approved_by)
  where id = p_id
  returning * into v_sermon;
  return v_sermon;
end;
$$;

create function public.publish_sermon(p_id uuid)
returns public.sermons
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_sermon public.sermons;
begin
  if not private.can_edit_content() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN', detail = 'Only content staff can publish a sermon';
  end if;
  select * into v_sermon from public.sermons where id = p_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'No sermon with that id';
  end if;

  update public.sermons
  set status = private.next_content_status('publish', v_sermon.status, v_sermon.author_id, v_sermon.approved_by),
      approved_by = private.next_content_approver('publish', v_sermon.approved_by),
      publish_at = coalesce(v_sermon.publish_at, now())
  where id = p_id
  returning * into v_sermon;
  return v_sermon;
end;
$$;

create function public.return_sermon_to_draft(p_id uuid)
returns public.sermons
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_sermon public.sermons;
begin
  if not private.can_edit_content() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN', detail = 'Only content staff can return a sermon to draft';
  end if;
  select * into v_sermon from public.sermons where id = p_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'No sermon with that id';
  end if;

  update public.sermons
  set status = private.next_content_status('return_to_draft', v_sermon.status, v_sermon.author_id, v_sermon.approved_by),
      approved_by = private.next_content_approver('return_to_draft', v_sermon.approved_by)
  where id = p_id
  returning * into v_sermon;
  return v_sermon;
end;
$$;

create function public.archive_sermon(p_id uuid)
returns public.sermons
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_sermon public.sermons;
begin
  if not private.can_edit_content() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN', detail = 'Only content staff can archive a sermon';
  end if;
  select * into v_sermon from public.sermons where id = p_id for update;
  if not found then
    raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'No sermon with that id';
  end if;

  update public.sermons
  set status = private.next_content_status('archive', v_sermon.status, v_sermon.author_id, v_sermon.approved_by)
  where id = p_id
  returning * into v_sermon;
  return v_sermon;
end;
$$;

comment on function public.submit_content_for_review(uuid) is 'Moves a draft content item to in_review and returns the row. The author, a pastor or a super admin. Errors: AUTH_FORBIDDEN, NOT_FOUND, VALIDATION_FAILED.';
comment on function public.approve_content(uuid) is 'Approves a content item that is in review: sets approved_by to the caller and returns the row. The status stays in_review until publish_content. Pastor or super admin only; may approve their own item. Errors: AUTH_FORBIDDEN, NOT_FOUND, VALIDATION_FAILED.';
comment on function public.publish_content(uuid) is 'Publishes an in-review content item and returns the row. publish_at becomes now() when empty; a future publish_at schedules it. Any content role may publish an approved item; a pastor or super admin may publish an unapproved one, which approves it. Errors: AUTH_FORBIDDEN, NOT_FOUND, VALIDATION_FAILED, CONTENT_NOT_APPROVED.';
comment on function public.return_content_to_draft(uuid) is 'Returns an in-review item (author or approver) or a published item (approver only) to draft, clears approved_by and returns the row. Errors: AUTH_FORBIDDEN, NOT_FOUND, VALIDATION_FAILED.';
comment on function public.archive_content(uuid) is 'Archives a content item and returns the row. Archived is final. The author or an approver; only an approver for a published item. Errors: AUTH_FORBIDDEN, NOT_FOUND, VALIDATION_FAILED.';
comment on function public.submit_sermon_for_review(uuid) is 'Moves a draft sermon to in_review and returns the row. The author, a pastor or a super admin. Errors: AUTH_FORBIDDEN, NOT_FOUND, VALIDATION_FAILED.';
comment on function public.approve_sermon(uuid) is 'Approves a sermon that is in review: sets approved_by to the caller and returns the row. The status stays in_review until publish_sermon. Pastor or super admin only. Errors: AUTH_FORBIDDEN, NOT_FOUND, VALIDATION_FAILED.';
comment on function public.publish_sermon(uuid) is 'Publishes an in-review sermon and returns the row. publish_at becomes now() when empty; a future publish_at schedules it. Any content role may publish an approved sermon; a pastor or super admin may publish an unapproved one, which approves it. Errors: AUTH_FORBIDDEN, NOT_FOUND, VALIDATION_FAILED, CONTENT_NOT_APPROVED.';
comment on function public.return_sermon_to_draft(uuid) is 'Returns an in-review sermon (author or approver) or a published one (approver only) to draft, clears approved_by and returns the row. Errors: AUTH_FORBIDDEN, NOT_FOUND, VALIDATION_FAILED.';
comment on function public.archive_sermon(uuid) is 'Archives a sermon and returns the row. Archived is final. The author or an approver; only an approver for a published sermon. Errors: AUTH_FORBIDDEN, NOT_FOUND, VALIDATION_FAILED.';

revoke execute on function
  private.next_content_status(private.content_action, public.content_status, uuid, uuid),
  private.next_content_approver(private.content_action, uuid),
  private.expiry_job_name(),
  private.expiry_job_schedule()
from public, anon, authenticated;

revoke execute on function
  public.submit_content_for_review(uuid),
  public.approve_content(uuid),
  public.publish_content(uuid),
  public.return_content_to_draft(uuid),
  public.archive_content(uuid),
  public.submit_sermon_for_review(uuid),
  public.approve_sermon(uuid),
  public.publish_sermon(uuid),
  public.return_sermon_to_draft(uuid),
  public.archive_sermon(uuid)
from public, anon;

grant execute on function
  public.submit_content_for_review(uuid),
  public.approve_content(uuid),
  public.publish_content(uuid),
  public.return_content_to_draft(uuid),
  public.archive_content(uuid),
  public.submit_sermon_for_review(uuid),
  public.approve_sermon(uuid),
  public.publish_sermon(uuid),
  public.return_sermon_to_draft(uuid),
  public.archive_sermon(uuid)
to authenticated;

-- Expiry job (CNT-06). Anon visibility never depends on it: the policy compares expires_at with now(). The job only
-- keeps the stored status truthful, so dashboards list an expired announcement as archived. It is plain SQL so it can
-- be tested directly, is idempotent (a second run finds nothing left), and runs as the migration owner with no
-- signed-in user, so its audit rows carry a null actor_id. Nothing scheduled flips to published here: a scheduled
-- item is already status published and becomes visible by itself when publish_at passes.

create function private.archive_expired_content()
returns integer
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_archived integer;
begin
  update public.content_items
  set status = 'archived'
  where status = 'published'
    and expires_at is not null
    and expires_at <= now();
  get diagnostics v_archived = row_count;
  return v_archived;
end;
$$;

comment on function private.archive_expired_content() is 'Archives every published content item whose expires_at has passed and returns how many it archived. Safe to run any number of times. Run by the pg_cron job and callable only by the database owner.';

revoke execute on function private.archive_expired_content() from public, anon, authenticated, service_role;

create extension if not exists pg_cron with schema pg_catalog;

-- cron.schedule with an existing name updates that job, so this migration can be re-run without a second job.
select cron.schedule(
  private.expiry_job_name(),
  private.expiry_job_schedule(),
  'select private.archive_expired_content()'
);
