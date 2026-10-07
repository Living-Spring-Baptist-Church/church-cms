-- LBC-21 (AC 3, 4): log_audit_event, the only way app code adds an audit row, and what the GraphQL API shows.
-- It records LOGIN and EXPORT for the signed-in active staff member and nothing else. Fixture ids:
-- 70...01 and 70...02 active staff, 71...01 inactive staff, 72...01 a signed-in user with no staff profile.

begin;

select plan(48);

create function pg_temp.call_as(p_db_role name, p_user_id uuid, p_statement text)
returns text
language plpgsql
as $$
declare
  v_original name := current_user;
  v_result text;
begin
  perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', p_db_role, 'sub', p_user_id)::text, true);
  perform set_config('role', p_db_role::text, true);
  execute p_statement into v_result;
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_result;
end;
$$;

create function pg_temp.fails_as(p_db_role name, p_user_id uuid, p_statement text)
returns text
language sql
as $$
  select format('select pg_temp.call_as(%L, %L, %L)', p_db_role, p_user_id, p_statement);
$$;

create function pg_temp.log_sql(p_action text, p_table_name text, p_record_id uuid default null, p_details text default null)
returns text
language sql
as $$
  select format('select public.log_audit_event(%L, %L, %L, %L::jsonb)', p_action, p_table_name, p_record_id, p_details);
$$;

create function pg_temp.graphql_as(p_db_role name, p_user_id uuid, p_query text)
returns jsonb
language plpgsql
as $$
declare
  v_original name := current_user;
  v_result jsonb;
begin
  perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', p_db_role, 'sub', p_user_id)::text, true);
  perform set_config('role', p_db_role::text, true);
  v_result := graphql.resolve(p_query);
  perform set_config('role', v_original::text, true);
  perform set_config('request.jwt.claims', '', true);
  return v_result;
end;
$$;

insert into auth.users (id, aud, role, email)
values
  ('70000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'event-a@test.invalid'),
  ('70000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'event-b@test.invalid'),
  ('71000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'event-inactive@test.invalid'),
  ('72000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'event-nostaff@test.invalid');

insert into public.staff (id, full_name, is_active)
values
  ('70000000-0000-4000-8000-000000000001', 'Event A', true),
  ('70000000-0000-4000-8000-000000000002', 'Event B', true),
  ('71000000-0000-4000-8000-000000000001', 'Event Inactive', false);

create temp table log_before as select count(*) as total from audit.log;

-- LOGIN

select is(
  pg_temp.call_as('authenticated', '70000000-0000-4000-8000-000000000001', pg_temp.log_sql('LOGIN', 'staff')),
  '70000000-0000-4000-8000-000000000001',
  'should return the signed-in staff id as the record id of a LOGIN'
);
select is(
  (select count(*) from audit.log where action = 'LOGIN' and actor_id = '70000000-0000-4000-8000-000000000001' and record_id = '70000000-0000-4000-8000-000000000001' and table_name = 'staff'),
  1::bigint,
  'should record a LOGIN row about the signed-in user'
);
select is(
  (select old_data is null and changed_fields is null and new_data is null
   from audit.log where action = 'LOGIN' and actor_id = '70000000-0000-4000-8000-000000000001'),
  true,
  'should leave old_data, new_data and changed_fields empty on a LOGIN without details'
);

select is(
  pg_temp.call_as('authenticated', '70000000-0000-4000-8000-000000000001', pg_temp.log_sql('LOGIN', 'staff', '70000000-0000-4000-8000-000000000001', '{"method":"password_totp"}')),
  '70000000-0000-4000-8000-000000000001',
  'should accept a LOGIN that names the caller as the record'
);
select is(
  (select new_data ->> 'method' from audit.log where action = 'LOGIN' and new_data is not null),
  'password_totp',
  'should keep the details of a LOGIN in new_data'
);

select throws_ok(
  pg_temp.fails_as('authenticated', '70000000-0000-4000-8000-000000000001', pg_temp.log_sql('LOGIN', 'staff', '70000000-0000-4000-8000-000000000002')),
  'P0001', 'VALIDATION_FAILED',
  'should refuse a LOGIN logged about another user'
);

-- EXPORT

create temp table export_result as
select pg_temp.call_as('authenticated', '70000000-0000-4000-8000-000000000002', pg_temp.log_sql('EXPORT', 'staff_roles', null, '{"format":"csv","rows":12}'))::uuid as export_id;

select isnt((select export_id from export_result), null, 'should return a new export id for an EXPORT');
select is(
  (select count(*) from audit.log where action = 'EXPORT' and actor_id = '70000000-0000-4000-8000-000000000002' and table_name = 'staff_roles' and record_id = (select export_id from export_result) and new_data ->> 'format' = 'csv'),
  1::bigint,
  'should record an EXPORT row with the caller as actor, the table and the details'
);
select is(
  pg_temp.call_as('authenticated', '70000000-0000-4000-8000-000000000002', pg_temp.log_sql('EXPORT', 'departments', '73000000-0000-4000-8000-000000000001')),
  '73000000-0000-4000-8000-000000000001',
  'should keep an export id the caller supplies'
);

-- The actor is always the caller: there is no parameter to forge it with

select is(
  (select count(*) from audit.log where action in ('LOGIN', 'EXPORT') and actor_id = '70000000-0000-4000-8000-000000000001'),
  2::bigint,
  'should attribute user A only the two events A logged'
);
select is(
  (select count(*) from audit.log where action in ('LOGIN', 'EXPORT') and actor_id = '70000000-0000-4000-8000-000000000002'),
  2::bigint,
  'should attribute user B only the two events B logged'
);
select is(
  (select count(*) from audit.log where action in ('LOGIN', 'EXPORT') and actor_id is null),
  0::bigint,
  'should never record an event with no actor'
);

-- Only LOGIN and EXPORT may be logged: no forging of data-change rows

select throws_ok(
  pg_temp.fails_as('authenticated', '70000000-0000-4000-8000-000000000001', pg_temp.log_sql(action, 'staff')),
  'P0001', 'VALIDATION_FAILED',
  format('should refuse to log the action %L', action)
) from unnest(array['INSERT', 'UPDATE', 'DELETE', 'login', 'Export', 'ARCHIVE', '']) as actions (action);

select throws_ok(
  pg_temp.fails_as('authenticated', '70000000-0000-4000-8000-000000000001', pg_temp.log_sql(null, 'staff')),
  'P0001', 'VALIDATION_FAILED',
  'should refuse a null action'
);

select throws_ok(
  pg_temp.fails_as('authenticated', '70000000-0000-4000-8000-000000000001', pg_temp.log_sql('EXPORT', table_name)),
  'P0001', 'VALIDATION_FAILED',
  format('should refuse the table name %L', table_name)
) from unnest(array['not_a_table', 'log', 'audit.log', 'pg_class', '']) as tables (table_name);

select throws_ok(
  pg_temp.fails_as('authenticated', '70000000-0000-4000-8000-000000000001', pg_temp.log_sql('EXPORT', null)),
  'P0001', 'VALIDATION_FAILED',
  'should refuse a null table name'
);

select throws_ok(
  pg_temp.fails_as('authenticated', '70000000-0000-4000-8000-000000000001', pg_temp.log_sql('EXPORT', 'staff', null, details)),
  'P0001', 'VALIDATION_FAILED',
  format('should refuse details that are not a JSON object (%s)', details)
) from unnest(array['[1,2]', '"text"', '42', 'true']) as all_details (details);

select throws_ok(
  pg_temp.fails_as('authenticated', '70000000-0000-4000-8000-000000000001', pg_temp.log_sql('EXPORT', 'staff', null, json_build_object('note', repeat('x', audit.max_event_details_bytes()))::text)),
  'P0001', 'VALIDATION_FAILED',
  'should refuse details larger than the limit'
);

select lives_ok(
  pg_temp.fails_as('authenticated', '70000000-0000-4000-8000-000000000001', pg_temp.log_sql('EXPORT', 'staff', null, json_build_object('note', repeat('x', audit.max_event_details_bytes() - 50))::text)),
  'should accept details just under the limit'
);

-- Who may call it

select throws_ok(
  pg_temp.fails_as('anon', null, pg_temp.log_sql('LOGIN', 'staff')),
  '42501', null,
  'should refuse anon calling log_audit_event'
);
select throws_ok(
  pg_temp.fails_as('service_role', null, pg_temp.log_sql('LOGIN', 'staff')),
  '42501', null,
  'should refuse service_role calling log_audit_event'
);
select throws_ok(
  pg_temp.fails_as('authenticated', '72000000-0000-4000-8000-000000000001', pg_temp.log_sql('LOGIN', 'staff')),
  'P0001', 'AUTH_FORBIDDEN',
  'should refuse a signed-in user who has no staff profile'
);
select throws_ok(
  pg_temp.fails_as('authenticated', '71000000-0000-4000-8000-000000000001', pg_temp.log_sql('LOGIN', 'staff')),
  'P0001', 'AUTH_FORBIDDEN',
  'should refuse a deactivated staff member'
);
select throws_ok(
  pg_temp.fails_as('authenticated', null, pg_temp.log_sql('LOGIN', 'staff')),
  'P0001', 'AUTH_FORBIDDEN',
  'should refuse an authenticated session whose token has no user id'
);
select throws_ok(
  pg_temp.fails_as('authenticated', '70000000-0000-4000-8000-000000000001', $$select audit.log_event('LOGIN', 'staff')$$),
  '42501', null,
  'should refuse authenticated calling audit.log_event directly'
);
select throws_ok(
  pg_temp.fails_as('authenticated', '70000000-0000-4000-8000-000000000001', $$select audit.record_change()$$),
  '42501', null,
  'should refuse authenticated calling audit.record_change directly'
);

select is(
  (select count(*) from audit.log where action in ('LOGIN', 'EXPORT')),
  5::bigint,
  'should have recorded only the five accepted events (two LOGIN, three EXPORT) and none of the refused ones'
);
select is(
  (select count(*) from audit.log where action in ('INSERT', 'UPDATE', 'DELETE') and actor_id is not null),
  0::bigint,
  'should hold no data-change row written by an app user through log_audit_event'
);

-- GraphQL: only the wrapper is visible, never the audit table

select is(
  pg_temp.graphql_as('authenticated', '70000000-0000-4000-8000-000000000002', $$mutation { logAuditEvent(pAction: "EXPORT", pTableName: "departments", pDetails: "{\"format\":\"csv\"}") }$$) #>> '{data,logAuditEvent}' ~ '^[0-9a-f-]{36}$',
  true,
  'should expose log_audit_event as the logAuditEvent mutation returning the record id'
);
select is(
  (select new_data ->> 'format' from audit.log where action = 'EXPORT' and table_name = 'departments' and new_data is not null),
  'csv',
  'should pass the JSON details through the GraphQL mutation'
);
select is(
  pg_temp.graphql_as('authenticated', '70000000-0000-4000-8000-000000000002', $$mutation { logAuditEvent(pAction: "DELETE", pTableName: "departments") }$$) -> 'errors' -> 0 ->> 'message',
  'VALIDATION_FAILED',
  'should return the error code through GraphQL for an action that is not allowed'
);
select isnt(
  pg_temp.graphql_as('anon', null, $$mutation { logAuditEvent(pAction: "LOGIN", pTableName: "staff") }$$) -> 'errors',
  null,
  'should not offer the logAuditEvent mutation to anon'
);

-- pg_graphql answers introspection only when the schema comment turns it on (as scripts/export-graphql-schema.mjs
-- does). Switched on here for this rolled-back transaction only.
do $enable_introspection$
begin
  execute format(
    'comment on schema public is %L',
    regexp_replace(obj_description('public'::regnamespace, 'pg_namespace'), '^@graphql[(][{]', '@graphql({"introspection": true, ')
  );
end
$enable_introspection$;

create function pg_temp.audit_names_visible_to(p_db_role name, p_user_id uuid)
returns text
language sql
as $$
  with schema_view as (
    select pg_temp.graphql_as(
      p_db_role, p_user_id,
      $q$ { __schema { types { name } queryType { fields { name } } mutationType { fields { name } } } } $q$
    ) -> 'data' -> '__schema' as body
  ),
  names as (
    select entry ->> 'name' as name
    from schema_view, jsonb_array_elements(body -> 'types') as entry
    union all
    select entry ->> 'name'
    from schema_view, jsonb_array_elements(body #> '{queryType,fields}') as entry
    union all
    select entry ->> 'name'
    from schema_view, jsonb_array_elements(coalesce(body #> '{mutationType,fields}', '[]')) as entry
  )
  select coalesce(string_agg(name, ',' order by name), '') from names where name ~* '(^log|audit)'
$$;

select is(
  pg_temp.audit_names_visible_to('authenticated', '70000000-0000-4000-8000-000000000001'),
  'logAuditEvent',
  'should show authenticated nothing of audit.log in the GraphQL schema except the logAuditEvent mutation'
);
select is(
  pg_temp.audit_names_visible_to('anon', null),
  '',
  'should show anon nothing of audit.log or the audit mutation in the GraphQL schema'
);

select is(
  (select count(*) from pg_proc as functions
   join pg_namespace as schemas on schemas.oid = functions.pronamespace
   where schemas.nspname = 'public' and functions.proname ~ 'audit|record_change'),
  1::bigint,
  'should expose exactly one audit function in public, the wrapper'
);

select * from finish();

rollback;
