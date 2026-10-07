-- LBC-21 (AC 4, 6): nobody can edit or delete audit rows, and app roles cannot write them at all.
-- Every statement runs as the real database role, through SET ROLE. The owner has table privileges, so for
-- the owner the refusal comes from the immutability trigger (AUDIT_LOG_IMMUTABLE); every other role is
-- stopped earlier by missing privileges (SQLSTATE 42501).
-- Residual, not tested here because it is the owner's right: ALTER TABLE ... DISABLE TRIGGER and DROP TRIGGER.

begin;

select plan(45);

create function pg_temp.as_role(p_db_role name, p_statement text)
returns bigint
language plpgsql
as $$
declare
  v_original name := current_user;
  v_rows bigint;
begin
  perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', p_db_role, 'sub', gen_random_uuid())::text, true);
  perform set_config('role', p_db_role::text, true);
  execute p_statement;
  get diagnostics v_rows = row_count;
  perform set_config('role', v_original::text, true);
  return v_rows;
end;
$$;

create function pg_temp.fails_as(p_db_role name, p_statement text)
returns text
language sql
as $$
  select format('select pg_temp.as_role(%L, %L)', p_db_role, p_statement);
$$;

create temp table attempts (label text, statement text);
insert into attempts (label, statement)
values
  ('UPDATE', $$update audit.log set actor_id = null$$),
  ('UPDATE of nothing', $$update audit.log set actor_id = null where false$$),
  ('DELETE', $$delete from audit.log$$),
  ('DELETE of nothing', $$delete from audit.log where false$$),
  ('TRUNCATE', $$truncate audit.log$$),
  ('TRUNCATE CASCADE', $$truncate audit.log cascade$$);

insert into audit.log (table_name, record_id, action) values ('probe', gen_random_uuid(), 'EXPORT');

create temp table log_before as select count(*) as total, md5(string_agg(id::text || coalesce(new_data::text, ''), ',' order by id)) as digest from audit.log;

-- The owner: the trigger refuses, for every statement kind, even when no row matches

select throws_ok(
  pg_temp.fails_as('postgres', statement),
  'P0001',
  'AUDIT_LOG_IMMUTABLE',
  format('should refuse %s by the table owner', label)
) from attempts order by label;

select throws_ok(
  $$ insert into audit.log (id, table_name, record_id, action) overriding system value
     select id, table_name, record_id, 'LOGIN' from audit.log limit 1
     on conflict (id) do update set action = 'LOGIN' $$,
  'P0001',
  'AUDIT_LOG_IMMUTABLE',
  'should refuse an INSERT ... ON CONFLICT DO UPDATE that would edit a row'
);

set local session_replication_role = replica;
select throws_ok(
  $$ update audit.log set actor_id = null $$,
  'P0001',
  'AUDIT_LOG_IMMUTABLE',
  'should refuse an UPDATE even with session_replication_role = replica'
);
select throws_ok(
  $$ delete from audit.log $$,
  'P0001',
  'AUDIT_LOG_IMMUTABLE',
  'should refuse a DELETE even with session_replication_role = replica'
);
select throws_ok(
  $$ truncate audit.log $$,
  'P0001',
  'AUDIT_LOG_IMMUTABLE',
  'should refuse a TRUNCATE even with session_replication_role = replica'
);
set local session_replication_role = origin;

-- Every app role and the service role: no privilege at all

select throws_ok(pg_temp.fails_as('authenticated', statement), '42501', null, format('should refuse %s by authenticated', label))
from attempts order by label;

select throws_ok(pg_temp.fails_as('anon', statement), '42501', null, format('should refuse %s by anon', label))
from attempts order by label;

select throws_ok(pg_temp.fails_as('service_role', statement), '42501', null, format('should refuse %s by service_role', label))
from attempts order by label;

-- No role but the trigger path writes or reads rows

select throws_ok(
  pg_temp.fails_as('authenticated', $$insert into audit.log (table_name, record_id, action) values ('departments', gen_random_uuid(), 'INSERT')$$),
  '42501', null, 'should refuse a direct INSERT forging a data-change row by authenticated'
);
select throws_ok(
  pg_temp.fails_as('anon', $$insert into audit.log (table_name, record_id, action) values ('departments', gen_random_uuid(), 'INSERT')$$),
  '42501', null, 'should refuse a direct INSERT by anon'
);
select throws_ok(
  pg_temp.fails_as('service_role', $$insert into audit.log (table_name, record_id, action) values ('departments', gen_random_uuid(), 'INSERT')$$),
  '42501', null, 'should refuse a direct INSERT by service_role'
);
select throws_ok(
  pg_temp.fails_as('authenticated', $$select * from audit.log$$),
  '42501', null, 'should refuse a SELECT on audit.log by authenticated until the audit viewer exists'
);
select throws_ok(
  pg_temp.fails_as('anon', $$select * from audit.log$$),
  '42501', null, 'should refuse a SELECT on audit.log by anon'
);
select throws_ok(
  pg_temp.fails_as('authenticated', $$select nextval('audit.log_id_seq')$$),
  '42501', null, 'should refuse authenticated advancing the audit.log sequence'
);

-- App roles cannot switch the guard off or lift RLS

select throws_ok(
  pg_temp.fails_as('authenticated', $$alter table audit.log disable trigger log_reject_change$$),
  '42501', null, 'should refuse authenticated disabling the immutability trigger'
);
select throws_ok(
  pg_temp.fails_as('authenticated', $$alter table audit.log disable trigger all$$),
  '42501', null, 'should refuse authenticated disabling all triggers on audit.log'
);
select throws_ok(
  pg_temp.fails_as('anon', $$alter table audit.log disable trigger log_reject_change$$),
  '42501', null, 'should refuse anon disabling the immutability trigger'
);
select throws_ok(
  pg_temp.fails_as('service_role', $$alter table audit.log disable trigger log_reject_change$$),
  '42501', null, 'should refuse service_role disabling the immutability trigger'
);
select throws_ok(
  pg_temp.fails_as('authenticated', $$drop trigger log_reject_change on audit.log$$),
  '42501', null, 'should refuse authenticated dropping the immutability trigger'
);
select throws_ok(
  pg_temp.fails_as('authenticated', $$alter table audit.log disable row level security$$),
  '42501', null, 'should refuse authenticated disabling row level security on audit.log'
);
select throws_ok(
  pg_temp.fails_as('authenticated', $$grant all on audit.log to authenticated$$),
  '42501', null, 'should refuse authenticated granting itself privileges on audit.log'
);
select throws_ok(
  pg_temp.fails_as('authenticated', $$alter table public.staff disable trigger audit_staff$$),
  '42501', null, 'should refuse authenticated disabling the audit trigger on a business table'
);
select throws_ok(
  pg_temp.fails_as('authenticated', $$set session_replication_role = replica$$),
  '42501', null, 'should refuse authenticated switching session_replication_role, which would skip origin triggers'
);

select is(
  (select total from log_before),
  (select count(*) from audit.log),
  'should leave the number of audit rows unchanged after every refused statement'
);
select is(
  (select digest from log_before),
  (select md5(string_agg(id::text || coalesce(new_data::text, ''), ',' order by id)) from audit.log),
  'should leave every audit row unchanged after every refused statement'
);

select * from finish();

rollback;
