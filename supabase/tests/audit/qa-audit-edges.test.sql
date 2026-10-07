-- LBC-21 QA: edge cases on top of the worker's tests, run against the real demo seed and rolled back.
-- Covers: a non-owner role granted ALL on audit.log, action and details edge cases of log_audit_event,
-- actor attribution for each of the seven seeded roles, changed_fields for several columns and null
-- transitions, unicode data, bulk updates, and failed statements leaving no audit rows.

begin;

select plan(30);

create function pg_temp.as_user(p_db_role name, p_user_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', p_db_role, 'sub', p_user_id)::text, true);
  perform set_config('role', p_db_role::text, true);
end;
$$;

create function pg_temp.as_owner()
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end;
$$;

-- 1. A role that holds every privilege on audit.log still cannot change it

create role qa_audit_all nologin;
grant qa_audit_all to postgres;
grant usage on schema audit to qa_audit_all;
grant all on table audit.log to qa_audit_all;

create temp table marks (name text primary key, max_id bigint not null);

create function pg_temp.mark(p_name text)
returns void
language sql
as $$
  insert into marks select p_name, coalesce(max(id), 0) from audit.log;
$$;

create function pg_temp.rows_since(p_name text)
returns bigint
language sql
as $$
  select count(*) from audit.log where id > (select max_id from marks where name = p_name);
$$;

create function pg_temp.run_as_all_role(p_statement text)
returns void
language plpgsql
as $$
begin
  perform set_config('role', 'qa_audit_all', true);
  execute p_statement;
  perform set_config('role', 'postgres', true);
end;
$$;

select throws_ok(
  $$ select pg_temp.run_as_all_role('update audit.log set action = ''LOGIN''') $$,
  'P0001', 'AUDIT_LOG_IMMUTABLE',
  'should refuse UPDATE on audit.log even for a non-owner role granted ALL'
);
select throws_ok(
  $$ select pg_temp.run_as_all_role('delete from audit.log') $$,
  'P0001', 'AUDIT_LOG_IMMUTABLE',
  'should refuse DELETE on audit.log even for a non-owner role granted ALL'
);
select throws_ok(
  $$ select pg_temp.run_as_all_role('truncate audit.log') $$,
  'P0001', 'AUDIT_LOG_IMMUTABLE',
  'should refuse TRUNCATE on audit.log even for a non-owner role granted ALL'
);
select throws_ok(
  $$ select pg_temp.run_as_all_role('insert into audit.log (table_name, record_id, action) values (''staff'', gen_random_uuid(), ''LOGIN'')') $$,
  '42501', null::text,
  'should refuse a direct INSERT into audit.log even for a non-owner role granted ALL, because no policy allows it'
);

-- 2. Actor attribution through the public wrapper for each of the seven roles

create function pg_temp.log_login_as(p_user_id uuid)
returns uuid
language plpgsql
as $$
declare
  v_record_id uuid;
begin
  perform pg_temp.as_user('authenticated', p_user_id);
  v_record_id := public.log_audit_event('LOGIN', 'staff');
  perform pg_temp.as_owner();
  return v_record_id;
end;
$$;


select pg_temp.log_login_as(id) from public.staff;

select is(
  (select count(*) from audit.log where action = 'LOGIN' and actor_id is not null and actor_id = record_id),
  7::bigint,
  'should record one LOGIN row per seeded role with the actor and the record id both set to that user'
);

select is(
  (select count(distinct actor_id) from audit.log where action = 'LOGIN'),
  7::bigint,
  'should attribute each LOGIN row to a different actor'
);

-- 3. log_audit_event action and details edge cases

create function pg_temp.log_as_pastor(p_action text, p_details jsonb default null)
returns uuid
language plpgsql
as $$
declare
  v_record_id uuid;
begin
  perform pg_temp.as_user('authenticated', '10000000-0000-4000-8000-000000000002');
  v_record_id := public.log_audit_event(p_action, 'staff', null, p_details);
  perform pg_temp.as_owner();
  return v_record_id;
end;
$$;

-- staff.member_id has a foreign key since LBC-26, so the linked member has to exist.
insert into public.members (id, first_name, last_name, date_of_birth)
values ('30000000-0000-4000-8000-000000000001', 'Audit', 'Edge', '1980-01-01');

select pg_temp.mark('before_calls');

select throws_ok($$ select pg_temp.log_as_pastor('login') $$, 'P0001', 'VALIDATION_FAILED', 'should reject a lower case action');
select throws_ok($$ select pg_temp.log_as_pastor(' LOGIN') $$, 'P0001', 'VALIDATION_FAILED', 'should reject an action with a leading space');
select throws_ok($$ select pg_temp.log_as_pastor(E'LOGIN\n') $$, 'P0001', 'VALIDATION_FAILED', 'should reject an action with a trailing newline');
select throws_ok($$ select pg_temp.log_as_pastor('LОGIN') $$, 'P0001', 'VALIDATION_FAILED', 'should reject an action that uses a Cyrillic lookalike letter');
select throws_ok($$ select pg_temp.log_as_pastor('') $$, 'P0001', 'VALIDATION_FAILED', 'should reject an empty action');
select throws_ok($$ select pg_temp.log_as_pastor('UPDATE') $$, 'P0001', 'VALIDATION_FAILED', 'should reject a data-change action that only the trigger may write');
select throws_ok(
  $$ select pg_temp.log_as_pastor('EXPORT', jsonb_build_object('k', repeat('a', 4088))) $$,
  'P0001', 'VALIDATION_FAILED',
  'should reject details of 4097 bytes'
);
select lives_ok(
  $$ select pg_temp.log_as_pastor('EXPORT', jsonb_build_object('k', repeat('a', 4087))) $$,
  'should accept details of exactly 4096 bytes'
);

select is(
  pg_temp.rows_since('before_calls'),
  1::bigint,
  'should leave exactly one new row after seven rejected calls and one accepted call'
);

-- 4. changed_fields for several columns, null transitions and unicode

select pg_temp.as_user('authenticated', '10000000-0000-4000-8000-000000000001');

update public.staff
set phone = '0201234567', member_id = '30000000-0000-4000-8000-000000000001', full_name = E'Ọ''Brien Ñandi 日本'
where id = '10000000-0000-4000-8000-000000000005';

select pg_temp.as_owner();

select is(
  (select changed_fields from audit.log where table_name = 'staff' and action = 'UPDATE' order by id desc limit 1),
  array['full_name', 'member_id', 'phone', 'updated_at']::text[],
  'should list every changed column, sorted, including null-to-value transitions'
);

select is(
  (select new_data ->> 'full_name' from audit.log where table_name = 'staff' and action = 'UPDATE' order by id desc limit 1),
  E'Ọ''Brien Ñandi 日本',
  'should keep diacritics, an apostrophe and non-Latin text intact in new_data'
);

select is(
  (select new_data ->> 'phone' from audit.log where table_name = 'staff' and action = 'UPDATE' order by id desc limit 1),
  '0201234567',
  'should keep the leading zero of a phone number in new_data'
);

select pg_temp.as_user('authenticated', '10000000-0000-4000-8000-000000000001');

update public.staff
set phone = null
where id = '10000000-0000-4000-8000-000000000005';

select pg_temp.as_owner();

select is(
  (select changed_fields from audit.log where table_name = 'staff' and action = 'UPDATE' order by id desc limit 1),
  array['phone']::text[],
  'should list a value-to-null change, with updated_at unchanged inside one transaction'
);

select is(
  (select old_data ->> 'phone' from audit.log where table_name = 'staff' and action = 'UPDATE' order by id desc limit 1),
  '0201234567',
  'should keep the previous phone in old_data when it is cleared'
);

-- 5. Bulk update: one audit row per changed row

select pg_temp.mark('before_bulk');

select pg_temp.as_user('authenticated', '10000000-0000-4000-8000-000000000001');
update public.staff set phone = '0555000000';
select pg_temp.as_owner();

select is(
  (select count(*) from audit.log where id > (select max_id from marks where name = 'before_bulk') and action = 'UPDATE' and table_name = 'staff'),
  7::bigint,
  'should write one audit row for each of the seven rows touched by one UPDATE statement'
);

select is(
  pg_temp.rows_since('before_bulk'),
  7::bigint,
  'should write exactly seven rows for a seven row update and no more'
);

-- 6. Archiving a department is an UPDATE with archived_at in changed_fields, by the super admin

select pg_temp.as_user('authenticated', '10000000-0000-4000-8000-000000000001');
insert into public.departments (name) values ('QA Edge Dept Ñ');
update public.departments set archived_at = now() where name = 'QA Edge Dept Ñ';
select pg_temp.as_owner();

select is(
  (select changed_fields from audit.log where table_name = 'departments' and action = 'UPDATE' order by id desc limit 1),
  array['archived_at']::text[],
  'should record archiving a department as an UPDATE that changes only archived_at'
);

select is(
  (select actor_id from audit.log where table_name = 'departments' and action = 'UPDATE' order by id desc limit 1),
  '10000000-0000-4000-8000-000000000001'::uuid,
  'should attribute the archive to the super admin who did it'
);

select is(
  (select count(*) from audit.log where table_name = 'departments' and action = 'INSERT' and new_data ->> 'name' = 'QA Edge Dept Ñ'),
  1::bigint,
  'should record the department insert with the unicode name'
);

-- 7. A failed business statement leaves no audit row

select pg_temp.mark('before_failure');

select pg_temp.as_user('authenticated', '10000000-0000-4000-8000-000000000001');
select throws_ok(
  $$ select public.revoke_role('10000000-0000-4000-8000-000000000001', 'super_admin') $$,
  'P0001', 'STAFF_LAST_SUPER_ADMIN',
  'should refuse to revoke the last super admin'
);
select pg_temp.as_owner();

select is(
  pg_temp.rows_since('before_failure'),
  0::bigint,
  'should leave no audit row when the change was refused'
);

-- 8. A denied role changes nothing and logs nothing

select pg_temp.as_user('authenticated', '10000000-0000-4000-8000-000000000002');
select throws_ok(
  $$ select public.grant_role('10000000-0000-4000-8000-000000000005', 'treasurer') $$,
  'P0001', 'AUTH_FORBIDDEN',
  'should refuse a pastor granting a role'
);
select pg_temp.as_owner();

select is(
  pg_temp.rows_since('before_failure'),
  0::bigint,
  'should leave no audit row after a denied grant_role call'
);

select is(
  (select count(*) from audit.log where actor_id is null and id > (select max_id from marks where name = 'before_calls')),
  0::bigint,
  'should attribute every row written by these user actions to an actor'
);

select * from finish();

rollback;
