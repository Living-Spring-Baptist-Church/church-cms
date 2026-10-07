-- LBC-31 QA: the PRD permission matrix (Attendance, Programs and the program participants that follow Programs)
-- walked cell by cell for every role, inactive staff, a signed-in user with no staff row and anon. Each cell is one
-- statement run as a real database role, undone afterwards, compared with the outcome the PRD requires:
--   a number = rows returned or affected, 42501 = denied by grants or RLS, AUTH = AUTH_FORBIDDEN, VALID = VALIDATION_FAILED.
-- Fixture: the demo seed plus a few extra rows added below, all rolled back.

begin;

select plan(480);

insert into auth.users (instance_id,id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 ('00000000-0000-0000-0000-000000000000','10000000-0000-4000-8000-000000000008','authenticated','authenticated','isec@x.org',now(),now(),now()),
 ('00000000-0000-0000-0000-000000000000','10000000-0000-4000-8000-000000000009','authenticated','authenticated','ch@x.org',now(),now(),now()),
 ('00000000-0000-0000-0000-000000000000','10000000-0000-4000-8000-00000000000a','authenticated','authenticated','ns@x.org',now(),now(),now()),
 ('00000000-0000-0000-0000-000000000000','10000000-0000-4000-8000-00000000000b','authenticated','authenticated','ius@x.org',now(),now(),now());
insert into public.staff (id, full_name, is_active) values
 ('10000000-0000-4000-8000-000000000008','Inactive Sec', false),
 ('10000000-0000-4000-8000-000000000009','Children Head', true),
 ('10000000-0000-4000-8000-00000000000b','Inactive Usher', false);
insert into public.staff_roles (staff_id, role, department_id, granted_by) values
 ('10000000-0000-4000-8000-000000000008','secretary',null,'10000000-0000-4000-8000-000000000001'),
 ('10000000-0000-4000-8000-000000000009','department_head','20000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001'),
 ('10000000-0000-4000-8000-00000000000b','usher',null,'10000000-0000-4000-8000-000000000001');
insert into public.services (id,name,type,starts_at,program_id,archived_at) values
 ('b1000000-0000-4000-8000-000000000006','Choir Concert','program','2026-11-14 18:00+00','b2000000-0000-4000-8000-000000000002',null),
 ('b1000000-0000-4000-8000-000000000007','Cancelled Svc','special','2026-11-15 18:00+00',null,now());
insert into public.program_participants (program_id, member_id) values ('b2000000-0000-4000-8000-000000000002','40000000-0000-4000-8000-000000000004');
insert into public.attendance_counts (service_id,men,women,children,visitors,recorded_by) values ('b1000000-0000-4000-8000-000000000006',1,1,1,1,'10000000-0000-4000-8000-000000000001');
insert into public.attendance_checkins (service_id,member_id,checked_in_by) values
 ('b1000000-0000-4000-8000-000000000006','40000000-0000-4000-8000-000000000004','10000000-0000-4000-8000-000000000001'),
 ('b1000000-0000-4000-8000-000000000005','40000000-0000-4000-8000-000000000003','10000000-0000-4000-8000-000000000001'),
 ('b1000000-0000-4000-8000-000000000005','40000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000005');

create temp table actors(ord int, label text, sub uuid, dbrole text);
insert into actors values
 (1,'SA','10000000-0000-4000-8000-000000000001','authenticated'),
 (2,'Pa','10000000-0000-4000-8000-000000000002','authenticated'),
 (3,'Tr','10000000-0000-4000-8000-000000000003','authenticated'),
 (4,'Se','10000000-0000-4000-8000-000000000004','authenticated'),
 (5,'Us','10000000-0000-4000-8000-000000000005','authenticated'),
 (6,'HCh','10000000-0000-4000-8000-000000000006','authenticated'),
 (7,'CE','10000000-0000-4000-8000-000000000007','authenticated'),
 (8,'iSe','10000000-0000-4000-8000-000000000008','authenticated'),
 (9,'iUs','10000000-0000-4000-8000-00000000000b','authenticated'),
 (10,'HCm','10000000-0000-4000-8000-000000000009','authenticated'),
 (11,'NoS','10000000-0000-4000-8000-00000000000a','authenticated'),
 (12,'Anon',null,'anon');
grant all on actors to public;

create function pg_temp.probe(p_sub uuid, p_role text, p_stmt text) returns text language plpgsql as $$
declare v text; n bigint;
begin
  begin
    perform set_config('request.jwt.claims', json_build_object('role',p_role,'sub',p_sub)::text, true);
    perform set_config('role', p_role, true);
    execute p_stmt;
    get diagnostics n = row_count;
    v := n::text;
    raise exception using errcode='QAUND';
  exception when sqlstate 'QAUND' then null;
    when others then v := 'E' || sqlstate || case when sqlerrm like 'AUTH_%' or sqlerrm like 'VALID%' or sqlerrm like 'NOT_%' then ':'||left(sqlerrm,5) else '' end;
  end;
  return v;
end $$;

create temp table acts(ord int, name text, stmt text);
insert into acts values
(1,'R services','select * from public.services'),
(2,'R services archived','select * from public.services where archived_at is not null'),
(3,'R counts','select * from public.attendance_counts'),
(4,'R checkins','select * from public.attendance_checkins'),
(5,'R checkins of Kofi(minor)','select * from public.attendance_checkins where member_id=''40000000-0000-4000-8000-000000000003'''),
(6,'R programs','select * from public.programs'),
(7,'R participants','select * from public.program_participants'),
(8,'R participants Kofi','select * from public.program_participants where member_id=''40000000-0000-4000-8000-000000000003'''),
(10,'W insert service','insert into public.services(name,type,starts_at) values(''QA'',''special'',now())'),
(11,'W insert service in Choir program','insert into public.services(name,type,starts_at,program_id) values(''QA'',''program'',now(),''b2000000-0000-4000-8000-000000000002'')'),
(12,'W update service name','update public.services set name=''QA2'' where id=''b1000000-0000-4000-8000-000000000001'''),
(13,'W archive service','update public.services set archived_at=now() where id=''b1000000-0000-4000-8000-000000000001'''),
(14,'W delete service','delete from public.services'),
(15,'W insert program (no dept)','insert into public.programs(name) values(''QA'')'),
(16,'W insert program Choir','insert into public.programs(name,department_id) values(''QA'',''20000000-0000-4000-8000-000000000001'')'),
(17,'W insert program Children','insert into public.programs(name,department_id) values(''QA'',''20000000-0000-4000-8000-000000000003'')'),
(18,'W update Choir program','update public.programs set name=''x'' where id=''b2000000-0000-4000-8000-000000000002'''),
(19,'W update Children program','update public.programs set name=''x'' where id=''b2000000-0000-4000-8000-000000000001'''),
(20,'W move Choir program to Youth','update public.programs set department_id=''20000000-0000-4000-8000-000000000002'' where id=''b2000000-0000-4000-8000-000000000002'''),
(21,'W delete program','delete from public.programs'),
(22,'F record counts s1','select public.record_attendance_counts(''b1000000-0000-4000-8000-000000000001'',1,2,3,4)'),
(23,'F record counts new svc','select public.record_attendance_counts(''b1000000-0000-4000-8000-000000000003'',1,2,3,4)'),
(24,'F record counts archived','select public.record_attendance_counts(''b1000000-0000-4000-8000-000000000007'',1,2,3,4)'),
(25,'F generate','select public.generate_recurring_services(''[{"name":"QA","type":"midweek","weekday":3,"time":"18:00"}]'',1)'),
(26,'W counts direct insert','insert into public.attendance_counts(service_id,men,women,children,visitors,recorded_by) values(''b1000000-0000-4000-8000-000000000003'',1,1,1,1,auth.uid())'),
(27,'W counts direct update','update public.attendance_counts set men=5'),
(28,'W counts direct delete','delete from public.attendance_counts'),
(30,'W checkin adult Esi','insert into public.attendance_checkins(service_id,member_id,checked_in_by) values(''b1000000-0000-4000-8000-000000000003'',''40000000-0000-4000-8000-000000000004'',auth.uid())'),
(31,'W checkin minor Kofi','insert into public.attendance_checkins(service_id,member_id,checked_in_by) values(''b1000000-0000-4000-8000-000000000003'',''40000000-0000-4000-8000-000000000003'',auth.uid())'),
(32,'W checkin archived Akosua','insert into public.attendance_checkins(service_id,member_id,checked_in_by) values(''b1000000-0000-4000-8000-000000000003'',''40000000-0000-4000-8000-000000000008'',auth.uid())'),
(33,'W checkin visitor Abena','insert into public.attendance_checkins(service_id,member_id,checked_in_by) values(''b1000000-0000-4000-8000-000000000003'',''40000000-0000-4000-8000-000000000006'',auth.uid())'),
(34,'W checkin archived svc','insert into public.attendance_checkins(service_id,member_id,checked_in_by) values(''b1000000-0000-4000-8000-000000000007'',''40000000-0000-4000-8000-000000000004'',auth.uid())'),
(35,'W checkin as someone else','insert into public.attendance_checkins(service_id,member_id,checked_in_by) values(''b1000000-0000-4000-8000-000000000003'',''40000000-0000-4000-8000-000000000004'',''10000000-0000-4000-8000-000000000001'')'),
(36,'W delete checkins','delete from public.attendance_checkins'),
(37,'W update checkin','update public.attendance_checkins set checked_in_at=now()'),
(40,'W participant Kwame->Choir','insert into public.program_participants(program_id,member_id) values(''b2000000-0000-4000-8000-000000000002'',''40000000-0000-4000-8000-000000000001'')'),
(41,'W participant Kofi->Choir','insert into public.program_participants(program_id,member_id) values(''b2000000-0000-4000-8000-000000000002'',''40000000-0000-4000-8000-000000000003'')'),
(42,'W participant Kwame->Children prog','insert into public.program_participants(program_id,member_id) values(''b2000000-0000-4000-8000-000000000001'',''40000000-0000-4000-8000-000000000001'')'),
(43,'W delete participants','delete from public.program_participants'),
(44,'W update participant','update public.program_participants set member_id=member_id');


create temp table expected (action text, outcomes text[]);
insert into expected values
('R services', array['7','7','0','7','6','1','0','0','0','1','0','42501']),
('R services archived', array['1','1','0','1','0','0','0','0','0','0','0','42501']),
('R counts', array['2','2','0','2','2','1','0','0','0','0','0','42501']),
('R checkins', array['4','4','0','3','2','1','0','0','0','1','0','42501']),
('R checkins of Kofi(minor)', array['1','1','0','0','0','0','0','0','0','1','0','42501']),
('R programs', array['2','2','0','2','0','1','0','0','0','1','0','42501']),
('R participants', array['3','3','0','2','0','1','0','0','0','1','0','42501']),
('R participants Kofi', array['1','1','0','0','0','0','0','0','0','1','0','42501']),
('W insert service', array['1','42501','42501','1','42501','42501','42501','42501','42501','42501','42501','42501']),
('W insert service in Choir program', array['1','42501','42501','1','42501','42501','42501','42501','42501','42501','42501','42501']),
('W update service name', array['1','0','0','1','0','0','0','0','0','0','0','42501']),
('W archive service', array['1','0','0','1','0','0','0','0','0','0','0','42501']),
('W delete service', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W insert program (no dept)', array['1','42501','42501','1','42501','42501','42501','42501','42501','42501','42501','42501']),
('W insert program Choir', array['1','42501','42501','1','42501','1','42501','42501','42501','42501','42501','42501']),
('W insert program Children', array['1','42501','42501','1','42501','42501','42501','42501','42501','1','42501','42501']),
('W update Choir program', array['1','0','0','1','0','1','0','0','0','0','0','42501']),
('W update Children program', array['1','0','0','1','0','0','0','0','0','1','0','42501']),
('W move Choir program to Youth', array['1','0','0','1','0','42501','0','0','0','0','0','42501']),
('W delete program', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('F record counts s1', array['1','AUTH','AUTH','1','1','AUTH','AUTH','AUTH','AUTH','AUTH','AUTH','42501']),
('F record counts new svc', array['1','AUTH','AUTH','1','1','AUTH','AUTH','AUTH','AUTH','AUTH','AUTH','42501']),
('F record counts archived', array['VALID','AUTH','AUTH','VALID','VALID','AUTH','AUTH','AUTH','AUTH','AUTH','AUTH','42501']),
('F generate', array['1','AUTH','AUTH','1','AUTH','AUTH','AUTH','AUTH','AUTH','AUTH','AUTH','42501']),
('W counts direct insert', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W counts direct update', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W counts direct delete', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W checkin adult Esi', array['1','42501','42501','1','1','42501','42501','42501','42501','42501','42501','42501']),
('W checkin minor Kofi', array['1','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W checkin archived Akosua', array['1','42501','42501','1','42501','42501','42501','42501','42501','42501','42501','42501']),
('W checkin visitor Abena', array['1','42501','42501','1','1','42501','42501','42501','42501','42501','42501','42501']),
('W checkin archived svc', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W checkin as someone else', array['1','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W delete checkins', array['4','0','0','3','2','0','0','0','0','0','0','42501']),
('W update checkin', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W participant Kwame->Choir', array['1','42501','42501','1','42501','42501','42501','42501','42501','42501','42501','42501']),
('W participant Kofi->Choir', array['1','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W participant Kwame->Children prog', array['1','42501','42501','1','42501','42501','42501','42501','42501','42501','42501','42501']),
('W delete participants', array['3','0','0','2','0','1','0','0','0','1','0','42501']),
('W update participant', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']);

select is(
  regexp_replace(regexp_replace(regexp_replace(pg_temp.probe(actors.sub, actors.dbrole, acts.stmt), '^E42501$', '42501'), '^EP0001:AUTH_$', 'AUTH'), '^EP0001:VALID$', 'VALID'),
  expected.outcomes[actors.ord],
  format('should give %s for "%s" when the actor is %s', expected.outcomes[actors.ord], acts.name, actors.label)
)
from acts
join expected on expected.action = acts.name
cross join actors
order by acts.ord, actors.ord;

select * from finish();

rollback;
