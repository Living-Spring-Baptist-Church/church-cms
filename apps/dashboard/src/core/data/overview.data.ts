import { FINANCE_ROLES, type StaffRoleName } from "@core/auth/roles";
import { OVERVIEW_COPY } from "@core/copy/overview.copy";
import { ROUTES } from "@core/data/routes.data";
import type { RoleGatedLink } from "@core/types/navigation.types";

export const OVERVIEW_CARD_IDS = {
  lastSundayAttendance: "lastSundayAttendance",
  newVisitorsThisMonth: "newVisitorsThisMonth",
  monthToDateGiving: "monthToDateGiving",
} as const;

export type OverviewCardId = (typeof OVERVIEW_CARD_IDS)[keyof typeof OVERVIEW_CARD_IDS];

export type OverviewCardConfig = {
  readonly id: OverviewCardId;
  readonly allowedRoles: readonly StaffRoleName[];
  /** False until the card has a real data source. Nothing is shown for an unavailable card. */
  readonly isAvailable: boolean;
};

// Department heads are left out: attendance is a church-wide headcount, and the PRD limits their
// view to their own department, which this card cannot show.
const ATTENDANCE_CARD_ROLES: readonly StaffRoleName[] = [
  "super_admin",
  "pastor",
  "secretary",
  "usher",
];

// Matches private.can_see_visitor_counts: the database refuses every other role with AUTH_FORBIDDEN.
const NEW_VISITORS_CARD_ROLES: readonly StaffRoleName[] = ["super_admin", "pastor", "secretary"];

export const OVERVIEW_CARDS: readonly OverviewCardConfig[] = [
  {
    id: OVERVIEW_CARD_IDS.lastSundayAttendance,
    allowedRoles: ATTENDANCE_CARD_ROLES,
    isAvailable: true,
  },
  {
    id: OVERVIEW_CARD_IDS.newVisitorsThisMonth,
    allowedRoles: NEW_VISITORS_CARD_ROLES,
    isAvailable: true,
  },
  {
    id: OVERVIEW_CARD_IDS.monthToDateGiving,
    allowedRoles: FINANCE_ROLES,
    isAvailable: false,
  },
];

export const QUICK_ACTIONS: readonly RoleGatedLink[] = [
  {
    id: "recordAttendance",
    label: OVERVIEW_COPY.quickActions.recordAttendance,
    href: ROUTES.attendance,
    isAvailable: false,
    allowedRoles: ["super_admin", "secretary", "usher"],
  },
  {
    id: "recordOffering",
    label: OVERVIEW_COPY.quickActions.recordOffering,
    href: ROUTES.finance,
    isAvailable: false,
    allowedRoles: ["treasurer"],
  },
  {
    id: "addMember",
    label: OVERVIEW_COPY.quickActions.addMember,
    href: ROUTES.membersNew,
    isAvailable: false,
    allowedRoles: ["super_admin", "secretary"],
  },
];
