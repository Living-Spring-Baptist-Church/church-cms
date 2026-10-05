# Living Spring Baptist Church: Church Management System

A pnpm + Turborepo monorepo with two Next.js App Router apps (the staff dashboard and the public website) and the shared packages they use. Read [`CLAUDE.md`](CLAUDE.md) before contributing, then [`docs/standards/frontend.md`](docs/standards/frontend.md) or [`docs/standards/backend.md`](docs/standards/backend.md).

## Workspaces

| Path                 | Package          | What it is                                                             |
| -------------------- | ---------------- | ---------------------------------------------------------------------- |
| `apps/dashboard`     | `@lbc/dashboard` | Staff app. Dev server on port 3000                                     |
| `apps/web`           | `@lbc/web`       | Public website. Dev server on port 3001                                |
| `packages/ui`        | `@lbc/ui`        | Shared UI kit (shadcn/ui primitives, brand assets)                     |
| `packages/config`    | `@lbc/config`    | Tailwind v4 theme (`theme.css`), ESLint, Prettier and tsconfig presets |
| `packages/db`        | `@lbc/db`        | Pinned Supabase CLI and generated database types                       |
| `packages/providers` | `@lbc/providers` | SMS, email, payment and monitoring adapters (stub, ADR-016)            |

The database lives in `supabase/` at the root, where the Supabase CLI requires it: `config.toml`, `migrations/`, pgTAP `tests/`, `seed.sql` and edge `functions/`.

## Prerequisites

- Node.js 24.19.0 or later
- pnpm 12.6.0 (`corepack enable` picks up the version pinned in `package.json`). Never use npm or yarn.
- Git
- Docker (Docker Desktop on Windows and macOS), running, for the local database
- Optional: [gitleaks](https://github.com/gitleaks/gitleaks) for the local secret scan. The pre-commit hook warns and skips the scan when it is not installed.

## Pinned versions

Every dependency is pinned to an exact version. ESLint is held at 9.x and TypeScript at 6.0.x because typescript-eslint supports TypeScript below 6.1 only and eslint-plugin-jsx-a11y does not support ESLint 10 yet. Check those peer ranges (`pnpm view <package> peerDependencies`) before bumping either.

The shadcn CLI is not a dependency; it runs through `pnpm dlx` at the version verified against this setup, **shadcn 4.21.0**. See `docs/standards/frontend.md` section 3 for the steps after `shadcn add`.

## Install

```sh
pnpm install
```

This also installs the Git hooks (Husky runs through the `prepare` script).

## Run

```sh
pnpm dev
```

Starts both apps: the dashboard at http://localhost:3000 and the public site at http://localhost:3001. To run one app only, use `pnpm --filter @lbc/dashboard dev` or `pnpm --filter @lbc/web dev`.

## Quality commands

| Command              | What it does                                                                           |
| -------------------- | -------------------------------------------------------------------------------------- |
| `pnpm lint`          | ESLint in every workspace plus the root scripts. Zero errors and zero warnings allowed |
| `pnpm typecheck`     | `tsc --noEmit` in every workspace (the apps generate Next.js route types first)        |
| `pnpm test`          | Vitest with v8 coverage (80% lines and branches in `packages/ui`)                      |
| `pnpm format`        | Prettier, writes changes                                                               |
| `pnpm format:check`  | Prettier, fails on any difference                                                      |
| `pnpm check:em-dash` | Fails if any tracked or new text file contains an em dash                              |
| `pnpm duplicates`    | jscpd: fails on any duplicated block of 100 or more tokens (`.jscpd.json`)             |
| `pnpm verify`        | Every gate above in order, plus the database and generated files checks (see below)    |
| `pnpm build`         | Production build of both apps                                                          |

### `pnpm verify`

One command, same locally and in CI. It stops at the first failure and runs, in order:

1. Static checks: `format:check`, `lint`, `check:em-dash`, `typecheck`, `test` (coverage), `duplicates`.
2. Database checks: `db:reset`, `db:test` (pgTAP, including the RLS and audit structure test), then `schema:export --require-database`.
3. `codegen:check`: the committed GraphQL schema and generated types must match what the migrations and `.graphql` files produce.

Local and CI differ only in when step 2 runs. In CI it always runs. Locally it runs when `supabase/` changed against `main` (or `origin/main`), or when you pass `pnpm verify --database`. It needs the local stack: run `pnpm db:start` first. `codegen:check` compares with Git, so after changing a migration, commit the regenerated `graphql/schema.graphql` and `packages/db/src/generated/` before expecting `verify` to pass.

## Database

The Supabase CLI is pinned in `packages/db` (**supabase 2.117.0**) and runs through these root scripts. Never install it globally or through npm.

| Command                       | What it does                                                       |
| ----------------------------- | ------------------------------------------------------------------ |
| `pnpm db:start`               | Starts local Postgres, Auth, Storage and the GraphQL API in Docker |
| `pnpm db:status`              | Prints the local URLs and keys                                     |
| `pnpm db:reset`               | Rebuilds the database from zero: every migration, then `seed.sql`  |
| `pnpm db:test`                | Runs the pgTAP tests in `supabase/tests`                           |
| `pnpm db:new <verb>_<object>` | Creates a timestamped migration, e.g. `pnpm db:new create_members` |
| `pnpm db:stop`                | Stops the local stack                                              |

First run: `pnpm db:start` (the first start downloads the Docker images and takes a few minutes), then copy `.env.example` to `.env.local` and fill it in from `pnpm db:status`. `.env.local` is gitignored; never commit keys.

### Hosted demo project (manual, one time)

The demo runs on the Supabase **free** plan with seed data only (ADR-004, ADR-016). A church account owner does this once:

1. Create a project at https://supabase.com/dashboard on the free plan, in the region closest to the church.
2. `pnpm --filter @lbc/db supabase login`, then `pnpm --filter @lbc/db supabase link --project-ref <project-ref>`.
3. `pnpm --filter @lbc/db supabase db push` to apply the migrations. Never enter real member data.
4. Put the project URL and anon key in the hosting provider's environment settings (LBC-16), never in Git.

To preview a production build locally, build first, then run `pnpm --filter @lbc/web exec next start --port 3001` (or the dashboard on 3000).

## GraphQL

Operations live in `graphql/queries/` and `graphql/mutations/` as `.graphql` files. The pg_graphql schema is exported to `graphql/schema.graphql`, and GraphQL Code Generator writes typed documents to `packages/db/src/generated/graphql.ts`. Both are committed and marked generated: never edit them by hand.

| Command              | What it does                                                                                            |
| -------------------- | ------------------------------------------------------------------------------------------------------- |
| `pnpm schema:export` | Refreshes `graphql/schema.graphql` from the running local database (`pnpm db:start` first)              |
| `pnpm codegen`       | Runs `schema:export`, then generates the types. Without Docker it keeps the committed schema            |
| `pnpm codegen:check` | Regenerates and fails if the generated files differ from Git. CI only: it fails on any uncommitted tree |

`pnpm verify` runs `pnpm codegen:check` (see Quality commands). For full coverage of "CI fails if generated types are out of date", CI runs, in order: `supabase db reset`, `pnpm schema:export --require-database` (fails instead of skipping when the database is down), then `pnpm codegen:check`. That catches both a schema that drifted from the migrations and types that drifted from the schema.

The export runs the introspection query inside Postgres as the `anon` role (`docker exec psql` and `graphql.resolve()`). It needs no API key, and the service role key is never used. It turns pg_graphql introspection on inside a transaction that is rolled back, because introspection is off by default.

The client is urql (ADR-015). `apps/dashboard/src/config/graphql-client.ts` sends the signed-in user's access token as the bearer and the anon key as `apikey`.

## Continuous integration

`.github/workflows/ci.yml` runs on every pull request and on every push to `main`. It uses free GitHub-hosted `ubuntu-latest` runners only, needs no secrets, and cancels a superseded run when a pull request gets a new push. Actions are pinned by commit SHA (the release tag is in the comment); bump them by hand. Node is pinned to major 24 in the workflow, because `engines` (`>=24.19.0`) would otherwise float to Node 26. pnpm comes from the `packageManager` field through Corepack, and the Supabase CLI is the one pinned in `packages/db`. CI starts only the database container (`supabase start -x ...`) because pgTAP and the schema export need nothing else.

| Job (status check name) | What it runs                                                                                                  | Required |
| ----------------------- | ------------------------------------------------------------------------------------------------------------- | -------- |
| `Verify`                | Install, then `pnpm verify`: format, lint, em dashes, types, tests, duplicates, pgTAP, schema export, codegen | Yes      |
| `Secret scan`           | gitleaks 8.30.1 (binary, checksum verified) over the full Git history, zero findings allowed                  | Yes      |
| `Dependency audit`      | `pnpm audit --prod`. Reports only (`continue-on-error`), so a new advisory cannot block unrelated work        | No       |

The `gitleaks-action` is not used: it needs a paid license key for organisation repositories.

### RLS and audit structure check

`supabase/tests/structure/public-tables-security.test.sql` runs inside `pnpm db:test`, locally and in CI. It fails if any table in `public` has row level security disabled (`RLS_DISABLED`), has no policy (`NO_POLICIES`) or has no enabled audit trigger (`NO_AUDIT_TRIGGER`). A table counts as audited when it has an enabled trigger that runs `audit.record_change()`. That function does not exist yet, so the audit part is off and turns itself on the moment `audit.record_change()` is created; no edit is needed. The same file proves each failure with probe tables that are rolled back.

### Branch protection on `main` (a repository setting, applied once by the tech lead)

Branch protection is not part of the workflow file. Apply it with an admin token, once the `CI` workflow has run at least once so the check names exist:

```sh
gh api --method PUT repos/Living-Spring-Baptist-Church/church-cms/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": { "strict": true, "checks": [{ "context": "Verify" }, { "context": "Secret scan" }] },
  "enforce_admins": true,
  "required_pull_request_reviews": { "required_approving_review_count": 1, "dismiss_stale_reviews": true },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```

This requires a pull request with one approval, requires `Verify` and `Secret scan` to pass on an up-to-date branch, applies to admins too, and blocks direct pushes, force pushes and deletion. Renaming a job in `ci.yml` changes its check name and must be matched here. GitHub only offers branch protection on private repositories on a paid plan; on the free plan the repository must be public, or a repository ruleset on a public repository is needed.

## Git hooks

Installed by Husky on `pnpm install`.

| Hook         | Checks                                                                                                                                                                                                                                                                    |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pre-commit` | lint-staged (ESLint and Prettier on staged files), the em dash check on staged files, gitleaks on staged changes when installed                                                                                                                                           |
| `commit-msg` | commitlint: Conventional Commits, header at most 72 characters                                                                                                                                                                                                            |
| `pre-push`   | Each pushed branch matches `<type>/LBC-<n>-<short-description>` (types: feat, fix, chore, docs, refactor, test, perf, hotfix, release) or is `dev`, `staging` or `production`. Pushes to `main` are rejected; it changes only through pull requests. Tags are not checked |

To check the current branch name by hand, run `node scripts/check-branch-name.mjs < /dev/null`. In Git Bash the redirect is needed, otherwise the script waits for the ref list git would normally pipe in.

## Styling

Both apps import `@lbc/config/theme.css` from their `src/app/globals.css`. It holds the church palette, the semantic light and dark tokens and the base layer. There is no `tailwind.config.js`. `theme.css` has the `@source` line for `packages/ui/src`, so the UI kit classes are generated in both apps.
