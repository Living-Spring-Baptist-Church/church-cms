-- LBC-33 QA: the PRD permission matrix row "Public content" (and the sermon library and public site rules) walked
-- cell by cell for every role, inactive staff, a signed-in user with no staff row and anon. Each cell is one
-- statement run as a real database role, undone afterwards, and compared with the outcome the PRD requires:
--   a number = rows returned or affected, 42501 = denied by grants, and an upper case word = the error message
--   raised by the workflow function.
-- Actor order in every row: super admin, pastor, treasurer, secretary, usher, department head, content editor,
-- inactive secretary, signed-in user with no staff row, anon.
-- Fixture: the demo seed (7 content items, 2 sermons) plus an approved in-review item and two in-review sermons.

begin;

select plan(360);

insert into auth.users (instance_id,id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 ('00000000-0000-0000-0000-000000000000','10000000-0000-4000-8000-000000000008','authenticated','authenticated','qa-isec@x.org',now(),now(),now()),
 ('00000000-0000-0000-0000-000000000000','10000000-0000-4000-8000-00000000000a','authenticated','authenticated','qa-ns@x.org',now(),now(),now());
insert into public.staff (id, full_name, is_active) values ('10000000-0000-4000-8000-000000000008','Inactive Sec', false);
insert into public.staff_roles (staff_id, role, department_id, granted_by) values
 ('10000000-0000-4000-8000-000000000008','secretary',null,'10000000-0000-4000-8000-000000000001');

insert into public.content_items (id, kind, title, status, publish_at, author_id, approved_by) values
 ('c1000000-0000-4000-8000-00000000000a','announcement','Approved and waiting','in_review',null,'10000000-0000-4000-8000-000000000007','10000000-0000-4000-8000-000000000002');
insert into public.sermons (id, title, preacher, preached_on, status, author_id, approved_by) values
 ('c2000000-0000-4000-8000-000000000003','Sermon in review','Demo Pastor','2026-10-05','in_review','10000000-0000-4000-8000-000000000007',null),
 ('c2000000-0000-4000-8000-000000000004','Sermon approved','Demo Pastor','2026-10-05','in_review','10000000-0000-4000-8000-000000000007','10000000-0000-4000-8000-000000000002');

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
 (9,'NoS','10000000-0000-4000-8000-00000000000a','authenticated'),
 (10,'Anon',null,'anon');
grant all on actors to public;

create function pg_temp.probe(p_sub uuid, p_role text, p_stmt text) returns text language plpgsql as $$
declare v text; n bigint;
begin
  begin
    perform set_config('request.jwt.claims', json_build_object('aal', 'aal2', 'role',p_role,'sub',p_sub)::text, true);
    perform set_config('role', p_role, true);
    execute p_stmt;
    get diagnostics n = row_count;
    v := n::text;
    raise exception using errcode='QAUND';
  exception when sqlstate 'QAUND' then null;
    when others then v := case when sqlstate = 'P0001' then sqlerrm else sqlstate end;
  end;
  return v;
end $$;

create temp table acts(ord int, name text, stmt text);
insert into acts values
(1,'R content all columns','select * from public.content_items'),
(2,'R content public columns','select id, kind, slug, title, body, image_path, publish_at, expires_at from public.content_items'),
(3,'R content status','select status from public.content_items'),
(4,'R content approved_by','select approved_by from public.content_items'),
(5,'R sermons all columns','select * from public.sermons'),
(6,'R sermons public columns','select id, title, preacher, preached_on, series, scripture, notes, video_url, audio_path, publish_at from public.sermons'),
(7,'R sermons author_id','select author_id from public.sermons'),
(8,'W insert own draft','insert into public.content_items(kind,title,author_id) values (''announcement'',''QA'',auth.uid())'),
(9,'W insert as another author','insert into public.content_items(kind,title,author_id) values (''announcement'',''QA'',''10000000-0000-4000-8000-000000000003'')'),
(10,'W insert published directly','insert into public.content_items(kind,title,author_id,status) values (''announcement'',''QA'',auth.uid(),''published'')'),
(11,'W insert own sermon draft','insert into public.sermons(title,preacher,preached_on,author_id) values (''QA'',''QA'',''2026-10-01'',auth.uid())'),
(12,'W update CE draft title','update public.content_items set title = ''QA2'' where id = ''c1000000-0000-4000-8000-000000000002'''),
(13,'W update in-review title','update public.content_items set title = ''QA2'' where id = ''c1000000-0000-4000-8000-000000000003'''),
(14,'W update status','update public.content_items set status = ''published'' where id = ''c1000000-0000-4000-8000-000000000002'''),
(15,'W update approved_by','update public.content_items set approved_by = auth.uid() where id = ''c1000000-0000-4000-8000-000000000002'''),
(16,'W update author_id','update public.content_items set author_id = auth.uid() where id = ''c1000000-0000-4000-8000-000000000002'''),
(17,'W delete content','delete from public.content_items'),
(18,'W delete sermons','delete from public.sermons'),
(19,'W update sermon draft title','update public.sermons set title = ''QA2'' where id = ''c2000000-0000-4000-8000-000000000002'''),
(20,'F approve content in review','select public.approve_content(''c1000000-0000-4000-8000-000000000003'')'),
(21,'F publish unapproved content','select public.publish_content(''c1000000-0000-4000-8000-000000000003'')'),
(22,'F publish approved content','select public.publish_content(''c1000000-0000-4000-8000-00000000000a'')'),
(23,'F submit CE draft','select public.submit_content_for_review(''c1000000-0000-4000-8000-000000000002'')'),
(24,'F return in-review to draft','select public.return_content_to_draft(''c1000000-0000-4000-8000-000000000003'')'),
(25,'F archive published content','select public.archive_content(''c1000000-0000-4000-8000-000000000001'')'),
(26,'F archive CE draft','select public.archive_content(''c1000000-0000-4000-8000-000000000002'')'),
(27,'F return published to draft','select public.return_content_to_draft(''c1000000-0000-4000-8000-000000000001'')'),
(28,'F approve sermon in review','select public.approve_sermon(''c2000000-0000-4000-8000-000000000003'')'),
(29,'F publish unapproved sermon','select public.publish_sermon(''c2000000-0000-4000-8000-000000000003'')'),
(30,'F publish approved sermon','select public.publish_sermon(''c2000000-0000-4000-8000-000000000004'')'),
(31,'F submit sermon draft','select public.submit_sermon_for_review(''c2000000-0000-4000-8000-000000000002'')'),
(32,'F archive published sermon','select public.archive_sermon(''c2000000-0000-4000-8000-000000000001'')'),
(33,'F approve a missing item','select public.approve_content(''c1000000-0000-4000-8000-0000000000ff'')'),
(34,'F publish a draft','select public.publish_content(''c1000000-0000-4000-8000-000000000002'')'),
(35,'R cron jobs','select * from cron.job'),
(36,'F run the expiry job','select private.archive_expired_content()');

create temp table expected (action text, outcomes text[]);
insert into expected values
('R content all columns', array['8','8','0','8','0','0','8','0','0','42501']),
('R content public columns', array['8','8','0','8','0','0','8','0','0','3']),
('R content status', array['8','8','0','8','0','0','8','0','0','42501']),
('R content approved_by', array['8','8','0','8','0','0','8','0','0','42501']),
('R sermons all columns', array['4','4','0','4','0','0','4','0','0','42501']),
('R sermons public columns', array['4','4','0','4','0','0','4','0','0','1']),
('R sermons author_id', array['4','4','0','4','0','0','4','0','0','42501']),
('W insert own draft', array['1','1','42501','1','42501','42501','1','42501','42501','42501']),
('W insert as another author', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W insert published directly', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W insert own sermon draft', array['1','1','42501','1','42501','42501','1','42501','42501','42501']),
('W update CE draft title', array['1','1','0','0','0','0','1','0','0','42501']),
('W update in-review title', array['0','0','0','0','0','0','0','0','0','42501']),
('W update status', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W update approved_by', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W update author_id', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W delete content', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W delete sermons', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('W update sermon draft title', array['1','1','0','0','0','0','1','0','0','42501']),
('F approve content in review', array['1','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('F publish unapproved content', array['1','1','AUTH_FORBIDDEN','CONTENT_NOT_APPROVED','AUTH_FORBIDDEN','AUTH_FORBIDDEN','CONTENT_NOT_APPROVED','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('F publish approved content', array['1','1','AUTH_FORBIDDEN','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('F submit CE draft', array['1','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('F return in-review to draft', array['1','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('F archive published content', array['1','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('F archive CE draft', array['1','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('F return published to draft', array['1','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('F approve sermon in review', array['1','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('F publish unapproved sermon', array['1','1','AUTH_FORBIDDEN','CONTENT_NOT_APPROVED','AUTH_FORBIDDEN','AUTH_FORBIDDEN','CONTENT_NOT_APPROVED','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('F publish approved sermon', array['1','1','AUTH_FORBIDDEN','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('F submit sermon draft', array['1','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('F archive published sermon', array['1','1','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('F approve a missing item', array['NOT_FOUND','NOT_FOUND','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('F publish a draft', array['VALIDATION_FAILED','VALIDATION_FAILED','AUTH_FORBIDDEN','VALIDATION_FAILED','AUTH_FORBIDDEN','AUTH_FORBIDDEN','VALIDATION_FAILED','AUTH_FORBIDDEN','AUTH_FORBIDDEN','42501']),
('R cron jobs', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']),
('F run the expiry job', array['42501','42501','42501','42501','42501','42501','42501','42501','42501','42501']);

select is(
  pg_temp.probe(actors.sub, actors.dbrole, acts.stmt),
  expected.outcomes[actors.ord],
  format('should give %s for "%s" when the actor is %s', expected.outcomes[actors.ord], acts.name, actors.label)
)
from acts
join expected on expected.action = acts.name
cross join actors
order by acts.ord, actors.ord;

select * from finish();

rollback;
