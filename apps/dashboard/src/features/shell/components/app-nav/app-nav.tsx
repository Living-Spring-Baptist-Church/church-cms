import type { RoleGatedLink } from "@core/types/navigation.types";
import { SHELL_COPY } from "@core/copy/shell.copy";

import { AppNavLink } from "@features/shell/components/app-nav/app-nav-link";

type AppNavProps = {
  /** Already filtered to the modules the signed-in roles may use. */
  modules: readonly RoleGatedLink[];
};

type AppNavListProps = AppNavProps & {
  className: string;
};

/** One list of modules. Unbuilt modules show as plain text, so no link leads nowhere. */
function AppNavList({ modules, className }: AppNavListProps) {
  return (
    <ul className={className}>
      {modules.map((module) => (
        <li key={module.id}>
          {module.isAvailable ? (
            <AppNavLink href={module.href} label={module.label} />
          ) : (
            <span className="flex min-h-11 flex-col justify-center px-3 text-sm text-sidebar-foreground/70">
              {module.label}
              <span className="text-xs">{SHELL_COPY.notAvailable}</span>
            </span>
          )}
        </li>
      ))}
    </ul>
  );
}

/** Desktop shows the modules in a row. Phones get the same list in a menu that opens in place. */
export function AppNav({ modules }: AppNavProps) {
  return (
    <nav aria-label={SHELL_COPY.mainNavLabel}>
      <details className="md:hidden">
        <summary className="inline-flex min-h-11 cursor-pointer items-center rounded-md px-3 text-sm font-medium focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none">
          {SHELL_COPY.menuLabel}
        </summary>
        <div className="pt-2">
          <AppNavList modules={modules} className="flex flex-col gap-1" />
        </div>
      </details>
      <div className="hidden md:block">
        <AppNavList modules={modules} className="flex flex-wrap gap-1" />
      </div>
    </nav>
  );
}
