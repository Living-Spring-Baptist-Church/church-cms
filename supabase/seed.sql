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

-- Congregation fixture (LBC-26): a handful of fake people for manual testing and the seed sanity test.
-- The full demo congregation of about 300 members arrives with LBC-37. All names, numbers and addresses are invented.
insert into public.households (id, name, address)
values
  ('30000000-0000-4000-8000-000000000001', 'The Mensah Family', '12 Demo Street, Accra'),
  ('30000000-0000-4000-8000-000000000002', 'The Owusu Family', '7 Sample Road, Kumasi'),
  ('30000000-0000-4000-8000-000000000003', 'The Boateng Family', '3 Example Avenue, Takoradi');

insert into public.members (
  id, household_id, first_name, last_name, phone, email, date_of_birth, gender, marital_status, status,
  first_visit_on, joined_on, archived_at
)
values
  ('40000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 'Kwame', 'Mensah', '+233200000101', 'kwame.mensah@example.org', '1980-04-12', 'male', 'married', 'active', null, '2012-03-04', null),
  ('40000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', 'Ama', 'Mensah', '+233200000102', 'ama.mensah@example.org', '1983-09-03', 'female', 'married', 'active', null, '2012-03-04', null),
  ('40000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000001', 'Kofi', 'Mensah', null, null, '2014-06-20', 'male', null, 'active', null, '2014-07-06', null),
  ('40000000-0000-4000-8000-000000000004', '30000000-0000-4000-8000-000000000002', 'Esi', 'Owusu', '+233200000104', 'esi.owusu@example.org', '1990-01-25', 'female', 'single', 'active', null, '2018-05-13', null),
  ('40000000-0000-4000-8000-000000000005', '30000000-0000-4000-8000-000000000002', 'Yaw', 'Owusu', null, null, '2010-11-02', 'male', null, 'active', null, '2016-02-07', null),
  ('40000000-0000-4000-8000-000000000006', null, 'Abena', 'Asante', '+233200000106', 'abena.asante@example.org', '1995-02-14', 'female', 'single', 'visitor', '2026-09-27', null, null),
  ('40000000-0000-4000-8000-000000000007', '30000000-0000-4000-8000-000000000003', 'Kojo', 'Boateng', '+233200000107', 'kojo.boateng@example.org', '1975-08-30', 'male', 'married', 'inactive', null, '2005-01-09', null),
  ('40000000-0000-4000-8000-000000000008', null, 'Akosua', 'Darko', '+233200000108', 'akosua.darko@example.org', '1968-12-05', 'female', 'widowed', 'transferred', null, '2001-06-10', '2026-01-15 09:00:00+00');

-- Kojo Boateng belongs to two departments; Kofi Mensah is in the children's ministry, Yaw Owusu in Youth.
insert into public.member_departments (member_id, department_id)
values
  ('40000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000003'),
  ('40000000-0000-4000-8000-000000000004', '20000000-0000-4000-8000-000000000001'),
  ('40000000-0000-4000-8000-000000000005', '20000000-0000-4000-8000-000000000002'),
  ('40000000-0000-4000-8000-000000000007', '20000000-0000-4000-8000-000000000001'),
  ('40000000-0000-4000-8000-000000000007', '20000000-0000-4000-8000-000000000002');

insert into public.visitor_followups (id, member_id, assigned_to, status, notes, due_on)
values
  ('50000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000006', '10000000-0000-4000-8000-000000000004', 'pending', 'Demo follow-up: call after the first visit.', '2026-10-11');

-- Services and attendance fixture (LBC-31): fake and small. The recurring Sunday services are generated by
-- generate_recurring_services, so only a past Sunday, an upcoming one, a special service and a program event are
-- seeded here. The year of Sundays arrives with LBC-37.
insert into public.programs (id, name, description, department_id, lead_staff_id, starts_on, ends_on)
values
  ('b2000000-0000-4000-8000-000000000001', 'Children''s Holiday Programme', 'A demo week of games and Bible stories for children.', '20000000-0000-4000-8000-000000000003', null, '2026-12-19', '2026-12-23'),
  ('b2000000-0000-4000-8000-000000000002', 'Choir Anniversary Concert', 'A demo evening of songs by the choir.', '20000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000006', '2026-11-14', '2026-11-14');

insert into public.services (id, name, type, starts_at, program_id)
values
  ('b1000000-0000-4000-8000-000000000001', 'Sunday First Service', 'sunday', '2026-10-04 08:00:00+00', null),
  ('b1000000-0000-4000-8000-000000000002', 'Sunday Second Service', 'sunday', '2026-10-04 10:30:00+00', null),
  ('b1000000-0000-4000-8000-000000000003', 'Sunday First Service', 'sunday', '2026-10-11 08:00:00+00', null),
  ('b1000000-0000-4000-8000-000000000004', 'Harvest Thanksgiving Service', 'special', '2026-10-25 09:00:00+00', null),
  ('b1000000-0000-4000-8000-000000000005', 'Children''s Holiday Programme Opening', 'program', '2026-12-19 09:00:00+00', 'b2000000-0000-4000-8000-000000000001');

insert into public.attendance_counts (id, service_id, men, women, children, visitors, recorded_by)
values
  ('b3000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', 42, 58, 31, 4, '10000000-0000-4000-8000-000000000005');

insert into public.attendance_checkins (id, service_id, member_id, checked_in_by)
values
  ('b4000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000005');

-- Kofi Mensah is a minor in the children's ministry, so the children's programme shows how minors are protected.
insert into public.program_participants (id, program_id, member_id)
values
  ('b5000000-0000-4000-8000-000000000001', 'b2000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000003'),
  ('b5000000-0000-4000-8000-000000000002', 'b2000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000002');

-- Content fixture (LBC-33): fake and small. Dates are fixed far from now so the fixture behaves the same on every reset:
-- 2099 is "in the future" and 2025 is "already expired". The large demo content arrives with LBC-37.
-- Authored by the demo content editor, approved by the demo pastor.
insert into public.content_items (id, kind, slug, title, body, image_path, status, publish_at, expires_at, author_id, approved_by)
values
  ('c1000000-0000-4000-8000-000000000001', 'announcement', null, 'Harvest Thanksgiving Service', 'Join us for a demo service of thanksgiving. All are welcome.', null, 'published', '2026-09-01 00:00:00+00', '2099-01-01 00:00:00+00', '10000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000002'),
  ('c1000000-0000-4000-8000-000000000002', 'announcement', null, 'Draft: Youth Camp Registration', 'This demo draft is not ready yet.', null, 'draft', null, null, '10000000-0000-4000-8000-000000000007', null),
  ('c1000000-0000-4000-8000-000000000003', 'announcement', null, 'Waiting for review: Choir Rehearsal Change', 'This demo item is waiting for the pastor.', null, 'in_review', null, null, '10000000-0000-4000-8000-000000000007', null),
  ('c1000000-0000-4000-8000-000000000004', 'announcement', null, 'Scheduled: New Year Service', 'This demo announcement goes live in the future.', null, 'published', '2099-01-01 00:00:00+00', null, '10000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000002'),
  ('c1000000-0000-4000-8000-000000000005', 'announcement', null, 'Expired: Easter Rehearsal', 'This demo announcement ended long ago.', null, 'published', '2025-01-01 00:00:00+00', '2025-02-01 00:00:00+00', '10000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000002'),
  ('c1000000-0000-4000-8000-000000000006', 'quote', null, 'Psalm 23:1', 'The Lord is my shepherd; I shall not want.', null, 'published', '2026-09-28 00:00:00+00', null, '10000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000002'),
  ('c1000000-0000-4000-8000-000000000007', 'page', 'history', 'Our History', 'This demo page tells the story of the church.', null, 'published', '2026-01-01 00:00:00+00', null, '10000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000002');

insert into public.sermons (id, title, preacher, preached_on, series, scripture, notes, video_url, audio_path, status, publish_at, author_id, approved_by)
values
  ('c2000000-0000-4000-8000-000000000001', 'Walking in Faith', 'Demo Pastor', '2026-09-27', 'Faith Series', 'Hebrews 11:1', 'Demo notes: faith is confidence in what we hope for.', 'https://www.youtube.com/watch?v=demo0000000', 'sermons/walking-in-faith.mp3', 'published', '2026-09-28 00:00:00+00', '10000000-0000-4000-8000-000000000007', '10000000-0000-4000-8000-000000000002'),
  ('c2000000-0000-4000-8000-000000000002', 'Draft: Grace Upon Grace', 'Demo Pastor', '2026-10-04', 'Grace Series', 'John 1:16', null, null, null, 'draft', null, '10000000-0000-4000-8000-000000000007', null);
