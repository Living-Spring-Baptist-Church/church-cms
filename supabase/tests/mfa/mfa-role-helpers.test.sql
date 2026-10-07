-- LBC-41 (AC 1, 2, 4): the role helpers treat super_admin, pastor and treasurer as held only at aal2, leave every
-- other role alone, and fail closed on every missing, malformed or unexpected claim. Also proves that the
-- two-factor role list in the database is the documented one (MFA_REQUIRED_ROLES in
-- apps/dashboard/src/core/auth/roles.ts) and that the new helpers are not callable by app roles.
-- Helpers are evaluated as the table owner with the JWT claims set: they are SECURITY DEFINER and read the claims
-- of the current session, so this exercises exactly what a policy evaluates.

begin;

select plan(147);

-- Fixture: start from an empty identity model so the demo seed cannot influence the results.
set local session_replication_role = replica;
delete from public.staff_roles;
delete from public.staff;
delete from public.departments;
set local session_replication_role = origin;

create temp table actors (label text primary key, staff_id uuid, is_active boolean not null default true);
create temp table actor_roles (label text not null, role public.app_role not null, department_id uuid);

insert into public.departments (id, name) values ('d1000000-0000-4000-8000-000000000001', 'MfaHelperDepartment');

insert into actors (label)
select role::text from unnest(enum_range(null::public.app_role)) as roles (role);
insert into actors (label) values ('pastor_usher'), ('no_role');
insert into actors (label, is_active) values ('inactive_pastor', false);

insert into actor_roles (label, role, department_id)
select role::text, role, case role when 'department_head' then 'd1000000-0000-4000-8000-000000000001'::uuid end
from unnest(enum_range(null::public.app_role)) as roles (role);
insert into actor_roles (label, role)
values ('pastor_usher', 'pastor'), ('pastor_usher', 'usher'), ('inactive_pastor', 'pastor');

update actors
set staff_id = ('e5000000-0000-4000-8000-' || lpad(numbered.position::text, 12, '0'))::uuid
from (select label, row_number() over (order by label) as position from actors) as numbered
where actors.label = numbered.label;

insert into auth.users (id, aud, role, email)
select staff_id, 'authenticated', 'authenticated', label || '@test.invalid' from actors;
insert into public.staff (id, full_name, is_active) select staff_id, label, is_active from actors;
insert into public.staff_roles (staff_id, role, department_id)
select actors.staff_id, actor_roles.role, actor_roles.department_id from actor_roles join actors using (label);

-- Evaluates a helper expression for an actor with the given raw claims text and returns the result as text.
create function pg_temp.helper_with_claims(p_claims text, p_expression text)
returns text
language plpgsql
as $$
declare
  v_result text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute format('select (%s)::text', p_expression) into v_result;
  perform set_config('request.jwt.claims', '', true);
  return v_result;
end;
$$;

create function pg_temp.helper_as(p_label text, p_aal text, p_expression text)
returns text
language sql
as $$
  select pg_temp.helper_with_claims(
    jsonb_strip_nulls(jsonb_build_object('role', 'authenticated', 'sub', (select staff_id from actors where label = p_label), 'aal', p_aal))::text,
    p_expression);
$$;

-- The two-factor role list is the documented one, and one list only.
select is(
  private.mfa_required_roles(),
  array['super_admin', 'pastor', 'treasurer']::public.app_role[],
  'should require two-factor for exactly super admin, pastor and treasurer (MFA_REQUIRED_ROLES in the dashboard)'
);

select is(private.required_assurance_level(), 'aal2', 'should require the aal2 assurance level');

-- has_role: every role, at aal1 and aal2. A held role is usable unless it needs two-factor and the session is not aal2.
select is(
  pg_temp.helper_as(label, aal, format('private.has_role(%L)', label)),
  (case when label::public.app_role = any (private.mfa_required_roles()) and aal <> 'aal2' then 'false' else 'true' end),
  format('should give has_role(%s) as %s at %s', label, 'the role is usable', aal)
) from (select role::text as label from unnest(enum_range(null::public.app_role)) as roles (role)) as role_labels
  cross join (values ('aal1'), ('aal2')) as levels (aal)
  order by label, aal;

select is(
  pg_temp.helper_as(label, aal, 'private.has_any_role(enum_range(null::public.app_role))'),
  (case when label::public.app_role = any (private.mfa_required_roles()) and aal <> 'aal2' then 'false' else 'true' end),
  format('should give has_any_role over every role for %s at %s', label, aal)
) from (select role::text as label from unnest(enum_range(null::public.app_role)) as roles (role)) as role_labels
  cross join (values ('aal1'), ('aal2')) as levels (aal)
  order by label, aal;

-- A role held by someone else, or not held at all, is never true, whatever the aal.
select is(
  pg_temp.helper_as('usher', aal, format('private.has_role(%L)', role)),
  'false',
  format('should not give %s to an usher at %s', role, aal)
) from (values ('pastor'), ('super_admin'), ('treasurer')) as roles (role)
  cross join (values ('aal1'), ('aal2')) as levels (aal)
  order by role, aal;

-- Mixed roles: at aal1 only the role that needs no second factor remains.
select is(pg_temp.helper_as('pastor_usher', 'aal1', 'private.has_role(''pastor'')'), 'false', 'should not give a pastor and usher the pastor role at aal1');
select is(pg_temp.helper_as('pastor_usher', 'aal1', 'private.has_role(''usher'')'), 'true', 'should keep the usher role of a pastor and usher at aal1');
select is(pg_temp.helper_as('pastor_usher', 'aal1', 'private.has_any_role(array[''pastor'', ''usher'']::public.app_role[])'), 'true', 'should say a pastor and usher holds one of pastor or usher at aal1 through the usher role');
select is(pg_temp.helper_as('pastor_usher', 'aal1', 'private.has_any_role(array[''pastor'', ''treasurer'']::public.app_role[])'), 'false', 'should say a pastor and usher holds neither pastor nor treasurer at aal1');
select is(pg_temp.helper_as('pastor_usher', 'aal2', 'private.has_role(''pastor'')'), 'true', 'should give a pastor and usher the pastor role at aal2');
select is(pg_temp.helper_as('pastor_usher', 'aal2', 'private.has_role(''usher'')'), 'true', 'should give a pastor and usher the usher role at aal2');

-- Department head is not a two-factor role, so heading a department works at aal1.
select is(pg_temp.helper_as('department_head', 'aal1', 'private.heads_department(''d1000000-0000-4000-8000-000000000001'')'), 'true', 'should let a department head head the department at aal1');
select is(pg_temp.helper_as('department_head', 'aal2', 'private.heads_department(''d1000000-0000-4000-8000-000000000001'')'), 'true', 'should let a department head head the department at aal2');
select is(pg_temp.helper_as('pastor', 'aal2', 'private.heads_department(''d1000000-0000-4000-8000-000000000001'')'), 'false', 'should not let a pastor head a department');

-- is_active_staff only says the staff row is active: it must stay true at aal1 (the own-profile reads depend on it).
select is(
  pg_temp.helper_as(label, aal, 'private.is_active_staff()'),
  (case when label = 'inactive_pastor' then 'false' else 'true' end),
  format('should say %s is active staff only when the profile is active, at %s', label, aal)
) from actors
  cross join (values ('aal1'), ('aal2')) as levels (aal)
  where label in ('super_admin', 'pastor', 'treasurer', 'usher', 'pastor_usher', 'no_role', 'inactive_pastor')
  order by label, aal;

-- has_dashboard_session (the audit event gate): active staff, and aal2 when they hold a two-factor role.
select is(
  pg_temp.helper_as(label, aal, 'private.has_dashboard_session()'),
  (case
    when label = 'inactive_pastor' then 'false'
    when label in ('super_admin', 'pastor', 'treasurer', 'pastor_usher') and aal <> 'aal2' then 'false'
    else 'true'
  end),
  format('should give the dashboard session of %s at %s only when the session meets their two-factor need', label, aal)
) from actors
  cross join (values ('aal1'), ('aal2')) as levels (aal)
  where label in ('super_admin', 'pastor', 'treasurer', 'usher', 'secretary', 'pastor_usher', 'no_role', 'inactive_pastor')
  order by label, aal;

-- Fail closed: for a pastor, anything but exactly aal2 means the role is not held.
create temp table claim_variants (description text primary key, claims_json text not null, is_usable boolean not null);

insert into claim_variants
select description, replace(replace(claims_json, '$SUB', (select staff_id::text from actors where label = 'pastor')), '$ROLE', 'authenticated'), is_usable
from (values
  ('aal2', '{"role":"$ROLE","sub":"$SUB","aal":"aal2"}', true),
  ('aal2 with an amr entry as well', '{"role":"$ROLE","sub":"$SUB","aal":"aal2","amr":[{"method":"totp","timestamp":1}]}', true),
  ('aal1', '{"role":"$ROLE","sub":"$SUB","aal":"aal1"}', false),
  ('aal missing', '{"role":"$ROLE","sub":"$SUB"}', false),
  ('aal null', '{"role":"$ROLE","sub":"$SUB","aal":null}', false),
  ('aal empty string', '{"role":"$ROLE","sub":"$SUB","aal":""}', false),
  ('aal in capitals', '{"role":"$ROLE","sub":"$SUB","aal":"AAL2"}', false),
  ('aal with a trailing space', '{"role":"$ROLE","sub":"$SUB","aal":"aal2 "}', false),
  ('aal with a leading space', '{"role":"$ROLE","sub":"$SUB","aal":" aal2"}', false),
  ('aal3', '{"role":"$ROLE","sub":"$SUB","aal":"aal3"}', false),
  ('aal as a number', '{"role":"$ROLE","sub":"$SUB","aal":2}', false),
  ('aal as a boolean', '{"role":"$ROLE","sub":"$SUB","aal":true}', false),
  ('aal as an array holding aal2', '{"role":"$ROLE","sub":"$SUB","aal":["aal2"]}', false),
  ('aal as an object', '{"role":"$ROLE","sub":"$SUB","aal":{"level":"aal2"}}', false),
  ('aal2 only inside user_metadata, which a user can edit', '{"role":"$ROLE","sub":"$SUB","user_metadata":{"aal":"aal2"}}', false),
  ('aal2 only inside app_metadata', '{"role":"$ROLE","sub":"$SUB","app_metadata":{"aal":"aal2"}}', false),
  ('totp in amr but aal1', '{"role":"$ROLE","sub":"$SUB","aal":"aal1","amr":[{"method":"totp","timestamp":1}]}', false),
  ('aal with a different key case', '{"role":"$ROLE","sub":"$SUB","AAL":"aal2"}', false)
) as variants (description, claims_json, is_usable);

select is(
  pg_temp.helper_with_claims(claims_json, 'private.has_role(''pastor'')'),
  case when is_usable then 'true' else 'false' end,
  format('should %s the pastor role when the claims have %s', case when is_usable then 'give' else 'refuse' end, description)
) from claim_variants order by description;

select is(
  pg_temp.helper_with_claims(claims_json, 'private.is_aal2()'),
  case when is_usable then 'true' else 'false' end,
  format('should say is_aal2 is %s when the claims have %s', is_usable, description)
) from claim_variants order by description;

-- Claims that are not an object or not JSON at all must give false, never an error, from the aal check itself.
select is(pg_temp.helper_with_claims('', 'private.is_aal2()'), 'false', 'should say not aal2 for empty claims');
select is(pg_temp.helper_with_claims('not json', 'private.is_aal2()'), 'false', 'should say not aal2 for claims that are not JSON');
select is(pg_temp.helper_with_claims('{"aal":"aal2"', 'private.is_aal2()'), 'false', 'should say not aal2 for truncated JSON');
select is(pg_temp.helper_with_claims('"aal2"', 'private.is_aal2()'), 'false', 'should say not aal2 for a bare JSON string');
select is(pg_temp.helper_with_claims('["aal2"]', 'private.is_aal2()'), 'false', 'should say not aal2 for a JSON array');
select is(pg_temp.helper_with_claims('null', 'private.is_aal2()'), 'false', 'should say not aal2 for the JSON null');
select is(pg_temp.helper_with_claims('{}', 'private.is_aal2()'), 'false', 'should say not aal2 for an empty object');

-- No claims setting at all (a session that never set one).
reset request.jwt.claims;
select is(private.is_aal2(), false, 'should say not aal2 when the session has no claims setting');
select is(private.has_role('pastor'), false, 'should not give any role when the session has no claims setting');

-- is_role_usable on its own: a role outside the list is always usable, one inside only at aal2.
select is(
  pg_temp.helper_as('usher', aal, format('private.is_role_usable(%L)', role)),
  expected,
  format('should say the %s role is usable: %s at %s', role, expected, aal)
) from (values
  ('aal1', 'usher', 'true'), ('aal2', 'usher', 'true'),
  ('aal1', 'department_head', 'true'), ('aal1', 'content_editor', 'true'), ('aal1', 'secretary', 'true'),
  ('aal1', 'pastor', 'false'), ('aal2', 'pastor', 'true'),
  ('aal1', 'super_admin', 'false'), ('aal2', 'super_admin', 'true'),
  ('aal1', 'treasurer', 'false'), ('aal2', 'treasurer', 'true')
) as cases (aal, role, expected)
order by role, aal;

-- Grants: the four original helpers stay executable by authenticated, the new ones are not.
select is(
  has_function_privilege('authenticated', signature::regprocedure, 'execute'),
  true,
  format('should keep %s executable by authenticated', signature)
) from (values
  ('private.has_any_role(public.app_role[])'), ('private.has_role(public.app_role)'),
  ('private.heads_department(uuid)'), ('private.is_active_staff()')
) as helpers (signature);

select is(
  has_function_privilege(role_name, signature::regprocedure, 'execute'),
  false,
  format('should not let %s execute %s', role_name, signature)
) from (values
  ('private.mfa_required_roles()'), ('private.required_assurance_level()'), ('private.is_aal2()'),
  ('private.is_role_usable(public.app_role)'), ('private.has_dashboard_session()')
) as helpers (signature)
cross join (values ('anon'), ('authenticated')) as app_roles (role_name)
order by signature, role_name;

select is(
  (select proconfig from pg_proc where oid = 'private.is_active_staff()'::regprocedure),
  array['search_path=""'],
  'should keep an empty search_path on is_active_staff'
);

select is(
  (select bool_and(proconfig = array['search_path=""']) from pg_proc
   where oid in (
     'private.mfa_required_roles()'::regprocedure, 'private.required_assurance_level()'::regprocedure,
     'private.is_aal2()'::regprocedure, 'private.is_role_usable(public.app_role)'::regprocedure,
     'private.has_dashboard_session()'::regprocedure, 'private.has_any_role(public.app_role[])'::regprocedure,
     'private.heads_department(uuid)'::regprocedure)),
  true,
  'should give every new or changed helper an empty search_path'
);

select * from finish();

rollback;
