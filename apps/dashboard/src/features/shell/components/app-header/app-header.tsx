import logoMark from "@lbc/ui/assets/brand/lbc-mark.png";
import Image from "next/image";
import Link from "next/link";

import { AUTH_COPY } from "@core/copy/auth.copy";
import { ROUTES } from "@core/data/routes.data";
import { logoutAction } from "@core/services/auth/auth.actions";
import { LogoutButton } from "@features/auth/components/logout-button/logout-button";

type AppHeaderProps = {
  staffName: string;
};

/** The minimal authenticated header: logo, who is signed in, and sign out. The full shell is LBC-20. */
export function AppHeader({ staffName }: AppHeaderProps) {
  return (
    <header className="bg-primary text-primary-foreground">
      <div className="mx-auto flex max-w-5xl items-center justify-between gap-4 px-4 py-3">
        <Link
          href={ROUTES.home}
          aria-label={AUTH_COPY.shell.homeLinkLabel}
          className="rounded-md focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none"
        >
          <Image src={logoMark} alt="" priority className="h-11 w-auto" />
        </Link>
        <nav aria-label={AUTH_COPY.shell.accountNavLabel} className="flex items-center gap-3">
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
    </header>
  );
}
