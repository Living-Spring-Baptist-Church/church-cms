-- Children's records (LBC-42, owner decision 6, option d).
-- The secretary is treated like the head of a children's ministry for every department flagged
-- is_childrens_ministry. She reads, creates and edits only the minors who belong to such a department, never
-- youth or other minors. The head of a children's ministry department can edit (not archive) the minors of
-- the department they head and register new ones. Department heads stay read-only for everyone else.
--
-- Creating a child cannot be a plain insert: the row must exist before it can be linked to a department, and a
-- minor with no link is unreadable to the secretary and the head. register_child inserts the member and the
-- department link in one transaction, so no unreadable orphan can be left behind. Direct inserts of minors
-- stay super admin only.
--
-- Households (decision for the human to confirm): the secretary sees a household when it has no members yet
-- (so she can create one) or when it contains at least one person she may see. A household holding only
-- minors outside the children's ministry stays hidden from her, so its address does not leak.

create function private.is_in_childrens_ministry(p_member_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.member_departments as membership
    join public.departments on departments.id = membership.department_id
    where membership.member_id = p_member_id
      and departments.is_childrens_ministry
  );
$$;

comment on function private.is_in_childrens_ministry(uuid) is 'True when the member belongs to at least one department flagged is_childrens_ministry. Reads member_departments as owner so the members policies do not recurse.';

create function private.is_childrens_ministry_link(p_member_id uuid, p_department_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.members
    join public.departments on departments.id = p_department_id
    where members.id = p_member_id
      and departments.is_childrens_ministry
      and private.is_minor(members.date_of_birth, members.adult_confirmed)
  );
$$;

comment on function private.is_childrens_ministry_link(uuid, uuid) is 'True when the department is a children''s ministry and the member is a minor, so removing the link would leave the child unreadable to the secretary and the department head. Only a super admin may remove such a link.';

create function private.household_visible_to_secretary(p_household_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (select 1 from public.members where members.household_id = p_household_id)
    or exists (
      select 1
      from public.members
      where members.household_id = p_household_id
        and (
          not private.is_minor(members.date_of_birth, members.adult_confirmed)
          or private.is_in_childrens_ministry(members.id)
        )
    );
$$;

comment on function private.household_visible_to_secretary(uuid) is 'True when the household has no members yet or holds at least one person the secretary may see (an adult, or a minor in a children''s ministry). Households with only other minors stay hidden from her.';

revoke execute on function
  private.is_in_childrens_ministry(uuid),
  private.is_childrens_ministry_link(uuid, uuid),
  private.household_visible_to_secretary(uuid)
from public, anon, authenticated;

grant execute on function
  private.is_in_childrens_ministry(uuid),
  private.is_childrens_ministry_link(uuid, uuid),
  private.household_visible_to_secretary(uuid)
to authenticated;

-- members: the secretary reads and edits adults and children's ministry minors, archived ones included.

alter policy members_select_secretary on public.members
  using (
    (select private.has_role('secretary'))
    and (not private.is_minor(date_of_birth, adult_confirmed) or private.is_in_childrens_ministry(id))
  );

alter policy members_update_secretary on public.members
  using (
    (select private.has_role('secretary'))
    and (not private.is_minor(date_of_birth, adult_confirmed) or private.is_in_childrens_ministry(id))
  )
  with check (
    (select private.has_role('secretary'))
    and (not private.is_minor(date_of_birth, adult_confirmed) or private.is_in_childrens_ministry(id))
  );

-- The head of a children's ministry edits the minors of the department they head. They cannot archive
-- (the select policy hides archived rows from them), turn the child into an adult or touch anyone else.
create policy members_update_children_head on public.members for update to authenticated
  using (
    archived_at is null
    and private.is_minor(date_of_birth, adult_confirmed)
    and private.heads_department_of_member(id, true)
  )
  with check (
    archived_at is null
    and private.is_minor(date_of_birth, adult_confirmed)
    and private.heads_department_of_member(id, true)
  );

-- households: the secretary sees and edits the ones that hold someone she may see.

alter policy households_select_secretary on public.households
  using ((select private.has_role('secretary')) and private.household_visible_to_secretary(id));

alter policy households_update_office on public.households
  using (
    (select private.has_role('super_admin'))
    or ((select private.has_role('secretary')) and private.household_visible_to_secretary(id))
  )
  with check (
    (select private.has_role('super_admin'))
    or ((select private.has_role('secretary')) and private.household_visible_to_secretary(id))
  );

-- member_departments: removing a minor's children's ministry link would orphan the child, so only a super admin may.

alter policy member_departments_delete_office on public.member_departments
  using (
    (select private.can_manage_members())
    and exists (select 1 from public.members where members.id = member_departments.member_id)
    and (
      (select private.has_role('super_admin'))
      or not private.is_childrens_ministry_link(member_id, department_id)
    )
  );

-- register_child: the one path that creates a minor for the secretary and the head of a children's ministry.
-- SECURITY DEFINER because no policy can allow inserting a minor before its department link exists; the role
-- and department checks run first and every write is still recorded by the audit triggers (actor auth.uid()).
-- No enum parameter for the status: pg_graphql silently drops a function that has one, so a child starts active.
create function public.register_child(
  p_first_name text,
  p_last_name text,
  p_department_id uuid,
  p_date_of_birth date default null,
  p_household_id uuid default null,
  p_gender text default null
)
returns public.members
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_member public.members;
  v_can_manage boolean := private.can_manage_members();
begin
  if not (v_can_manage or private.heads_department(p_department_id)) then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN',
      detail = 'Only a super admin, a secretary or the head of the children''s ministry department can register a child';
  end if;

  if p_first_name is null or btrim(p_first_name) = '' or p_last_name is null or btrim(p_last_name) = '' then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED', detail = 'first_name and last_name are required';
  end if;
  if not exists (
    select 1 from public.departments
    where departments.id = p_department_id and departments.is_childrens_ministry and departments.archived_at is null
  ) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = 'department_id must be an active children''s ministry department';
  end if;
  if p_date_of_birth is not null
     and (p_date_of_birth > current_date or not private.is_minor_on(p_date_of_birth, current_date))
  then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = 'date_of_birth must be a past date that makes the person a minor';
  end if;
  if p_household_id is not null then
    if not v_can_manage then
      raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN', detail = 'Only the office can set a household';
    end if;
    if not exists (
      select 1 from public.households
      where households.id = p_household_id
        and households.archived_at is null
        and (private.has_role('super_admin') or private.household_visible_to_secretary(households.id))
    ) then
      raise exception using errcode = 'P0001', message = 'NOT_FOUND', detail = 'No household with that id';
    end if;
  end if;

  insert into public.members (first_name, last_name, date_of_birth, household_id, gender, status)
  values (btrim(p_first_name), btrim(p_last_name), p_date_of_birth, p_household_id, p_gender, 'active')
  returning * into v_member;

  insert into public.member_departments (member_id, department_id) values (v_member.id, p_department_id);

  return v_member;
end;
$$;

comment on function public.register_child(text, text, uuid, date, uuid, text) is 'Registers an active child (a minor) and links them to a children''s ministry department in one step, and returns the member. Super admin, secretary, or the head of that department. A date of birth, when given, must make the person a minor. The household is set by the office only. Errors: AUTH_FORBIDDEN, VALIDATION_FAILED, NOT_FOUND.';

revoke execute on function public.register_child(text, text, uuid, date, uuid, text) from public, anon;
grant execute on function public.register_child(text, text, uuid, date, uuid, text) to authenticated;

comment on table public.members is 'Members and visitors in one table (MEM-01, MEM-02). Records of people under the age of majority are visible only to super admin, pastor, and, for the minors of a children''s ministry department, the secretary and the head of that department. Archived instead of deleted (MEM-05).';
