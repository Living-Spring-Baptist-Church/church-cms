-- OVR-01 (LBC-20 overview card): the number of new visitors this month, as one GraphQL operation.
-- Source: docs/prd.md OVR-01; docs/standards/backend.md sections 5, 7 and 8.
--
-- Business rule (tech lead decision): a new visitor this month is a member row whose first_visit_on falls in the
-- current calendar month in the church time zone, whatever its status now (a converted visitor keeps first_visit_on).
--
-- Access: only super admin, pastor and secretary get a number; every other caller is refused with AUTH_FORBIDDEN, and
-- anon has no execute grant. For those roles the count uses the same rows the members policies let them read (see the
-- comment in the function). The function is security definer, not invoker, because app roles have no USAGE on schema
-- private and a plpgsql body resolves private.* names when it runs, so an invoker function could not reach the helpers.
-- The pgTAP suite pins the count to the rows each role can read from the table, so drift from the policies fails there.

create function private.can_see_visitor_counts()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.has_any_role(array['super_admin', 'pastor', 'secretary']::public.app_role[]);
$$;

comment on function private.can_see_visitor_counts() is 'True when the signed-in user is an active super admin, pastor or secretary, the roles that see the new visitor count on the overview.';

revoke execute on function private.can_see_visitor_counts() from public, anon, authenticated;

create function public.get_new_visitors_this_month()
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_month_start date;
  v_next_month_start date;
begin
  if not private.can_see_visitor_counts() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN',
      detail = 'Only a super admin, pastor or secretary can see the new visitor count';
  end if;

  v_month_start := date_trunc('month', now() at time zone private.church_time_zone())::date;
  v_next_month_start := (v_month_start + interval '1 month')::date;

  -- Mirrors the members select policies for these roles: super admin and pastor read every member (can_view_minors);
  -- the secretary reads adults and the children of a children's ministry (is_minor false, or is_in_childrens_ministry).
  return (
    select count(*)::integer
    from public.members
    where members.first_visit_on >= v_month_start
      and members.first_visit_on < v_next_month_start
      and (
        private.can_view_minors()
        or not private.is_minor(members.date_of_birth, members.adult_confirmed)
        or private.is_in_childrens_ministry(members.id)
      )
  );
end;
$$;

comment on function public.get_new_visitors_this_month() is 'Number of people whose first visit was in the current calendar month in the church time zone, whatever their status now. Counts only the members the caller can read, so the number can differ by role: super admin and pastor see every member, the secretary sees adults and the children of a children''s ministry. Super admin, pastor and secretary only. Errors: AUTH_FORBIDDEN.';

revoke execute on function public.get_new_visitors_this_month() from public, anon;
grant execute on function public.get_new_visitors_this_month() to authenticated;
