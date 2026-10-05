# CLAUDE.md: Living Spring Baptist Church, Church Management System

Every agent and every human contributor reads this file before touching the code.

**Prime directive:** never invent an architecture, a library or an API on the spot. Search the codebase first and reuse or extend what is there. If something is genuinely ambiguous, stop and ask.

This file holds the rules that apply everywhere. The detailed rules for each side live in:

- `docs/standards/frontend.md`: Next.js apps, UI kit, styling, accessibility, client data flow
- `docs/standards/backend.md`: Postgres, RLS, SQL functions, migrations, edge functions

Product and design sources of truth: `docs/prd.md`, `docs/architecture.md`, `docs/adr/`, `docs/system-design.md`. If code and docs disagree, stop and flag it. Never silently pick one.

---

## 1. Project setup

| Item | Value |
|---|---|
| Project | Church Management System (staff dashboard + public website) |
| Jira | Project `LBC` (tickets like `LBC-12`) |
| Repo shape | pnpm + Turborepo monorepo |
| Language | TypeScript, `strict: true`, everywhere (SQL for the database) |
| Apps | Next.js App Router: `apps/dashboard` (staff), `apps/web` (public) |
| Styling | Tailwind CSS v4, CSS-first `@theme` tokens in `packages/config`, shadcn/ui |
| Backend | Supabase: Postgres + RLS, Auth (TOTP 2FA), Storage, Edge Functions, pg_cron |
| API | GraphQL via pg_graphql; business rules in Postgres functions |
| Tests | Vitest (unit/component), Playwright (end to end), pgTAP (database) |
| Package manager | pnpm only. One lockfile (`pnpm-lock.yaml`). Never npm or yarn. |
| Brand palette | Defined in `packages/config/theme.css`. See `docs/standards/frontend.md` §4 |
| Verify command | `pnpm verify` (see §6) |

Pinned versions: do not upgrade Next.js, React, Tailwind, Supabase CLI or any major dependency without an ADR.

### Repository layout

```
apps/
  dashboard/          staff app (private, login + 2FA)
  web/                public website (anonymous, published content only)
packages/
  ui/                 the shared UI kit (@lbc/ui)
  config/             Tailwind v4 theme, ESLint, Prettier, tsconfig (@lbc/config)
  db/                 pinned Supabase CLI, db:* scripts, generated types (@lbc/db)
  providers/          SMS / email / payment / monitoring adapters (@lbc/providers)
supabase/
  config.toml         local Supabase stack
  migrations/         SQL migrations: schema, RLS, functions
  tests/              pgTAP tests
  seed.sql            fake demo data only
  functions/          edge functions (background jobs)
docs/
  standards/          frontend.md, backend.md
  adr/                architecture decision records
```

Frontend and backend communicate only through the GraphQL contract. Apps never import SQL or database internals; `packages/db` exposes only generated types.

---

## 2. Non-negotiable rules

1. **Security lives in the database.** Every table has RLS enabled in the migration that creates it. Hiding a button is not a permission check.
2. **Money is `amount_minor bigint`** (pesewas) plus `currency`. Never floats, never formatted strings in logic.
3. **The ledger is append-only.** No UPDATE or DELETE on `ledger_entries`. Corrections are reversal entries. Closed periods reject inserts.
4. **Every business table has the audit trigger.** App code never writes `audit.log`.
5. **The public site reads published content only**, through persisted queries, as the anonymous role.
6. **No vendor SDK outside `packages/providers`.** Paid services go through adapters; demo adapters never call a paid service (ADR-016).
7. **No real data** outside production. Seed data only. Never paste real member, child or financial data into code, tests, fixtures, screenshots or AI prompts.
8. **No secrets in Git.** `.env` is gitignored; `.env.example` lists every variable with dummy values. The service role key exists only in edge functions.
9. **Migrations are forward-only.** Never edit a migration that has run outside your own machine.
10. **Never use em dashes** (the long dash) anywhere: UI copy, code, comments, commit messages, docs. Rewrite with a period, comma, colon or "and".

---

## 3. How work flows

Work happens one Jira ticket at a time, one vertical slice at a time (UI + logic + data working end to end), never a big unverified scaffold.

```
ticket -> worker builds -> reviewer: APPROVE or REQUEST_CHANGES -> loop (max 3 rounds)
       -> qa-engineer: PASS or FAIL -> human reviews and merges the PR
```

- `frontend-worker` is reviewed by `frontend-reviewer`; `backend-worker` by `backend-reviewer`.
- A ticket touching both sides runs backend first (schema, RLS, API), then frontend.
- Reviewers never edit code. Workers never approve their own work. Agents never merge.
- Plan before code: list the files to touch and confirm they match the ticket.
- Report honestly: say what was verified (tests passed, build green, checked in browser) and what was written but not yet confirmed.
- Run it: `/ship-ticket LBC-<n>`.

---

## 4. Rules that apply to both sides

**Reuse before create.** Search `packages/ui`, `core/`, `helpers/` and existing SQL functions before writing anything new. If something similar exists, extend it (a new variant, a new option, a new parameter) instead of writing a parallel version. See the Shared Component Extension Rule in `docs/standards/frontend.md` §3.

**DRY and KISS.** Logic exists in exactly one place; the second copy-paste is the signal to extract. Pick the simplest implementation that meets the requirement; no speculative abstractions. Three similar lines beat a premature abstraction.

**Naming.**
- Names describe purpose: `selectedMemberId`, `filteredServices`, `calculatePledgeBalance()`. Never `data`, `item`, `temp`, `value`, `x`.
- Booleans are yes/no questions: `isLoading`, `hasError`, `canApprove`.
- Functions are verbs (`fetchMembers`, `recordOffering`); types and components are nouns (`MemberProfile`, `LedgerEntry`).
- Global fixed constants are `SCREAMING_SNAKE_CASE` (`DEFAULT_PAGE_SIZE`). No abbreviations (`usr`, `cfg`, `btn`).
- TypeScript: `camelCase` values, `PascalCase` types/components, `kebab-case` files and folders. SQL: `snake_case` everything.

**No magic values.** No unexplained numbers or repeated string literals in logic. Numbers other than -1, 0, 1, 2 become named constants. Route paths, role names, error codes, storage keys and feature flag keys are constants. User-facing text lives in per-domain copy files (ready for a second language later).

**Size and focus.**
- One file, one job. Functions at most 80 lines, cyclomatic complexity at most 10, at most 3 positional parameters (use an options object beyond that), files at most 400 lines.
- A file that is hard to scan in one pass is the signal to split it now, not later.

**Types.** No `any`. No `unknown` where the real shape is knowable. Prefer `readonly` and immutable data. GraphQL and database types are generated, never hand-written or hand-edited.

**Comments.** Default to none; good names should make code readable. A comment is one line explaining *why* (a business rule, a workaround), never *what*. No commented-out code, no TODO essays. Exception: `comment on` statements in SQL, because pg_graphql turns them into API documentation.

**Errors.** One global error handler per side (see each standards doc). Never swallow an error silently; never show users a raw error, stack trace or database message. Every error has a code, a plain actionable message and a logged technical detail.

**Logging.** A real logger with levels (`debug`, `info`, `warn`, `error`), no stray `console.log`. Never log secrets, tokens or personal data. Carry a request ID through a request's full path.

**Dependencies.** Don't add a package for what a few lines can do. Before adding one, check it is maintained, reasonably small and not already covered. `pnpm audit` must be clean before release. Remove unused packages.

**Performance.** Lazy-load routes, paginate every list that can grow, never introduce N+1 queries, measure before optimizing.

**Environment.** Behaviour that differs by environment comes from configuration, never `if (isProduction)` branches in business logic. Same code path in dev, staging and production.

---

## 5. Git

**Branches:** `<type>/<ticket>-<short-description>`, e.g. `feat/LBC-27-member-search`. Types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `perf`, `hotfix`, `release`.

**Commits:** Conventional Commits, `type(scope): message`, imperative, at most 72 characters, no em dashes, type must match what the commit actually does.
- `feat(members): add visitor to member conversion (LBC-29)`
- `fix(attendance): reject negative headcounts`
- `chore(deps): bump next to 15.x`

One logical change per commit. Every commit builds and passes tests. Review what is staged before committing; never stage secrets, generated files or build output.

**Pre-commit hooks** (Husky, set up in LBC-12/LBC-15): Prettier + ESLint on staged files (lint-staged), secret scanning (gitleaks), em dash check, commit message check (commitlint), branch name check on push.

**Pull requests:** title says what changed, description links the Jira ticket, lists what was verified, and includes screenshots for UI changes at mobile and desktop widths.

---

## 6. Quality gates

`pnpm verify` runs, in order: format check, lint, em dash check, typecheck, unit tests with coverage, duplicate detection, and (when the database changed) `supabase db reset && supabase test db`. CI runs the same command on every pull request; a red pipeline blocks the merge.

| Gate | Tool | Threshold |
|---|---|---|
| Format | Prettier | No diff |
| Lint | ESLint (shared config in `packages/config`) | Zero errors, zero warnings |
| Complexity | ESLint `complexity`, `max-lines-per-function`, `max-lines`, `max-params` | 10 / 80 / 400 / 3 |
| Magic numbers | ESLint `no-magic-numbers` | Allowed: -1, 0, 1, 2 (relaxed in tests) |
| Accessibility | `eslint-plugin-jsx-a11y` + axe in Playwright | Zero violations |
| Types | `tsc --noEmit` | Zero errors |
| Unit coverage | Vitest (v8) | 80% lines and 80% branches for `helpers/`, `core/services/`, `packages/ui`, `packages/providers` |
| Database | pgTAP | Every RLS policy and finance rule has allowed and denied tests |
| Duplication | jscpd | No duplicated block of 100+ tokens |
| Secrets | gitleaks | Zero findings |
| Dependencies | `pnpm audit --prod` | No high or critical vulnerabilities |

Coverage excludes: route files (`app/**/page.tsx`, `layout.tsx`), generated types, config files, and pure presentational wrappers with no logic.

---

## 7. Definition of done

- Acceptance criteria met and each one proven by a test
- `pnpm verify` passes locally and in CI
- Loading (skeleton), empty and error states exist for every data screen
- Works at 375px, tablet and desktop; keyboard usable; axe clean
- New tables have RLS, policies, audit trigger and pgTAP tests
- Reviewer verdict APPROVE, QA verdict PASS
- Docs, `.env.example` and README updated if behaviour, schema, setup or variables changed

---

## 8. Before marking any task done

- [ ] Searched for existing code first; extended rather than duplicated
- [ ] Code is in the correct layer (see the standards docs); imports use path aliases
- [ ] Names are descriptive; no magic numbers or repeated literals
- [ ] No file or function over the size limits
- [ ] No `any`, no hand-edited generated files
- [ ] No em dashes in code, copy, comments or commit messages
- [ ] Errors go through the global handler; users see plain messages only
- [ ] No secrets, real data or debug logging committed
- [ ] Tests cover normal, edge and error cases (and both allowed and denied for permissions)
- [ ] `pnpm verify` actually run and green
