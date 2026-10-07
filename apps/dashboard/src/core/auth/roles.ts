export const STAFF_ROLES = [
  "super_admin",
  "pastor",
  "treasurer",
  "secretary",
  "usher",
  "department_head",
  "content_editor",
] as const;

export type StaffRoleName = (typeof STAFF_ROLES)[number];

/**
 * PRD NFR Authentication: these roles may not use the dashboard without two-factor. The database enforces the
 * same list in private.mfa_required_roles() (LBC-41): change both together.
 */
export const MFA_REQUIRED_ROLES: readonly StaffRoleName[] = ["super_admin", "pastor", "treasurer"];

export function isStaffRoleName(candidate: string): candidate is StaffRoleName {
  return STAFF_ROLES.some((roleName) => roleName === candidate);
}

export function hasRole(
  heldRoles: readonly StaffRoleName[],
  allowedRoles: readonly StaffRoleName[],
): boolean {
  return heldRoles.some((heldRole) => allowedRoles.includes(heldRole));
}

export function requiresMfa(heldRoles: readonly StaffRoleName[]): boolean {
  return hasRole(heldRoles, MFA_REQUIRED_ROLES);
}

export type RoleHolder = {
  readonly roles: readonly StaffRoleName[];
  /** True when the database holds a role this app does not know yet. */
  readonly hasUnrecognisedRole: boolean;
};

/** Fails closed: a role the app does not know is treated as one that requires two-factor. */
export function profileRequiresMfa(holder: RoleHolder): boolean {
  return holder.hasUnrecognisedRole || requiresMfa(holder.roles);
}

/** A staff row with no role at all has no access, so it never reaches the dashboard. */
export function hasAnyRole(holder: RoleHolder): boolean {
  return holder.hasUnrecognisedRole || holder.roles.length > 0;
}
