# Church Management System: Architecture Decision Records

Sep 24, 2026 · @Kofi

## Index

Seven foundational decisions are proposed here; each becomes Accepted once the developer and church leadership sign off. An accepted ADR is never edited to change its decision: a new ADR supersedes it. Context: [PRD](https://claude.ai/code/artifact/222bd20d-dd30-4be4-a961-d4fe1278bcb8) · [System Architecture](https://claude.ai/code/artifact/870b2612-605e-4158-9368-61c6c1dcfe9d).

| ADR | Title | Status | Decision |
| --- | --- | --- | --- |
| ADR-001 | Build vs buy | Proposed | Build a custom system |
| ADR-002 | Language | Proposed | TypeScript (strict) everywhere |
| ADR-003 | Web framework | Proposed | Next.js App Router for both apps |
| ADR-004 | Backend platform | Proposed | Supabase: Postgres, Auth, Storage |
| ADR-008 | Hosting | Proposed | Vercel Hobby for the demo; church production use needs written confirmation from Vercel or Pro |
| ADR-015 | API layer | Proposed | GraphQL via pg\_graphql |
| ADR-016 | Paid services | Proposed | Free tiers for the demo; paid services behind adapters, switched on after church review |

ADR-005 to ADR-014, except ADR-008 (migrations, UI, forms, jobs, messaging, media, monitoring, testing, monorepo) are listed in the architecture doc and will be written before their phase starts.

## ADR-001: Build a custom system instead of buying a ChMS

**Status:** Proposed · **Date:** 24 Sep 2026 · **Deciders:** Developer, Senior Pastor, Church Administrator

**Context.** The church needs member, attendance, finance and communication management plus a public website (PRD). Ready-made church management products exist, such as Planning Center and ChurchSuite. They are mature, but priced per month (often in foreign currency), built around Western giving habits, and not designed for local payment methods like mobile money or local SMS gateways.

**Decision.** Build a custom system, in phases, on managed services (ADR-004) so the custom part stays small.

**Options considered**

| Option | For | Against |
| --- | --- | --- |
| Buy an existing ChMS | Ready now; vendor handles security and updates | Recurring cost; poor fit for local payments and SMS; data held by a foreign vendor; limited customisation |
| Spreadsheets + free tools | Near zero cost | No permissions, no audit trail, error-prone totals: the problem we're solving |
| **Build custom** | Fits church processes exactly; local integrations; church owns code and data; grows the developer's skills | One-developer risk; time to deliver; the church must fund hosting and maintenance |

**Consequences**

- The church takes on maintenance: a named backup developer and church-owned accounts are required (PRD risks).
- Delivery is phased; Phase 1 must ship before later phases start.
- If the build stalls or maintenance proves unaffordable, revisit this ADR. Data stays exportable (CSV) so migrating to a product later is possible.

**To confirm before accepting:** a one-hour trial of at least one existing product, and leadership agreement on the monthly hosting budget.

## ADR-002: TypeScript across the whole stack

**Status:** Proposed · **Date:** 24 Sep 2026 · **Deciders:** Developer

**Context.** One developer with frontend experience builds and maintains both apps, background jobs and API code. Bugs in finance and permission logic are costly and often silent (a wrong field name, a missing null check).

**Decision.** Use TypeScript in strict mode for all application code: both Next.js apps, shared packages and Supabase Edge Functions. Database types and GraphQL types are generated, never hand-written. SQL stays SQL for migrations, RLS policies and Postgres functions.

**Options considered**

| Option | For | Against |
| --- | --- | --- |
| **TypeScript (strict)** | Catches errors before runtime; one language front to back; generated types keep code and database in sync | Learning curve for advanced types; slightly slower to start |
| JavaScript | No setup, faster at first | Errors surface in production; refactors are risky |
| TypeScript frontend + another backend language (Python, Go) | Strong backend ecosystems | Two languages for one developer; types don't cross the boundary |

**Consequences**

- `strict: true`, no `any` without a comment explaining why; enforced by ESLint in CI.
- Types are generated from the database (Supabase CLI) and GraphQL schema (GraphQL Code Generator) on every schema change.
- Input from users is validated at runtime with Zod too, because types disappear once the code runs.

## ADR-003: Next.js (App Router) for the dashboard and the public site

**Status:** Proposed · **Date:** 24 Sep 2026 · **Deciders:** Developer

**Context.** We need a private, logged-in dashboard and a fast, shareable public website. The developer's strength is frontend React. Secrets (service keys, provider keys) must never reach the browser, and public pages must load fast on 4G phones and preview well on WhatsApp.

**Decision.** Build both apps with Next.js using the App Router, React Server Components and TypeScript, styled with Tailwind CSS v4 (latest stable, version pinned) and shadcn/ui. The dashboard renders per request behind auth; the public site uses static generation with on-demand revalidation when content is published.

**Options considered**

| Option | For | Against |
| --- | --- | --- |
| **Next.js (App Router)** | React skills carry over; server-side code keeps secrets private; static + dynamic pages in one framework; first-class Vercel hosting | Framework complexity (server vs client components, caching rules); frequent major releases |
| React SPA (Vite) + separate API | Simple mental model | No server rendering for the public site; secrets need a separate backend; worse SEO and link previews |
| Remix / React Router framework | Clean data loading, web standards | Smaller ecosystem; less hosting/tooling synergy with the rest of the stack |
| Astro for public site + React dashboard | Very fast public pages | Two frameworks for one developer; less shared code |

**Consequences**

- Pin Next.js, React and Tailwind to exact versions; upgrade deliberately on a branch, not automatically.
- Default to server components; mark client components only where interaction needs them.
- Tailwind v4 uses CSS-first configuration (`@theme` tokens) instead of `tailwind.config.js`; the shared theme lives in `packages/config` and both apps import it.
- Caching and revalidation rules get documented in System Design, since stale public content is the most likely bug.

## ADR-004: Supabase for database, auth and file storage

**Status:** Proposed · **Date:** 24 Sep 2026 · **Deciders:** Developer, Church Administrator (budget)

**Context.** The data is relational (members, households, departments, services, offerings, pledges) and financial, so it needs transactions, constraints and an audit trail. Staff need secure login with two-factor authentication. The developer has limited backend experience, so hand-building auth, backups and permission enforcement is the biggest risk in the project.

**Decision.** Use Supabase: managed Postgres with row-level security, Supabase Auth (email + password, TOTP two-factor), Supabase Storage for files, Edge Functions and pg\_cron for background jobs. The demo runs on the free plan with fake seed data only; moving to a paid plan with daily backups happens after church approval and before any real data is entered. Region: closest to the church that satisfies data-residency rules.

**Options considered**

| Option | For | Against |
| --- | --- | --- |
| **Supabase** | Real Postgres (portable, standard SQL); RLS enforces permissions in the database; auth, 2FA, storage, backups built in; local dev via CLI | Vendor dependency for auth and hosting; paid plan needed for production-grade backups; RLS must be written and tested carefully |
| Firebase | Mature, generous free tier | NoSQL fits financial and relational data poorly; no SQL constraints or joins; harder reporting |
| Custom backend (Node + Postgres on a VPS) | Full control | Developer must build auth, 2FA, backups, patching, security: the riskiest path for this team |
| Separate services (e.g. Neon + Clerk + S3) | Best-in-class parts | More vendors, bills and integration code to maintain |

**Consequences**

- All schema changes are SQL migrations in Git (ADR-005); nobody edits production tables through the dashboard UI.
- Every table has RLS enabled from creation; a CI check fails if a table lacks policies, and pgTAP tests cover each role.
- The service role key is used only by background jobs, never in either Next.js app.
- Exit path: Postgres can be dumped and moved to any Postgres host; auth users would need migrating, which is the main lock-in to accept.
- Budget: request the paid plan in the church review. Free-tier limits (limited backups, projects pause when idle, small database) are acceptable for the demo only.

## ADR-008: Vercel Hobby for the demo; church use needs confirmation or Pro

**Status:** Proposed (the church-use question is open and needs a human) · **Date:** 5 Oct 2026 · **Deciders:** Developer, Church Administrator (budget)

**Context.** Both apps need hosting with a preview deploy per pull request and no server to maintain (architecture doc). There is no budget before the church reviews the demo (ADR-016). Facts checked on vercel.com/docs/plans/hobby (page last updated 14 Sep 2026): the Hobby plan "is free and aimed at developers with personal projects, and small-scale applications", and its fair use guidelines "restrict users to non-commercial, personal use only". Vercel's documentation and search do not say whether a church or other non-profit organisation counts as personal use. Hobby also cannot connect a private repository owned by a GitHub organisation (API error 409: "The repository is private and owned by an organization, which is not supported on the Hobby plan. Upgrade to Pro to continue."). Hobby limits: 100 deployments per day, 200 projects, 100 GB fast data transfer, builds on 2 vCPUs, runtime logs kept 1 hour. Pro is $20 per developer seat per month.

**Decision.** Host the demo on Vercel Hobby: two projects, `lbc-dashboard` (root `apps/dashboard`) and `lbc-web` (root `apps/web`), connected to the GitHub repository. Every pull request gets a preview of each app, and `main` deploys the demo (fake seed data only, ADR-016). Make the repository public so Hobby can connect it. Hobby is acceptable for the demo. **It is not confirmed that the Hobby terms permit running the church's real system.** Before any real member or financial data is entered, the human must either get written confirmation from Vercel that a church on Hobby is permitted, or move both projects to Pro (or another host, which ADR-003 keeps possible because the apps are plain Next.js).

**Options considered**

| Option | For | Against |
| --- | --- | --- |
| **Vercel Hobby (demo only)** | Free; preview per pull request; first-class Next.js support | Personal, non-commercial terms; church use unverified; needs a public repository; low limits (100 deployments per day, 1 hour of logs) |
| Vercel Pro | Commercial use allowed; private organisation repositories; team features | $20 per developer seat per month; no budget before the review |
| Other host (Netlify, Cloudflare, a VPS) | Different terms or prices | Loses the zero-setup Next.js integration; more to run for one developer |

**Consequences**

- **Open question for the human:** ask Vercel (support or sales) whether a church or non-profit may use the Hobby plan for its production system. Record the answer here and move this ADR to Accepted or supersede it. Until then, treat the answer as unknown.
- The repository is public, so no secret and no real member, child or financial data may ever be committed, in code, tests, fixtures, screenshots or history (CLAUDE.md rules 7 and 8). The secret scan blocks merges, and `pnpm check:service-role-key` stops the Supabase service role key from reaching either app or Vercel.
- Branch protection on `main` works on the free GitHub plan because the repository is public (README, "Branch protection on `main`").
- The service role key is never added to either Vercel project. Environment variables are set per environment in Vercel, and previews use the demo database (README, "Deployment on Vercel").
- Both apps send security headers (HTTPS only, no framing) from one shared definition in `packages/config`.
- Hobby has no budget alerts, so watch the 100 deployments per day and data transfer limits during busy review weeks.
- Revisit when the church review decides on production hosting, or when Vercel answers the open question.

## ADR-015: GraphQL via Supabase pg\_graphql as the API layer

**Status:** Proposed · **Date:** 24 Sep 2026 · **Deciders:** Developer

**Context.** Two apps read the same data in different shapes: the dashboard needs nested views (a member with household, departments, attendance and giving history) and flexible report queries; the public site needs a few simple published-content queries. The developer wants one typed contract for both. The biggest risk with any API layer here is a permission gap that leaks member or finance data.

**Decision.** Use GraphQL through Supabase's built-in pg\_graphql extension. Reads use the generated schema. Writes that carry business rules (record offering, reverse entry, close month, approve expense) are Postgres functions exposed as mutations. Clients use GraphQL Code Generator for TypeScript types and typed documents. The client library is **urql** (`@urql/core`, with `@urql/next` added when a client component needs it), chosen in LBC-14. Server components and services call one `createGraphqlClient` per app, which sends the signed-in user's access token as the bearer and the anon key as `apikey`; the service role key is never given to it.

**Options considered**

| Option | For | Against |
| --- | --- | --- |
| **GraphQL via pg\_graphql** | Schema generated from the database; every query runs as the signed-in user so RLS applies; no resolver code to secure; typed end to end | Schema shape follows table design; complex logic must live in SQL functions; less control over naming |
| Client: urql | Small (about a fifth of Apollo's size), works in server components with plain `@urql/core`, document cache is enough for this app, `fetch` is injectable so the session token is added in one place | Smaller ecosystem than Apollo; normalised cache needs an extra package if ever required |
| Client: Apollo Client | Largest ecosystem, normalised cache built in | Heavier; its cache and hooks are built for client-side data, while this app reads on the server |
| Custom GraphQL server (GraphQL Yoga + Pothos in Next.js) | Full control over schema and resolvers | Every resolver must enforce permissions by hand; more code to test and maintain |
| REST / Supabase client + Server Actions | Simplest; fewest moving parts at this scale | No single typed contract for nested reads; developer prefers GraphQL for skill growth |

**Consequences**

- RLS remains the only source of truth for permissions; no permission logic in GraphQL clients.
- Production hardening: introspection off, query depth and size limits, persisted (allow-listed) queries for the public site.
- Finance rules live in Postgres functions with pgTAP tests, not in app code.
- The schema is exported from the local database as SDL into `graphql/schema.graphql` (`pnpm schema:export`) and committed. pg_graphql 1.6 only answers introspection when the schema comment sets `"introspection": true`; the export switches it on inside a rolled-back transaction, so the database and production setting are untouched.
- Operations are `.graphql` files under `graphql/`. `pnpm codegen` writes typed documents to `packages/db/src/generated/graphql.ts`, committed and marked do not edit. `pnpm codegen:check` fails when they are stale. LBC-15 wires it into `pnpm verify` and CI.
- Learning cost: GraphQL, codegen and client caching add setup time in Phase 1; budget a week for it.
- Revisit (supersede this ADR) if the generated schema blocks a needed feature; the fallback is a custom Yoga server calling the database as the signed-in user.

## ADR-016: Free tiers for the demo, paid services behind adapters

**Status:** Proposed · **Date:** 24 Sep 2026 · **Deciders:** Developer

**Context.** There is no budget until church leadership sees a working demo and reviews it. The plan still needs services that will cost money later: SMS, transactional email, online giving, a paid database plan with backups, possibly monitoring and a domain. The review will also change requirements, so the demo must be easy to refine.

**Decision.** Build the demo entirely on free tiers (Supabase free, Vercel free, YouTube, GitHub; see ADR-008 for the open question on Vercel free terms for church use) using fake seed data. Every paid capability is defined as a TypeScript interface in `packages/providers` (`SmsProvider`, `EmailProvider`, `PaymentProvider`, `Monitoring`) with a free demo implementation (an outbox table or console log). Paid modules are toggled by feature flags and shown as "coming soon" where not yet active.

**Options considered**

| Option | For | Against |
| --- | --- | --- |
| **Free tiers + adapters** | Zero cost now; paid services plug in later without rewriting features; demo shows the full shape of the system | Some features can't be shown working end to end (e.g. SMS delivery) |
| Leave paid features out entirely | Simplest demo | Retrofitting them later touches many files; leadership can't see the full vision |
| Use paid trials now | Everything works in the demo | Trials expire; risks surprise charges; commits the church before it has agreed |

**Consequences**

- No vendor SDK is imported outside `packages/providers`; a lint rule enforces it.
- Messages always go through a `message_outbox` table, so switching on a real gateway later is a worker change, not a feature change.
- No real member, child or financial data in the demo; it is fake data only.
- The church review produces a costed list of services to switch on; each gets its own ADR (ADR-010 messaging, and future ones for payments) before it goes live.

## Template for the next ADR

Copy this for ADR-005 onward. Keep each ADR under one page; if it needs more, the decision is probably two decisions. In the repo, each ADR also lives as `docs/adr/NNN-short-title.md`.

```markdown
## ADR-NNN: <Decision as a short statement>

**Status:** Proposed | Accepted | Superseded by ADR-XXX
**Date:** DD Mon YYYY · **Deciders:** <names/roles>

**Context.** What problem forces a decision now? Constraints, requirements (PRD IDs), risks.

**Decision.** What we will do, in one or two sentences.

**Options considered**
| Option | For | Against |
| --- | --- | --- |

**Consequences.** What becomes easier, what becomes harder, what we must now do, and when to revisit.
```
