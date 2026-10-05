-- LBC-21 (AC 2, 6): the audit trigger records inserts, updates, archives and deletes on departments, staff and
-- staff_roles with the right actor, old and new data and changed_fields, and a rejected statement leaves no row.
-- Actors run as the real database roles with JWT claims set. The demo seed is left alone: every assertion
-- filters on the ids created here. Fixture ids: 60...01 super admin, 60...02 plain staff, 61...01 and 61...02
-- departments, 62...01 a deletable department.

begin;

select plan(44);

create function pg_temp.as_actor(p_db_role name, p_staff_id uuid, p_statement text)
returns bigint
language plpgsql
as $$
declare
  v_original name := current_user;
  v_rows bigint;
begin
  perform set_config('request.jwt.claims', json_build_object('role', p_db_role, 'sub', p_staff_id)::text, true);
  perform set_config('role', p_db_role::text, true);
  execute p_statement;
  get diagnostics v_rows = row_count;
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_rows;
end;
$$;

create function pg_temp.fails_as(p_staff_id uuid, p_statement text)
returns text
language sql
as $$
  select format('select pg_temp.as_actor(%L, %L, %L)', 'authenticated', p_staff_id, p_statement);
$$;

create function pg_temp.entries_for(p_record_id uuid, p_action text)
returns bigint
language sql
stable
as $$
  select count(*) from audit.log where record_id = p_record_id and action = p_action;
$$;

create function pg_temp.entry_field(p_record_id uuid, p_action text, p_column text)
returns text
language sql
stable
as $$
  select to_jsonb(entry) ->> p_column
  from audit.log as entry
  where entry.record_id = p_record_id and entry.action = p_action
  order by entry.id desc
  limit 1;
$$;

insert into auth.users (id, aud, role, email)
values
  ('60000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'audit-admin@test.invalid'),
  ('60000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'audit-plain@test.invalid');

-- Owner session, no JWT: a system job. The actor must be null.
select set_config('request.jwt.claims', '', true);

insert into public.departments (id, name) values ('61000000-0000-4000-8000-000000000001', 'Audit Choir');

select is(pg_temp.entries_for('61000000-0000-4000-8000-000000000001', 'INSERT'), 1::bigint, 'should record exactly one INSERT row for a new department');
select is(pg_temp.entry_field('61000000-0000-4000-8000-000000000001', 'INSERT', 'table_name'), 'departments', 'should name the table in the INSERT row');
select is(pg_temp.entry_field('61000000-0000-4000-8000-000000000001', 'INSERT', 'actor_id'), null, 'should record a null actor for a write by the owner with no JWT');
select is(pg_temp.entry_field('61000000-0000-4000-8000-000000000001', 'INSERT', 'old_data'), null, 'should leave old_data empty on INSERT');
select is(pg_temp.entry_field('61000000-0000-4000-8000-000000000001', 'INSERT', 'changed_fields'), null, 'should leave changed_fields empty on INSERT');
select is(
  (select new_data from audit.log where record_id = '61000000-0000-4000-8000-000000000001' and action = 'INSERT'),
  (select to_jsonb(departments) from public.departments where id = '61000000-0000-4000-8000-000000000001'),
  'should store the whole inserted row as new_data'
);

-- updated_at starts in the past, so the set_updated_at trigger visibly changes it inside this transaction
insert into public.staff (id, full_name, phone, created_at, updated_at)
values
  ('60000000-0000-4000-8000-000000000001', 'Audit Admin', null, '2000-01-01T00:00:00Z', '2000-01-01T00:00:00Z'),
  ('60000000-0000-4000-8000-000000000002', 'Audit Plain', '0200000000', '2000-01-01T00:00:00Z', '2000-01-01T00:00:00Z');
insert into public.staff_roles (staff_id, role) values ('60000000-0000-4000-8000-000000000001', 'super_admin');

select is(pg_temp.entries_for('60000000-0000-4000-8000-000000000002', 'INSERT'), 1::bigint, 'should record an INSERT row for a new staff member');
select is(
  (select count(*) from audit.log where table_name = 'staff_roles' and action = 'INSERT' and new_data ->> 'staff_id' = '60000000-0000-4000-8000-000000000001'),
  1::bigint,
  'should record an INSERT row for a new staff_roles row'
);

-- UPDATE by a signed-in super admin: actor from auth.uid(), exact changed_fields, final values.

select is(
  pg_temp.as_actor('authenticated', '60000000-0000-4000-8000-000000000001', $$update public.departments set name = 'Audit Choir Renamed' where id = '61000000-0000-4000-8000-000000000001'$$),
  1::bigint,
  'should let the super admin rename a department'
);
select is(pg_temp.entries_for('61000000-0000-4000-8000-000000000001', 'UPDATE'), 1::bigint, 'should record one UPDATE row for the rename');
select is(pg_temp.entry_field('61000000-0000-4000-8000-000000000001', 'UPDATE', 'actor_id'), '60000000-0000-4000-8000-000000000001', 'should record the signed-in super admin as the actor');
select is(
  (select changed_fields from audit.log where record_id = '61000000-0000-4000-8000-000000000001' and action = 'UPDATE'),
  array['name'],
  'should list only the changed column in changed_fields'
);
select is(
  (select old_data ->> 'name' || ' > ' || (new_data ->> 'name') from audit.log where record_id = '61000000-0000-4000-8000-000000000001' and action = 'UPDATE'),
  'Audit Choir > Audit Choir Renamed',
  'should keep the old and the new value'
);

-- Archive is an UPDATE of archived_at (records, never deletes)

select is(
  pg_temp.as_actor('authenticated', '60000000-0000-4000-8000-000000000001', $$update public.departments set archived_at = '2026-01-01T00:00:00Z' where id = '61000000-0000-4000-8000-000000000001'$$),
  1::bigint,
  'should let the super admin archive a department'
);
select is(
  (select changed_fields from audit.log where record_id = '61000000-0000-4000-8000-000000000001' and action = 'UPDATE' order by id desc limit 1),
  array['archived_at'],
  'should record archiving as an UPDATE whose changed_fields is archived_at'
);
select is(
  (select old_data ->> 'archived_at' from audit.log where record_id = '61000000-0000-4000-8000-000000000001' and action = 'UPDATE' order by id desc limit 1),
  null,
  'should show archived_at as null before the archive'
);
select is(pg_temp.entries_for('61000000-0000-4000-8000-000000000001', 'DELETE'), 0::bigint, 'should not record a DELETE when a department is archived');

-- staff: the updated_at trigger runs first, so the audit row holds the final values

select is(
  pg_temp.as_actor('authenticated', '60000000-0000-4000-8000-000000000001', $$update public.staff set phone = '0244000000' where id = '60000000-0000-4000-8000-000000000002'$$),
  1::bigint,
  'should let the super admin edit a staff phone number'
);
select is(
  (select changed_fields from audit.log where record_id = '60000000-0000-4000-8000-000000000002' and action = 'UPDATE' order by id desc limit 1),
  array['phone', 'updated_at'],
  'should list phone and the trigger-maintained updated_at, in name order'
);
select is(
  (select new_data -> 'updated_at' from audit.log where record_id = '60000000-0000-4000-8000-000000000002' and action = 'UPDATE' order by id desc limit 1),
  (select to_jsonb(updated_at) from public.staff where id = '60000000-0000-4000-8000-000000000002'),
  'should store the final updated_at written by the BEFORE trigger'
);

select is(
  pg_temp.as_actor('authenticated', '60000000-0000-4000-8000-000000000001', $$update public.staff set is_active = false where id = '60000000-0000-4000-8000-000000000002'$$),
  1::bigint,
  'should let the super admin deactivate a staff member'
);
select is(
  (select changed_fields from audit.log where record_id = '60000000-0000-4000-8000-000000000002' and action = 'UPDATE' order by id desc limit 1),
  array['is_active'],
  'should record deactivation as an UPDATE of is_active (updated_at is already this transaction time)'
);

-- A bulk statement writes one row per changed row, in one statement

select is(
  pg_temp.as_actor('authenticated', '60000000-0000-4000-8000-000000000001', $$update public.departments set is_childrens_ministry = true where name like 'Audit Choir%'$$),
  1::bigint,
  'should update the department in a set-based statement'
);

insert into public.departments (id, name) values
  ('61000000-0000-4000-8000-000000000002', 'Audit Youth'),
  ('62000000-0000-4000-8000-000000000001', 'Audit Temporary');
update public.departments set is_childrens_ministry = true where name in ('Audit Youth', 'Audit Temporary');

select is(
  (select count(*) from audit.log where action = 'UPDATE' and record_id in ('61000000-0000-4000-8000-000000000002', '62000000-0000-4000-8000-000000000001')),
  2::bigint,
  'should record one UPDATE row per row changed by a single statement'
);

-- DELETE

delete from public.departments where id = '62000000-0000-4000-8000-000000000001';

select is(pg_temp.entries_for('62000000-0000-4000-8000-000000000001', 'DELETE'), 1::bigint, 'should record a DELETE row');
select is(
  (select new_data is null and changed_fields is null and old_data ->> 'name' = 'Audit Temporary'
   from audit.log where record_id = '62000000-0000-4000-8000-000000000001' and action = 'DELETE'),
  true,
  'should keep the removed row as old_data and leave new_data and changed_fields empty on DELETE'
);

-- grant_role and revoke_role run as security definer: the actor is still the signed-in super admin

select is(
  pg_temp.as_actor('authenticated', '60000000-0000-4000-8000-000000000001', $$select public.grant_role('60000000-0000-4000-8000-000000000001', 'pastor')$$),
  1::bigint,
  'should let the super admin grant a role'
);
select is(
  (select actor_id from audit.log where table_name = 'staff_roles' and action = 'INSERT' and new_data ->> 'role' = 'pastor' and new_data ->> 'staff_id' = '60000000-0000-4000-8000-000000000001'),
  '60000000-0000-4000-8000-000000000001'::uuid,
  'should record the super admin as the actor of grant_role even though the function is security definer'
);

select is(
  pg_temp.as_actor('authenticated', '60000000-0000-4000-8000-000000000001', $$select public.revoke_role('60000000-0000-4000-8000-000000000001', 'pastor')$$),
  1::bigint,
  'should let the super admin revoke a role'
);
select is(
  (select actor_id from audit.log where table_name = 'staff_roles' and action = 'DELETE' and old_data ->> 'role' = 'pastor' and old_data ->> 'staff_id' = '60000000-0000-4000-8000-000000000001'),
  '60000000-0000-4000-8000-000000000001'::uuid,
  'should record the super admin as the actor of revoke_role'
);
select is(
  (select new_data is null from audit.log where table_name = 'staff_roles' and action = 'DELETE' and old_data ->> 'role' = 'pastor' and old_data ->> 'staff_id' = '60000000-0000-4000-8000-000000000001'),
  true,
  'should leave new_data empty on the revoke_role DELETE row'
);

-- Other callers

select is(
  pg_temp.as_actor('service_role', null, $$insert into public.departments (id, name) values ('61000000-0000-4000-8000-000000000003', 'Audit Service')$$),
  1::bigint,
  'should let the service role write a department'
);
select is(pg_temp.entry_field('61000000-0000-4000-8000-000000000003', 'INSERT', 'actor_id'), null, 'should record a null actor for the service role, which has no user');

set local session_replication_role = replica;
insert into public.departments (id, name) values ('61000000-0000-4000-8000-000000000004', 'Audit Replica');
set local session_replication_role = origin;

select is(pg_temp.entries_for('61000000-0000-4000-8000-000000000004', 'INSERT'), 1::bigint, 'should still audit a write made with session_replication_role = replica');

select is(
  pg_temp.as_actor('authenticated', '60000000-0000-4000-8000-000000000001', $$update public.departments set name = 'Audit Youth Renamed' where id = '61000000-0000-4000-8000-000000000002'$$),
  1::bigint,
  'should let a second rename succeed'
);
select is(
  (select count(*) from audit.log where record_id = '61000000-0000-4000-8000-000000000002' and action = 'UPDATE' and actor_id = '60000000-0000-4000-8000-000000000001'),
  1::bigint,
  'should record the actor only on the rows that the signed-in user wrote'
);

-- Writes the database refuses leave no audit row: the audit row rolls back with the statement.
-- 10...01 is the seeded super admin and 60...01 the fixture one; a bulk delete removes the first row, then
-- raises STAFF_LAST_SUPER_ADMIN on the second.

create temp table audit_count_before as select count(*) as total from audit.log;
create temp table role_count_before as select count(*) as total from public.staff_roles where role = 'super_admin';

select throws_ok(
  $$ delete from public.staff_roles where role = 'super_admin' $$,
  'P0001',
  'STAFF_LAST_SUPER_ADMIN',
  'should refuse to delete every super admin'
);

select is(
  (select count(*) from audit.log),
  (select total from audit_count_before),
  'should leave no audit row behind when the statement that deleted the first super admin row is rolled back'
);
select is(
  (select count(*) from public.staff_roles where role = 'super_admin'),
  (select total from role_count_before),
  'should keep every super admin row after the refused delete'
);

select throws_ok(
  pg_temp.fails_as('60000000-0000-4000-8000-000000000002', $$insert into public.departments (name) values ('Audit Denied')$$),
  '42501',
  null,
  'should refuse an insert by a role that has no insert grant'
);
select is(
  (select count(*) from audit.log where new_data ->> 'name' = 'Audit Denied'),
  0::bigint,
  'should record nothing for a write that row level security or grants refused'
);

select throws_ok(
  pg_temp.fails_as('60000000-0000-4000-8000-000000000001', $$insert into public.departments (name) values ('Audit Choir Renamed')$$),
  '23505',
  null,
  'should refuse a duplicate department name'
);
select is(
  (select count(*) from audit.log where action = 'INSERT' and new_data ->> 'name' = 'Audit Choir Renamed'),
  0::bigint,
  'should record nothing for an insert that violated a constraint'
);

-- Every audit row has an allowed action and a record id

select is(
  (select count(*) from audit.log where action not in ('INSERT', 'UPDATE', 'DELETE', 'LOGIN', 'EXPORT') or record_id is null),
  0::bigint,
  'should hold only valid actions and a record id on every row'
);

select * from finish();

rollback;
