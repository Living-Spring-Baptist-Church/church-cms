import type { StaffRoleName } from "@core/auth/roles";

/**
 * A link that only some roles see: a navigation module or a quick action. It is shown as a link
 * once its route is built (`isAvailable`), and as plain text with a note until then.
 */
export type RoleGatedLink = {
  readonly id: string;
  readonly label: string;
  readonly href: string;
  readonly isAvailable: boolean;
  readonly allowedRoles: readonly StaffRoleName[];
};
