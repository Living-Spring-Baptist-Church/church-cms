-- Structural gate (LBC-15, backend.md section 10): every table in the public schema must have
-- row level security enabled, at least one policy and the audit trigger.
--
-- The rule lives in pg_temp.public_table_security_gaps(), defined once below and used twice:
--   1. against the real database, where it must report nothing (this passes vacuously while
--      public has no tables, and fails the moment a future migration forgets one of the three);
--   2. against probe tables created inside this transaction, to prove each failure is detected.
-- Everything is rolled back, so no probe table ever reaches the database.
--
-- Audit trigger detection: a trigger counts when it is enabled and its function is the one
-- passed in p_audit_function. The real check passes audit.record_change(), looked up with
-- to_regprocedure(). That function does not exist until the audit work lands, so the audit
-- part is switched off (null) today and switches itself on as soon as the function exists.
-- The real check below is the only line that decides that.

begin;

select plan(12);

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
          and pg_trigger.tgenabled <> 'D'
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
create trigger probe_secured_audit after insert on public.probe_secured
  for each row execute function pg_temp.probe_audit();

create table public.probe_no_rls (id uuid primary key);
create policy probe_no_rls_select on public.probe_no_rls for select using (true);
create trigger probe_no_rls_audit after insert on public.probe_no_rls
  for each row execute function pg_temp.probe_audit();

create table public.probe_no_policy (id uuid primary key);
alter table public.probe_no_policy enable row level security;
create trigger probe_no_policy_audit after insert on public.probe_no_policy
  for each row execute function pg_temp.probe_audit();

create table public.probe_no_trigger (id uuid primary key);
alter table public.probe_no_trigger enable row level security;
create policy probe_no_trigger_select on public.probe_no_trigger for select using (true);

create table public.probe_disabled_trigger (id uuid primary key);
alter table public.probe_disabled_trigger enable row level security;
create policy probe_disabled_trigger_select on public.probe_disabled_trigger for select using (true);
create trigger probe_disabled_trigger_audit after insert on public.probe_disabled_trigger
  for each row execute function pg_temp.probe_audit();
alter table public.probe_disabled_trigger disable trigger probe_disabled_trigger_audit;

create table public.probe_nothing (id uuid primary key);

select is(pg_temp.gaps_of('probe_secured', true), null, 'should report nothing for a table with RLS, a policy and the audit trigger');
select is(pg_temp.gaps_of('probe_no_rls', true), 'RLS_DISABLED', 'should report a public table that has RLS disabled');
select is(pg_temp.gaps_of('probe_no_policy', true), 'NO_POLICIES', 'should report a public table that has RLS enabled but no policy');
select is(pg_temp.gaps_of('probe_no_trigger', true), 'NO_AUDIT_TRIGGER', 'should report a public table that has no audit trigger');
select is(pg_temp.gaps_of('probe_disabled_trigger', true), 'NO_AUDIT_TRIGGER', 'should report a public table whose audit trigger is disabled');
select is(pg_temp.gaps_of('probe_nothing', true), 'NO_AUDIT_TRIGGER,NO_POLICIES,RLS_DISABLED', 'should report every gap of a table that has none of the three');

-- 3. The audit part is gated on the audit function existing

select is(pg_temp.gaps_of('probe_no_trigger', false), null, 'should not require the audit trigger while the audit function does not exist');
select is(pg_temp.gaps_of('probe_nothing', false), 'NO_POLICIES,RLS_DISABLED', 'should still require RLS and a policy while the audit function does not exist');

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
