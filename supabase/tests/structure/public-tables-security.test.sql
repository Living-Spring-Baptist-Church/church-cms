-- Structural gate (LBC-15, backend.md section 10): every table in the public schema must have
-- row level security enabled, at least one policy and the audit trigger.
--
-- The rule lives in pg_temp.public_table_security_gaps(), defined once below and used twice:
--   1. against the real database, where it must report nothing (this passes vacuously while
--      public has no tables, and fails the moment a future migration forgets one of the three);
--   2. against probe tables created inside this transaction, to prove each failure is detected.
-- Everything is rolled back, so no probe table ever reaches the database.
--
-- Audit trigger detection (LBC-21): a trigger counts only when it runs the function passed in
-- p_audit_function and is a complete audit: enabled for normal sessions (tgenabled O, or A for
-- always; R fires only in replica mode and D is disabled), a ROW trigger (a statement trigger
-- has no old or new row), AFTER (it sees the final row), covering INSERT, UPDATE and DELETE,
-- with no UPDATE OF column list and no WHEN condition (either would skip changes).
-- The real check passes audit.record_change(), looked up with to_regprocedure(). A null function
-- switches the audit part off; that is for probes only, and the first test below fails if
-- audit.record_change() ever stops existing, so the gate cannot go quiet by accident.

begin;

select plan(20);

create function pg_temp.public_table_security_gaps(p_audit_function regprocedure)
returns table (table_name name, gap text)
language sql
stable
as $$
  select tables.relname, gaps.gap
  from pg_class as tables
  join pg_namespace as schemas on schemas.oid = tables.relnamespace
  cross join lateral (
    select 'RLS_DISABLED' as gap
    where not tables.relrowsecurity
    union all
    select 'NO_POLICIES'
    where not exists (select 1 from pg_policy where pg_policy.polrelid = tables.oid)
    union all
    select 'NO_AUDIT_TRIGGER'
    where p_audit_function is not null
      and not exists (
        select 1
        from pg_trigger
        where pg_trigger.tgrelid = tables.oid
          and pg_trigger.tgfoid = p_audit_function::oid
          and not pg_trigger.tgisinternal
          and pg_trigger.tgenabled in ('O', 'A')
          and pg_trigger.tgtype & 1 = 1
          and pg_trigger.tgtype & 2 = 0
          and pg_trigger.tgtype & 64 = 0
          and pg_trigger.tgtype & 28 = 28
          and pg_trigger.tgattr::text = ''
          and pg_trigger.tgqual is null
      )
  ) as gaps
  where schemas.nspname = 'public'
    and tables.relkind in ('r', 'p')
    and not tables.relispartition
    and not exists (
      select 1 from pg_depend
      where pg_depend.classid = 'pg_class'::regclass
        and pg_depend.objid = tables.oid
        and pg_depend.deptype = 'e'
    )
$$;

-- 1. The real database

select isnt(
  to_regprocedure('audit.record_change()'),
  null,
  'should have audit.record_change(), so the audit part of the gate is switched on'
);

select is_empty(
  $$ select * from pg_temp.public_table_security_gaps(to_regprocedure('audit.record_change()')) $$,
  'should have RLS, at least one policy and the audit trigger on every public table'
);

-- 2. Probes, created only after the real check has run

create function pg_temp.probe_audit()
returns trigger
language plpgsql
as $$
begin
  return new;
end;
$$;

create function pg_temp.gaps_of(p_table name, p_with_audit boolean)
returns text
language sql
stable
as $$
  select string_agg(gap, ',' order by gap)
  from pg_temp.public_table_security_gaps(
    case when p_with_audit then 'pg_temp.probe_audit()'::regprocedure end
  )
  where table_name = p_table
$$;

create table public.probe_secured (id uuid primary key, label text);
alter table public.probe_secured enable row level security;
create policy probe_secured_select on public.probe_secured for select using (true);
create trigger probe_secured_audit after insert or update or delete on public.probe_secured
  for each row execute function pg_temp.probe_audit();

create table public.probe_no_rls (id uuid primary key);
create policy probe_no_rls_select on public.probe_no_rls for select using (true);
create trigger probe_no_rls_audit after insert or update or delete on public.probe_no_rls
  for each row execute function pg_temp.probe_audit();

create table public.probe_no_policy (id uuid primary key);
alter table public.probe_no_policy enable row level security;
create trigger probe_no_policy_audit after insert or update or delete on public.probe_no_policy
  for each row execute function pg_temp.probe_audit();

create table public.probe_no_trigger (id uuid primary key);
alter table public.probe_no_trigger enable row level security;
create policy probe_no_trigger_select on public.probe_no_trigger for select using (true);

create table public.probe_disabled_trigger (id uuid primary key);
alter table public.probe_disabled_trigger enable row level security;
create policy probe_disabled_trigger_select on public.probe_disabled_trigger for select using (true);
create trigger probe_disabled_trigger_audit after insert or update or delete on public.probe_disabled_trigger
  for each row execute function pg_temp.probe_audit();
alter table public.probe_disabled_trigger disable trigger probe_disabled_trigger_audit;

create table public.probe_nothing (id uuid primary key);

-- Triggers that exist and are enabled but do not audit every change. Each table is otherwise secured.
create function pg_temp.make_secured_probe(p_table name)
returns void
language plpgsql
as $$
begin
  execute format('create table public.%I (id uuid primary key, label text)', p_table);
  execute format('alter table public.%I enable row level security', p_table);
  execute format('create policy %I on public.%I for select using (true)', p_table || '_select', p_table);
end;
$$;

select pg_temp.make_secured_probe(name)
from unnest(array[
  'probe_replica_only', 'probe_statement_level', 'probe_insert_only',
  'probe_before_trigger', 'probe_update_of_columns', 'probe_when_condition', 'probe_always_trigger'
]::name[]) as names (name);

create trigger probe_replica_only_audit after insert or update or delete on public.probe_replica_only
  for each row execute function pg_temp.probe_audit();
alter table public.probe_replica_only enable replica trigger probe_replica_only_audit;

create trigger probe_statement_level_audit after insert or update or delete on public.probe_statement_level
  for each statement execute function pg_temp.probe_audit();

create trigger probe_insert_only_audit after insert on public.probe_insert_only
  for each row execute function pg_temp.probe_audit();

create trigger probe_before_trigger_audit before insert or update or delete on public.probe_before_trigger
  for each row execute function pg_temp.probe_audit();

create trigger probe_update_of_columns_audit after insert or update of label or delete on public.probe_update_of_columns
  for each row execute function pg_temp.probe_audit();

create trigger probe_when_condition_audit after insert or update or delete on public.probe_when_condition
  for each row when (pg_trigger_depth() = 0) execute function pg_temp.probe_audit();

create trigger probe_always_trigger_audit after insert or update or delete on public.probe_always_trigger
  for each row execute function pg_temp.probe_audit();
alter table public.probe_always_trigger enable always trigger probe_always_trigger_audit;

select is(pg_temp.gaps_of('probe_secured', true), null, 'should report nothing for a table with RLS, a policy and the audit trigger');
select is(pg_temp.gaps_of('probe_no_rls', true), 'RLS_DISABLED', 'should report a public table that has RLS disabled');
select is(pg_temp.gaps_of('probe_no_policy', true), 'NO_POLICIES', 'should report a public table that has RLS enabled but no policy');
select is(pg_temp.gaps_of('probe_no_trigger', true), 'NO_AUDIT_TRIGGER', 'should report a public table that has no audit trigger');
select is(pg_temp.gaps_of('probe_disabled_trigger', true), 'NO_AUDIT_TRIGGER', 'should report a public table whose audit trigger is disabled');
select is(pg_temp.gaps_of('probe_nothing', true), 'NO_AUDIT_TRIGGER,NO_POLICIES,RLS_DISABLED', 'should report every gap of a table that has none of the three');

select is(pg_temp.gaps_of('probe_replica_only', true), 'NO_AUDIT_TRIGGER', 'should report a table whose audit trigger fires only in replica mode');
select is(pg_temp.gaps_of('probe_statement_level', true), 'NO_AUDIT_TRIGGER', 'should report a table whose audit trigger is statement-level');
select is(pg_temp.gaps_of('probe_insert_only', true), 'NO_AUDIT_TRIGGER', 'should report a table whose audit trigger covers only INSERT');
select is(pg_temp.gaps_of('probe_before_trigger', true), 'NO_AUDIT_TRIGGER', 'should report a table whose audit trigger runs BEFORE the change');
select is(pg_temp.gaps_of('probe_update_of_columns', true), 'NO_AUDIT_TRIGGER', 'should report a table whose audit trigger fires only for some updated columns');
select is(pg_temp.gaps_of('probe_when_condition', true), 'NO_AUDIT_TRIGGER', 'should report a table whose audit trigger has a WHEN condition');
select is(pg_temp.gaps_of('probe_always_trigger', true), null, 'should accept an audit trigger that is enabled always');

-- 3. The audit part can be switched off with a null function (probes only)

select is(pg_temp.gaps_of('probe_no_trigger', false), null, 'should not require the audit trigger when the audit check is switched off');
select is(pg_temp.gaps_of('probe_nothing', false), 'NO_POLICIES,RLS_DISABLED', 'should still require RLS and a policy when the audit check is switched off');

select is(
  (select count(distinct table_name) from pg_temp.public_table_security_gaps(null) where table_name like 'probe\_%'),
  3::bigint,
  'should report only the three probe tables that miss RLS or a policy when the audit check is off'
);

-- 4. Scope: only ordinary public tables are checked

create schema probe_other_schema;
create table probe_other_schema.probe_elsewhere (id uuid primary key);
create view public.probe_view as select 1 as id;

select is(
  (select count(*) from pg_temp.public_table_security_gaps(null) where table_name in ('probe_elsewhere', 'probe_view')),
  0::bigint,
  'should ignore views and tables outside the public schema'
);

select is(
  (select count(*) from pg_temp.public_table_security_gaps(null) where table_name = 'probe_secured'),
  0::bigint,
  'should not report the secured probe table when the audit check is off'
);

select * from finish();

rollback;
