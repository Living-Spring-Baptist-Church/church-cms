import { FINANCE_ROLES, STAFF_ROLES, type StaffRoleName } from "@core/auth/roles";
import { SHELL_COPY } from "@core/copy/shell.copy";
import { ROUTES } from "@core/data/routes.data";
import type { RoleGatedLink } from "@core/types/navigation.types";

// Module access follows the PRD permission matrix (view or edit at least once per module).
const MEMBER_ROLES: readonly StaffRoleName[] = [
  "super_admin",
  "pastor",
  "treasurer",
  "secretary",
  "usher",
  "department_head",
];
const ATTENDANCE_ROLES: readonly StaffRoleName[] = [
  "super_admin",
  "pastor",
  "secretary",
  "usher",
  "department_head",
];
const DEPARTMENT_LEADER_ROLES: readonly StaffRoleName[] = [
  "super_admin",
  "pastor",
  "secretary",
  "department_head",
];
const REPORT_ROLES: readonly StaffRoleName[] = [
  "super_admin",
  "pastor",
  "treasurer",
  "secretary",
  "department_head",
];
const CONTENT_ROLES: readonly StaffRoleName[] = [
  "super_admin",
  "pastor",
  "secretary",
  "department_head",
  "content_editor",
];
const LEADERSHIP_ROLES: readonly StaffRoleName[] = ["super_admin", "pastor"];
const SUPER_ADMIN_ROLES: readonly StaffRoleName[] = ["super_admin"];

/** Every module in the sidebar or header menu. `isAvailable` flips to true when its route is built. */
export const NAVIGATION_MODULES: readonly RoleGatedLink[] = [
  {
    id: "overview",
    label: SHELL_COPY.modules.overview,
    href: ROUTES.home,
    isAvailable: true,
    allowedRoles: STAFF_ROLES,
  },
  {
    id: "members",
    label: SHELL_COPY.modules.members,
    href: ROUTES.members,
    isAvailable: false,
    allowedRoles: MEMBER_ROLES,
  },
  {
    id: "attendance",
    label: SHELL_COPY.modules.attendance,
    href: ROUTES.attendance,
    isAvailable: false,
    allowedRoles: ATTENDANCE_ROLES,
  },
  {
    id: "programs",
    label: SHELL_COPY.modules.programs,
    href: ROUTES.programs,
    isAvailable: false,
    allowedRoles: DEPARTMENT_LEADER_ROLES,
  },
  {
    id: "finance",
    label: SHELL_COPY.modules.finance,
    href: ROUTES.finance,
    isAvailable: false,
    allowedRoles: FINANCE_ROLES,
  },
  {
    id: "messaging",
    label: SHELL_COPY.modules.messaging,
    href: ROUTES.messaging,
    isAvailable: false,
    allowedRoles: DEPARTMENT_LEADER_ROLES,
  },
  {
    id: "reports",
    label: SHELL_COPY.modules.reports,
    href: ROUTES.reports,
    isAvailable: false,
    allowedRoles: REPORT_ROLES,
  },
  {
    id: "content",
    label: SHELL_COPY.modules.content,
    href: ROUTES.content,
    isAvailable: false,
    allowedRoles: CONTENT_ROLES,
  },
  {
    id: "audit",
    label: SHELL_COPY.modules.audit,
    href: ROUTES.audit,
    isAvailable: false,
    allowedRoles: LEADERSHIP_ROLES,
  },
  {
    id: "settings",
    label: SHELL_COPY.modules.settings,
    href: ROUTES.settings,
    isAvailable: false,
    allowedRoles: SUPER_ADMIN_ROLES,
  },
];
