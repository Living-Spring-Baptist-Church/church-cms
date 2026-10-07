import type { ReactNode } from "react";

import { requireStaff } from "@core/auth/session";
import { AUTH_COPY } from "@core/copy/auth.copy";
import { AppHeader } from "@features/shell/components/app-header/app-header";

type DashboardLayoutProps = {
  children: ReactNode;
};

export default async function DashboardLayout({ children }: DashboardLayoutProps) {
  const { profile } = await requireStaff();
  return (
    <>
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:absolute focus:z-10 focus:m-2 focus:rounded-md focus:bg-background focus:px-3 focus:py-2 focus:text-foreground"
      >
        {AUTH_COPY.shell.skipLink}
      </a>
      <AppHeader staffName={profile.fullName} />
      {children}
    </>
  );
}
