-- LBC-21 (AC 1, 2, 4): the shape of audit.log, who may touch it, and the audit triggers on every business table.

begin;

select plan(55);

-- Table shape (system design, "Audit trail")

select has_table('audit', 'log', 'should have the audit.log table');
select has_pk('audit', 'log', 'should have a primary key on audit.log');
select col_type_is('audit', 'log', 'id', 'bigint', 'should key entries by a bigint');
select is(
  (select attidentity from pg_attribute where attrelid = 'audit.log'::regclass and attname = 'id'),
  'a'::"char",
  'should generate the id always, so a caller cannot choose it'
);
select col_type_is('audit', 'log', 'occurred_at', 'timestamp with time zone', 'should store occurred_at as timestamptz');
select col_not_null('audit', 'log', 'occurred_at', 'should require occurred_at');
select col_has_default('audit', 'log', 'occurred_at', 'should default occurred_at to now()');
select col_type_is('audit', 'log', 'actor_id', 'uuid', 'should store the actor as a uuid');
select col_is_null('audit', 'log', 'actor_id', 'should allow a null actor for system jobs');
select col_not_null('audit', 'log', 'table_name', 'should require table_name');
select col_type_is('audit', 'log', 'record_id', 'uuid', 'should store record_id as a uuid');
select col_not_null('audit', 'log', 'record_id', 'should require record_id');
select col_not_null('audit', 'log', 'action', 'should require action');
select col_is_null('audit', 'log', 'old_data', 'should allow old_data to be empty');
select col_type_is('audit', 'log', 'new_data', 'jsonb', 'should store new_data as jsonb');
select col_type_is('audit', 'log', 'changed_fields', 'text[]', 'should store changed_fields as a text array');

select has_index('audit', 'log', 'log_table_name_record_id_idx', array['table_name', 'record_id'], 'should index the history of one record');
select has_index('audit', 'log', 'log_actor_id_occurred_at_idx', 'should index the activity of one actor');
select has_index('audit', 'log', 'log_occurred_at_idx', 'should index entries by time for the audit viewer');
select has_index('audit', 'log', 'log_table_name_occurred_at_idx', 'should index entries of one module by time for the audit viewer');

select lives_ok(
  $$ insert into audit.log (table_name, record_id, action)
     select 'probe', gen_random_uuid(), action from unnest(array['INSERT', 'UPDATE', 'DELETE', 'LOGIN', 'EXPORT']) as actions (action) $$,
  'should accept the five actions the design lists'
);

select throws_ok(
  $$ insert into audit.log (table_name, record_id, action) values ('probe', gen_random_uuid(), 'ARCHIVE') $$,
  '23514',
  null,
  'should reject an action outside the five the design lists (archiving is an UPDATE)'
);

select is(
  (select count(*) from pg_attribute
   where attrelid = 'audit.log'::regclass and attnum > 0 and not attisdropped
     and col_description(attrelid, attnum) is null),
  0::bigint,
  'should document every audit.log column'
);

-- RLS and privileges (AC 4)

select is(
  (select relrowsecurity from pg_class where oid = 'audit.log'::regclass),
  true,
  'should have row level security enabled on audit.log'
);

select is(
  (select count(*) from pg_policy where polrelid = 'audit.log'::regclass),
  0::bigint,
  'should have no policy on audit.log, so no app role can see or write a row'
);

select table_privs_are('audit', 'log', 'anon', array[]::text[], 'should give anon no privilege on audit.log');
select table_privs_are('audit', 'log', 'authenticated', array[]::text[], 'should give authenticated no privilege on audit.log');
select table_privs_are('audit', 'log', 'service_role', array[]::text[], 'should give service_role no privilege on audit.log');
select sequence_privs_are('audit', 'log_id_seq', 'anon', array[]::text[], 'should give anon no privilege on the audit.log sequence');
select sequence_privs_are('audit', 'log_id_seq', 'authenticated', array[]::text[], 'should give authenticated no privilege on the audit.log sequence');
select sequence_privs_are('audit', 'log_id_seq', 'service_role', array[]::text[], 'should give service_role no privilege on the audit.log sequence');
select schema_privs_are('audit', 'service_role', array[]::text[], 'should give service_role no access to the audit schema');

select is(
  (select count(*) from pg_class, aclexplode(relacl)
   where oid in ('audit.log'::regclass, 'audit.log_id_seq'::regclass) and grantee = 0),
  0::bigint,
  'should not grant the audit.log table or its sequence to PUBLIC'
);

select is(
  (select count(*) from pg_proc as functions
   join pg_namespace as schemas on schemas.oid = functions.pronamespace
   where schemas.nspname = 'audit'
     and not exists (select 1 from aclexplode(functions.proacl) where grantee = 0)
     and functions.proacl is not null),
  (select count(*) from pg_proc as functions join pg_namespace as schemas on schemas.oid = functions.pronamespace where schemas.nspname = 'audit'),
  'should have an explicit ACL without PUBLIC on every function in the audit schema'
);

select function_privs_are('audit', 'record_change', array[]::text[], 'anon', array[]::text[], 'should deny anon execute on audit.record_change');
select function_privs_are('audit', 'record_change', array[]::text[], 'authenticated', array[]::text[], 'should deny authenticated execute on audit.record_change');
select function_privs_are('audit', 'record_change', array[]::text[], 'service_role', array[]::text[], 'should deny service_role execute on audit.record_change');
select function_privs_are('audit', 'log_event', array['text', 'text', 'uuid', 'jsonb'], 'anon', array[]::text[], 'should deny anon execute on audit.log_event');
select function_privs_are('audit', 'log_event', array['text', 'text', 'uuid', 'jsonb'], 'authenticated', array[]::text[], 'should deny authenticated execute on audit.log_event');
select function_privs_are('audit', 'log_event', array['text', 'text', 'uuid', 'jsonb'], 'service_role', array[]::text[], 'should deny service_role execute on audit.log_event');
select function_privs_are('audit', 'reject_log_change', array[]::text[], 'authenticated', array[]::text[], 'should deny authenticated execute on audit.reject_log_change');
select function_privs_are('public', 'log_audit_event', array['text', 'text', 'uuid', 'jsonb'], 'authenticated', array['EXECUTE'], 'should let authenticated execute the log_audit_event wrapper');
select function_privs_are('public', 'log_audit_event', array['text', 'text', 'uuid', 'jsonb'], 'anon', array[]::text[], 'should deny anon execute on the log_audit_event wrapper');
select function_privs_are('public', 'log_audit_event', array['text', 'text', 'uuid', 'jsonb'], 'service_role', array[]::text[], 'should deny service_role execute on the log_audit_event wrapper');

-- Function safety

select is(
  (select prosecdef from pg_proc where oid = 'audit.record_change()'::regprocedure),
  true,
  'should run audit.record_change as its owner, because the callers cannot write audit.log'
);
select is(
  (select proconfig from pg_proc where oid = 'audit.record_change()'::regprocedure),
  array['search_path=""'],
  'should pin an empty search_path on audit.record_change'
);
select is(
  (select prosecdef from pg_proc where oid = 'audit.log_event(text, text, uuid, jsonb)'::regprocedure),
  false,
  'should run audit.log_event as the invoker, so a mistaken grant fails instead of escalating'
);
select is(
  (select proconfig from pg_proc where oid = 'audit.log_event(text, text, uuid, jsonb)'::regprocedure),
  array['search_path=""'],
  'should pin an empty search_path on audit.log_event'
);
select is(
  (select proconfig from pg_proc where oid = 'public.log_audit_event(text, text, uuid, jsonb)'::regprocedure),
  array['search_path=""'],
  'should pin an empty search_path on the log_audit_event wrapper'
);
select is(
  (select prosecdef from pg_proc where oid = 'public.log_audit_event(text, text, uuid, jsonb)'::regprocedure),
  true,
  'should run the wrapper as its owner, because app roles cannot reach the audit schema'
);
select is(
  (select proargnames::text from pg_proc where oid = 'audit.log_event(text, text, uuid, jsonb)'::regprocedure),
  '{p_action,p_table_name,p_record_id,p_details}',
  'should take no actor parameter, so the actor can only be auth.uid()'
);

-- The audit triggers (AC 2): attached to each business table, complete and always enabled

select is(
  (select count(*) from pg_trigger
   where tgfoid = 'audit.record_change()'::regprocedure and not tgisinternal
     and tgrelid in ('public.departments'::regclass, 'public.staff'::regclass, 'public.staff_roles'::regclass)
     and tgname = 'audit_' || tgrelid::regclass::text
     and tgenabled = 'A' and tgtype & 1 = 1 and tgtype & 2 = 0 and tgtype & 28 = 28),
  3::bigint,
  'should have an always-enabled AFTER INSERT OR UPDATE OR DELETE row trigger audit_<table> on departments, staff and staff_roles'
);

select is(
  (select tgenabled from pg_trigger where tgrelid = 'audit.log'::regclass and tgname = 'log_reject_change'),
  'A'::"char",
  'should keep the audit.log immutability trigger enabled in every session replication mode'
);

select is(
  (select count(*) from pg_trigger where tgrelid = 'audit.log'::regclass and not tgisinternal),
  1::bigint,
  'should have exactly one trigger on audit.log, the immutability guard'
);

select is(
  (select tgtype & 1 = 0 and tgtype & 2 = 2 and tgtype & 8 = 8 and tgtype & 16 = 16 and tgtype & 32 = 32
   from pg_trigger where tgrelid = 'audit.log'::regclass and tgname = 'log_reject_change'),
  true,
  'should run the guard before UPDATE, DELETE and TRUNCATE once per statement, so it fires even when no row matches'
);

select * from finish();

rollback;
