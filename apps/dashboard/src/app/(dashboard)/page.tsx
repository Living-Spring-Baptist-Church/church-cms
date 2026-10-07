import type { Metadata } from "next";
import Link from "next/link";

import { Button, Card, CardContent, CardDescription, CardHeader, CardTitle } from "@lbc/ui";

import { requireStaff } from "@core/auth/session";
import { AUTH_COPY } from "@core/copy/auth.copy";
import { ROUTES } from "@core/data/routes.data";

export const metadata: Metadata = { title: AUTH_COPY.home.pageTitle };

export default async function HomePage() {
  const { profile } = await requireStaff();
  return (
    <main id="main-content" className="mx-auto flex w-full max-w-5xl flex-col gap-6 px-4 py-8">
      <section aria-labelledby="home-heading" className="flex flex-col gap-6">
        <h1 id="home-heading" className="text-2xl font-semibold text-primary">
          {`${AUTH_COPY.home.greeting}, ${profile.fullName}`}
        </h1>
        <Card>
          <CardHeader>
            <CardTitle as="h2">{AUTH_COPY.home.rolesLabel}</CardTitle>
            <CardDescription>
              {profile.roles.length === 0 ? AUTH_COPY.home.noRoles : null}
            </CardDescription>
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
