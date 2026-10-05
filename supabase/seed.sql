-- Demo seed data: fake and deterministic, never real people (CLAUDE.md §2 rule 7).
-- Fixed random seed so every `supabase db reset` produces the same demo data.
select setseed(0.2026);

-- Identity: one staff account per role (system design, "Migrations, seed data & testing").
-- The auth users have no password, so nobody can sign in with them yet; sign-in arrives with the auth work.
insert into auth.users (instance_id, id, aud, role, email, email_confirmed_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'super-admin@demo.church', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'pastor@demo.church', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'treasurer@demo.church', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'secretary@demo.church', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'usher@demo.church', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'department-head@demo.church', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', '10000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'content-editor@demo.church', now(), now(), now());

insert into public.departments (id, name, is_childrens_ministry)
values
  ('20000000-0000-4000-8000-000000000001', 'Choir', false),
  ('20000000-0000-4000-8000-000000000002', 'Youth', false),
  ('20000000-0000-4000-8000-000000000003', 'Children''s Ministry', true);

insert into public.staff (id, full_name)
values
  ('10000000-0000-4000-8000-000000000001', 'Demo Super Admin'),
  ('10000000-0000-4000-8000-000000000002', 'Demo Pastor'),
  ('10000000-0000-4000-8000-000000000003', 'Demo Treasurer'),
  ('10000000-0000-4000-8000-000000000004', 'Demo Secretary'),
  ('10000000-0000-4000-8000-000000000005', 'Demo Usher'),
  ('10000000-0000-4000-8000-000000000006', 'Demo Department Head'),
  ('10000000-0000-4000-8000-000000000007', 'Demo Content Editor');

-- The first super admin has no granter; every other role is granted by that super admin.
insert into public.staff_roles (staff_id, role, department_id, granted_by)
values
  ('10000000-0000-4000-8000-000000000001', 'super_admin', null, null),
  ('10000000-0000-4000-8000-000000000002', 'pastor', null, '10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000003', 'treasurer', null, '10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000004', 'secretary', null, '10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000005', 'usher', null, '10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000006', 'department_head', '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000001'),
  ('10000000-0000-4000-8000-000000000007', 'content_editor', null, '10000000-0000-4000-8000-000000000001');
