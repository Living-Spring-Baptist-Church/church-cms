import type { Metadata } from "next";
import Link from "next/link";

import { Button, Card, CardContent, CardHeader, CardTitle } from "@lbc/ui";

import { STAFF_ROLES } from "@core/auth/roles";
import { requireRole } from "@core/auth/session";
import { AUTH_COPY } from "@core/copy/auth.copy";
import { ROUTES } from "@core/data/routes.data";
import { loadOverview } from "@core/services/overview/overview.service";
import { OverviewCards, QuickActions } from "@features/overview/components";
import { visibleQuickActions } from "@helpers/overview.utils";

export const metadata: Metadata = { title: AUTH_COPY.home.pageTitle };

/** The overview is for every recognised staff role. Each card and action then filters by role. */
export default async function HomePage() {
  const { profile, client } = await requireRole(STAFF_ROLES);
  const overview = await loadOverview({ client, roles: profile.roles, asOf: new Date() });
  return (
    <main id="main-content" className="mx-auto flex w-full max-w-5xl flex-col gap-8 px-4 py-8">
      <section aria-labelledby="home-heading" className="flex flex-col gap-8">
        <h1 id="home-heading" className="text-2xl font-semibold text-primary">
          {`${AUTH_COPY.home.greeting}, ${profile.fullName}`}
        </h1>
        <QuickActions actions={visibleQuickActions(profile.roles)} />
        <OverviewCards overview={overview} />
        <Card>
          <CardHeader>
            <CardTitle as="h2">{AUTH_COPY.home.rolesLabel}</CardTitle>
          </CardHeader>
          <CardContent>
            <ul className="flex flex-wrap gap-2">
              {profile.roles.map((roleName) => (
                <li key={roleName} className="rounded-md border border-border px-3 py-1 text-sm">
                  {AUTH_COPY.roleLabels[roleName]}
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>
        <Button asChild variant="outline" className="self-start">
          <Link href={ROUTES.accountSecurity}>{AUTH_COPY.home.securityLink}</Link>
        </Button>
      </section>
    </main>
  );
}
