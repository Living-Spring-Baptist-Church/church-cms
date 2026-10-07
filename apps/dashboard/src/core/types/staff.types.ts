import type { StaffRoleName } from "@core/auth/roles";

/** The signed-in staff member as the dashboard needs to know them. */
export type StaffProfile = {
  readonly id: string;
  readonly fullName: string;
  readonly isActive: boolean;
  readonly roles: readonly StaffRoleName[];
  readonly hasUnrecognisedRole: boolean;
};
