-- LBC-42 hardening, owner decisions after review.
-- 1. Only a super admin may turn an existing minor into an adult (a date_of_birth change or an adult_confirmed
--    tick). The secretary can still register adults, tick adult_confirmed on new adults and correct a date of
--    birth that keeps the person in the same minor or adult state.
-- 2. household_id on members must be null, unchanged, or a household the caller may see, so a person cannot be
--    moved into a household that is hidden from the caller to reveal it. Ministry heads cannot set a household.
-- Both rules are triggers because column grants and policies cannot compare the old and new row by role.
-- Roles other than the app roles (migrations, seed, the service role) are not restricted, as in
-- guard_adult_confirmed. A refused statement raises, so it rolls back and leaves no audit row.

-- Why security definer: the app roles have no USAGE on schema private, and a plpgsql trigger function that runs
-- as its caller cannot even resolve private.* names. (guard_adult_confirmed was written that way and fails with
-- 42501 on a real signed-in write, which the old tests missed, probably because the fixture ran it first as the
-- owner and left a cached plan.) The trigger functions therefore run as their owner and ask
-- private.in_app_session() whether the statement came from a signed-in or anonymous API session. That reads the
-- session role setting, which security definer does not change, unlike current_user.
create function private.in_app_session()
returns boolean
language sql
stable
set search_path = ''
as $$
  select current_setting('role') in ('authenticated', 'anon');
$$;

comment on function private.in_app_session() is 'True when the statement runs in an API session (SET ROLE authenticated or anon). False for migrations, seed data and the service role. Reads the role setting so it also works inside security definer functions.';

revoke execute on function private.in_app_session() from public, anon, authenticated;

create or replace function private.guard_adult_confirmed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if (tg_op = 'INSERT' and new.adult_confirmed)
     or (tg_op = 'UPDATE' and new.adult_confirmed is distinct from old.adult_confirmed)
  then
    if private.in_app_session() and not private.can_manage_members() then
      raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN',
        detail = 'Only a super admin or secretary can set adult_confirmed';
    end if;
  end if;
  return new;
end;
$$;

create function private.guard_minor_conversion()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.in_app_session()
     and private.is_minor(old.date_of_birth, old.adult_confirmed)
     and not private.is_minor(new.date_of_birth, new.adult_confirmed)
     and not private.has_role('super_admin')
  then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN',
      detail = 'Only a super admin can change a minor into an adult';
  end if;
  return new;
end;
$$;

comment on function private.guard_minor_conversion() is 'Trigger function: refuses a change that turns a minor into an adult (date_of_birth or adult_confirmed) by any signed-in user who is not an active super admin.';

create function private.guard_member_household()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.household_id is null
     or (tg_op = 'UPDATE' and new.household_id is not distinct from old.household_id)
     or not private.in_app_session()
  then
    return new;
  end if;

  if private.has_role('super_admin')
     or (private.has_role('secretary')
         and exists (select 1 from public.households where id = new.household_id)
         and private.household_visible_to_secretary(new.household_id))
  then
    return new;
  end if;

  raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN',
    detail = 'You cannot place a member in a household you cannot see';
end;
$$;

comment on function private.guard_member_household() is 'Trigger function: a signed-in user may set members.household_id only to null, to its current value, or (secretary) to a household she can see. Super admin is unrestricted; ministry heads cannot set a household.';

revoke execute on function private.guard_minor_conversion(), private.guard_member_household()
from public, anon, authenticated;

create trigger members_guard_minor_conversion
  before update of date_of_birth, adult_confirmed on public.members
  for each row execute function private.guard_minor_conversion();

create trigger members_guard_household
  before insert or update of household_id on public.members
  for each row execute function private.guard_member_household();

-- Comment-only follow-ups from review.
comment on column public.members.archived_at is 'Set when the record is archived (MEM-05). Null while active. Archived records are visible to super admin, pastor and, for adults and children of a children''s ministry, the secretary.';

comment on function private.is_in_childrens_ministry(uuid) is 'True when the member belongs to at least one department flagged is_childrens_ministry. Deliberately ignores departments.archived_at, so children of a retired ministry stay visible to the secretary. Reads member_departments as owner so the members policies do not recurse.';
