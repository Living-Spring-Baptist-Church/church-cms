import type { ReactNode } from "react";

import { filterByRoles } from "@core/auth/roles";
import { requireStaff } from "@core/auth/session";
import { SHELL_COPY } from "@core/copy/shell.copy";
import { NAVIGATION_MODULES } from "@core/data/navigation.data";
import { AppHeader } from "@features/shell/components/app-header/app-header";

type DashboardLayoutProps = {
  children: ReactNode;
};

/**
 * Every signed-in staff member gets the shell, so this layout uses requireStaff. Each module
 * page calls requireRole with its own roles, and the navigation below only lists modules the
 * signed-in roles may use.
 */
export default async function DashboardLayout({ children }: DashboardLayoutProps) {
  const { profile } = await requireStaff();
  const modules = filterByRoles(NAVIGATION_MODULES, profile.roles);
  return (
    <>
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:absolute focus:z-10 focus:m-2 focus:rounded-md focus:bg-background focus:px-3 focus:py-2 focus:text-foreground"
      >
        {SHELL_COPY.skipLink}
      </a>
      <AppHeader staffName={profile.fullName} modules={modules} />
      {children}
    </>
  );
}
