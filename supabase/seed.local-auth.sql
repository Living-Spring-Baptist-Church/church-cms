-- LOCAL DEVELOPMENT ONLY. Never load this file into the hosted demo or any shared project.
-- It gives the seeded demo staff a known, public password so that sign in can be tried locally.
-- The repository is public: this password protects nothing and must never be reused anywhere.
-- It meets the local password policy (12+ characters, upper, lower and digits).
-- Run it with `pnpm db:seed-local-auth` after `pnpm db:reset`. It is NOT in [db.seed] sql_paths on purpose,
-- so `supabase db push --include-seed` and any hosted reset can never load it.
--
-- Sign in as any seeded staff email (super-admin@demo.church, pastor@demo.church, ...) with the
-- password below. Super admin, pastor and treasurer are walked through authenticator app setup.

update auth.users
set
  encrypted_password = extensions.crypt('Dev-Only-Passw0rd', extensions.gen_salt('bf')),
  email_confirmed_at = coalesce(email_confirmed_at, now()),
  raw_app_meta_data = '{"provider": "email", "providers": ["email"]}'::jsonb,
  raw_user_meta_data = '{}'::jsonb,
  -- GoTrue scans these columns into plain strings and fails on NULL, so they must be empty strings.
  confirmation_token = '',
  recovery_token = '',
  email_change = '',
  email_change_token_new = '',
  email_change_token_current = '',
  phone_change = '',
  phone_change_token = '',
  reauthentication_token = '',
  email_change_confirm_status = 0
where email like '%@demo.church';

insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
select
  gen_random_uuid(),
  id,
  id::text,
  'email',
  jsonb_build_object('sub', id::text, 'email', email, 'email_verified', true, 'phone_verified', false),
  now(),
  now(),
  now()
from auth.users
where email like '%@demo.church'
  and not exists (
    select 1 from auth.identities where identities.user_id = users.id and identities.provider = 'email'
  );
