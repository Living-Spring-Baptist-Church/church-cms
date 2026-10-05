-- QA edge cases for the public table security gate (LBC-15). The gate query is copied from
-- public-tables-security.test.sql, which defines it inside its own transaction; keep both in step.
-- Everything is rolled back.

begin;

select plan(14);

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

create function pg_temp.gaps_of(p_table name, p_audit regprocedure)
returns text
language sql
stable
as $$
  select string_agg(gap, ',' order by gap)
  from pg_temp.public_table_security_gaps(p_audit)
  where table_name = p_table
$$;

-- The audit part is on: audit.record_change() exists (LBC-21)

select isnt(to_regprocedure('audit.record_change()'), null, 'should have audit.record_change(), so the audit part is on');

create table public.edge_plain (id uuid primary key);
alter table public.edge_plain enable row level security;
create policy edge_plain_select on public.edge_plain for select using (true);

select is(
  pg_temp.gaps_of('edge_plain', to_regprocedure('audit.record_change()')),
  'NO_AUDIT_TRIGGER',
  'should require the audit trigger on a table that has none'
);

create trigger edge_plain_audit after insert or update or delete on public.edge_plain
  for each row execute function audit.record_change();

select is(
  pg_temp.gaps_of('edge_plain', to_regprocedure('audit.record_change()')),
  null,
  'should pass a table with RLS, a policy and an enabled row-level audit trigger for every change'
);

-- A policy for one command counts, whatever the command

create table public.edge_insert_policy (id uuid primary key);
alter table public.edge_insert_policy enable row level security;
create policy edge_insert_only on public.edge_insert_policy for insert with check (true);

select is(pg_temp.gaps_of('edge_insert_policy', null), null, 'should count a policy that covers a single command');

-- Names

create table public."Edge_Mixed_Case" (id uuid primary key);
create table public."édge_ünïcode ""quoted""" (id uuid primary key);

select is(pg_temp.gaps_of('Edge_Mixed_Case', null), 'NO_POLICIES,RLS_DISABLED', 'should report a mixed-case table name');
select is(pg_temp.gaps_of('édge_ünïcode "quoted"', null), 'NO_POLICIES,RLS_DISABLED', 'should report a unicode table name with quotes');

-- Kinds of table

create unlogged table public.edge_unlogged (id uuid primary key);
select is(pg_temp.gaps_of('edge_unlogged', null), 'NO_POLICIES,RLS_DISABLED', 'should report an unlogged table');

create temporary table edge_temporary (id uuid primary key);
select is(
  (select count(*) from pg_temp.public_table_security_gaps(null) where table_name = 'edge_temporary'),
  0::bigint,
  'should ignore temporary tables, which live in a pg_temp schema'
);

create table public.edge_partitioned (id uuid, day date) partition by range (day);
create table public.edge_partition_child partition of public.edge_partitioned for values from ('2026-01-01') to ('2027-01-01');
select is(pg_temp.gaps_of('edge_partitioned', null), 'NO_POLICIES,RLS_DISABLED', 'should report a partitioned parent table');
select is(pg_temp.gaps_of('edge_partition_child', null), null, 'should skip partition children, which the parent covers');

create table public.edge_inherited_child () inherits (public.edge_plain);
select is(pg_temp.gaps_of('edge_inherited_child', null), 'NO_POLICIES,RLS_DISABLED', 'should report a table that uses classic inheritance');

-- Triggers that do not audit every change are no longer counted (LBC-21 tightened the gate)

create table public.edge_replica_trigger (id uuid primary key);
alter table public.edge_replica_trigger enable row level security;
create policy edge_replica_select on public.edge_replica_trigger for select using (true);
create trigger edge_replica_audit after insert on public.edge_replica_trigger
  for each row execute function audit.record_change();
alter table public.edge_replica_trigger enable replica trigger edge_replica_audit;
select is(pg_temp.gaps_of('edge_replica_trigger', to_regprocedure('audit.record_change()')), 'NO_AUDIT_TRIGGER', 'should not count a trigger set to fire only in replica mode as audited');

create table public.edge_statement_trigger (id uuid primary key);
alter table public.edge_statement_trigger enable row level security;
create policy edge_statement_select on public.edge_statement_trigger for select using (true);
create trigger edge_statement_audit after insert on public.edge_statement_trigger
  for each statement execute function audit.record_change();
select is(pg_temp.gaps_of('edge_statement_trigger', to_regprocedure('audit.record_change()')), 'NO_AUDIT_TRIGGER', 'should not count a statement-level trigger as audited');

create table public.edge_insert_only_trigger (id uuid primary key);
alter table public.edge_insert_only_trigger enable row level security;
create policy edge_insert_only_trigger_select on public.edge_insert_only_trigger for select using (true);
create trigger edge_insert_only_trigger_audit after insert on public.edge_insert_only_trigger
  for each row execute function audit.record_change();
select is(pg_temp.gaps_of('edge_insert_only_trigger', to_regprocedure('audit.record_change()')), 'NO_AUDIT_TRIGGER', 'should not count an insert-only trigger as audited');

select * from finish();

rollback;
