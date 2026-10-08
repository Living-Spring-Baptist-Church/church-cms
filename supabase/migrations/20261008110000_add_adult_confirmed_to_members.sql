-- Product decision 5 (LBC-42): a person with no date of birth is a minor unless an office user ticked
-- "adult confirmed" at registration. A known date of birth always decides on its own.
-- private.is_minor(date) becomes private.is_minor(date, boolean) and every caller is switched in this file,
-- then the old one-argument function is dropped so no policy can use the unsafe form by mistake.
-- Only super admin and secretary may set the flag: column grants cannot tell roles apart, so a trigger does.

alter table public.members add column adult_confirmed boolean not null default false;

comment on column public.members.adult_confirmed is 'True when an office user confirmed the person is an adult although no date of birth is known. Ignored when a date of birth is set. With no date of birth and no confirmation the person is treated as a minor. Only super admin and secretary can set it.';

create function private.is_minor(p_date_of_birth date, p_adult_confirmed boolean)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_date_of_birth is null then not coalesce(p_adult_confirmed, false)
    else private.is_minor_on(p_date_of_birth, current_date)
  end;
$$;

comment on function private.is_minor(date, boolean) is 'True when the person is a minor today. A date of birth decides. With no date of birth the person is an adult only when adult_confirmed is true; otherwise a minor, so unknown ages stay hidden from everyone but super admin and pastor.';

revoke execute on function private.is_minor(date, boolean) from public, anon, authenticated;
grant execute on function private.is_minor(date, boolean) to authenticated;

-- Switch every user of the old function.

alter policy members_select_secretary on public.members
  using ((select private.has_role('secretary')) and not private.is_minor(date_of_birth, adult_confirmed));

alter policy members_select_department_head on public.members
  using (archived_at is null and private.heads_department_of_member(id, private.is_minor(date_of_birth, adult_confirmed)));

alter policy members_insert_secretary on public.members
  with check ((select private.has_role('secretary')) and not private.is_minor(date_of_birth, adult_confirmed));

alter policy members_update_secretary on public.members
  using ((select private.has_role('secretary')) and not private.is_minor(date_of_birth, adult_confirmed))
  with check ((select private.has_role('secretary')) and not private.is_minor(date_of_birth, adult_confirmed));

create or replace view public.member_names
with (security_invoker = false, security_barrier = true)
as
select members.id, members.first_name, members.last_name, members.status
from public.members
where (select private.has_any_role(array['usher', 'treasurer']::public.app_role[]))
  and members.archived_at is null
  and (not private.is_minor(members.date_of_birth, members.adult_confirmed) or (select private.can_view_minors()));

drop function private.is_minor(date);

comment on column public.members.date_of_birth is 'Date of birth. Decides whether the record is a minor''s (private.is_minor). Unknown counts as a minor unless adult_confirmed is true.';

-- Who may set adult_confirmed. Roles other than the app roles (migrations, seed, the service role) are not
-- restricted here: the table grants and policies already keep them out of app sessions.
create function private.guard_adult_confirmed()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (tg_op = 'INSERT' and new.adult_confirmed)
     or (tg_op = 'UPDATE' and new.adult_confirmed is distinct from old.adult_confirmed)
  then
    if current_user in ('authenticated', 'anon') and not private.can_manage_members() then
      raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN',
        detail = 'Only a super admin or secretary can set adult_confirmed';
    end if;
  end if;
  return new;
end;
$$;

comment on function private.guard_adult_confirmed() is 'Trigger function: refuses a change to members.adult_confirmed by any signed-in user who is not an active super admin or secretary.';

revoke execute on function private.guard_adult_confirmed() from public, anon, authenticated;

create trigger members_guard_adult_confirmed
  before insert or update of adult_confirmed on public.members
  for each row execute function private.guard_adult_confirmed();

-- Column grants: the new column joins the writable set, the trigger decides who may use it.
grant insert (adult_confirmed), update (adult_confirmed) on public.members to authenticated;

comment on view public.member_names is
  e'@graphql({"primary_key_columns": ["id"], "description": "Names and status of active members for ushers and the treasurer. Returns nothing to any other role. Minors are listed only to roles that may see every minor, and people with no date of birth are treated as minors unless an office user confirmed they are adults."})';
