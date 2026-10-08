-- Product decision 4 (LBC-42): the pastor sees archived members and households, like the super admin.
-- Nothing else changes: the pastor still cannot write, and department heads still see non-archived rows only.

alter policy members_select_pastor on public.members
  using ((select private.has_role('pastor')));

alter policy households_select_pastor on public.households
  using ((select private.has_role('pastor')));

comment on column public.members.archived_at is 'Set when the record is archived (MEM-05). Null while active. Archived records are visible to super admin, pastor and, for adults, secretary.';
comment on column public.households.archived_at is 'Set when the household is archived (MEM-05). Null while active. Archived households are visible to super admin, pastor and secretary.';
