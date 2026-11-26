import Link from "next/link";

import { Button } from "@lbc/ui";

import { OVERVIEW_COPY } from "@core/copy/overview.copy";
import { SHELL_COPY } from "@core/copy/shell.copy";
import type { RoleGatedLink } from "@core/types/navigation.types";

type QuickActionsProps = {
  /** Already filtered to the actions the signed-in roles may use. */
  actions: readonly RoleGatedLink[];
};

type QuickActionItemProps = {
  action: RoleGatedLink;
};

/** A built action is a link. An unbuilt one is a disabled button with a note, never a dead link. */
function QuickActionItem({ action }: QuickActionItemProps) {
  if (action.isAvailable) {
    return (
      <Button asChild variant="outline">
        <Link href={action.href}>{action.label}</Link>
      </Button>
    );
  }
  const noteId = `quick-action-${action.id}-note`;
  return (
    <div className="flex flex-col gap-1">
      <Button variant="outline" disabled aria-describedby={noteId}>
        {action.label}
      </Button>
      <p id={noteId} className="text-xs text-muted-foreground">
        {SHELL_COPY.notAvailable}
      </p>
    </div>
  );
}

/** OVR-02: the actions this role does its daily work with. Renders nothing for a role with none. */
export function QuickActions({ actions }: QuickActionsProps) {
  if (actions.length === 0) {
    return null;
  }
  return (
    <section aria-labelledby="quick-actions-heading" className="flex flex-col gap-3">
      <h2 id="quick-actions-heading" className="text-lg font-semibold text-primary">
        {OVERVIEW_COPY.quickActions.heading}
      </h2>
      <ul className="flex flex-wrap gap-3">
        {actions.map((action) => (
          <li key={action.id}>
            <QuickActionItem action={action} />
          </li>
        ))}
      </ul>
    </section>
  );
}
