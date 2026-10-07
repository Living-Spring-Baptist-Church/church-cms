import type { Metadata } from "next";

import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@lbc/ui";

import { requireStaff } from "@core/auth/session";
import { AUTH_COPY } from "@core/copy/auth.copy";
import { confirmEnrolmentAction, startEnrolmentAction } from "@core/services/auth/auth.actions";
import { TotpEnrolForm } from "@features/auth/components/totp-enrol-form/totp-enrol-form";

export const metadata: Metadata = { title: AUTH_COPY.security.pageTitle };

export default async function AccountSecurityPage() {
  const { hasVerifiedFactor } = await requireStaff();
  return (
    <main id="main-content" className="mx-auto flex w-full max-w-lg flex-col gap-6 px-4 py-8">
      <section aria-labelledby="security-heading" className="flex flex-col gap-6">
        <h1 id="security-heading" className="text-2xl font-semibold text-primary">
          {AUTH_COPY.security.heading}
        </h1>
        <Card>
          <CardHeader>
            <CardTitle as="h2">
              {hasVerifiedFactor
                ? AUTH_COPY.security.enabledHeading
                : AUTH_COPY.security.disabledHeading}
            </CardTitle>
            <CardDescription>
              {hasVerifiedFactor
                ? AUTH_COPY.security.enabledDescription
                : AUTH_COPY.enrol.optionalDescription}
            </CardDescription>
          </CardHeader>
          {hasVerifiedFactor ? null : (
            <CardContent>
              <TotpEnrolForm
                startEnrolment={startEnrolmentAction}
                confirmEnrolment={confirmEnrolmentAction}
              />
            </CardContent>
          )}
        </Card>
      </section>
    </main>
  );
}
