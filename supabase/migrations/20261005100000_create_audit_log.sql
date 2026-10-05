-- Audit trail (LBC-21, PRD AUD-01): audit.log, the generic audit.record_change() trigger function, the
-- audit.log_event() entry point for LOGIN and EXPORT events and its public wrapper, and the audit triggers
-- on every existing business table (departments, staff, staff_roles).
-- Source: docs/system-design.md, section "Audit trail".
--
-- The audit schema and its closed privileges already exist from the base migration; nothing here recreates them.
--
-- Deliberate differences from the design sketch, all of them hardening:
--   * record_id is read from the row as jsonb, so a missing id column fails on the NOT NULL, not inside plpgsql.
--   * changed_fields is ordered, so the array is deterministic.
--   * action has a CHECK for the five values the design lists.
--   * audit.log is made immutable for every role by a trigger, not only by missing privileges, because the
--     design says nobody can edit or delete rows. The triggers are ENABLE ALWAYS so session_replication_role
--     = replica does not skip them. Only DDL by the table owner (ALTER TABLE ... DISABLE TRIGGER, DROP) remains.
--   * the audit triggers are ENABLE ALWAYS too, for the same reason.

create function audit.event_actions()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['LOGIN', 'EXPORT'];
$$;

create function audit.login_action()
returns text
language sql
immutable
set search_path = ''
as $$
  select 'LOGIN';
$$;

create function audit.max_event_details_bytes()
returns integer
language sql
immutable
set search_path = ''
as $$
  select 4096;
$$;

comment on function audit.event_actions() is 'The actions an app caller may log through log_event. Data-change actions are written by the trigger only.';
comment on function audit.login_action() is 'The action value that records a sign-in.';
comment on function audit.max_event_details_bytes() is 'Largest p_details payload log_event accepts, in bytes of its text form.';

create table audit.log (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_id uuid,
  table_name text not null,
  record_id uuid not null,
  action text not null,
  old_data jsonb,
  new_data jsonb,
  changed_fields text[],
  constraint log_action_check check (action in ('INSERT', 'UPDATE', 'DELETE', 'LOGIN', 'EXPORT'))
);

comment on table audit.log is 'Append-only record of every change to business tables and of logins and exports. Written only by audit.record_change() and audit.log_event(). No role can update, delete or truncate rows.';
comment on column audit.log.id is 'Strictly increasing sequence number of the entry.';
comment on column audit.log.occurred_at is 'Transaction time of the change.';
comment on column audit.log.actor_id is 'auth.uid() of the signed-in user. Null for system jobs and direct database access.';
comment on column audit.log.table_name is 'The public table that changed, or the table an export or login relates to.';
comment on column audit.log.record_id is 'Id of the changed row. For LOGIN the signed-in staff id; for EXPORT an export id.';
comment on column audit.log.action is 'INSERT, UPDATE or DELETE (archiving is an UPDATE of archived_at), LOGIN or EXPORT.';
comment on column audit.log.old_data is 'Row before the change (UPDATE and DELETE). Null otherwise.';
comment on column audit.log.new_data is 'Row after the change (INSERT and UPDATE), or the details of a LOGIN or EXPORT event.';
comment on column audit.log.changed_fields is 'For UPDATE: the sorted names of the columns whose value changed. Null otherwise.';

-- The two design indexes, plus the two listing AUD-02 needs (newest first, optionally by module).
create index log_table_name_record_id_idx on audit.log (table_name, record_id);
create index log_actor_id_occurred_at_idx on audit.log (actor_id, occurred_at desc);
create index log_occurred_at_idx on audit.log (occurred_at desc);
create index log_table_name_occurred_at_idx on audit.log (table_name, occurred_at desc);

alter table audit.log enable row level security;

-- No policies on purpose: with RLS on and no policy, every non-owner role sees and writes nothing.
revoke all on table audit.log from public, anon, authenticated, service_role;
revoke all on sequence audit.log_id_seq from public, anon, authenticated, service_role;

create function audit.reject_log_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = 'P0001',
    message = 'AUDIT_LOG_IMMUTABLE',
    detail = format('%s on audit.log is not allowed for any role', tg_op),
    hint = 'The audit log is append-only. Anonymisation needs the documented admin procedure.';
end;
$$;

comment on function audit.reject_log_change() is 'Statement-level trigger on audit.log: refuses UPDATE, DELETE and TRUNCATE for every role, the owner included, even when no row matches.';

create trigger log_reject_change
  before update or delete or truncate on audit.log
  for each statement execute function audit.reject_log_change();

-- Fire in replica mode too, so session_replication_role = replica cannot be used to edit the log.
alter table audit.log enable always trigger log_reject_change;

-- SECURITY DEFINER: the trigger fires as the caller, who has no privilege on audit.log. This is the only writer.
create function audit.record_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_old jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  v_new jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
begin
  insert into audit.log (actor_id, table_name, record_id, action, old_data, new_data, changed_fields)
  values (
    auth.uid(),
    tg_table_name,
    (coalesce(v_new, v_old) ->> 'id')::uuid,
    tg_op,
    v_old,
    v_new,
    case when tg_op = 'UPDATE' then
      array(
        select changed.key
        from jsonb_each(v_new) as changed
        where v_new -> changed.key is distinct from v_old -> changed.key
        order by changed.key
      )
    end
  );
  return coalesce(new, old);
end;
$$;

comment on function audit.record_change() is 'AFTER INSERT OR UPDATE OR DELETE row trigger that records the change in audit.log with the actor from auth.uid() (null for system jobs). Attach to every business table as audit_<table>.';

-- Called only by public.log_audit_event (a definer running as the owner), so it runs as invoker: if it were ever
-- granted to an app role by mistake it would fail on audit.log instead of escalating.
create function audit.log_event(
  p_action text,
  p_table_name text,
  p_record_id uuid default null,
  p_details jsonb default null
)
returns uuid
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_actor_id uuid := auth.uid();
  v_record_id uuid;
begin
  if v_actor_id is null or not private.is_active_staff() then
    raise exception using errcode = 'P0001', message = 'AUTH_FORBIDDEN',
      detail = 'Only signed-in active staff can log an event';
  end if;

  if p_action is null or not (p_action = any (audit.event_actions())) then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = 'action must be LOGIN or EXPORT';
  end if;

  if p_table_name is null
     or not exists (select 1 from pg_catalog.pg_tables where schemaname = 'public' and tablename = p_table_name)
  then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = 'table_name must name a table in the public schema';
  end if;

  if p_details is not null
     and (jsonb_typeof(p_details) <> 'object' or octet_length(p_details::text) > audit.max_event_details_bytes())
  then
    raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
      detail = format('details must be a JSON object of at most %s bytes', audit.max_event_details_bytes());
  end if;

  if p_action = audit.login_action() then
    if p_record_id is not null and p_record_id <> v_actor_id then
      raise exception using errcode = 'P0001', message = 'VALIDATION_FAILED',
        detail = 'A login can only be logged for the signed-in user';
    end if;
    v_record_id := v_actor_id;
  else
    v_record_id := coalesce(p_record_id, gen_random_uuid());
  end if;

  insert into audit.log (actor_id, table_name, record_id, action, new_data)
  values (v_actor_id, p_table_name, v_record_id, p_action, p_details);

  return v_record_id;
end;
$$;

comment on function audit.log_event(text, text, uuid, jsonb) is 'Records a LOGIN or EXPORT event for the signed-in active staff member (actor is always auth.uid(), never a parameter) and returns the record id. LOGIN is always about the caller; EXPORT gets a new export id unless one is given. Errors: AUTH_FORBIDDEN, VALIDATION_FAILED.';

-- SECURITY DEFINER because pg_graphql only exposes public and app roles have no access to the audit schema.
-- It adds nothing but the hop: every rule, and the actor, live in audit.log_event.
create function public.log_audit_event(
  p_action text,
  p_table_name text,
  p_record_id uuid default null,
  p_details jsonb default null
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  return audit.log_event(p_action, p_table_name, p_record_id, p_details);
end;
$$;

comment on function public.log_audit_event(text, text, uuid, jsonb) is 'Logs a LOGIN or EXPORT event as the signed-in active staff member and returns the record id (the staff id for LOGIN, an export id for EXPORT). p_table_name must be a public table. p_details is an optional JSON object of at most 4096 bytes; never put personal data in it. Errors: AUTH_FORBIDDEN, VALIDATION_FAILED.';

revoke execute on function
  audit.event_actions(),
  audit.login_action(),
  audit.max_event_details_bytes(),
  audit.reject_log_change(),
  audit.record_change(),
  audit.log_event(text, text, uuid, jsonb)
from public, anon, authenticated, service_role;

revoke execute on function public.log_audit_event(text, text, uuid, jsonb) from public, anon, service_role;
grant execute on function public.log_audit_event(text, text, uuid, jsonb) to authenticated;

-- The audit triggers. AFTER, so they see the final row after the updated_at and last-super-admin triggers,
-- and a statement that raises rolls its audit row back with it.

create trigger audit_departments
  after insert or update or delete on public.departments
  for each row execute function audit.record_change();

create trigger audit_staff
  after insert or update or delete on public.staff
  for each row execute function audit.record_change();

create trigger audit_staff_roles
  after insert or update or delete on public.staff_roles
  for each row execute function audit.record_change();

alter table public.departments enable always trigger audit_departments;
alter table public.staff enable always trigger audit_staff;
alter table public.staff_roles enable always trigger audit_staff_roles;
