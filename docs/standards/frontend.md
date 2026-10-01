# Frontend Standards

Applies to `apps/dashboard`, `apps/web` and `packages/ui`. Read `CLAUDE.md` first; this document adds the frontend detail.

Part I (§1 to §9) describes where things live and how they fit together. Part II (§10 to §17) is mandatory behaviour.

---

# Part I: Architecture

## 1. Stack

- **Next.js App Router** with React Server Components by default. `"use client"` only where interaction needs it, pushed as low in the tree as possible.
- **TypeScript strict.** No `any`.
- **Tailwind CSS v4**, CSS-first configuration. Tokens live in `packages/config/theme.css` inside `@theme { }`. There is no `tailwind.config.js`.
- **shadcn/ui** as the base for primitives in `packages/ui`. Variants use `cva`, the one variant mechanism in the codebase (it ships with shadcn). Never invent a second one.
- **Forms:** React Hook Form + Zod. The same Zod schema validates in the browser and in the server action.
- **Data:** GraphQL (pg_graphql) with typed documents from GraphQL Code Generator. The client library is decided in LBC-14 and recorded in ADR-015.
- **Tests:** Vitest + Testing Library (colocated), Playwright + axe (end to end).

## 2. App structure

Both apps follow the same shape. `apps/web` is smaller (no auth, no server actions for staff data).

```
apps/dashboard/src/
  app/                               routing layer only (Next App Router)
    (auth)/login/page.tsx
    (dashboard)/layout.tsx           wraps pages in <AppShell>
    (dashboard)/members/page.tsx     thin: fetch via service, compose components
    (dashboard)/members/loading.tsx  skeleton matching the page layout
    error.tsx  global-error.tsx  not-found.tsx
  features/<domain>/                 feature-local UI only
    components/
      index.ts                       barrel
      <component-name>/
        <component-name>.tsx
        <component-name>.test.tsx
  core/                              everything that is not page UI, centralized by domain
    types/<domain>.types.ts          hand-written view models (DB/GraphQL types are generated)
    data/<domain>.data.ts            dropdown options, table columns, nav config, badge maps
    copy/<domain>.copy.ts            user-facing strings for that domain
    schemas/<domain>.schema.ts       Zod schemas shared by forms and server actions
    services/<domain>/
      <domain>.service.ts            server-only reads (called from pages)
      <domain>.actions.ts            server actions (writes, called from client forms)
    auth/                            session helpers, requireRole(), role groups
    errors/                          AppError, error classification, error-messages.data.ts
  graphql/
    queries/<domain>.queries.ts      typed documents, one file per domain
    mutations/<domain>.mutations.ts
  config/
    graphql-client.ts                the one GraphQL client (auth header + error handling)
    env.ts                           environment variables validated with Zod at startup
  helpers/<domain>.utils.ts          pure functions (dates, money, pagination, strings)
  middleware.ts                      redirects unauthenticated users to /login
```

**Centralize by domain, never nest per feature.** A `features/<domain>/` folder contains only components and their tests. It never grows its own `types/`, `data/`, `services/`, `schemas/` or `utils/` folders; those belong in `core/` and `helpers/`, grouped by the same domain names everywhere (`members`, `attendance`, `content`, `finance`, `settings`, `audit`).

### Path aliases

Configured in each app's `tsconfig.json` and mirrored in Vitest config:

```
@core/*      -> src/core/*
@features/*  -> src/features/*
@graphql/*   -> src/graphql/*
@config/*    -> src/config/*
@helpers/*   -> src/helpers/*
```

Workspace packages: `@lbc/ui`, `@lbc/config`, `@lbc/db` (generated types only), `@lbc/providers`.

Always import through an alias. Never use deep relative imports (`../../../`). Relative imports are only allowed within the same folder (`./member-card.test.tsx` importing `./member-card`).

## 3. The UI kit (`packages/ui`)

```
packages/ui/src/
  primitives/     button, input, select, textarea, checkbox, dialog, dropdown-menu,
                  table, card, badge, skeleton, tooltip, tabs, toast
  components/     page-header, data-table, empty-state, error-state, search-toolbar,
                  confirm-dialog, stat-card, form-field, pagination, money, date-display
  layouts/        app-shell (sidebar + top bar + main), public-shell (header + footer)
  icons/          icon.tsx (the one icon entry point)
  index.ts        barrel
```

- **Primitives** are generic design-system pieces with no church knowledge.
- **Components** are composites built from primitives (a `data-table` is `table` + `pagination` + `skeleton` + `empty-state`).
- **Layouts** are the page shells. The dashboard has one authenticated shell; the public site has one public shell.

This is the single source of truth for reusable UI. See the Shared Component Extension Rule (§10).

Inside `packages/ui`, import across folders with the package's subpath imports (`#helpers/*`, `#primitives/*`, `#components/*`, defined in its `package.json`); apps import only from `@lbc/ui`.

**Adding a shadcn primitive.** The shadcn CLI writes one flat file (`src/primitives/<name>.tsx`), and its current registry imports `cn` from the `cn` npm package and Radix from `radix-ui`. So preview first with `pnpm dlx shadcn@4.21.0 add <name> --dry-run --view` (the version verified in LBC-12, also recorded in the root README) from `packages/ui`, then after adding: move the file to `primitives/<name>/<name>.tsx`, import `cn` from `#helpers/cn.utils` and Radix from its scoped `@radix-ui/react-*` package, remove any `cn` or `radix-ui` dependency the CLI added, replace arbitrary values and raw colours with tokens, review any `theme.css` edit, export it from `src/index.ts`, and add its colocated test.

## 4. Styling and design tokens

- Colours, spacing, font sizes, radii, shadows, durations and easings come from tokens in `packages/config/theme.css`. Both apps import that one file.
- **Palette:** taken from the church logos, each colour a 50 to 950 ramp in `theme.css`. Use only these, through the semantic tokens (`bg-primary`, `text-link`, `bg-brand`, `text-destructive-text` and so on), not raw ramp steps, unless no semantic token fits.

| Colour | Brand hex | Meaning to the church | Used for |
|---|---|---|---|
| Navy | `#111A3D` (navy-950) | The wordmark | Primary buttons, headings, text, the sidebar |
| Spring blue | `#120AC5` (spring-800) | The living spring, God's presence | Links, focus rings, info messages |
| Gold | `#E5C164` (gold-300), `#D5A33D` (gold-400) | The glory of God, the light of Christ | The logo, active nav item, highlights, primary buttons in dark mode |
| Crimson | `#9B0D1A` (crimson-700) | The blood of Christ, the Holy Spirit's fire | Design accents: public site hero accents, section dividers, quote marks, event date blocks, sermon series markers |
| Danger red | `#F00D10` (danger-500), `#CE121B` (danger-600) | (the bright logo red) | Errors and destructive actions only |
| White | `#FFFFFF` | Purity and holiness | Page and card surfaces |

- **Two reds, two jobs.** Deep crimson (`bg-crimson`, `text-crimson-text`) is a design colour for decoration and emphasis. Bright danger red (`bg-destructive`, `text-destructive-text`) means "something needs attention" and is used for nothing else.
- **Crimson never looks like an error.** Don't use it on form fields, validation messages, status badges, alerts or buttons, and don't put it next to an error. Errors always come with an icon and a message, never colour alone.
- **Gold text on white** uses `text-brand-text` (gold-700). Bright gold (gold-300) fails contrast on white and is only for fills, the logo and text on navy.
- **Warning is orange** (`warning` ramp), deliberately distinct from gold, so a warning never looks like a highlight.
- **Logo:** the gold LBC mark (`packages/ui/assets/brand/`) is the app logo. It sits on navy or white only, never on a photo or another colour, never recoloured or stretched. The mark alone (`lbc-mark.png`) is for the sidebar and small spaces; the full logo with the church name (`lbc-logo-full.png`) is for the login page, public site header and footer.
- **Fonts:** Inter for all interface text; Cinzel (`font-display`) only for the public site's large headings and the church name, echoing the logo's classic lettering. Both via `next/font`.
- **Dark mode:** remap the same CSS custom properties inside a `.dark { }` block. When adding a token, add its dark value in the same change if it differs.
- **Spacing** stays on the Tailwind scale (1, 2, 3, 4, 6, 8, 10, 12, 16, 20, 24). No arbitrary values (`w-[37px]`, `bg-[#1a1a1a]`). If a value is genuinely needed repeatedly, add a token.
- **No inline styles** (`style={{ }}`) except for a genuinely runtime-computed value (a chart offset, a progress width).
- **No component CSS files.** Tailwind classes in JSX; anything global goes in the shared theme file under `@layer base` or `@layer utilities`.
- **Icons:** always `<Icon name="..." />` from `@lbc/ui`, typed against a closed `IconName` union. It wraps lucide-react (shadcn's default); features never import lucide directly (enforced by `no-restricted-imports`). Never paste raw `<svg>` into a feature.

## 5. Data flow

Every feature follows the same chain. No link is skipped.

**Reading data**

```
page.tsx (server component)
  -> core/services/<domain>/<domain>.service.ts   server-only function
    -> graphql/queries/<domain>.queries.ts        typed document
      -> config/graphql-client.ts                 runs as the signed-in user
```

**Writing data**

```
client component form (React Hook Form + Zod)
  -> core/services/<domain>/<domain>.actions.ts   server action: re-validates with the same Zod schema
    -> graphql/mutations/<domain>.mutations.ts
      -> config/graphql-client.ts
  -> revalidatePath / revalidateTag so the page shows fresh data
```

- Components never call the GraphQL client directly. Pages never contain queries inline.
- **Client state:** filters, search text, sort and page number live in the URL search params (shareable, survive refresh, work with the back button). Ephemeral UI state (a dialog open) uses `useState`. There is no global client store; adding one (Zustand, Redux) needs an ADR.
- Money arrives as `amountMinor` integers and is displayed only through the shared `<Money>` component or `formatMoney()` helper.

## 6. Types, data, copy and constants

- **Generated types** (from the database and GraphQL schema) are the source of truth for entities. Never redeclare an entity by hand.
- `core/types/<domain>.types.ts` holds hand-written view models and component prop shapes that are reused. A small, never-exported type used by one component may live at the top of that component file.
- `core/data/<domain>.data.ts` holds static config: dropdown options, table column definitions, nav items, status-to-badge maps. Exported as `SCREAMING_SNAKE_CASE` constants, typed and `readonly`.
- `core/copy/<domain>.copy.ts` holds user-facing strings (labels, empty-state text, confirmations). Components read copy from here, not string literals. This keeps wording consistent and makes a second language possible later.
- Role groups (`FINANCE_ROLES`, `OFFICE_ROLES`) and `hasRole()` live in `core/auth/roles.ts`.
- There is no `constants/` folder and no `utils/` folder outside `helpers/`.

## 7. Routing

- `app/` contains route files only. A `page.tsx` fetches through a service and composes feature components: typically under 40 lines.
- Every route segment with data has a `loading.tsx` skeleton and relies on the nearest `error.tsx`.
- Authentication: `middleware.ts` redirects unauthenticated users to `/login`. Authorization: each protected page or layout calls `requireRole(ALLOWED_ROLES)` from `@core/auth`, and the database enforces it again with RLS.
- Route paths are constants in `core/data/routes.data.ts`; never hand-type `"/members"` in a link.

## 8. Barrels (`index.ts`)

Only for UI component groups: `packages/ui/src/index.ts` and each `features/<domain>/components/index.ts`. Never for `core/types`, `core/data`, `core/copy`, `helpers` or `graphql`; import those by direct path.

## 9. Naming reference

| Artifact | Location | File | Example |
|---|---|---|---|
| Route | `app/(group)/<segment>/` | `page.tsx`, `layout.tsx`, `loading.tsx` | `app/(dashboard)/members/page.tsx` |
| Feature component | `features/<domain>/components/<name>/` | `<name>.tsx` + `<name>.test.tsx` | `member-profile-card.tsx` |
| UI kit primitive | `packages/ui/src/primitives/<name>/` | `<name>.tsx` + test | `button.tsx` |
| UI kit component | `packages/ui/src/components/<name>/` | `<name>.tsx` + test | `data-table.tsx` |
| Service (reads) | `core/services/<domain>/` | `<domain>.service.ts` + test | `members.service.ts` |
| Server actions | `core/services/<domain>/` | `<domain>.actions.ts` + test | `members.actions.ts` |
| Query / mutation | `graphql/queries/`, `graphql/mutations/` | `<domain>.queries.ts` | `members.queries.ts` |
| View types | `core/types/` | `<domain>.types.ts` | `members.types.ts` |
| Static config | `core/data/` | `<domain>.data.ts` | `members.data.ts` |
| Copy | `core/copy/` | `<domain>.copy.ts` | `members.copy.ts` |
| Zod schema | `core/schemas/` | `<domain>.schema.ts` + test | `members.schema.ts` |
| Helper | `helpers/` | `<domain>.utils.ts` + test | `money.utils.ts` |
| Hook | next to its only consumer, or `helpers/` if shared | `use-<name>.ts` | `use-query-state.ts` |

Components are `PascalCase` exports from `kebab-case` files. One exported component per file.

---

# Part II: Mandatory rules

## 10. Shared Component Extension Rule

The UI kit is the single source of truth for reusable UI. Before creating any component, search `packages/ui` and every `features/*/components/` folder.

If the new need is similar to something that exists, **do not create another component. Extend the existing one.**

Example: `DataTable` supports basic, striped and compact. A feature needs selectable rows.

- Do not create `MemberTable`, `SelectableTable`, `AdvancedTable`.
- Do add a `selectable` option (or variant) to `DataTable`, keeping every existing consumer working unchanged.

Ask before creating anything reusable:

1. Does something similar already exist?
2. Can I extend it with a variant or an option?
3. Can I keep its API backward compatible?

If any answer is yes, extend. Prefer variants over new components, options over duplicated implementations, composition over inheritance. A component used by two features moves from `features/` into `packages/ui`.

## 11. Modern React and Next.js

- Server components by default. Fetch data in server components, not in `useEffect`.
- No data fetching or side effects during render. Effects are for synchronising with something outside React (a subscription, the DOM), not for deriving state.
- Derive values during render instead of copying props into state. Add `useMemo`/`useCallback` only when a measurement shows a need.
- Hooks follow the rules of hooks (enforced by ESLint). Custom hooks start with `use`.
- Props are typed with an explicit `type <Name>Props`. No `React.FC`. No default exports except where Next requires them (`page.tsx`, `layout.tsx`, `error.tsx`).
- Every list rendered with `.map()` has a stable `key` from data, never the array index.
- Use `next/image` for images, `next/link` for navigation, `next/font` for fonts.
- Keep JSX declarative: branching and derivation go in variables above the `return`, not deeply nested ternaries.

## 12. Config-driven UI

When several elements share a structure and differ only in label, icon, value or handler, render them from a typed array with `.map()` instead of repeating markup. Applies to nav items, tabs, buttons, table columns, form fields, filters, stat cards, menu items and breadcrumbs. The array lives in `core/data/<domain>.data.ts` if it is static, or as a `const` in the component if it closes over handlers.

## 13. Accessibility and semantic HTML

Accessibility is not optional and not "later".

- Structure uses `<header>`, `<nav>`, `<main>`, `<section>`, `<article>`, `<aside>`, `<footer>`, never stacks of `<div>` for page layout.
- `<button>` performs actions; `<a href>` (via `next/link`) navigates. Never a clickable `<div>`.
- Every input has a `<label>` (the `FormField` component handles this). Every image has meaningful `alt`, or `alt=""` if decorative.
- One `<h1>` per page, no skipped heading levels.
- ARIA only fills gaps native HTML cannot (`aria-live`, tabs); never a substitute for the right element.
- Everything works by keyboard: logical tab order, visible focus rings, `Escape` closes dialogs and menus, focus returns to the trigger.
- Colour is never the only signal: errors, statuses and required fields also have text or an icon.
- Contrast meets WCAG 2.1 AA in light and dark themes.

**Established element mappings** (use these, do not invent alternatives):

| Shape | Element |
|---|---|
| Page or tab root | `<section>` with a heading |
| Repeated list-shaped UI (stat cards, member cards, legends, nav items) | `<ul>` container, `<li>` per item |
| Search + filter toolbar | `<search>` wrapping the inputs |
| Dialog title referenced by `aria-labelledby` | `<h2>` |
| Breadcrumbs | `<nav aria-label="Breadcrumb"><ol>...</ol></nav>` |
| Tabs | WAI-ARIA tabs: `role="tablist"`, `role="tab"`, `role="tabpanel"` (shadcn Tabs does this) |
| Tabular data | a real `<table>` with `<th scope>`; never a div grid |

## 14. Responsive design

- Mobile-first. Every screen works at 375px, tablet and desktop. Ushers record attendance on phones on Sunday mornings.
- No fixed pixel widths on layout containers; use flex/grid, relative units and `max-w-*`.
- Tap targets at least 44px. Wide tables scroll inside their own container, never the page.
- Check the real rendered layout at a small width before calling UI work done.

## 15. Loading, empty and error states

Every screen that fetches or submits data has all three, not just the happy path.

- **Loading:** skeletons that mirror the real layout (a skeleton row where a row will render), via `loading.tsx` and the `Skeleton` primitive. Never a full-screen spinner. Buttons that submit show a pending state and are disabled while pending.
- **Empty:** the `EmptyState` component with plain text and, where useful, the next action ("No members yet. Add the first member.").
- **Error:** the `ErrorState` component with a plain, actionable message and a retry.

**One global error path.**
- `config/graphql-client.ts` is the only place GraphQL responses are inspected. It reads the `errors` array (a GraphQL response can be HTTP 200 and still fail) and classifies each failure as `network`, `unauthenticated`, `forbidden`, `validation`, `not_found` or `server`, returning a typed `AppError`.
- `core/errors/error-messages.data.ts` maps every error code to a plain message. Users never see raw backend text, codes or stack traces.
- Partial data: render what resolved and flag what did not; a fully failed query shows the error state.
- `error.tsx` and `global-error.tsx` catch anything unhandled and log it.
- Validation errors appear inline next to the field, not only as a toast. Toasts are for outcomes ("Offering recorded").
- No scattered `try/catch` in components. Server actions return a typed result (`{ ok: true, data } | { ok: false, error: AppError }`).

## 16. Visual design and motion

**No generic AI look.**
- No gradients as default backgrounds or buttons; flat, deliberate colours from the palette.
- No decorative badges ("New", "Beta", sparkles). A badge only shows real state (a status, a count).
- No emoji in UI copy, headings or buttons.
- Plain, direct, warm copy. No marketing filler in the dashboard.

**Motion communicates, it does not decorate.**
- 150 to 300ms, standard easing, from duration and easing tokens. Nothing bouncy or elastic.
- Animate only `transform` and `opacity`.
- Respect `prefers-reduced-motion` (little to no motion).
- Hover, focus and press feedback is near-instant. Longer transitions only for significant changes (dialog open, item added or removed).

**Required site structure.**
- Both apps have a footer linking to real **Terms of Use** and **Privacy Policy** pages with actual content, never `#` or "coming soon". The privacy page explains what member data the church keeps and why.
- Both apps have a real `not-found.tsx` page.
- The public site also has service times, location and contact (PRD CNT-08).

## 17. Testing

- Colocated: `<name>.test.tsx` next to `<name>.tsx`. No top-level `__tests__` folders.
- BDD names: `it('should show the empty state when no members match the search')`.
- Query by role and label (`getByRole('button', { name: 'Save' })`), the way users and screen readers find things. Avoid test IDs unless there is no accessible handle.
- Minimum per component: renders without error, props change the output, events and callbacks fire. Minimum per function: normal case, edge case, error case.
- Mock services and actions as plain objects with `vi.fn()`. Never hit a real network in unit tests.
- Playwright covers each role's key journey at 375px and desktop, logged in as the matching seed user, with an axe scan on every page visited.
- Permissions are tested from both sides: the allowed role succeeds and a disallowed role is blocked.

### Commands

```
pnpm dev             run both apps
pnpm lint            ESLint
pnpm format          Prettier write
pnpm typecheck       tsc --noEmit across the workspace
pnpm test            Vitest
pnpm test:e2e        Playwright
pnpm verify          everything CI runs (see CLAUDE.md §6)
```

---

## Known inconsistencies

Record real deviations here as they are discovered, with the majority pattern to follow. Never use a minority pattern as a precedent for new code.

- None yet.

---

## Frontend checklist

- [ ] Searched `packages/ui` and existing features; extended instead of duplicating
- [ ] File is in the right layer (`app/` routes, `features/` components, `core/` types/data/copy/schemas/services, `helpers/` pure logic)
- [ ] Imports use aliases; no deep relative paths
- [ ] Server component unless interaction requires client; no data fetching in `useEffect`
- [ ] Data flows page -> service -> GraphQL document -> client; writes go through a server action with Zod
- [ ] Tokens only: no arbitrary values, no inline styles, no component CSS, icons via `<Icon>`
- [ ] Semantic elements per the mapping table; keyboard and screen reader usable; axe clean
- [ ] Works at 375px, tablet and desktop
- [ ] Skeleton, empty and error states present; errors via the global path with plain messages
- [ ] Repeated UI rendered from a typed array
- [ ] Copy comes from `core/copy`; no em dashes; no emoji or decorative badges
- [ ] Colocated tests with BDD names; allowed and denied roles tested where relevant
