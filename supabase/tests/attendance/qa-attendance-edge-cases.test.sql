-- LBC-31 QA: edge cases beyond the worker's tests. service_role writes, the 200 character name cap with multi-byte
-- text, archived services, the generator under other session time zones and for every role, abuse of its input,
-- the audit trail of an upsert, the age boundary for check-ins and the absence of side channels for hidden members.
-- Fixture: the demo seed, extended below and rolled back.

begin;

select plan(68);

create function pg_temp.probe(p_sub uuid, p_role text, p_stmt text)
returns text
language plpgsql
as $$
declare
  v_result text;
  v_rows bigint;
  v_detail text;
begin
  begin
    perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', p_role, 'sub', p_sub)::text, true);
    perform set_config('role', p_role, true);
    execute p_stmt;
    get diagnostics v_rows = row_count;
    v_result := 'ok ' || v_rows;
    raise exception using errcode = 'QAUND';
  exception
    when sqlstate 'QAUND' then null;
    when others then
      get stacked diagnostics v_detail = pg_exception_detail;
      v_result := sqlstate || ' ' || case when sqlstate = 'P0001' then sqlerrm else '' end;
  end;
  return v_result;
end;
$$;

-- Same idea, but returns the rows count of a select as a plain number.
create function pg_temp.visible(p_sub uuid, p_statement text)
returns bigint
language plpgsql
as $$
declare
  v_count bigint;
begin
  begin
    perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role', 'authenticated', 'sub', p_sub)::text, true);
    perform set_config('role', 'authenticated', true);
    execute 'select count(*) from (' || p_statement || ') as visible_rows' into v_count;
    raise exception using errcode = 'QAUND';
  exception when sqlstate 'QAUND' then null;
  end;
  return v_count;
end;
$$;

create temp table ids (label text primary key, id uuid);
insert into ids values
  ('super_admin', '10000000-0000-4000-8000-000000000001'),
  ('pastor', '10000000-0000-4000-8000-000000000002'),
  ('treasurer', '10000000-0000-4000-8000-000000000003'),
  ('secretary', '10000000-0000-4000-8000-000000000004'),
  ('usher', '10000000-0000-4000-8000-000000000005'),
  ('department_head', '10000000-0000-4000-8000-000000000006'),
  ('content_editor', '10000000-0000-4000-8000-000000000007');
grant all on ids to public;

-- An archived (cancelled) service, an inactive secretary and a signed-in user with no staff row.
insert into public.services (id, name, type, starts_at, archived_at)
values ('b1000000-0000-4000-8000-0000000000a1', 'Cancelled Vigil', 'special', '2026-11-15 18:00:00+00', now());
insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-0000000000a8', 'authenticated', 'authenticated', 'qa-inactive@example.org', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-0000000000aa', 'authenticated', 'authenticated', 'qa-nostaff@example.org', now(), now(), now());
insert into public.staff (id, full_name, is_active) values ('10000000-0000-4000-8000-0000000000a8', 'QA Inactive Secretary', false);
insert into public.staff_roles (staff_id, role, granted_by)
values ('10000000-0000-4000-8000-0000000000a8', 'secretary', '10000000-0000-4000-8000-000000000001');

-- service_role (an edge function) writes counts directly, so the CHECK must be executable by it (round 1 fix)

select is(pg_temp.probe(null, 'service_role', $$insert into public.attendance_counts (service_id, men, women, children, visitors, recorded_by) values ('b1000000-0000-4000-8000-000000000003', 0, 0, 0, 0, '10000000-0000-4000-8000-000000000001')$$),
  'ok 1', 'should let service_role insert a count of 0 when it writes directly');
select is(pg_temp.probe(null, 'service_role', $$insert into public.attendance_counts (service_id, men, women, children, visitors, recorded_by) values ('b1000000-0000-4000-8000-000000000003', 1, 1, 1, 1, '10000000-0000-4000-8000-000000000001')$$),
  'ok 1', 'should let service_role insert a count of 1 when it writes directly');
select is(pg_temp.probe(null, 'service_role', $$insert into public.attendance_counts (service_id, men, women, children, visitors, recorded_by) values ('b1000000-0000-4000-8000-000000000003', 100000, 100000, 100000, 100000, '10000000-0000-4000-8000-000000000001')$$),
  'ok 1', 'should let service_role insert the maximum count of 100000 when it writes directly');
select is(pg_temp.probe(null, 'service_role', $$insert into public.attendance_counts (service_id, men, women, children, visitors, recorded_by) values ('b1000000-0000-4000-8000-000000000003', 100001, 0, 0, 0, '10000000-0000-4000-8000-000000000001')$$),
  '23514 ', 'should reject 100001 men from service_role with a check violation');
select is(pg_temp.probe(null, 'service_role', $$insert into public.attendance_counts (service_id, men, women, children, visitors, recorded_by) values ('b1000000-0000-4000-8000-000000000003', 0, 0, 0, -1, '10000000-0000-4000-8000-000000000001')$$),
  '23514 ', 'should reject -1 visitors from service_role with a check violation');
select is(pg_temp.probe(null, 'service_role', $$insert into public.attendance_counts (service_id, men, women, children, visitors, recorded_by) values ('b1000000-0000-4000-8000-000000000003', null, 0, 0, 0, '10000000-0000-4000-8000-000000000001')$$),
  '23502 ', 'should reject a null count from service_role with a not null violation');
select is(pg_temp.probe(null, 'service_role', $$update public.attendance_counts set women = 100001$$),
  '23514 ', 'should reject raising a count above 100000 from service_role');

-- the 200 character name cap counts characters, never bytes, and never trips the btree row limit

select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', format('insert into public.services (name, type, starts_at) values (%L, ''special'', now())', repeat('a', 200))),
  'ok 1', 'should accept a service name of exactly 200 characters when a secretary creates it');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', format('insert into public.services (name, type, starts_at) values (%L, ''special'', now())', repeat('a', 201))),
  '23514 ', 'should reject a service name of 201 characters with a check violation');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', format('insert into public.services (name, type, starts_at) values (%L, ''special'', now())', repeat(chr(128512), 200))),
  'ok 1', 'should accept 200 emoji (800 bytes) when counting characters');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', format('insert into public.services (name, type, starts_at) values (%L, ''special'', now())', repeat(chr(1078), 200))),
  'ok 1', 'should accept 200 Cyrillic characters without a btree row size error');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', format('insert into public.services (name, type, starts_at) values (%L, ''special'', now())', repeat(chr(20013), 200))),
  'ok 1', 'should accept 200 Chinese characters without a btree row size error');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', format('insert into public.services (name, type, starts_at) values (%L, ''special'', now())', repeat(chr(128512), 201))),
  '23514 ', 'should reject 201 emoji with a check violation and not a btree error');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', format('update public.services set name = %L where id = %L', repeat('a', 201), 'b1000000-0000-4000-8000-000000000001')),
  '23514 ', 'should reject renaming a service to 201 characters');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', format('update public.services set name = %L where id = %L', repeat(chr(128512), 200), 'b1000000-0000-4000-8000-000000000001')),
  'ok 1', 'should accept renaming a service to 200 emoji');
select is(pg_temp.probe(null, 'service_role', format('insert into public.services (name, type, starts_at) values (%L, ''special'', now())', repeat('a', 201))),
  '23514 ', 'should reject a 201 character name from service_role');

select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', format('select public.generate_recurring_services(%L::jsonb, 1)', jsonb_build_array(jsonb_build_object('name', repeat('a', 200), 'type', 'midweek', 'weekday', 3, 'time', '18:00'))::text)),
  'ok 1', 'should accept a template name of exactly 200 characters');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', format('select public.generate_recurring_services(%L::jsonb, 1)', jsonb_build_array(jsonb_build_object('name', repeat('a', 201), 'type', 'midweek', 'weekday', 3, 'time', '18:00'))::text)),
  'P0001 VALIDATION_FAILED', 'should reject a template name of 201 characters with VALIDATION_FAILED');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', format('select public.generate_recurring_services(%L::jsonb, 1)', jsonb_build_array(jsonb_build_object('name', repeat(chr(128512), 200), 'type', 'midweek', 'weekday', 4, 'time', '18:00'))::text)),
  'ok 1', 'should accept a template name of 200 emoji');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', format('select public.generate_recurring_services(%L::jsonb, 1)', jsonb_build_array(jsonb_build_object('name', repeat(chr(128512), 201), 'type', 'midweek', 'weekday', 4, 'time', '18:00'))::text)),
  'P0001 VALIDATION_FAILED', 'should reject a template name of 201 emoji with VALIDATION_FAILED');

-- archived and missing services

select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', $$select public.record_attendance_counts('b1000000-0000-4000-8000-0000000000a1', 1, 1, 1, 1)$$),
  'P0001 VALIDATION_FAILED', 'should reject a count for an archived service when a secretary records it');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000001', 'authenticated', $$select public.record_attendance_counts('b1000000-0000-4000-8000-0000000000a1', 1, 1, 1, 1)$$),
  'P0001 VALIDATION_FAILED', 'should reject a count for an archived service when a super admin records it');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000005', 'authenticated', $$select public.record_attendance_counts('00000000-0000-4000-8000-000000000000', 1, 1, 1, 1)$$),
  'P0001 NOT_FOUND', 'should answer NOT_FOUND when the service does not exist');
select is(pg_temp.probe('10000000-0000-4000-8000-0000000000a8', 'authenticated', $$select public.record_attendance_counts('b1000000-0000-4000-8000-000000000003', 1, 1, 1, 1)$$),
  'P0001 AUTH_FORBIDDEN', 'should refuse an inactive secretary recording a count');
select is(pg_temp.probe('10000000-0000-4000-8000-0000000000aa', 'authenticated', $$select public.record_attendance_counts('b1000000-0000-4000-8000-000000000003', 1, 1, 1, 1)$$),
  'P0001 AUTH_FORBIDDEN', 'should refuse a signed-in user with no staff row recording a count');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000005', 'authenticated', $$select public.record_attendance_counts('b1000000-0000-4000-8000-000000000003', 1.5, 0, 0, 0)$$),
  '42883 ', 'should reject a decimal headcount because no function accepts it');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000005', 'authenticated', $$select public.record_attendance_counts('b1000000-0000-4000-8000-000000000003', 2147483647, 0, 0, 0)$$),
  'P0001 VALIDATION_FAILED', 'should reject the largest integer as a headcount');

-- the generator for every role

select is(pg_temp.probe(ids.id, 'authenticated', $$select public.generate_recurring_services('[{"name":"Role Study","type":"midweek","weekday":3,"time":"18:00"}]'::jsonb, 1)$$),
  case when ids.label in ('super_admin', 'secretary') then 'ok 1' else 'P0001 AUTH_FORBIDDEN' end,
  format('should %s generating services when the actor is %s', case when ids.label in ('super_admin', 'secretary') then 'allow' else 'refuse' end, ids.label))
from ids order by ids.label;
select is(pg_temp.probe(null, 'anon', $$select public.generate_recurring_services('[{"name":"Anon Study","type":"midweek","weekday":3,"time":"18:00"}]'::jsonb, 1)$$),
  '42501 ', 'should refuse anon generating services');
select is(pg_temp.probe('10000000-0000-4000-8000-0000000000a8', 'authenticated', $$select public.generate_recurring_services('[{"name":"Inactive Study","type":"midweek","weekday":3,"time":"18:00"}]'::jsonb, 1)$$),
  'P0001 AUTH_FORBIDDEN', 'should refuse an inactive secretary generating services');

-- generator input abuse: nothing is created and the message is a code, not database text

select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', $$select public.generate_recurring_services('[{"name":"A","type":"midweek","weekday":8,"time":"18:00"}]'::jsonb, 1)$$),
  'P0001 VALIDATION_FAILED', 'should reject weekday 8');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', $$select public.generate_recurring_services('[{"name":"A","type":"midweek","weekday":3,"time":"24:00"}]'::jsonb, 1)$$),
  'P0001 VALIDATION_FAILED', 'should reject the time 24:00');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', $$select public.generate_recurring_services('[{"name":"A","type":"midweek","weekday":3,"time":"8:00"}]'::jsonb, 1)$$),
  'P0001 VALIDATION_FAILED', 'should reject the time 8:00 without a leading zero');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', $$select public.generate_recurring_services('[{"name":"A","type":"midweek","weekday":"3","time":"18:00"}]'::jsonb, 1)$$),
  'P0001 VALIDATION_FAILED', 'should reject a weekday given as a string');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', $$select public.generate_recurring_services('[{"name":"A","type":"midweek","weekday":3,"time":"18:00"}]'::jsonb, 27)$$),
  'P0001 VALIDATION_FAILED', 'should reject 27 weeks');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', $$select public.generate_recurring_services('[{"name":"A","type":"midweek","weekday":3,"time":"18:00"}]'::jsonb, 0)$$),
  'P0001 VALIDATION_FAILED', 'should reject 0 weeks');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', $$select public.generate_recurring_services('[{"name":"A","type":"midweek","weekday":3,"time":"18:00"}]'::jsonb, -1)$$),
  'P0001 VALIDATION_FAILED', 'should reject -1 weeks');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', format('select public.generate_recurring_services(%L::jsonb, 1)', (select jsonb_agg(jsonb_build_object('name', 'T' || n, 'type', 'midweek', 'weekday', 1, 'time', '10:00')) from generate_series(1, 21) as n)::text)),
  'P0001 VALIDATION_FAILED', 'should reject 21 templates');
select is(pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', $$select public.generate_recurring_services('[{"name":"Robert''); DROP TABLE public.services;--","type":"midweek","weekday":2,"time":"18:00"}]'::jsonb, 1)$$),
  'ok 1', 'should store an SQL injection looking name as plain text');
select is((select count(*) from public.services where name like 'Robert%'), 0::bigint,
  'should leave nothing behind from that rolled back injection trial');

-- the same templates give the same instants whatever the session time zone (round 1 fix)

create function pg_temp.generated_instants(p_time_zone text)
returns text
language plpgsql
as $$
declare
  v_instants text;
begin
  begin
    perform set_config('TimeZone', p_time_zone, true);
    perform set_config('request.jwt.claims', '{"aal":"aal2","role":"authenticated","sub":"10000000-0000-4000-8000-000000000004"}', true);
    perform set_config('role', 'authenticated', true);
    perform public.generate_recurring_services(
      '[{"name":"Tz First","type":"sunday","weekday":7,"time":"08:00"},{"name":"Tz Second","type":"sunday","weekday":7,"time":"10:30"},{"name":"Tz Study","type":"midweek","weekday":3,"time":"18:00"},{"name":"Tz Late","type":"midweek","weekday":1,"time":"23:59"}]'::jsonb, 8);
    perform set_config('role', 'postgres', true);
    select string_agg(name || ' ' || to_char(starts_at at time zone 'UTC', 'YYYY-MM-DD HH24:MI'), ';' order by starts_at, name)
      into v_instants from public.services where name like 'Tz %';
    raise exception using errcode = 'QAUND';
  exception when sqlstate 'QAUND' then null;
  end;
  return v_instants;
end;
$$;

select isnt(pg_temp.generated_instants('Africa/Accra'), null, 'should generate services in the reference time zone');
select is(pg_temp.generated_instants('UTC'), pg_temp.generated_instants('Africa/Accra'), 'should generate identical instants when the session time zone is UTC');
select is(pg_temp.generated_instants('Pacific/Kiritimati'), pg_temp.generated_instants('Africa/Accra'), 'should generate identical instants when the session time zone is UTC+14');
select is(pg_temp.generated_instants('Etc/GMT+12'), pg_temp.generated_instants('Africa/Accra'), 'should generate identical instants when the session time zone is UTC-12');
select is(pg_temp.generated_instants('America/Los_Angeles'), pg_temp.generated_instants('Africa/Accra'), 'should generate identical instants when the session time zone is Los Angeles');
select is((select count(*) from regexp_matches(pg_temp.generated_instants('Etc/GMT+12'), 'Tz Second \d{4}-\d{2}-\d{2} 10:30', 'g')), 8::bigint,
  'should generate eight Sunday second services at 10:30 church time (Accra is UTC)');

-- upsert and audit: one row, INSERT then UPDATE, and the second writer becomes recorded_by

create temp table audit_mark (id bigint);
insert into audit_mark select coalesce(max(id), 0) from audit.log;

select set_config('request.jwt.claims', '{"aal":"aal2","role":"authenticated","sub":"10000000-0000-4000-8000-000000000005"}', true);
set local role authenticated;
select public.record_attendance_counts('b1000000-0000-4000-8000-000000000004', 10, 20, 5, 1);
select set_config('request.jwt.claims', '{"aal":"aal2","role":"authenticated","sub":"10000000-0000-4000-8000-000000000004"}', true);
select public.record_attendance_counts('b1000000-0000-4000-8000-000000000004', 11, 20, 5, 1);
reset role;
select set_config('request.jwt.claims', '', true);

select is((select count(*) from public.attendance_counts where service_id = 'b1000000-0000-4000-8000-000000000004'), 1::bigint,
  'should keep one count row when the same service is recorded twice');
select is((select recorded_by from public.attendance_counts where service_id = 'b1000000-0000-4000-8000-000000000004'), '10000000-0000-4000-8000-000000000004'::uuid,
  'should make the later writer the recorded_by');
select is((select array_agg(action order by id) from audit.log where id > (select id from audit_mark) and table_name = 'attendance_counts'), array['INSERT', 'UPDATE'],
  'should write INSERT then UPDATE to the audit log for an upserted count');
select is((select array_agg(actor_id order by id) from audit.log where id > (select id from audit_mark) and table_name = 'attendance_counts'),
  array['10000000-0000-4000-8000-000000000005', '10000000-0000-4000-8000-000000000004']::uuid[],
  'should attribute each audit row to the staff member who made the write');
select is((select changed_fields from audit.log where id > (select id from audit_mark) and table_name = 'attendance_counts' and action = 'UPDATE'), array['men', 'recorded_by'],
  'should list exactly the changed fields on the audited overwrite (updated_at is unchanged inside one transaction)');

update audit_mark set id = (select coalesce(max(id), 0) from audit.log);
select is(pg_temp.probe('10000000-0000-4000-8000-000000000005', 'authenticated', $$select public.record_attendance_counts('b1000000-0000-4000-8000-000000000004', -5, 0, 0, 0)$$),
  'P0001 VALIDATION_FAILED', 'should reject a negative count for an existing service');
select is((select count(*) from audit.log where id > (select id from audit_mark)), 0::bigint, 'should leave no audit rows when a write is rejected');
select is((select men from public.attendance_counts where service_id = 'b1000000-0000-4000-8000-000000000004'), 11, 'should keep the earlier count when a later one is rejected');

-- age boundary between check-in and read: a child checked in by the super admin turns 18. The seeded child is taken out
-- of the children's ministry first, because the secretary reads the children of that ministry.

delete from public.member_departments where member_id = '40000000-0000-4000-8000-000000000003';

insert into public.attendance_checkins (service_id, member_id, checked_in_by)
values ('b1000000-0000-4000-8000-000000000005', '40000000-0000-4000-8000-000000000003', '10000000-0000-4000-8000-000000000001');

select is(pg_temp.visible('10000000-0000-4000-8000-000000000004', $$select 1 from public.attendance_checkins where member_id = '40000000-0000-4000-8000-000000000003'$$), 0::bigint,
  'should hide the check-in of a minor from the secretary');
update public.members set date_of_birth = current_date + 1 - interval '18 years' where id = '40000000-0000-4000-8000-000000000003';
select is(pg_temp.visible('10000000-0000-4000-8000-000000000004', $$select 1 from public.attendance_checkins where member_id = '40000000-0000-4000-8000-000000000003'$$), 0::bigint,
  'should still hide the check-in the day before the member turns 18');
update public.members set date_of_birth = current_date - interval '18 years' where id = '40000000-0000-4000-8000-000000000003';
select is(pg_temp.visible('10000000-0000-4000-8000-000000000004', $$select 1 from public.attendance_checkins where member_id = '40000000-0000-4000-8000-000000000003'$$), 1::bigint,
  'should show the check-in to the secretary on the day the member turns 18');
update public.members set date_of_birth = null where id = '40000000-0000-4000-8000-000000000003';
select is(pg_temp.visible('10000000-0000-4000-8000-000000000004', $$select 1 from public.attendance_checkins where member_id = '40000000-0000-4000-8000-000000000003'$$), 0::bigint,
  'should hide the check-in from the secretary when the date of birth is unknown');
select is(pg_temp.visible('10000000-0000-4000-8000-000000000002', $$select 1 from public.attendance_checkins where member_id = '40000000-0000-4000-8000-000000000003'$$), 1::bigint,
  'should keep the check-in visible to the pastor when the date of birth is unknown');
update public.members set date_of_birth = '2014-06-20' where id = '40000000-0000-4000-8000-000000000003';

-- no side channel: a hidden member and a member who does not exist look the same to a secretary

select is(
  pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', $$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('b1000000-0000-4000-8000-000000000005', '40000000-0000-4000-8000-000000000003', auth.uid())$$),
  pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', $$insert into public.attendance_checkins (service_id, member_id, checked_in_by) values ('b1000000-0000-4000-8000-000000000005', '40000000-0000-4000-8000-0000000000ff', auth.uid())$$),
  'should give the same answer for an already checked in minor and for a member who does not exist');
select is(
  pg_temp.probe('10000000-0000-4000-8000-000000000004', 'authenticated', $$insert into public.program_participants (program_id, member_id) values ('b2000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000003')$$),
  '42501 ', 'should answer with a plain denial and not a duplicate key error when a secretary registers an already registered minor');

insert into public.member_departments (member_id, department_id)
select '40000000-0000-4000-8000-000000000003', id from public.departments where is_childrens_ministry limit 1;

select is(pg_temp.visible('10000000-0000-4000-8000-000000000004', $$select 1 from public.attendance_checkins where member_id = '40000000-0000-4000-8000-000000000003'$$), 1::bigint,
  'should show the check-in of a child of the children''s ministry to the secretary');

select * from finish();

rollback;
