import logoMark from "@lbc/ui/assets/brand/lbc-mark.png";
import Image from "next/image";
import Link from "next/link";

import { SHELL_COPY } from "@core/copy/shell.copy";
import { ROUTES } from "@core/data/routes.data";
import { logoutAction } from "@core/services/auth/auth.actions";
import type { RoleGatedLink } from "@core/types/navigation.types";
import { LogoutButton } from "@features/auth/components/logout-button/logout-button";
import { AppNav } from "@features/shell/components/app-nav/app-nav";

type AppHeaderProps = {
  staffName: string;
  /** The modules this signed-in user may use, already filtered by role. */
  modules: readonly RoleGatedLink[];
};

/** The authenticated header: church name, the user's account and sign out, and the module navigation. */
export function AppHeader({ staffName, modules }: AppHeaderProps) {
  return (
    <header className="bg-primary text-primary-foreground">
      <div className="mx-auto flex max-w-5xl items-center justify-between gap-4 px-4 py-3">
        <Link
          href={ROUTES.home}
          aria-label={SHELL_COPY.homeLinkLabel}
          className="flex min-w-0 items-center gap-3 rounded-md focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
        >
          <Image src={logoMark} alt="" priority className="h-11 w-auto shrink-0" />
          <span className="truncate font-display text-lg">{SHELL_COPY.churchName}</span>
        </Link>
        <nav aria-label={SHELL_COPY.accountNavLabel} className="flex shrink-0 items-center gap-3">
          <Link
            href={ROUTES.accountSecurity}
            className="hidden min-h-11 items-center rounded-md px-2 text-sm underline-offset-4 hover:underline focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none sm:inline-flex"
          >
            {staffName}
          </Link>
          <LogoutButton
            signOut={logoutAction}
            variant="outline"
            className="border-primary-foreground bg-transparent text-primary-foreground hover:bg-primary-foreground hover:text-primary"
          />
        </nav>
      </div>
      <div className="mx-auto max-w-5xl px-4 pb-3">
        <AppNav modules={modules} />
      </div>
    </header>
  );
}
