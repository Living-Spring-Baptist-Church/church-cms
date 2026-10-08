# Go-live checklist

Everything here must be true **before any real member, child or financial data is entered**. The hosted demo runs on free plans with dummy data only (ADR-008, ADR-016, [decisions](decisions.md)). The repository is public: tick items in the pull request or ticket that does the work, and never commit secrets or real data.

**Owner** means the church account owner does it in a dashboard. **Dev** means a ticket or code change.

## Accounts and plans

- [ ] **Vercel plan (ADR-008, Owner).** Upgrade `lbc-dashboard` and `lbc-web` to Pro, or get written confirmation from Vercel that a church may run its production system on Hobby. Record the answer in ADR-008.
- [ ] **Paid Supabase plan with daily backups (ADR-004, Owner).** The free plan is for the demo only.
- [ ] Vercel, Supabase and GitHub accounts are owned by the church, with a named backup developer (ADR-001).

## Supabase

- [ ] **Hosted Auth settings (Owner, Supabase dashboard).** Set and check each one:
  - [ ] Sign-up (self registration) is off
  - [ ] Email provider is on, and no other provider is enabled
  - [ ] Two-factor (TOTP) is on
  - [ ] Strong password policy (minimum length and character classes)
  - [ ] Refresh token rotation is on
  - [ ] JWT expiry is set deliberately (short)
  - [ ] Auth rate limits are reviewed (sign-in, token refresh, email)
- [x] **Database-side two-factor (aal2) enforcement is done (Dev, LBC-41).** Done in migration `20261008090000_enforce_mfa_for_privileged_roles.sql`: super admin, pastor and treasurer hold no role in the database below aal2. Before real data, re-check on the hosted project that `private.mfa_required_roles()` matches the PRD and that the hosted access token carries the `aal` claim (sign in as a pastor without a code and confirm `membersCollection` returns nothing).
- [ ] **First enrolment is done with the person present (Owner).** The first sign in of each super admin, pastor and treasurer account is protected only by its password, because there is no authenticator yet (after that, GoTrue refuses a second one without a code). Create each of these accounts, enrol its authenticator with the person present, and only then enter real data. The same applies when a role that requires two-factor is granted to an existing person who has none: they can enrol their own authenticator at password-only level, so do it together.
- [ ] **Token lifetime reviewed (Owner).** Role changes and deactivation take effect at once, but signing out or removing an authenticator does not revoke an access token already issued: it works until it expires (`jwt_expiry`, 3600 s by default). Choose the expiry deliberately and accept or shorten that window.
- [ ] **Hosted `pg_cron` job verified.** `cron.job` lists the content expiry job and `cron.job_run_details` shows successful runs on the hosted project.
- [ ] `pg_cron` run history is purged on a schedule so `cron.job_run_details` does not grow without limit.
- [ ] **REST exposure.** PostgREST exposes `public` with `max_rows` 1000: confirm `max_rows` is deliberate. The `private` and `audit` schemas stay out of the exposed schemas.
- [ ] Migrations on the hosted project match `supabase/migrations` on `main` (applied with `db push`, never edited in the dashboard).

## Vercel and domain

- [ ] **Real church domain** chosen and attached to `lbc-web` (public site) and `lbc-dashboard` (staff app, for example a subdomain).
- [ ] **HSTS preload decision recorded.** The apps send `max-age=63072000; includeSubDomains` without `preload` (README, "Security headers"). Preload only once every subdomain of the domain serves HTTPS.
- [ ] Environment variables are set per environment. Production points at the production Supabase project; Preview does not (demo project or none).
- [ ] CSP follow-up reviewed: nonce based `script-src` and `connect-src` (README, "Security headers").
- [ ] Terms and Privacy pages exist and are linked from the public site footer.

## Security

- [ ] **Service role key only in edge functions.** It is not in any Vercel environment, any file in Git or either app. Check the Vercel environment pages by hand; `pnpm check:service-role-key` cannot see them.
- [ ] **The dev-only seed password is never loaded.** `pnpm db:seed-local-auth` and `supabase/seed.local-auth.sql` are local only; the hosted project must never run them.
- [ ] **Persisted queries for the public site.** Anonymous GraphQL has no query cost limit today, so the public site uses persisted (allow-listed) queries and introspection is off in production (ADR-015).
- [ ] **gitleaks clean:** the "Secret scan" check is green on `main`, and a full history scan has been run once.
- [ ] **`pnpm audit --prod` clean:** no high or critical findings.
- [ ] Branch protection on `main` still requires a pull request and the `Verify` and `Secret scan` checks (README).
- [ ] Known gaps reviewed, each fixed or accepted in writing:
  - [ ] Failed sign-ins are not audited
  - [ ] No password reset and no authenticator recovery codes: define the support procedure for a lost phone
  - [ ] The per-IP auth rate limit sees the server IP when sign-in goes through the Next.js server, so it limits all users together
  - [ ] Session revocation when staff are deactivated (LBC-19)

## Data and privacy

- [ ] **Demo data removed.** The production project is created fresh or reset, so no seed rows or demo staff accounts remain.
- [ ] Data protection consent wording agreed with the church and stored with `consent_recorded_at`.
- [ ] **Retention** decided: finance audit rows are kept 7 years.
- [ ] **Anonymisation procedure for `audit.log` defined.** It does not exist yet and needs a migration, so a member can be erased without breaking the audit trail.
- [ ] Children's records rules in place (LBC-42): only the allowed roles create and edit (super admin, the secretary and the children's ministry heads, only for children of a children's ministry department), every change is audit logged, ushers never see children's names. Tested by `supabase/tests/members/childrens-records-access.test.sql`.
- [ ] Visitor rule works: with no birth date and no "adult confirmed" tick, the visitor is treated as a minor (LBC-42). Check with the church that the registration form asks for one of the two.

## Operations

- [ ] **Backups and a restore test.** Daily backups are on, and a restore into a scratch project has been tried once and timed.
- [ ] **ADR-016 holds:** demo adapters never call paid services. Real providers (SMS, email, payments) are switched on only through their own ADRs after church review.
- [ ] Error monitoring and a contact for incidents agreed (`Monitoring` adapter).
- [ ] At least two super admin accounts, both with two-factor enrolled.

## Product follow-ups

- [ ] **ADR statuses updated.** ADR-004, ADR-008, ADR-015 and ADR-016 move from Proposed or "Accepted for the demo" to Accepted (or superseded) after sign-off ([ADR index](adr/README.md)).
- [ ] Department heads are read-only for now: revisit with the church.
- [ ] Secretary access to children's records is settled (LBC-42, option d: she is treated like a children's ministry head). Confirm with the church: which departments are flagged as children's ministry, that the secretary also sees those children's check-ins and follow-ups, and that she sees a household only when it is empty or holds someone she may see.
- [ ] Ushers edit attendance within 7 days; later edits only by the secretary or super admin; all in the audit log (LBC-43).
- [ ] Self-approval is allowed, logged and shown as "self-approved" (LBC-44); decide whether to switch it off for production.
- [ ] Service times come from the `service_times` table (LBC-45).
